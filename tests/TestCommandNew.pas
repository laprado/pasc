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
  end;

implementation

uses
  Resources,
  StrUtils,
  MockCommandBuilder,
  Command.New,
  Command.Clean,
  Utils.IO,
  Utils.Shell;

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
    ContainsText(GetFileContent(LExpected), #10'/sample_test'#10));
  AssertTrue(
    'gitignore should ignore the test project executable',
    ContainsText(GetFileContent(LExpected), #10'/tests/Testsample_test'#10));
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

initialization
  RegisterTest(TTestCommandNew);
  
end.