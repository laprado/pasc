/// <summary> This unit contains procedures to configure and execute a command to install
/// the boss dependencies of a workspace and make them available to every member.
/// </summary>
unit Command.Deps;

{$MODE DELPHI}{$H+}

interface

uses
  Command.Interfaces;

  /// <summary> This command runs boss install at the root of the current workspace, even when
  /// called inside a member, so the whole workspace has a single boss.json and modules folder.
  /// Then it updates the search paths of every member (and its test project) with the source
  /// folders of the installed modules, relative to each member.
  ///
  /// boss "projects" attribute is not used because boss writes those paths relative to the
  /// workspace root, while lazarus resolves them relative to each project file.
  /// </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output user instructions about the execution state of this command. </param>
  procedure DepsCommand(ABuilder: ICommandBuilder);

  /// <summary> Registry a deps command using the command builder from pascli. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// registry the command. </param>
  procedure Registry(ABuilder: ICommandBuilder);

  /// <summary> Updates the search paths of every workspace member and of its test project with
  /// the source folders of the modules installed by boss. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output the updated files. </param>
  /// <param name="AWorkspaceDir"> Workspace root folder. </param>
  procedure SyncWorkspaceModules(ABuilder: ICommandBuilder; const AWorkspaceDir: string);

implementation

uses
  Classes,
  SysUtils,
  StrUtils,
  Utils.Boss,
  Utils.IO,
  Utils.Output,
  Utils.Shell,
  Utils.Workspace;

function IsValidDependency(const ADependency: string): Boolean;
var
  LChar: Char;
begin
  // a boss dependency like github.com/user/repo or github.com/user/repo@^1.0.0
  Result := ADependency <> '';
  for LChar in ADependency do
    if not (LChar in ['A'..'Z', 'a'..'z', '0'..'9', '.', '/', '-', '_', '@', ':', '^', '~']) then
      Exit(False);
end;

function RunBossInstall(ABuilder: ICommandBuilder; const AWorkspaceDir, ADependency: string): Boolean;
var
  LOutput, LDisplay, LCommand: string;
  LExitCode: Integer = 0;
  LNoiseFound: Boolean = False;
  LCurrentDir: string;
begin
  LCommand := 'boss install' + IfThen(ADependency <> '', ' ' + ADependency, '');
  OutputInfo(ABuilder, 'boss', LCommand);

  LCurrentDir := GetCurrentDir;
  SetCurrentDir(AWorkspaceDir);
  try
    {$IF DEFINED(LINUX)}
    LOutput := ShellExecute('/bin/sh', ['-c', LCommand], LExitCode);
    {$ELSE}
    if ADependency <> '' then
      LOutput := ShellExecute('boss', ['install', ADependency], LExitCode)
    else
      LOutput := ShellExecute('boss', ['install'], LExitCode);
    {$ENDIF}
  finally
    SetCurrentDir(LCurrentDir);
  end;

  if ABuilder.CheckOption('verbose') then
    LDisplay := LOutput
  else
    LDisplay := FilterBossOutput(LOutput, {$IF DEFINED(WINDOWS)}False{$ELSE}True{$ENDIF}, LNoiseFound);
  if Trim(LDisplay) <> '' then
    ABuilder.Output(LDisplay);
  if LNoiseFound then
    OutputInfo(ABuilder, 'boss', 'Delphi-only internal tools skipped on this platform');

  Result := LExitCode = 0;
  if not Result then
  begin
    OutputError(ABuilder, 'boss', 'exit code ' + IntToStr(LExitCode));
    ExitCode := LExitCode;
  end;
end;

procedure SyncProject(ABuilder: ICommandBuilder; const AWorkspaceDir, AProjectFile: string;
  const AModuleDirs: TArray<string>);
begin
  if SyncModulePaths(AProjectFile, AWorkspaceDir, AModuleDirs) then
    OutputInfo(ABuilder, 'Updating', ExtractRelativePath(
      IncludeTrailingPathDelimiter(AWorkspaceDir), AProjectFile));
end;

procedure SyncWorkspaceModules(ABuilder: ICommandBuilder; const AWorkspaceDir: string);
var
  LModuleDirs, LMissing: TArray<string>;
  LMember: TWorkspaceMember;
  LTestProject: string;
begin
  LModuleDirs := GetModuleSourceDirs(AWorkspaceDir);
  OutputInfo(ABuilder, 'Modules', IntToStr(Length(LModuleDirs)) + ' source folders found in the workspace modules');

  for LMember in GetWorkspaceMembers(AWorkspaceDir) do
  begin
    if FileExists(ConcatPaths([LMember.Dir, 'boss.json'])) then
      OutputError(ABuilder, 'Warning',
        LMember.Name + ' has its own boss.json, the workspace dependencies belong to the root boss.json');

    SyncProject(ABuilder, AWorkspaceDir, LMember.ProjectFile, LModuleDirs);
    LTestProject := GetMemberTestProject(LMember.Dir);
    if LTestProject <> '' then
      SyncProject(ABuilder, AWorkspaceDir, LTestProject, LModuleDirs);
  end;

  LMissing := GetModulesMissingFromLock(AWorkspaceDir);
  if Length(LMissing) > 0 then
    OutputError(ABuilder, 'Warning',
      'boss-lock.json records module folders that are not in modules: ' + string.Join(', ', LMissing) +
      '. The lock was written by another boss version (boss 3.x names them github_com_<user>_<repo>, ' +
      'older versions use the repository name), so the search paths only match the boss of this machine. ' +
      'Use the same boss version everywhere, locally and in the CI.');
end;

procedure DepsCommand(ABuilder: ICommandBuilder);
var
  LWorkspaceDir, LDependency: string;
begin
  LWorkspaceDir := FindWorkspaceRoot(GetCurrentDir);
  if LWorkspaceDir = '' then
  begin
    OutputError(ABuilder, 'Error',
      'The deps command must be used inside a workspace, ' + WORKSPACE_FILE + ' was not found. ' +
      'In a single project use boss install.');
    ExitCode := 1;
    Exit;
  end;

  LDependency := '';
  if Length(ABuilder.GetParsedArguments) > 0 then
    LDependency := Trim(ABuilder.GetParsedArguments[0].Value);
  if (LDependency <> '') and not IsValidDependency(LDependency) then
  begin
    OutputError(ABuilder, 'Error', 'Invalid dependency: ' + LDependency);
    ExitCode := 1;
    Exit;
  end;

  if not SameFileName(LWorkspaceDir, ExcludeTrailingPathDelimiter(GetCurrentDir)) then
    OutputInfo(ABuilder, 'Workspace', 'dependencies are installed at the root ' + LWorkspaceDir);

  try
    if not RunBossInstall(ABuilder, LWorkspaceDir, LDependency) then
      Exit;
    SyncWorkspaceModules(ABuilder, LWorkspaceDir);
    OutputInfo(ABuilder, 'Done', 'workspace dependencies installed');
  except
    on E: Exception do
    begin
      OutputError(ABuilder, 'Error', E.Message);
      ExitCode := 1;
    end;
  end;
end;

procedure Registry(ABuilder: ICommandBuilder);
begin
  ABuilder
    .AddCommand(
      'deps',
      'installs the boss dependencies of a workspace.'#13#10 +
      'Runs boss install at the workspace root, even inside a member, and updates the '#13#10 +
      'search paths of every member and test project with the installed modules, '#13#10 +
      'relative to each one. A dependency can be provided to be added to boss.json.'#13#10 +
      'The module folder names depend on the boss version, so the workspace should use '#13#10 +
      'the same boss version everywhere, locally and in the CI.'#13#10 +
      'Ex: ' + ABuilder.ExeName + ' deps'#13#10 +
      'Ex: ' + ABuilder.ExeName + ' deps github.com/user/repo',
      @DepsCommand,
      [])
      .AddOption(
        'v',
        'verbose',
        'shows the boss output as is, without removing the Delphi-only messages.',
        []);
end;

end.
