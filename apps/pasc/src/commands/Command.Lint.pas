/// <summary> This unit contains procedures to configure and execute a command to lint the
/// sources with the messages of the compiler: warnings, notes and hints, kept only for the
/// sources of each member and not for the modules installed by boss, which are compiled with
/// the project.
///
/// Each project is built with lazbuild -B, so every unit is compiled again and repeats its
/// messages, into lib/lint, so the normal build is not touched.
/// </summary>
unit Command.Lint;

{$MODE DELPHI}{$H+}

interface

uses
  Command.Interfaces;

  /// <summary> This command builds the project in the current folder and its test project, or
  /// at the root of a workspace every member and its test project, and outputs the messages of
  /// the compiler for their sources, as file:line:col links. The configuration in pasc.json
  /// says which messages are ignored and which ones fail; by default warnings fail. The exit
  /// code is 1 when there is a failing message or a project could not be built. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output the messages. </param>
  procedure LintCommand(ABuilder: ICommandBuilder);

  /// <summary> Registry a lint command using the command builder from pascli. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// registry the command. </param>
  procedure Registry(ABuilder: ICommandBuilder);

implementation

uses
  Classes,
  SysUtils,
  StrUtils,
  Command.Build,
  Command.Check,
  Command.Test,
  Utils.Lint,
  Utils.Output,
  Utils.Shell,
  Utils.Workspace;

type
  /// <summary> Result of the lint of a member. </summary>
  TMemberLint = record
    /// <summary> True if every project of the member was built. </summary>
    Ran: Boolean;
    /// <summary> Messages shown, by kind. </summary>
    Counts: array[TLintKind] of Integer;
    Ignored: Integer;
    Failing: Integer;
    /// <summary> Why a project could not be built, or empty. </summary>
    Error: string;
  end;

function DisplayPath(const ABaseDir, AFileName: string): string;
begin
  Result := StringReplace(
    ExtractRelativePath(IncludeTrailingPathDelimiter(ABaseDir), AFileName), '\', '/', [rfReplaceAll]);
end;

function Plural(const ACount: Integer; const AName: string): string;
begin
  Result := IntToStr(ACount) + ' ' + AName + IfThen(ACount <> 1, 's', '');
end;

function FormatCounts(const ACounts: array of Integer; const AIgnored, AFailing: Integer): string;
begin
  Result := Format('%s, %s, %s, %s', [Plural(ACounts[Ord(lkError)], 'error'), Plural(ACounts[Ord(lkWarning)], 'warning'),
    Plural(ACounts[Ord(lkNote)], 'note'), Plural(ACounts[Ord(lkHint)], 'hint')]) +
    IfThen(AIgnored > 0, Format(' (%d ignored)', [AIgnored]), '') + Format(', %d failing', [AFailing]);
end;

/// <summary> The projects of a member: its .lpi or .lpk and its test project. </summary>
function MemberProjects(const AMemberDir, AProjectFile: string): TArray<string>;
var
  LTestProject: string;
begin
  Result := [];
  if (AProjectFile <> '') and FileExists(AProjectFile) then
    Result := [AProjectFile];
  LTestProject := GetMemberTestProject(AMemberDir);
  if LTestProject <> '' then
    Result := Result + [LTestProject];
end;

/// <summary> Builds a project with lazbuild -B into lib/lint, with every message of the
/// compiler and its numbers, and returns the output. AError is empty when the build succeeded.
/// </summary>
function BuildForLint(const AProjectFile: string; out AOutput, AError: string): Boolean;
var
  LLintDir, LOptions: string;
  LExitCode: Integer = 0;
begin
  AError := '';
  LLintDir := ConcatPaths([ExtractFileDir(ExpandFileName(AProjectFile)), 'lib', 'lint']);
  // the compiler does not create the folders of -FU and -o
  ForceDirectories(ConcatPaths([LLintDir, 'units']));
  // -vwnhq: warnings, notes, hints and the message numbers. The options of --opt come after
  // the ones of the project, so they win. lazbuild splits them by spaces and keeps quotes, so
  // the folders are relative to the project folder, where the compiler runs.
  LOptions := '-vwnhq -FUlib/lint/units';
  if not SameText(ExtractFileExt(AProjectFile), '.lpk') then
    LOptions := LOptions + ' -olib/lint/' + ChangeFileExt(ExtractFileName(AProjectFile), '');
  try
    AOutput := ShellExecute('lazbuild', ['-B', '--opt=' + LOptions, AProjectFile], LExitCode);
  except
    on E: Exception do
    begin
      AOutput := '';
      AError := 'lazbuild was not found';
      Exit(False);
    end;
  end;
  Result := (LExitCode = 0) and not ContainsText(AOutput, 'Error: ');
  if not Result then
  begin
    AError := FirstBuildError(AOutput);
    if AError = '' then
      AError := 'the build failed';
  end;
end;

function LintMember(ABuilder: ICommandBuilder; const AMemberDir, AProjectFile, ARootDir, AStartDir: string;
  const AConfig: TLintConfig): TMemberLint;
var
  LProject, LOutput, LError, LTitle, LText: string;
  LMessages: TLintMessages;
  LMessage: TLintMessage;
  LProjects: TArray<string>;
  LBuilt: Boolean;
begin
  Result := Default(TMemberLint);
  LProjects := MemberProjects(AMemberDir, AProjectFile);
  if Length(LProjects) = 0 then
  begin
    Result.Error := 'no project or test project';
    Exit;
  end;

  LMessages := [];
  LBuilt := True;
  for LProject in LProjects do
  begin
    if not BuildForLint(LProject, LOutput, LError) then
    begin
      LBuilt := False;
      if Result.Error = '' then
        Result.Error := DisplayPath(ARootDir, LProject) + ': ' + LError;
    end;
    LMessages := LMessages + ParseCompilerMessages(LOutput, ExtractFileDir(ExpandFileName(LProject)));
  end;

  for LMessage in FilterMemberMessages(LMessages, AMemberDir) do
  begin
    if IsIgnored(AConfig, LMessage) then
    begin
      Inc(Result.Ignored);
      Continue;
    end;
    Inc(Result.Counts[LMessage.Kind]);
    LTitle := UpperCase(Copy(LintKindName(LMessage.Kind), 1, 1)) + Copy(LintKindName(LMessage.Kind), 2, MaxInt);
    // file:line:col, which editors and terminals turn into links
    LText := Format('%s:%d:%d %s%s', [DisplayPath(AStartDir, LMessage.FileName), LMessage.Line, LMessage.Column,
      IfThen(LMessage.Id > 0, '(' + IntToStr(LMessage.Id) + ') ', ''), LMessage.Text]);
    if IsFailing(AConfig, LMessage) then
    begin
      Inc(Result.Failing);
      OutputError(ABuilder, LTitle, LText);
    end
    else
      OutputInfo(ABuilder, LTitle, LText);
  end;

  // a build that failed without an error in the output still fails the lint
  if not LBuilt and (Result.Counts[lkError] = 0) then
    Inc(Result.Failing);
  Result.Ran := LBuilt;
  OutputInfo(ABuilder, 'Lint', Format('%s: %s', [DisplayPath(ARootDir, AMemberDir),
    FormatCounts(Result.Counts, Result.Ignored, Result.Failing)]));
end;

procedure LintWorkspace(ABuilder: ICommandBuilder; const AWorkspaceDir: string);
var
  LMember: TWorkspaceMember;
  LResult: TMemberLint;
  LCounts: array[TLintKind] of Integer;
  LKind: TLintKind;
  LCurrentDir, LLine: string;
  LLinted: Integer = 0;
  LIgnored: Integer = 0;
  LFailing: Integer = 0;
  LNotLinted: TArray<string> = [];
begin
  for LKind := Low(TLintKind) to High(TLintKind) do
    LCounts[LKind] := 0;
  LCurrentDir := GetCurrentDir;
  PrepareWorkspace(ABuilder, AWorkspaceDir);
  for LMember in SortMembersByDependency(GetWorkspaceMembers(AWorkspaceDir)) do
  begin
    ABuilder.Output('');
    OutputInfo(ABuilder, 'Linting', DisplayPath(AWorkspaceDir, LMember.Dir));
    LResult := LintMember(ABuilder, LMember.Dir, LMember.ProjectFile, AWorkspaceDir, LCurrentDir,
      LoadLintConfig(AWorkspaceDir, LMember.Name, DisplayPath(AWorkspaceDir, LMember.Dir)));
    if not LResult.Ran then
      LNotLinted := LNotLinted + [LMember.Name + IfThen(LResult.Error <> '', ': ' + LResult.Error, '')]
    else
      Inc(LLinted);
    for LKind := Low(TLintKind) to High(TLintKind) do
      Inc(LCounts[LKind], LResult.Counts[LKind]);
    Inc(LIgnored, LResult.Ignored);
    Inc(LFailing, LResult.Failing);
  end;

  ABuilder.Output('');
  OutputInfo(ABuilder, 'Workspace', Format('%s linted: %s', [Plural(LLinted, 'member'),
    FormatCounts(LCounts, LIgnored, LFailing)]));
  for LLine in LNotLinted do
    OutputError(ABuilder, 'Not linted', LLine);

  if (LFailing > 0) or (Length(LNotLinted) > 0) then
    ExitCode := 1;
end;

procedure LintProject(ABuilder: ICommandBuilder);
var
  LProjectDir, LProjectFile, LWorkspaceDir, LRelative: string;
  LResult: TMemberLint;
begin
  // the project of the current folder, or only its test project, like a library
  LProjectDir := ExcludeTrailingPathDelimiter(GetCurrentDir);
  LProjectFile := FindProject(LProjectDir, '');
  if SameText(ExtractFileExt(LProjectFile), '.lpr') then
    LProjectFile := ChangeFileExt(LProjectFile, '.lpi');
  if Length(MemberProjects(LProjectDir, LProjectFile)) = 0 then
  begin
    OutputError(ABuilder, 'Error', 'No project or test project found in the current folder.');
    ExitCode := 1;
    Exit;
  end;

  // a member of a workspace uses the configuration of the workspace
  LWorkspaceDir := FindWorkspaceRoot(LProjectDir);
  LRelative := '';
  if LWorkspaceDir <> '' then
    LRelative := DisplayPath(LWorkspaceDir, LProjectDir);
  LResult := LintMember(ABuilder, LProjectDir, LProjectFile, IfThen(LWorkspaceDir <> '', LWorkspaceDir,
    ExtractFileDir(LProjectDir)), LProjectDir,
    LoadLintConfig(LWorkspaceDir, ChangeFileExt(ExtractFileName(LProjectFile), ''), LRelative));
  if not LResult.Ran then
    OutputError(ABuilder, 'Not linted', LResult.Error);
  if (not LResult.Ran) or (LResult.Failing > 0) then
    ExitCode := 1;
end;

procedure LintCommand(ABuilder: ICommandBuilder);
var
  LWorkspaceDir: string;
begin
  try
    // at the root of a workspace, without a project of its own, lints every member
    LWorkspaceDir := FindWorkspaceRoot(GetCurrentDir);
    if (LWorkspaceDir <> '') and SameFileName(LWorkspaceDir, ExcludeTrailingPathDelimiter(GetCurrentDir)) and
       (FindProject(LWorkspaceDir, '') = '') then
      LintWorkspace(ABuilder, LWorkspaceDir)
    else
      LintProject(ABuilder);
  except
    on E: Exception do
    begin
      OutputError(ABuilder, 'Lint', E.Message);
      ExitCode := 1;
    end;
  end;
end;

procedure Registry(ABuilder: ICommandBuilder);
begin
  ABuilder
    .AddCommand(
      'lint',
      'shows the warnings, notes and hints of the compiler for your sources.'#13#10 +
      ''#13#10 +
      'This command builds the project in the current folder and its test project,'#13#10 +
      'or at the root of a workspace every member and its test project, with'#13#10 +
      'lazbuild -B into lib/lint, so the normal build is not touched. Only the'#13#10 +
      'messages for the sources of each member are shown, as file:line:col links,'#13#10 +
      'not the ones for the modules installed by boss.'#13#10 +
      ''#13#10 +
      'By default warnings fail, notes and hints are shown. In pasc.json:'#13#10 +
      '  "lint": { "ignore": [5024], "fail": ["warning", 5091],'#13#10 +
      '            "members": { "web": { "ignore": [5024] } } }'#13#10 +
      'ignore and fail take kinds (error, warning, note, hint) and message numbers.'#13#10 +
      'The exit code is 1 if a message fails or a project could not be built.'#13#10 +
      ''#13#10 +
      'Ex: ' + ABuilder.ExeName + ' lint',
      @LintCommand,
      [ccNoParameters]);
end;

end.
