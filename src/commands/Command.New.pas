/// <summary> This unit contains procedures to configure and execute a command to create 
/// a new free pascal/lazarus project. With also some basic repo initialization, boss
/// package manager ready and support to use vscode with pre configured tasks.
/// </summary>
unit Command.New;

{$MODE DELPHI}{$H+}

interface

uses
  Command.Interfaces;

  /// <summary> This command creates a freepascal/lazarus project respecting a previously 
  /// organized folder structure so that it is easier to operate the project in vscode, 
  /// with git previously initialized and ready to work with boss dependency manager.
  /// </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output user instructions about the execution state of this command. </param>
  procedure NewCommand(ABuilder: ICommandBuilder);

  /// <summary> Registry a new command using the command builder from pascli. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// registry the command. </param>
  procedure Registry(ABuilder: ICommandBuilder);

  {$IF DEFINED(TESTAPP)}

  /// <summary> Creates the project folders structure with a src and .vscode folders on 
  /// current path. Returns trough AProjectDir parameter the created folder. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output user instructions about the execution state of this command. </param>
  /// <param name="AProjectName">The project name that will be used as the main folder 
  /// name. </param>
  /// <param name="AProjectDir">Returns the created folder complete path that was created.
  /// </param>
  procedure CreateSupportFilesForVSCode(ABuilder: ICommandBuilder; const AProjectName, AProjectDir: string);

  /// <summary> Create the task and launch files for vscode. Within the tasks created 
  /// we have build, test build, test task using pasc to output the results. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output user instructions about the execution state of this command. </param>
  /// <param name="AProjectName">The project name that will be used as the file name
  /// for tasks and launch file. </param>
  /// <param name="AProjectDir">Project source path. </param>
  procedure CreateProjectFiles(ABuilder: ICommandBuilder; const AProjectName, AProjectDir: string);

  /// <summary> Configures the boss dependency manager to facilitate the installation of 
  /// new project dependencies. Returns the output of internal commands. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output user instructions about the execution state of this command. </param>
  /// <param name="AProjectDir">Project source path. </param>
  function InitializeBoss(ABuilder: ICommandBuilder; const AProjectDir: string): string;

  /// <summary> Adjust boss files, just change the source parameter to subfolder ./src.
  /// </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output user instructions about the execution state of this command. </param>
  /// <param name="AProjectDir">Project source path. </param>
  procedure ChangeBossFileSourcePath(ABuilder: ICommandBuilder; const AProjectDir: string);

  /// <summary> Init git repo on specified project folder and creates and .gitignore 
  /// file specific to object pascal repo. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output user instructions about the execution state of this command. </param>
  /// <param name="AProjectDir">Project source path. </param>
  procedure InitializeGit(ABuilder: ICommandBuilder; const AProjectDir: string);

  /// <summary> Creates the project folders structure with a src and .vscode folders on 
  /// current path. Returns trough AProjectDir parameter the created folder. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output user instructions about the execution state of this command. </param>
  /// <param name="AProjectName">The project name that will be used as the main folder 
  /// name. </param>
  /// <param name="AProjectDir">Returns the created folder complete path that was created.
  /// </param>
  procedure CreateProjectFolders(ABuilder: ICommandBuilder; const AProjectName: string; out AProjectDir: string);

  {$ENDIF}

implementation

uses
  Classes,
  SysUtils,
  StrUtils,
  Command.Colors,
  Utils.Boss,
  Utils.Shell,
  Utils.Resources,
  Utils.IO,
  Utils.Output;

procedure GuardShellCommand(ABuilder: ICommandBuilder; const ATitle, AOutput: string; const ACommandIsOptional: Boolean = false);
begin
  if not ContainsText(AOutput, 'Error when executing') then 
  begin
    if AOutput <> '' then
      OutputInfo(ABuilder, ATitle, AOutput, False);
    Exit;
  end;

  if ACommandIsOptional then
  begin
    if AOutput <> '' then
      OutputInfo(ABuilder, 'Warning', AOutput)
  end
  else
    raise Exception.Create(AOutput);
end;

procedure CreateProjectFolders(ABuilder: ICommandBuilder; const AProjectName: string; out AProjectDir: string);
begin
  AProjectDir := ConcatPaths([GetCurrentDir, AProjectName]);
  OutputInfo(ABuilder, 'Creating', 'project folders');

  if AProjectName = '' then
    raise Exception.Create('Project name not provided.');
  
  if DirectoryExists(AProjectDir) then
    raise Exception.Create('There is already a folder with this name in the current directory.');
  
  if FileExists(AProjectDir) then
    raise Exception.Create('There is already a file with this name in the current directory.');

  CreateDir(AProjectName);
  SetCurrentDir(AProjectDir);
  CreateDir('src');
  CreateDir('.vscode');
end;

procedure InitializeGit(ABuilder: ICommandBuilder; const AProjectDir: string);
var
  LGitOutput, LProjectName: string;
  LExitCode: Integer = 0;
begin
  SetCurrentDir(AProjectDir);
  LGitOutput := ShellCommand('git', ['init'], LExitCode);
  if LExitCode <> 0 then
    raise Exception.Create(LGitOutput);
  GuardShellCommand(ABuilder, 'git', LGitOutput, True);
  LProjectName := ExtractFileName(ExcludeTrailingPathDelimiter(AProjectDir));
  SaveFileContent(
    ConcatPaths([AProjectDir, '.gitignore']),
    GetResource('gitignore') + LineEnding +
    '# project executables' + LineEnding +
    '/' + LProjectName + LineEnding +
    '/tests/Test' + LProjectName + LineEnding);
end;

procedure ChangeBossFileSourcePath(ABuilder: ICommandBuilder; const AProjectDir: string);
var
  LFile, LContent: string;
begin
  LFile := ConcatPaths([AProjectDir, 'boss.json']);
  if FileExists(LFile) then
  begin
    OutputInfo(ABuilder, 'boss', 'adjusting "mainsrc" boss file attribute');
    LContent := GetFileContent(LFile);
    LContent := StringReplace(LContent, '"mainsrc": "./"', '"mainsrc": "src/"', [rfReplaceAll]);
    SaveFileContent(LFile, LContent);
  end;
end;

function InitializeBoss(ABuilder: ICommandBuilder; const AProjectDir: string): string;
var
  LOutput, LDisplay: string;
  LExitCode: Integer = 0;
  LNoiseFound: Boolean = False;
begin
  SetCurrentDir(AProjectDir);
  OutputInfo(ABuilder, 'boss', 'Initializing boss dependency manager');
  {$IF DEFINED(LINUX)}
  LOutput := ShellCommand('/bin/sh', ['-c', 'boss init --quiet'], LExitCode);
  {$ELSE}
  LOutput := ShellCommand('boss', ['init', '--quiet'], LExitCode);
  {$ENDIF}

  // boss output has cursor control sequences and, outside Windows, errors from its
  // Delphi-only internal tools; --verbose shows it as is
  if ABuilder.CheckOption('verbose') then
    LDisplay := LOutput
  else
  begin
    LDisplay := FilterBossOutput(LOutput, {$IF DEFINED(WINDOWS)}False{$ELSE}True{$ENDIF}, LNoiseFound);
    if LDisplay <> '' then
      LDisplay := LDisplay + LineEnding;
  end;

  if LNoiseFound then
    OutputInfo(ABuilder, 'boss', 'initialized (Delphi-only internal tools skipped on this platform)');
  if LExitCode <> 0 then
    LDisplay := LDisplay + #13#10'Warning: boss exit code: ' + LExitCode.ToString + #13#10;
  GuardShellCommand(ABuilder, 'boss', LDisplay, True);
  ChangeBossFileSourcePath(ABuilder, AProjectDir);
  Result := LOutput;
end;

procedure CreateProjectFiles(ABuilder: ICommandBuilder; const AProjectName, AProjectDir: string);
var
  LFile: TStringList = nil;
  LContent: string;
begin
  try
    OutputInfo(ABuilder, 'Creating', 'project files');
    SetCurrentDir(AProjectDir);
   
    LFile := TStringList.Create;

    LContent := GetResource('projectlpr');
    LContent := StringReplace(LContent, '{PROJECTNAME}', AProjectName, [rfReplaceAll]);
    LFile.AddText(LContent);
    LFile.SaveToFile(ConcatPaths([AProjectDir, AProjectName + '.lpr']));

    LContent := GetResource('projectlpi');
    LContent := StringReplace(LContent, '{PROJECTNAME}', AProjectName, [rfReplaceAll]);
    LFile.Clear;
    LFile.AddText(LContent);
    LFile.SaveToFile(ConcatPaths([AProjectDir, AProjectName + '.lpi']));

    LFile.Free;
  except
    on E: Exception do
    begin
      FreeAndNil(LFile);
      raise;
    end;
  end;  
end;

procedure CreateSupportFilesForVSCode(ABuilder: ICommandBuilder; const AProjectName, AProjectDir: string);
var
  LFile: TStringList = nil;
  LContent: string;
begin
  try
    OutputInfo(ABuilder, 'Creating', 'vs code tasks and launch files');
    SetCurrentDir(AProjectDir);
   
    LFile := TStringList.Create;

    LContent := GetResource('launchjson');
    LContent := StringReplace(LContent, '{PROJECTNAME}', AProjectName, [rfReplaceAll]);
    LFile.AddText(LContent);
    LFile.SaveToFile(ConcatPaths([AProjectDir, '.vscode', 'launch.json']));

    LContent := GetResource('tasksjson');
    LContent := StringReplace(LContent, '{PROJECTNAME}', AProjectName, [rfReplaceAll]);
    LFile.Clear;
    LFile.AddText(LContent);
    LFile.SaveToFile(ConcatPaths([AProjectDir, '.vscode', 'tasks.json']));

    LFile.Free;
  except
    on E: Exception do
    begin
      FreeAndNil(LFile);
      raise;
    end;
  end;  
end;

procedure NewCommand(ABuilder: ICommandBuilder);
var
  LProjectDir: string = '';
begin
  ABuilder.GetParsedArguments;

  if not ABuilder.HasArguments then
  begin
    OutputError(ABuilder, 'error', 'New command requires builder to accept an argument.');
    exit;
  end;

  if ABuilder.HasCommands then
  begin
    OutputInfo(ABuilder, 'Running', 'pasc new command for ', False);
    ABuilder.OutputColor(ABuilder.Arguments[0].Value + #13#10, ABuilder.ColorTheme.Value);
  end;

  try
    CreateProjectFolders(ABuilder, ABuilder.Arguments[0].Value, LProjectDir);
    CreateProjectFiles(ABuilder, ABuilder.Arguments[0].Value, LProjectDir);
    CreateSupportFilesForVSCode(ABuilder, ABuilder.Arguments[0].Value, LProjectDir);
    InitializeGit(ABuilder, LProjectDir);
    InitializeBoss(ABuilder, LProjectDir);
    OutputInfo(ABuilder, 'Project', 'was created successfully.');
  except
    on E: Exception do
    begin
      ABuilder.OutputColor(E.Message, ABuilder.ColorTheme.Error);
    end;
  end;
end;

procedure Registry(ABuilder: ICommandBuilder);
begin
  ABuilder
    .AddCommand(
      'new',
      'Creates a new free pascal program.'#13#10 +
      'From the current path create a subfolder with the given project name, '#13#10 +
      'initialize git, initialize the boss dependency manager, create build '#13#10 +
      'and debug support files for use with vscode and create a project based '#13#10 +
      'on a simple free pascal template.'#13#10 +
      'Ex: pasc new <project name>',
      @NewCommand,
      [ccRequiresOneArgument])
      .AddOption(
        'v',
        'verbose',
        'shows the boss output as is, without removing the Delphi-only messages.',
        []);
end;

end.
