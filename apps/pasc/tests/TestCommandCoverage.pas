unit TestCommandCoverage;

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

  TTestCommandCoverage = class(TTestCase)
  private
    FBuilder: ICommandBuilder;
    FCurrentDir, FProjectDir: string;
    function RunCoverage(const AArguments: TArray<string>): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCoverageCommandRegistry;
    {$IF DEFINED(WINDOWS)}
    procedure TestCoverageCommandOnWindows;
    {$ELSE}
    procedure TestCoverageCommand;
    procedure TestCoverageCommandBelowMinimum;
    procedure TestCoverageCommandInvalidMinimum;
    procedure TestCoverageCommandWithoutKcov;
    procedure TestCoverageCommandFailedTest;
    {$ENDIF}
  end;

implementation

uses
  StrUtils,
  FileUtil,
  MockCommandBuilder,
  Command.Coverage,
  Utils.IO,
  Utils.Shell;

var
  KcovMissing: Boolean;
  TestResult: string;

function TestResultsXml(const AResult: string): string;
begin
  Result :=
    '<?xml version="1.0" encoding="utf-8"?>' + LineEnding +
    '<TestResults>' + LineEnding +
    '  <TestListing>' + LineEnding +
    '    <TestSuite Name="" NumberOfErrors="0" NumberOfFailures="0" NumberOfRunTests="1">' + LineEnding +
    '      <TestSuite Name="TTestSample" NumberOfErrors="0" NumberOfFailures="0" NumberOfRunTests="1">' + LineEnding +
    '        <Test Name="TestOne" Result="' + AResult + '" ElapsedTime="00:00:00.000"/>' + LineEnding +
    '      </TestSuite>' + LineEnding +
    '    </TestSuite>' + LineEnding +
    '  </TestListing>' + LineEnding +
    '</TestResults>' + LineEnding;
end;

/// <summary> Like kcov, writes the tests results and the coverage report of the run. </summary>
function MockCoverageShell(const AProgram: string; AParams: TArray<string>; out AExitCode: Integer): string;
var
  LParam, LOutDir, LExeFile: string;
begin
  AExitCode := 0;
  Result := MockShell(AProgram, AParams, AExitCode);
  if AProgram = 'git' then
    // outside a git repository
    AExitCode := 128;
  if AProgram <> 'kcov' then
    Exit;
  if KcovMissing then
    raise Exception.Create('kcov not found');
  if (AParams[0] = '--version') or (AParams[0] = '--merge') then
    Exit;

  LOutDir := '';
  LExeFile := '';
  for LParam in AParams do
    if StartsStr('--file=', LParam) then
      SaveFileContent(Copy(LParam, Length('--file=') + 1, MaxInt), TestResultsXml(TestResult))
    else if not StartsStr('-', LParam) then
      if LOutDir = '' then
        LOutDir := LParam
      else if LExeFile = '' then
        LExeFile := LParam;
  ForceDirectories(ConcatPaths([LOutDir, ExtractFileName(LExeFile)]));
  SaveFileContent(ConcatPaths([LOutDir, ExtractFileName(LExeFile), 'coverage.json']),
    '{"files": [{"file": "' + ConcatPaths([GetCurrentDir, 'src', 'hello.pas']) + '", ' +
    '"covered_lines": "3", "total_lines": "4"}], "covered_lines": 3, "total_lines": 4}');
end;

procedure TTestCommandCoverage.SetUp;
begin
  FCurrentDir := GetCurrentDir;
  FBuilder := TCommandBuilder.Create(ExtractFileName(ParamStr(0)));
  MockSetup(FBuilder);
  Command.Coverage.Registry(FBuilder);
  KcovMissing := False;
  TestResult := 'OK';

  // a project with a unit that a test uses, one that no test uses, and the built executable
  FProjectDir := ConcatPaths([GetTempDir, '.TestCommandCoverage', TestName]);
  if DirectoryExists(FProjectDir) then
    DeleteDirectory(FProjectDir, False);
  ForceDirectories(ConcatPaths([FProjectDir, 'src']));
  ForceDirectories(ConcatPaths([FProjectDir, 'tests']));
  SaveFileContent(ConcatPaths([FProjectDir, 'src', 'hello.pas']), 'unit Hello; interface implementation begin end.');
  SaveFileContent(ConcatPaths([FProjectDir, 'src', 'extra.pas']), 'unit Extra; interface implementation begin end.');
  SaveFileContent(ConcatPaths([FProjectDir, 'tests', 'TestSample.lpr']), 'TTestPascRunner = class(TTestRunner)');
  SaveFileContent(ConcatPaths([FProjectDir, 'tests', 'TestSample.lpi']),
    '<?xml version="1.0" encoding="UTF-8"?><CONFIG><ProjectOptions><BuildModes>' + LineEnding +
    '      <Item Name="Default" Default="True"/>' + LineEnding + '    </BuildModes></ProjectOptions>' +
    '<CompilerOptions><Target><Filename Value="TestSample"/></Target></CompilerOptions></CONFIG>');
  SaveFileContent(ConcatPaths([FProjectDir, 'tests', 'TestSample-coverage']), 'just for test');
  SetCurrentDir(FProjectDir);
  FProjectDir := GetCurrentDir;
  ShellExecute := @MockCoverageShell;
  ExitCode := 0;
end;

procedure TTestCommandCoverage.TearDown;
begin
  SetCurrentDir(FCurrentDir);
  ShellExecute := @ShellCommand;
  ExitCode := 0;
end;

function TTestCommandCoverage.RunCoverage(const AArguments: TArray<string>): Integer;
begin
  FBuilder.UseArguments(['coverage'] + AArguments);
  FBuilder.Parse;
  CoverageCommand(FBuilder);
  Result := ExitCode;
  ExitCode := 0;
end;

procedure TTestCommandCoverage.TestCoverageCommandRegistry;
begin
  AssertEquals('coverage', FBuilder.Commands[0].Name);
end;

{$IF DEFINED(WINDOWS)}
procedure TTestCommandCoverage.TestCoverageCommandOnWindows;
begin
  AssertEquals('the exit code should be 1', 1, RunCoverage([]));
  AssertTrue('should say that kcov does not run on Windows. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, 'does not run on Windows'));
end;
{$ELSE}
procedure TTestCommandCoverage.TestCoverageCommand;
var
  LExitCode: Integer;
begin
  LExitCode := RunCoverage([]);

  AssertEquals('the exit code should be 0. Check: ' + MockOutputCaptured, 0, LExitCode);
  AssertTrue('should add the build mode. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, 'tests/TestSample.lpi with the Coverage build mode'));
  AssertTrue('should build the Coverage build mode. Check: ' + MockShellCapture,
    ContainsText(MockShellCapture, 'lazbuild --bm=Coverage ' + ConcatPaths([FProjectDir, 'tests', 'TestSample.lpi'])));
  AssertTrue('should count only the sources of the project. Check: ' + MockShellCapture,
    ContainsText(MockShellCapture, 'kcov --include-path=' + ConcatPaths([FProjectDir, 'src']) + ' ' +
    ConcatPaths([FProjectDir, 'coverage', ExtractFileName(FProjectDir)])));
  AssertTrue('should output the coverage with the project name. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, 'Coverage ' + ExtractFileName(FProjectDir) + ' 75.00% (3/4 lines)'));
  AssertTrue('should output the coverage of each file', ContainsText(MockOutputCaptured, '3/4  src/hello.pas'));
  AssertTrue('should list the unit that no test uses',
    ContainsText(MockOutputCaptured, 'src/extra.pas (no test uses it)'));
  AssertTrue('should output the path of the report',
    ContainsText(MockOutputCaptured, 'coverage/' + ExtractFileName(FProjectDir) + '/index.html'));
end;

procedure TTestCommandCoverage.TestCoverageCommandBelowMinimum;
var
  LExitCode: Integer;
begin
  LExitCode := RunCoverage(['--min=80']);

  AssertEquals('the exit code should be 1 below the minimum', 1, LExitCode);
  AssertTrue('should say that the coverage is below the minimum. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, '75.00% is below the minimum of 80.00%'));
  AssertEquals('the exit code should be 0 above the minimum', 0, RunCoverage(['--min=75']));
end;

procedure TTestCommandCoverage.TestCoverageCommandInvalidMinimum;
begin
  AssertEquals('the exit code should be 1', 1, RunCoverage(['--min=abc']));
  AssertTrue('should say that the value is invalid. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, 'Invalid --min value: abc'));
  AssertFalse('should not build the tests', ContainsText(MockShellCapture, 'lazbuild'));
end;

procedure TTestCommandCoverage.TestCoverageCommandWithoutKcov;
begin
  KcovMissing := True;

  AssertEquals('the exit code should be 1', 1, RunCoverage([]));
  AssertTrue('should say how to install kcov. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, 'kcov was not found') and ContainsText(MockOutputCaptured, 'pacman -S kcov'));
  AssertFalse('should not build the tests', ContainsText(MockShellCapture, 'lazbuild'));
end;

procedure TTestCommandCoverage.TestCoverageCommandFailedTest;
begin
  TestResult := 'Failed';

  AssertEquals('the exit code should be 1 when a test fails. Check: ' + MockOutputCaptured, 1, RunCoverage([]));
  AssertTrue('should still output the coverage', ContainsText(MockOutputCaptured, '75.00% (3/4 lines)'));
end;
{$ENDIF}

initialization
  RegisterTest(TTestCommandCoverage);

end.
