unit TestCommandDeps;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, 
  SysUtils, 
  fpcunit, 
  testregistry,
  Command.Interfaces,
  Command.Builder,
  Command.Deps;

type

  TTestCommandDeps= class(TTestCase)
  private
    FBuilder: ICommandBuilder;
    FExeName: string;
    FCurrentDir: string;
    FWorkingFolder: string;
    function CreateWorkspace: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCommandDepsRegistry;
    procedure TestCommandDepsOutsideWorkspace;
    procedure TestCommandDepsInvalidDependency;
    procedure TestCommandDepsFromMemberRunsAtRoot;
  end;

implementation

uses
  StrUtils,
  MockCommandBuilder,
  Utils.IO,
  Utils.Shell,
  Utils.Workspace;

const
  APP_LPI =
    '<?xml version="1.0" encoding="UTF-8"?>' + LineEnding +
    '<CONFIG>' + LineEnding +
    '  <CompilerOptions>' + LineEnding +
    '    <SearchPaths>' + LineEnding +
    '      <OtherUnitFiles Value="src"/>' + LineEnding +
    '    </SearchPaths>' + LineEnding +
    '  </CompilerOptions>' + LineEnding +
    '</CONFIG>' + LineEnding;

procedure TTestCommandDeps.SetUp;
begin
  FCurrentDir := GetCurrentDir;
  FExeName := ExtractFileName(ParamStr(0));
  FBuilder := TCommandBuilder.Create(FExeName);
  MockSetup(FBuilder);
  Command.Deps.Registry(FBuilder);
  FBuilder.AddArgument('project file name', acOptional);
  // a unique folder per test, so modules and members of other tests do not leak
  FWorkingFolder := ConcatPaths([GetTempDir, '.TestCommandDeps', TestName]);
  ForceDirectories(FWorkingFolder);
  SetCurrentDir(FWorkingFolder);
  ShellExecute := @MockShell;
end;

procedure TTestCommandDeps.TearDown;
begin
  SetCurrentDir(FCurrentDir);
  ShellExecute := @ShellCommand;
end;

function TTestCommandDeps.CreateWorkspace: string;
begin
  Result := ConcatPaths([FWorkingFolder, 'ws']);
  ForceDirectories(ConcatPaths([Result, 'apps', 'cli', 'src']));
  ForceDirectories(ConcatPaths([Result, 'modules', 'github_com_a_lib', 'src']));
  SaveFileContent(ConcatPaths([Result, WORKSPACE_FILE]), '{ "members": ["apps/*"] }');
  SaveFileContent(ConcatPaths([Result, 'apps', 'cli', 'cli.lpi']), APP_LPI);
  SaveFileContent(ConcatPaths([Result, 'modules', 'github_com_a_lib', 'boss.json']), '{ "mainsrc": "src/" }');
  SaveFileContent(ConcatPaths([Result, 'modules', 'github_com_a_lib', 'src', 'lib.pas']), 'unit lib;');
end;

procedure TTestCommandDeps.TestCommandDepsRegistry;
begin
  AssertEquals('deps', FBuilder.Commands[0].Name);
end;

procedure TTestCommandDeps.TestCommandDepsOutsideWorkspace;
begin
  FBuilder.UseArguments(['deps']);
  FBuilder.Parse;

  DepsCommand(FBuilder);

  AssertTrue(
    'Output should explain that a workspace is required. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, 'must be used inside a workspace'));
  AssertEquals('boss should not be called', '', MockShellCapture);
end;

procedure TTestCommandDeps.TestCommandDepsInvalidDependency;
begin
  SetCurrentDir(CreateWorkspace);
  FBuilder.UseArguments(['deps', 'github.com/a/b;rm']);
  FBuilder.Parse;

  DepsCommand(FBuilder);

  AssertTrue(
    'Output should reject the dependency. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, 'Invalid dependency'));
  AssertEquals('boss should not be called', '', MockShellCapture);
end;

procedure TTestCommandDeps.TestCommandDepsFromMemberRunsAtRoot;
var
  LWorkspaceDir: string;
begin
  LWorkspaceDir := CreateWorkspace;
  SetCurrentDir(ConcatPaths([LWorkspaceDir, 'apps', 'cli']));
  FBuilder.UseArguments(['deps', 'github.com/a/lib']);
  FBuilder.Parse;

  DepsCommand(FBuilder);

  AssertTrue(
    'boss install should be called with the dependency. Check: ' + MockShellCapture,
    ContainsText(MockShellCapture, 'boss install github.com/a/lib'));
  AssertEquals(
    'current dir should be restored',
    ConcatPaths([LWorkspaceDir, 'apps', 'cli']), GetCurrentDir);
  AssertTrue(
    'member search paths should include the module. Check: ' + MockOutputCaptured,
    ContainsText(
      GetFileContent(ConcatPaths([LWorkspaceDir, 'apps', 'cli', 'cli.lpi'])),
      '<OtherUnitFiles Value="src;../../modules/github_com_a_lib/src"/>'));
end;

initialization
  RegisterTest(TTestCommandDeps);
  
end.
