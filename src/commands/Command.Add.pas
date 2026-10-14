/// <summary> This unit contains procedures to configure and execute a command to add 
/// a new free pascal/lazarus unit tests project based on fpcunit test framework.
/// Also allows to add code documentation capabilities to the project base on pasdoc
/// </summary>
unit Command.Add;

{$MODE DELPHI}{$H+}

interface

uses
  Command.Interfaces;

  /// <summary> This command adds features to the project like a unit tests project creating a
  /// tests subfolder, or adds code documentation capabilities to the project base on pasdoc.
  /// </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output user instructions about the execution state of this command. </param>
  procedure AddCommand(ABuilder: ICommandBuilder);

  /// <summary> Registry a add command using the command builder from pascli. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// registry the command. </param>
  procedure Registry(ABuilder: ICommandBuilder);

  {$IF DEFINED(TESTAPP)}

  /// <summary> Create the task and launch files for vscode. Within the tasks created 
  /// we have build, test build, test task using pasc to output the results. </summary>
  /// <param name="AProjectName">The project name that will be used as the file name
  /// for tasks and launch file. </param>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output user instructions about the execution state of this command. </param>
  /// <param name="AProjectDir">Project source path. </param>
  procedure CreateTestProjectFiles(ABuilder: ICommandBuilder; const AProjectName, AProjectDir: string);

  /// <summary> Create docs folder, generate sub folder for documetation build using pasdoc. Add 
  /// minimal template files for documentation. Add an item to tasks.json to run docs/generate/build.ps1 
  /// script. This script will call pasdoc to generate code documentation. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output user instructions about the execution state of this command. </param>  
  /// <param name="AProjectName">The project name that will be used to create the documentation
  /// </param>
  /// <param name="AProjectDir">Project source path. </param>
  procedure CreateDocsFiles(ABuilder: ICommandBuilder; const AProjectName, AProjectDir: string);

  {$ENDIF}

implementation

uses
  Classes,
  SysUtils,
  StrUtils,
  Command.Colors,
  Utils.IO,
  Utils.Output,
  Utils.Resources;

procedure CreateTestProjectFiles(ABuilder: ICommandBuilder; const AProjectName, AProjectDir: string);
var
  LContent, LTestsDir, LTestProject, LProjectName: string;
begin
  try
    OutputInfo(ABuilder, 'Starting', 'to add a test project to the current folder'); 

    LTestsDir := ConcatPaths([AProjectDir, 'tests']);
    LProjectName := AProjectName;
    LTestProject := 'Test' + LProjectName;
    SetCurrentDir(AProjectDir);

    OutputInfo(ABuilder, 'Creating', 'tests sub folder'); 

    if not DirectoryExists(LTestsDir) then
      CreateDir('tests');

    OutputInfo(ABuilder, 'Creating', 'test project files');    

    LContent := GetResource('fpcunitprojectlpr');
    LContent := StringReplace(LContent, '{TESTPROJECTNAME}', LTestProject, [rfReplaceAll]);
    LContent := StringReplace(LContent, '{TestCase1}', 'TestCase' + LProjectName, [rfReplaceAll]);
    SaveFileContent(ConcatPaths([LTestsDir, LTestProject + '.lpr']), LContent);
    
    LContent := GetResource('fpcunitprojectlpi');
    LContent := StringReplace(LContent, '{TESTPROJECTNAME}', LTestProject, [rfReplaceAll]);
    LContent := StringReplace(LContent, '{TestCase1}', 'TestCase' + LProjectName, [rfReplaceAll]);
    SaveFileContent(ConcatPaths([LTestsDir, LTestProject + '.lpi']), LContent);
    
    LContent := GetResource('testcase1pas');
    LContent := StringReplace(LContent, '{TestCase1}', 'TestCase' + LProjectName, [rfReplaceAll]);
    SaveFileContent(ConcatPaths([LTestsDir, 'TestCase' + LProjectName + '.pas']), LContent);
    
    OutputInfo(ABuilder, 'Done', 'test project added with success'); 

  except
    on E: Exception do
    begin
      raise;
    end;
  end;  
end;

procedure CreateDocsFiles(ABuilder: ICommandBuilder; const AProjectName, AProjectDir: string);
var
  LContent, LDocsDir: string;
begin
  OutputInfo(ABuilder, 'Docs', 'adding documentation resources to the project'); 
  OutputInfo(ABuilder, 'Creating', 'docs sub folder'); 

  LDocsDir := ConcatPaths([AProjectDir, 'docs']);
  if not DirectoryExists(LDocsDir) then
  begin
    SetCurrentDir(AProjectDir);
    CreateDir('docs');
  end;

  LDocsDir := ConcatPaths([LDocsDir, 'generate']);
  if not DirectoryExists(LDocsDir) then
  begin
    SetCurrentDir(ConcatPaths([AProjectDir, 'docs']));
    CreateDir('generate');
  end;

  SetCurrentDir(AProjectDir);

  OutputInfo(ABuilder, 'Creating', 'documentation resource files'); 
  
  LContent := GetResource('buildps1');
  LContent := StringReplace(LContent, '{PROJECTNAME}', AProjectName, [rfReplaceAll]);
  SaveFileContent(ConcatPaths([LDocsDir, 'build.ps1']), LContent);

  LContent := GetResource('customcss');
  SaveFileContent(ConcatPaths([LDocsDir, 'custom.css']), LContent);

  LContent := GetResource('introduction');
  LContent := StringReplace(LContent, '{PROJECTNAME}', AProjectName, [rfReplaceAll]);
  SaveFileContent(ConcatPaths([LDocsDir, 'introduction.txt']), LContent);

  LContent := GetResource('quickstart');
  SaveFileContent(ConcatPaths([LDocsDir, 'quickstart.txt']), LContent);
  
  OutputInfo(ABuilder, 'Done', 'documentation resources added with success'); 
end;

procedure AddCommand(ABuilder: ICommandBuilder);
var
  LProjectDir: string = '';
  LAddTests, LAddDocs: Boolean;
  LProjectName: string;
  LSourceFound: Boolean = false;
begin
  LAddTests := ABuilder.CheckOption('tests');
  LAddDocs := ABuilder.CheckOption('docs');
  try
    OutputInfo(ABuilder, ABuilder.ExeName, 'running command Add');
    LProjectDir := GetCurrentDir;
    LProjectName := FindProjectFile(LProjectDir, '');
    LSourceFound := FindSourceFile(LProjectDir) <> '';

    if (not LAddTests) and (not LAddDocs) then
    begin
      OutputInfo(ABuilder, 'Error', 'you must specify at least one of the options --tests or --docs');
      Exit;
    end;

    OutputInfo(ABuilder, 'Project', IfThen(LProjectName = '', 'not found', LProjectName));
    // the project file is a source file too, so this is only relevant without a project
    if LProjectName = '' then
      OutputInfo(ABuilder, 'Source', 
        IfThen(LSourceFound, 'at least one pascal file detected', 'No pascal source file found'));

    if (not (LProjectName <> '')) and (not LSourceFound) then
      raise Exception.Create('No project or source file found in current directory.');

    if LAddTests then
    begin
      if DirectoryExists(ConcatPaths([LProjectDir, 'tests'])) then
        raise Exception.Create('There is already a tests folder in the current directory.');
      CreateTestProjectFiles(ABuilder, ExtractFileName(LProjectDir), LProjectDir);
    end;

    if LAddDocs then
    begin
      if DirectoryExists(ConcatPaths([LProjectDir, 'docs'])) then
        raise Exception.Create('There is already a docs folder in the current directory.');
      CreateDocsFiles(ABuilder, ExtractFileName(LProjectDir), LProjectDir);
    end;
      
  except
    on E: Exception do
    begin
      OutputError(ABuilder, 'Error', E.Message);
    end;
  end;
end;

procedure Registry(ABuilder: ICommandBuilder);
begin
  ABuilder
    .AddCommand(
      'add',
      'adds a unit test project or documentation capabilities to an existing project.'#13#10 +
      'For this command to work you need to provide at least one option. '#13#10 +
      'Ex: pasc add <option>',
      @AddCommand,
      [ccRequiresOneOption])
      .AddOption(
        't',
        'tests',
        'adds a unit test project based on fpcunit test framework. ',
        [])
      .AddOption(
        'd',
        'docs',
        'adds resources that automates the project documentation.',
        []);
end;

end.