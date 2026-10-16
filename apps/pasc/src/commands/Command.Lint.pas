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
  Math,
  fpjson,
  Command.Build,
  Command.Colors,
  Command.Check,
  Command.Test,
  Utils.IO,
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
    /// <summary> Source files of the member that were compiled or have a message. </summary>
    Files: Integer;
    /// <summary> Files without a message shown. </summary>
    FilesOK: Integer;
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

/// <summary> Files and messages, without the kinds with none, so the line fits in the console,
/// like 7 files, 5 OK, 1 warning, 1 hint, 1 failing. </summary>
function FormatCounts(const AFiles, AFilesOK: Integer; const ACounts: array of Integer;
  const AIgnored, AFailing: Integer): string;
var
  LKind: TLintKind;
begin
  Result := Format('%s, %d OK', [Plural(AFiles, 'file'), AFilesOK]);
  for LKind := Low(TLintKind) to High(TLintKind) do
    if ACounts[Ord(LKind)] > 0 then
      Result := Result + ', ' + Plural(ACounts[Ord(LKind)], LintKindName(LKind));
  Result := Result + IfThen(AIgnored > 0, Format(' (%d ignored)', [AIgnored]), '') + Format(', %d failing', [AFailing]);
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

function KindTitle(const AKind: TLintKind): string;
begin
  Result := UpperCase(Copy(LintKindName(AKind), 1, 1)) + Copy(LintKindName(AKind), 2, MaxInt);
end;

/// <summary> The messages shown for a file, sorted by line and column. </summary>
function FileMessages(const AMessages: TLintMessages; const AFileName: string): TLintMessages;
var
  LMessage, LSwap: TLintMessage;
  I, J: Integer;
begin
  Result := [];
  for LMessage in AMessages do
    if SameFileName(LMessage.FileName, AFileName) then
      Result := Result + [LMessage];
  for I := 1 to High(Result) do
  begin
    J := I;
    while (J > 0) and ((Result[J - 1].Line > Result[J].Line) or
      ((Result[J - 1].Line = Result[J].Line) and (Result[J - 1].Column > Result[J].Column))) do
    begin
      LSwap := Result[J - 1];
      Result[J - 1] := Result[J];
      Result[J] := LSwap;
      Dec(J);
    end;
  end;
end;

/// <summary> Outputs a file with the title of its most severe message, or OK, and its messages
/// below it. A failing message has the whole file:line:col, which editors turn into a link.
/// </summary>
procedure OutputFile(ABuilder: ICommandBuilder; const AFileName, AMemberDir, AStartDir: string;
  const AMessages: TLintMessages; const AConfig: TLintConfig);
var
  LMessage: TLintMessage;
  LWorst: TLintKind;
  LFailing: Boolean;
  LText: string;
begin
  if Length(AMessages) = 0 then
  begin
    ABuilder.OutputColor(PadLeft('OK ', 13), LightGreen);
    ABuilder.OutputColor(DisplayPath(AMemberDir, AFileName) + #13#10, ABuilder.ColorTheme.Other);
    Exit;
  end;

  LWorst := High(TLintKind);
  LFailing := False;
  for LMessage in AMessages do
  begin
    if LMessage.Kind < LWorst then
      LWorst := LMessage.Kind;
    LFailing := LFailing or IsFailing(AConfig, LMessage);
  end;
  ABuilder.OutputColor(PadLeft(KindTitle(LWorst) + ' ', 13), IfThen(LFailing, ABuilder.ColorTheme.Error, Yellow));
  ABuilder.OutputColor(DisplayPath(AMemberDir, AFileName) + #13#10, ABuilder.ColorTheme.Other);

  for LMessage in AMessages do
  begin
    LText := Format('%d:%d %s%s%s', [LMessage.Line, LMessage.Column,
      IfThen(LMessage.Id > 0, '(' + IntToStr(LMessage.Id) + ') ', ''),
      IfThen(AnsiMatchText(KindTitle(LMessage.Kind), [KindTitle(LWorst)]), '', LintKindName(LMessage.Kind) + ': '),
      LMessage.Text]);
    if IsFailing(AConfig, LMessage) then
      ABuilder.OutputColor(StringOfChar(' ', 15) + DisplayPath(AStartDir, AFileName) + ':' + LText + #13#10,
        ABuilder.ColorTheme.Error)
    else
      ABuilder.OutputColor(StringOfChar(' ', 15) + LText + #13#10, ABuilder.ColorTheme.Other);
  end;
end;

function LintMember(ABuilder: ICommandBuilder; const AMemberDir, AProjectFile, ARootDir, AStartDir: string;
  const AConfig: TLintConfig): TMemberLint;
var
  LProject, LOutput, LError, LFile: string;
  LMessages, LShown, LMessagesOfFile: TLintMessages;
  LMessage: TLintMessage;
  LProjects, LCompiled, LFiles: TArray<string>;
  LSorted: TStringList;
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
  LCompiled := [];
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
    LCompiled := LCompiled + ParseCompiledFiles(LOutput, ExtractFileDir(ExpandFileName(LProject)));
  end;

  LShown := [];
  for LMessage in FilterMemberMessages(LMessages, AMemberDir) do
    if IsIgnored(AConfig, LMessage) then
      Inc(Result.Ignored)
    else
    begin
      LShown := LShown + [LMessage];
      Inc(Result.Counts[LMessage.Kind]);
      if IsFailing(AConfig, LMessage) then
        Inc(Result.Failing);
    end;

  // every source of the member that was compiled, like the tests of pasc test, and the
  // files with a message, like an error in a module or an include file
  LFiles := FilterMemberFiles(LCompiled, AMemberDir);
  LSorted := TStringList.Create;
  try
    LSorted.Sorted := True;
    LSorted.Duplicates := dupIgnore;
    for LFile in LFiles do
      LSorted.Add(LFile);
    for LMessage in LShown do
      LSorted.Add(LMessage.FileName);
    for LFile in LSorted do
    begin
      LMessagesOfFile := FileMessages(LShown, LFile);
      OutputFile(ABuilder, LFile, AMemberDir, AStartDir, LMessagesOfFile, AConfig);
      Inc(Result.Files);
      if Length(LMessagesOfFile) = 0 then
        Inc(Result.FilesOK);
    end;
  finally
    LSorted.Free;
  end;

  // a build that failed without an error in the output still fails the lint
  if not LBuilt and (Result.Counts[lkError] = 0) then
    Inc(Result.Failing);
  Result.Ran := LBuilt;
  OutputInfo(ABuilder, 'Summary', Format('%s: %s', [DisplayPath(ARootDir, AMemberDir),
    FormatCounts(Result.Files, Result.FilesOK, Result.Counts, Result.Ignored, Result.Failing)]));
end;

/// <summary> Adds the counts of a member to the totals. </summary>
procedure AddCounts(var ATotal: TMemberLint; const AMember: TMemberLint);
var
  LKind: TLintKind;
begin
  for LKind := Low(TLintKind) to High(TLintKind) do
    Inc(ATotal.Counts[LKind], AMember.Counts[LKind]);
  Inc(ATotal.Ignored, AMember.Ignored);
  Inc(ATotal.Failing, AMember.Failing);
  Inc(ATotal.Files, AMember.Files);
  Inc(ATotal.FilesOK, AMember.FilesOK);
end;

/// <summary> Writes the totals as JSON to the file of --report, for a CI, like a badge.
/// </summary>
procedure WriteReport(ABuilder: ICommandBuilder; const ATotal: TMemberLint; const ANotLinted: Integer);
var
  LFileName: string = '';
  LJson: TJSONObject;
  LKind: TLintKind;
begin
  if not ABuilder.CheckOption('report', LFileName) or (Trim(LFileName) = '') then
    Exit;
  LJson := TJSONObject.Create;
  try
    LJson.Add('files', ATotal.Files);
    LJson.Add('ok', ATotal.FilesOK);
    for LKind := Low(TLintKind) to High(TLintKind) do
      LJson.Add(LintKindName(LKind) + 's', ATotal.Counts[LKind]);
    LJson.Add('ignored', ATotal.Ignored);
    LJson.Add('failing', ATotal.Failing);
    LJson.Add('notLinted', ANotLinted);
    ForceDirectories(ExtractFileDir(ExpandFileName(LFileName)));
    SaveFileContent(LFileName, LJson.FormatJSON + LineEnding);
  finally
    LJson.Free;
  end;
end;

procedure LintWorkspace(ABuilder: ICommandBuilder; const AWorkspaceDir: string);
var
  LMember: TWorkspaceMember;
  LResult, LTotal: TMemberLint;
  LCurrentDir, LLine: string;
  LLinted: Integer = 0;
  LNotLinted: TArray<string> = [];
begin
  LTotal := Default(TMemberLint);
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
    AddCounts(LTotal, LResult);
  end;

  ABuilder.Output('');
  OutputInfo(ABuilder, 'Workspace', Format('%s linted: %s', [Plural(LLinted, 'member'),
    FormatCounts(LTotal.Files, LTotal.FilesOK, LTotal.Counts, LTotal.Ignored, LTotal.Failing)]));
  for LLine in LNotLinted do
    OutputError(ABuilder, 'Not linted', LLine);
  WriteReport(ABuilder, LTotal, Length(LNotLinted));

  if (LTotal.Failing > 0) or (Length(LNotLinted) > 0) then
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
  WriteReport(ABuilder, LResult, IfThen(LResult.Ran, 0, 1));
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
      'lazbuild -B into lib/lint, so the normal build is not touched. It lists'#13#10 +
      'each source file of the members, OK or with its messages, and a summary.'#13#10 +
      'The messages for the modules installed by boss are not shown.'#13#10 +
      ''#13#10 +
      'By default warnings fail, notes and hints are shown. In pasc.json:'#13#10 +
      '  "lint": { "ignore": [5024], "fail": ["warning", 5091],'#13#10 +
      '            "members": { "web": { "ignore": [5024] } } }'#13#10 +
      'ignore and fail take kinds (error, warning, note, hint) and message numbers.'#13#10 +
      'The exit code is 1 if a message fails or a project could not be built.'#13#10 +
      ''#13#10 +
      'Ex: ' + ABuilder.ExeName + ' lint'#13#10 +
      'Ex: ' + ABuilder.ExeName + ' lint --report=lint.json',
      @LintCommand,
      [ccNoParameters])
      .AddOption(
        'r',
        'report',
        'writes the totals as JSON to the given file, for a CI or a badge.',
        [],
        ocRequiresValue);
end;

end.
