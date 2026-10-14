unit TestCommandNew;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, 
  SysUtils, 
  fpcunit, 
  testregistry,
  Command.Interfaces,
  Command.Builder;

type

  TTestCommandNew= class(TTestCase)
  private
    FBuilder: ICommandBuilder;
    FExeName: string;
    FWorkingFolder: string;
    FCurrentDir: string;

  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNewCommandRegistry;    
    procedure TestNewCommandBasic;
    procedure TestCreateSupportFilesForVSCode;
    procedure TestCreateProjectFiles;
    procedure TestInitializeBoss;
    procedure TestChangeBossFileSourcePath;
    procedure TestInitializeGit;
    procedure TestCreateProjectFolders;
    procedure TestCreateWorkspace;
    procedure TestCreateWorkspaceApp;
    procedure TestCreateWorkspacePackage;
    procedure TestCreateWorkspaceMemberInvalidName;
    procedure TestNewCommandAppRequiresWorkspace;
    procedure TestNewCommandInsideWorkspaceRequiresMemberOption;
    procedure TestNewCommandAppFromWorkspaceSubfolder;
  end;

implementation

uses
  Resources,
  StrUtils,
  MockCommandBuilder,
  Command.New,
  Command.Clean,
  Utils.IO,
  Utils.Shell,
  Utils.Workspace;

procedure TTestCommandNew.SetUp;
begin
  FCurrentDir := GetCurrentDir;
  FExeName := ExtractFileName(ParamStr(0));
  FBuilder := TCommandBuilder.Create(FExeName);
  MockSetup(FBuilder);
  Command.New.Registry(FBuilder);

  FWorkingFolder := ConcatPaths([GetTempDir, '.' + ChangeFileExt(FExeName, '')]);
  AnsweredAll := True;
    
  // clean old data
  if DirectoryExists(FWorkingFolder) then
    DeleteFolder(FBuilder, GetTempDir, '.' + ChangeFileExt(FExeName, ''));

  // create new working folder
  SetCurrentDir(GetTempDir);
  CreateDir('.' + ChangeFileExt(FExeName, ''));
  SetCurrentDir(FWorkingFolder);
end;

procedure TTestCommandNew.TearDown;
begin
  SetCurrentDir(FCurrentDir);
  AnsweredAll := False;
end;

procedure TTestCommandNew.TestNewCommandRegistry;
begin
  AssertEquals('new', FBuilder.Commands[0].Name);
end;

procedure TTestCommandNew.TestNewCommandBasic;
var
  LProjectDir: string;
begin
  // arrange
  FBuilder.AddArgument('project file name', acOptional);
  FBuilder.UseArguments(['new', 'sample_test']);
  FBuilder.Parse;
  
  // act
  NewCommand(FBuilder);
  
  // assert
  LProjectDir := GetCurrentDir;  
  AssertTrue(
    'Current path should contain the project name "sample_test". Check: ' + LProjectDir,
    ContainsText(LProjectDir, 'sample_test'));
end;

procedure TTestCommandNew.TestCreateSupportFilesForVSCode;
var
  LProjectFolder, LExpected: string;
begin
  CreateProjectFolders(FBuilder, 'sample_test', LProjectFolder);
  CreateSupportFilesForVSCode(FBuilder, 'sample_test', LProjectFolder);

  LExpected := ConcatPaths([LProjectFolder, '.vscode', 'tasks.json']);
  AssertTrue(
    'vscode tasks file "' + LExpected + '" does not exist',
    FileExists(LExpected));

  LExpected := ConcatPaths([LProjectFolder, '.vscode', 'launch.json']);
  AssertTrue(
    'vscode launch file "' + LExpected + '" does not exist',
    FileExists(LExpected));
end;

procedure TTestCommandNew.TestCreateProjectFiles;
var
  LProjectFolder, LExpected: string;
begin
  CreateProjectFolders(FBuilder, 'sample_test', LProjectFolder);
  CreateProjectFiles(FBuilder, 'sample_test', LProjectFolder);

  LExpected := ConcatPaths([LProjectFolder, 'sample_test.lpi']);
  AssertTrue(
    'Project file "' + LExpected + '" does not exist',
    FileExists(LExpected));

  LExpected := ConcatPaths([LProjectFolder, 'sample_test.lpr']);
  AssertTrue(
    'Project file "' + LExpected + '" does not exist',
    FileExists(LExpected));
end;

procedure TTestCommandNew.TestInitializeBoss;
var
  LProjectFolder, LExpected, LOutput: string;
begin
  CreateProjectFolders(FBuilder, 'sample_test', LProjectFolder);

  //AssertTrue('Project Folder: ' + LProjectFolder, false);

  LOutput := InitializeBoss(FBuilder, LProjectFolder);
  
  LExpected := ConcatPaths([LProjectFolder, 'boss.json']);
  AssertTrue(
    'Boss file "' + LExpected + '" does not exists'#13#10 +
    'Output: '#13#10 + LOutput, 
    FileExists(LExpected));
end;

procedure TTestCommandNew.TestChangeBossFileSourcePath;
var
  LProjectFolder, LBossFile, LContent: string;
begin
  CreateProjectFolders(FBuilder, 'sample_test', LProjectFolder);
  InitializeBoss(FBuilder, LProjectFolder);
  
  LBossFile := ConcatPaths([LProjectFolder, 'boss.json']);
  LContent := '';
  if FileExists(LBossFile) then
  LContent := GetFileContent(LBossFile);

  AssertTrue(
    'Boss file "' + LBossFile + '" should contain string: "mainsrc":', 
    ContainsText(LContent, '"mainsrc":'));
end;

procedure TTestCommandNew.TestInitializeGit;
var
  LProjectFolder, LExpected: string;
begin
  CreateProjectFolders(FBuilder, 'sample_test', LProjectFolder);
  InitializeGit(FBuilder, LProjectFolder);

  LExpected := ConcatPaths([LProjectFolder, '.git']);
  AssertTrue(
    'Project folder "' + LExpected + '" does not exists', 
    DirectoryExists(LExpected));

  LExpected := ConcatPaths([LProjectFolder, '.gitignore']);
  AssertTrue(
    'gitignore file does not exists in project folder "' + LProjectFolder + '"', 
    FileExists(LExpected));

  AssertTrue(
    'gitignore should ignore the project executable',
    ContainsText(GetFileContent(LExpected), LineEnding + '/sample_test' + LineEnding));
  AssertTrue(
    'gitignore should ignore the test project executable',
    ContainsText(GetFileContent(LExpected), LineEnding + '/tests/Testsample_test' + LineEnding));
end;

procedure TTestCommandNew.TestCreateProjectFolders;
var
  LProjectFolder, LExpected: string;
begin
  CreateProjectFolders(FBuilder, 'sample_test', LProjectFolder);
  
  AssertTrue(
    'Project folder "' + LProjectFolder + '" does not exists', 
    DirectoryExists(LProjectFolder));

  LExpected := ConcatPaths([LProjectFolder, '.vscode']);
  AssertTrue(
    'Project folder "' + LProjectFolder + '/.vscode" does not exists', 
    DirectoryExists(LExpected));

  LExpected := ConcatPaths([LProjectFolder, 'src']);
  AssertTrue(
    'Project folder "' + LProjectFolder + '/src" does not exists', 
    DirectoryExists(LExpected));
end;

// creates only the workspace files needed by the members, without git and boss
function CreateEmptyWorkspace(const AParentDir: string): string;
begin
  Result := ConcatPaths([AParentDir, 'sample_ws']);
  ForceDirectories(ConcatPaths([Result, WORKSPACE_APPS_DIR]));
  ForceDirectories(ConcatPaths([Result, WORKSPACE_PACKAGES_DIR]));
  SaveFileContent(ConcatPaths([Result, WORKSPACE_FILE]), '{ "members": ["packages/*", "apps/*"] }');
  SaveFileContent(ConcatPaths([Result, '.gitignore']), '**/lib/' + LineEnding);
end;

procedure TTestCommandNew.TestCreateWorkspace;
var
  LWorkspaceDir: string;
begin
  CreateWorkspace(FBuilder, 'sample_ws', LWorkspaceDir);

  AssertTrue('pasc.json should exist', FileExists(ConcatPaths([LWorkspaceDir, WORKSPACE_FILE])));
  AssertTrue('apps folder should exist', DirectoryExists(ConcatPaths([LWorkspaceDir, WORKSPACE_APPS_DIR])));
  AssertTrue('packages folder should exist', DirectoryExists(ConcatPaths([LWorkspaceDir, WORKSPACE_PACKAGES_DIR])));
  AssertTrue('git should be initialized', DirectoryExists(ConcatPaths([LWorkspaceDir, '.git'])));
  AssertTrue('boss.json should exist at the root', FileExists(ConcatPaths([LWorkspaceDir, 'boss.json'])));
  AssertFalse('src folder should not exist at the root', DirectoryExists(ConcatPaths([LWorkspaceDir, 'src'])));
  AssertFalse(
    '.gitignore should not ignore a root executable',
    ContainsText(GetFileContent(ConcatPaths([LWorkspaceDir, '.gitignore'])), '/sample_ws'));
end;

procedure TTestCommandNew.TestCreateWorkspaceApp;
var
  LWorkspaceDir, LAppDir: string;
begin
  LWorkspaceDir := CreateEmptyWorkspace(FWorkingFolder);
  CreateWorkspaceApp(FBuilder, LWorkspaceDir, 'cli');

  LAppDir := ConcatPaths([LWorkspaceDir, WORKSPACE_APPS_DIR, 'cli']);
  AssertTrue('cli.lpr should exist', FileExists(ConcatPaths([LAppDir, 'cli.lpr'])));
  AssertTrue('cli.lpi should exist', FileExists(ConcatPaths([LAppDir, 'cli.lpi'])));
  AssertTrue('src folder should exist', DirectoryExists(ConcatPaths([LAppDir, 'src'])));
  AssertFalse('app should not have its own boss.json', FileExists(ConcatPaths([LAppDir, 'boss.json'])));
  AssertFalse('app should not have its own git', DirectoryExists(ConcatPaths([LAppDir, '.git'])));
  AssertTrue(
    '.gitignore should ignore the app executable',
    ContainsText(GetFileContent(ConcatPaths([LWorkspaceDir, '.gitignore'])), '/apps/cli/cli' + LineEnding));
  AssertTrue(
    '.gitignore should ignore the app test executable',
    ContainsText(GetFileContent(ConcatPaths([LWorkspaceDir, '.gitignore'])), '/apps/cli/tests/Testcli' + LineEnding));
end;

procedure TTestCommandNew.TestCreateWorkspacePackage;
var
  LWorkspaceDir, LPackageDir: string;
begin
  LWorkspaceDir := CreateEmptyWorkspace(FWorkingFolder);
  CreateWorkspacePackage(FBuilder, LWorkspaceDir, 'core');

  LPackageDir := ConcatPaths([LWorkspaceDir, WORKSPACE_PACKAGES_DIR, 'core']);
  AssertTrue('core.lpk should exist', FileExists(ConcatPaths([LPackageDir, 'core.lpk'])));
  AssertTrue(
    'package name should be replaced',
    ContainsText(GetFileContent(ConcatPaths([LPackageDir, 'core.lpk'])), '<Name Value="core"/>'));
  AssertTrue(
    'sample unit should exist',
    FileExists(ConcatPaths([LPackageDir, 'src', 'core.hello.pas'])));
  AssertTrue(
    'sample unit name should be replaced',
    ContainsText(GetFileContent(ConcatPaths([LPackageDir, 'src', 'core.hello.pas'])), 'unit core.Hello;'));
end;

procedure TTestCommandNew.TestCreateWorkspaceMemberInvalidName;
var
  LWorkspaceDir: string;
  LRaised: Boolean = False;
begin
  LWorkspaceDir := CreateEmptyWorkspace(FWorkingFolder);
  try
    CreateWorkspaceApp(FBuilder, LWorkspaceDir, 'my-app');
  except
    LRaised := True;
  end;

  AssertTrue('an invalid pascal identifier should raise an exception', LRaised);
  AssertFalse(
    'the app folder should not be created',
    DirectoryExists(ConcatPaths([LWorkspaceDir, WORKSPACE_APPS_DIR, 'my-app'])));
end;

procedure TTestCommandNew.TestNewCommandAppRequiresWorkspace;
begin
  FBuilder.AddArgument('project file name', acOptional);
  FBuilder.UseArguments(['new', 'cli', '--app']);
  FBuilder.Parse;

  NewCommand(FBuilder);

  AssertTrue(
    'Output should explain that a workspace is required. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, 'must be used inside a workspace'));
  AssertFalse('no folder should be created', DirectoryExists(ConcatPaths([FWorkingFolder, 'cli'])));
end;

procedure TTestCommandNew.TestNewCommandInsideWorkspaceRequiresMemberOption;
var
  LWorkspaceDir: string;
begin
  LWorkspaceDir := CreateEmptyWorkspace(FWorkingFolder);
  SetCurrentDir(LWorkspaceDir);

  FBuilder.AddArgument('project file name', acOptional);
  FBuilder.UseArguments(['new', 'other']);
  FBuilder.Parse;

  NewCommand(FBuilder);

  AssertTrue(
    'Output should suggest --app or --package. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, 'use --app or --package'));
  AssertFalse('no project should be created', DirectoryExists(ConcatPaths([LWorkspaceDir, 'other'])));
end;

procedure TTestCommandNew.TestNewCommandAppFromWorkspaceSubfolder;
var
  LWorkspaceDir: string;
begin
  LWorkspaceDir := CreateEmptyWorkspace(FWorkingFolder);
  SetCurrentDir(ConcatPaths([LWorkspaceDir, WORKSPACE_PACKAGES_DIR]));

  FBuilder.AddArgument('project file name', acOptional);
  FBuilder.UseArguments(['new', 'cli', '--app']);
  FBuilder.Parse;

  NewCommand(FBuilder);

  AssertTrue(
    'app should be created in the apps folder of the workspace. Check: ' + MockOutputCaptured,
    FileExists(ConcatPaths([LWorkspaceDir, WORKSPACE_APPS_DIR, 'cli', 'cli.lpi'])));
end;

initialization
  RegisterTest(TTestCommandNew);
  
end.