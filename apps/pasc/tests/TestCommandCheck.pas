unit TestCommandCheck;

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

  TTestCommandCheck = class(TTestCase)
  private
    FBuilder: ICommandBuilder;
    FCurrentDir, FWorkspaceDir: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCheckCommandRegistry;
    procedure TestCheckCommandNoProblems;
    procedure TestCheckCommandProblems;
  end;

implementation

uses
  StrUtils,
  FileUtil,
  MockCommandBuilder,
  Command.Check,
  Utils.IO,
  Utils.Workspace;

procedure TTestCommandCheck.SetUp;
begin
  FCurrentDir := GetCurrentDir;
  FBuilder := TCommandBuilder.Create(ExtractFileName(ParamStr(0)));
  MockSetup(FBuilder);
  Command.Check.Registry(FBuilder);

  // a workspace with a package whose unit is listed in its files
  FWorkspaceDir := ConcatPaths([GetTempDir, '.TestCommandCheck', TestName]);
  if DirectoryExists(FWorkspaceDir) then
    DeleteDirectory(FWorkspaceDir, False);
  ForceDirectories(ConcatPaths([FWorkspaceDir, WORKSPACE_PACKAGES_DIR, 'core', 'src']));
  SaveFileContent(ConcatPaths([FWorkspaceDir, WORKSPACE_FILE]), '{ "members": ["packages/*"] }');
  SaveFileContent(ConcatPaths([FWorkspaceDir, WORKSPACE_PACKAGES_DIR, 'core', 'core.lpk']),
    '<?xml version="1.0" encoding="UTF-8"?><CONFIG><Package Version="5"><Name Value="core"/>' +
    '<CompilerOptions><SearchPaths><OtherUnitFiles Value="src"/></SearchPaths></CompilerOptions>' +
    '<Files><Item><Filename Value="src/core.hello.pas"/></Item></Files></Package></CONFIG>');
  SaveFileContent(ConcatPaths([FWorkspaceDir, WORKSPACE_PACKAGES_DIR, 'core', 'src', 'core.hello.pas']), 'unit core.Hello;');
  SetCurrentDir(FWorkspaceDir);
  ExitCode := 0;
end;

procedure TTestCommandCheck.TearDown;
begin
  SetCurrentDir(FCurrentDir);
  ExitCode := 0;
end;

procedure TTestCommandCheck.TestCheckCommandRegistry;
begin
  AssertEquals('check', FBuilder.Commands[0].Name);
end;

procedure TTestCommandCheck.TestCheckCommandNoProblems;
begin
  CheckCommand(FBuilder);

  AssertTrue('should report no problems. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, 'no problems found'));
  AssertEquals(0, ExitCode);
end;

procedure TTestCommandCheck.TestCheckCommandProblems;
var
  LExitCode: Integer;
begin
  SaveFileContent(ConcatPaths([FWorkspaceDir, WORKSPACE_PACKAGES_DIR, 'core', 'src', 'core.rules.pas']), 'unit core.Rules;');

  CheckCommand(FBuilder);
  LExitCode := ExitCode;

  AssertTrue('should warn about the unlisted unit. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, 'packages/core/src/core.rules.pas is not in the Files of core.lpk'));
  AssertTrue('should count the problems', ContainsText(MockOutputCaptured, '1 problem found'));
  AssertEquals('the exit code should be 1', 1, LExitCode);
end;

initialization
  RegisterTest(TTestCommandCheck);

end.
