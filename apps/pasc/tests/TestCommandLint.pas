unit TestCommandLint;

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

  TTestCommandLint = class(TTestCase)
  private
    FBuilder: ICommandBuilder;
    FCurrentDir, FProjectDir: string;
    function RunLint: Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLintCommandRegistry;
    procedure TestLintCommand;
    procedure TestLintCommandOnlyHints;
    procedure TestLintCommandBuildFails;
  end;

implementation

uses
  StrUtils,
  FileUtil,
  MockCommandBuilder,
  Command.Lint,
  Utils.IO,
  Utils.Shell;

var
  ProjectDir: string;
  WithWarning: Boolean;
  BuildFails: Boolean;

/// <summary> Like lazbuild, returns the messages of the compiler for each project. </summary>
function MockLintShell(const AProgram: string; AParams: TArray<string>; out AExitCode: Integer): string;
begin
  AExitCode := 0;
  MockShell(AProgram, AParams, AExitCode);
  Result := '';
  if AProgram <> 'lazbuild' then
    Exit;
  if BuildFails then
  begin
    AExitCode := 1;
    Exit(ConcatPaths([ProjectDir, 'src', 'Main.pas']) + '(3,1) Error: (5000) Identifier not found "x"' + LineEnding +
      'Error: (lazbuild) Failed compiling of project');
  end;
  if EndsText('Testapp.lpi', AParams[High(AParams)]) then
    Result :=
      '(3104) Compiling Testapp.lpr' + LineEnding +
      '(3104) Compiling ' + ConcatPaths([ProjectDir, 'modules', 'lib', 'src', 'Lib.pas']) + LineEnding +
      '(3104) Compiling TestMain.pas' + LineEnding +
      '(9022) Compiling resource ' + ConcatPaths([ProjectDir, 'tests', 'lib', 'lint', 'units', 'Testapp.or']) + LineEnding +
      ConcatPaths([ProjectDir, 'tests', 'TestMain.pas']) + '(10,5) Hint: (5024) Parameter "AValue" not used' + LineEnding +
      ConcatPaths([ProjectDir, 'modules', 'lib', 'src', 'Lib.pas']) + '(1,1) Warning: (4105) Implicit string type conversion'
  else
  begin
    Result := '(3104) Compiling app.lpr' + LineEnding + '(3104) Compiling ./src/Main.pas' + LineEnding +
      '(3104) Compiling ./src/Other.pas' + LineEnding;
    if WithWarning then
      Result := Result + ConcatPaths([ProjectDir, '.', 'src', 'Main.pas']) + '(38,19) Warning: (5093) function result ' +
        'variable of a managed type does not seem to be initialized' + LineEnding +
        ConcatPaths([ProjectDir, 'src', 'Main.pas']) + '(12,3) Note: (5025) Local variable "I" not used';
  end;
end;

procedure TTestCommandLint.SetUp;
begin
  FCurrentDir := GetCurrentDir;
  FBuilder := TCommandBuilder.Create(ExtractFileName(ParamStr(0)));
  MockSetup(FBuilder);
  Command.Lint.Registry(FBuilder);
  WithWarning := True;
  BuildFails := False;

  // a project outside a workspace, with a test project
  FProjectDir := ConcatPaths([GetTempDir, '.TestCommandLint', TestName, 'app']);
  if DirectoryExists(FProjectDir) then
    DeleteDirectory(FProjectDir, False);
  ForceDirectories(ConcatPaths([FProjectDir, 'src']));
  ForceDirectories(ConcatPaths([FProjectDir, 'tests']));
  SaveFileContent(ConcatPaths([FProjectDir, 'app.lpi']), '<CONFIG/>');
  SaveFileContent(ConcatPaths([FProjectDir, 'tests', 'Testapp.lpi']), '<CONFIG/>');
  SetCurrentDir(FProjectDir);
  FProjectDir := GetCurrentDir;
  ProjectDir := FProjectDir;
  ShellExecute := @MockLintShell;
  ExitCode := 0;
end;

procedure TTestCommandLint.TearDown;
begin
  SetCurrentDir(FCurrentDir);
  ShellExecute := @ShellCommand;
  ExitCode := 0;
end;

function TTestCommandLint.RunLint: Integer;
begin
  FBuilder.UseArguments(['lint']);
  FBuilder.Parse;
  LintCommand(FBuilder);
  Result := ExitCode;
  ExitCode := 0;
end;

procedure TTestCommandLint.TestLintCommandRegistry;
begin
  AssertEquals('lint', FBuilder.Commands[0].Name);
end;

procedure TTestCommandLint.TestLintCommand;
var
  LExitCode: Integer;
begin
  LExitCode := RunLint;

  AssertEquals('a warning fails by default. Check: ' + MockOutputCaptured, 1, LExitCode);
  AssertTrue('should build each project again into lib/lint. Check: ' + MockShellCapture,
    ContainsText(MockShellCapture, 'lazbuild -B --opt=-vwnhq -FUlib/lint/units -olib/lint/app ' +
      ConcatPaths([FProjectDir, 'app.lpi'])) and
    ContainsText(MockShellCapture, '-olib/lint/Testapp ' + ConcatPaths([FProjectDir, 'tests', 'Testapp.lpi'])));
  AssertTrue('should create the folder of the units', DirectoryExists(ConcatPaths([FProjectDir, 'lib', 'lint', 'units'])));
  AssertTrue('should output the file with its most severe message. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, '    Warning src/Main.pas' + #13#10));
  AssertTrue('should output the failing message as a link',
    ContainsText(MockOutputCaptured, 'src/Main.pas:38:19 (5093) function result variable'));
  AssertTrue('should output the other messages of the file with their kind, in order',
    Pos('12:3 (5025) note: Local variable "I" not used', MockOutputCaptured) <
    Pos('src/Main.pas:38:19', MockOutputCaptured));
  AssertTrue('should output the hint of the tests without the path',
    ContainsText(MockOutputCaptured, '       Hint tests/TestMain.pas' + #13#10 + StringOfChar(' ', 15) + '10:5 (5024)'));
  AssertTrue('should output the files without messages', ContainsText(MockOutputCaptured, '         OK src/Other.pas'));
  AssertTrue('should output the project files', ContainsText(MockOutputCaptured, '         OK tests/Testapp.lpr'));
  AssertFalse('should not output the modules', ContainsText(MockOutputCaptured, 'Lib.pas'));
  AssertFalse('should not output the resources', ContainsText(MockOutputCaptured, 'Testapp.or'));
  AssertTrue('should output the counts',
    ContainsText(MockOutputCaptured, 'app: 5 files, 3 OK, 1 warning, 1 note, 1 hint, 1 failing'));
end;

procedure TTestCommandLint.TestLintCommandOnlyHints;
begin
  WithWarning := False;

  AssertEquals('hints do not fail by default. Check: ' + MockOutputCaptured, 0, RunLint);
  AssertTrue(ContainsText(MockOutputCaptured, '5 files, 4 OK, 1 hint, 0 failing'));
end;

procedure TTestCommandLint.TestLintCommandBuildFails;
begin
  BuildFails := True;

  AssertEquals('an error fails', 1, RunLint);
  AssertTrue('should output the error. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, 'src/Main.pas:3:1 (5000) Identifier not found "x"'));
  AssertTrue('should say why it was not linted',
    ContainsText(MockOutputCaptured, 'app.lpi: Main.pas(3,1) Error: Identifier not found "x"'));
end;

initialization
  RegisterTest(TTestCommandLint);

end.
