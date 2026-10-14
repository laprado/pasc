unit TestCommandAdd;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, 
  SysUtils, 
  fpcunit, 
  testregistry,
  Command.Interfaces,
  Command.Builder,
  Command.Add;

type

  TTestCommandAdd= class(TTestCase)
  private
    FBuilder: ICommandBuilder;
    FExeName: string;
    FWorkingFolder: string;
    FCurrentDir: string;

  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCommandAddRegistry;    
    procedure TestCommandAddBasic;
    procedure TestCommandAddDocs;
    procedure TestCommandAddNoOptions;
    procedure TestCommandAddPackage;
    procedure TestCommandAddPackageOutsideWorkspace;
    procedure TestCommandAddTestsInWorkspacePackage;
  end;

implementation

uses
  Resources,
  StrUtils,
  MockCommandBuilder,
  Command.Clean,
  Utils.IO,
  Utils.Workspace;

const
  WS_APP_LPI =
    '<?xml version="1.0" encoding="UTF-8"?>' + LineEnding +
    '<CONFIG>' + LineEnding +
    '  <ProjectOptions>' + LineEnding +
    '    <Units>' + LineEnding +
    '    </Units>' + LineEnding +
    '  </ProjectOptions>' + LineEnding +
    '</CONFIG>' + LineEnding;

  WS_PACKAGE_LPK =
    '<?xml version="1.0" encoding="UTF-8"?>' + LineEnding +
    '<CONFIG>' + LineEnding +
    '  <Package Version="5">' + LineEnding +
    '    <Name Value="core"/>' + LineEnding +
    '    <Files>' + LineEnding +
    '    </Files>' + LineEnding +
    '    <RequiredPkgs>' + LineEnding +
    '      <Item>' + LineEnding +
    '        <PackageName Value="FCL"/>' + LineEnding +
    '      </Item>' + LineEnding +
    '    </RequiredPkgs>' + LineEnding +
    '  </Package>' + LineEnding +
    '</CONFIG>' + LineEnding;

// a workspace with packages/core and apps/cli, returns its root
function CreateSampleWorkspace(const AParentDir: string): string;
begin
  Result := ConcatPaths([AParentDir, 'ws']);
  ForceDirectories(ConcatPaths([Result, 'packages', 'core', 'src']));
  ForceDirectories(ConcatPaths([Result, 'apps', 'cli', 'src']));
  SaveFileContent(ConcatPaths([Result, WORKSPACE_FILE]), '{ "members": ["packages/*", "apps/*"] }');
  SaveFileContent(ConcatPaths([Result, 'packages', 'core', 'core.lpk']), WS_PACKAGE_LPK);
  SaveFileContent(ConcatPaths([Result, 'apps', 'cli', 'cli.lpi']), WS_APP_LPI);
  SaveFileContent(ConcatPaths([Result, 'apps', 'cli', 'cli.lpr']), 'program cli;');
end;

procedure TTestCommandAdd.SetUp;
begin
  FCurrentDir := GetCurrentDir;
  FExeName := ExtractFileName(ParamStr(0));
  FBuilder := TCommandBuilder.Create(FExeName);
  MockSetup(FBuilder);
  Command.Add.Registry(FBuilder);

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

procedure TTestCommandAdd.TearDown;
begin
  SetCurrentDir(FCurrentDir);
  AnsweredAll := False;
end;

procedure TTestCommandAdd.TestCommandAddRegistry;
begin
  AssertEquals('add', FBuilder.Commands[0].Name);
end;

procedure TTestCommandAdd.TestCommandAddBasic;
begin
  // arrange
  FBuilder.UseArguments(['add', '--tests']);
  FBuilder.Parse;

  SetCurrentDir(FWorkingFolder);
  SaveFileContent(ConcatPaths([FWorkingFolder, 'myproject.lpr']), 'program myproject;');

  // act
  AddCommand(FBuilder);

  // assert
  AssertTrue(
    'tests sub folder should exist in ' + FWorkingFolder, 
    DirectoryExists(ConcatPaths([FWorkingFolder, 'tests'])));
  AssertTrue(
    'Output should contain keyword: "test project added with success" ',
    ContainsText(MockOutputCaptured, 'test project added with success'));
end;

procedure TTestCommandAdd.TestCommandAddNoOptions;
begin
  // arrange
  FBuilder.UseArguments(['add']);
  FBuilder.Parse;

  SetCurrentDir(FWorkingFolder);
  SaveFileContent(ConcatPaths([FWorkingFolder, 'myproject.lpr']), 'program myproject;');
  
  // act
  //FBuilder.Output(FWorkingFolder);
  AddCommand(FBuilder);
  
  //AssertEquals('a', MockCommandCapture);

  // assert
  AssertTrue(
    'Output should contain keyword: "you must specify at least one of the options" ',
    ContainsText(MockOutputCaptured, 'you must specify at least one of the options'));
end;

procedure TTestCommandAdd.TestCommandAddDocs;
begin
  // arrange
  FBuilder.UseArguments(['add', '--docs']);
  FBuilder.Parse;

  SetCurrentDir(FWorkingFolder);
  SaveFileContent(ConcatPaths([FWorkingFolder, 'myproject.lpr']), 'program myproject;');

  // act
  AddCommand(FBuilder);

  // assert
  AssertTrue(
    'tests sub folder should exist in ' + FWorkingFolder, 
    DirectoryExists(ConcatPaths([FWorkingFolder, 'docs'])));
  AssertTrue(
    'Output should contain keyword: "documentation resources added with success" ',
    ContainsText(MockOutputCaptured, 'documentation resources added with success')); 
end;

procedure TTestCommandAdd.TestCommandAddPackage;
var
  LWorkspaceDir: string;
begin
  LWorkspaceDir := CreateSampleWorkspace(FWorkingFolder);
  SetCurrentDir(ConcatPaths([LWorkspaceDir, 'apps', 'cli']));
  FBuilder.UseArguments(['add', '--package=core']);
  FBuilder.Parse;

  AddCommand(FBuilder);

  AssertTrue(
    'cli.lpi should require core. Check: ' + MockOutputCaptured,
    ContainsText(
      GetFileContent(ConcatPaths([LWorkspaceDir, 'apps', 'cli', 'cli.lpi'])),
      '<DefaultFilename Value="../../packages/core/core.lpk" Prefer="True"/>'));
end;

procedure TTestCommandAdd.TestCommandAddPackageOutsideWorkspace;
begin
  SaveFileContent(ConcatPaths([FWorkingFolder, 'myproject.lpi']), WS_APP_LPI);
  FBuilder.UseArguments(['add', '--package=core']);
  FBuilder.Parse;

  AddCommand(FBuilder);

  AssertTrue(
    'Output should explain that a workspace is required. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, 'must be used inside a workspace'));
end;

procedure TTestCommandAdd.TestCommandAddTestsInWorkspacePackage;
var
  LWorkspaceDir, LContent: string;
begin
  LWorkspaceDir := CreateSampleWorkspace(FWorkingFolder);
  SetCurrentDir(ConcatPaths([LWorkspaceDir, 'packages', 'core']));
  FBuilder.UseArguments(['add', '--tests']);
  FBuilder.Parse;

  AddCommand(FBuilder);

  LContent := GetFileContent(ConcatPaths([LWorkspaceDir, 'packages', 'core', 'tests', 'Testcore.lpi']));
  AssertTrue(
    'test project should require the package. Check: ' + MockOutputCaptured,
    ContainsText(LContent, '<DefaultFilename Value="../core.lpk" Prefer="True"/>'));
  AssertFalse(
    'test project should not use the package sources directly',
    ContainsText(LContent, '<OtherUnitFiles Value="../src"/>'));
end;

initialization
  RegisterTest(TTestCommandAdd);
  
end.