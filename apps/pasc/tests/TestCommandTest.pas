unit TestCommandTest;

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

  TTestCommandTest= class(TTestCase)
  private
    FBuilder: ICommandBuilder;
    FExeName: string;
    FWorkingFolder: string;
    FCurrentDir: string;
    FExecutable: string;

  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCommandTestRegistry;    
    procedure TestCommandTestBasic;
    procedure TestCommandTestSpecificSuite;
    procedure TestGetTestExecutable;
    procedure TestCommandTestExitCodeOnFailure;
    procedure TestCommandTestExitCodeOnSuccess;
    procedure TestFirstBuildError;
  end;

implementation

uses
  Resources,
  StrUtils,
  MockCommandBuilder,
  Command.Test,
  Utils.IO,
  Utils.Shell;

procedure TTestCommandTest.SetUp;
begin
  FCurrentDir := GetCurrentDir;
  FExeName := ExtractFileName(ParamStr(0));
  FBuilder := TCommandBuilder.Create(FExeName);
  FExecutable := 'test_for_watch'{$IFDEF WINDOWS} + '.exe'{$ENDIF};
  MockSetup(FBuilder);
  Command.Test.Registry(FBuilder);
  FWorkingFolder := ConcatPaths([GetTempDir, '.' + ChangeFileExt(FExeName, '')]);
  SetCurrentDir(FWorkingFolder);
  FWorkingFolder := GetCurrentDir;
end;

procedure TTestCommandTest.TearDown;
begin
  SetCurrentDir(FCurrentDir);
end;

procedure TTestCommandTest.TestCommandTestRegistry;
begin
  AssertEquals('test', FBuilder.Commands[0].Name);
end;

procedure TTestCommandTest.TestCommandTestBasic;
begin
  // arrange
  FBuilder.UseArguments(['test']);
  FBuilder.Parse;

  // cannot call TestPasc again because it would produce recursive calls indenitely
  // so we need to change ShellCommand and check if it's being called.
  ShellExecute := @MockShell;

  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.lpr']), 'TTestPascRunner = class(TTestRunner)');
  SaveFileContent(ConcatPaths([FWorkingFolder, FExecutable]), 'just for test');
  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.xml']), '<xml></xml>');
  
  TestCommand(FBuilder);
    
  // assert
  AssertTrue(
    'Output should contain keyword: "Starting" ',
    ContainsText(MockOutputCaptured, 'Starting'));
  AssertTrue(
    'Should call the test app: "TestPasc" ',
    ContainsText(MockShellCapture, 'TestPasc'));
  AssertTrue(
    'Should build the test project: "lazbuild" ',
    ContainsText(MockShellCapture, 'lazbuild ' + ConcatPaths([FWorkingFolder, 'test_for_watch.lpr'])));
end;

procedure TTestCommandTest.TestGetTestExecutable;
var
  LExpected, LActual: string;
begin
  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.lpr']), 'TTestPascRunner = class(TTestRunner)');
  SaveFileContent(ConcatPaths([FWorkingFolder, FExecutable]), 'just for test');
  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.xml']), '<xml></xml>');

  LExpected := ConcatPaths([FWorkingFolder, FExecutable]);
  LActual := GetTestExecutable(FBuilder);
  AssertEquals(LExpected, LActual);
end;

procedure TTestCommandTest.TestCommandTestSpecificSuite;
begin
  // arrange
  FBuilder.UseArguments(['test', '-t=TTestCommandTest']);
  FBuilder.Parse;

  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.lpr']), 'TTestPascRunner = class(TTestRunner)');
  SaveFileContent(ConcatPaths([FWorkingFolder, FExecutable]), 'just for test');
  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.xml']), '<xml></xml>');  

  // cannot call TestPasc again because it would produce recursive calls indenitely
  // so we need to change ShellCommand and check if it's being called.
  ShellExecute := @MockShell;
  TestCommand(FBuilder);
    
  // assert
  AssertTrue(
    'Output should contain keyword: "Starting" ',
    ContainsText(MockOutputCaptured, 'Starting'));
  AssertTrue(
    'Should call the test app: "--suite=TTestCommandTest" ',
    ContainsText(MockShellCapture, '--suite=TTestCommandTest'));  
end;

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

procedure TTestCommandTest.TestCommandTestExitCodeOnFailure;
var
  LExitCode: Integer;
begin
  FBuilder.UseArguments(['test']);
  FBuilder.Parse;
  ShellExecute := @MockShell;
  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.lpr']), 'TTestPascRunner = class(TTestRunner)');
  SaveFileContent(ConcatPaths([FWorkingFolder, FExecutable]), 'just for test');
  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.xml']), TestResultsXml('Failed'));

  ExitCode := 0;
  TestCommand(FBuilder);
  LExitCode := ExitCode;
  ExitCode := 0;

  AssertEquals('exit code should be 1 when a test fails. Check: ' + MockOutputCaptured, 1, LExitCode);
end;

procedure TTestCommandTest.TestCommandTestExitCodeOnSuccess;
var
  LExitCode: Integer;
begin
  FBuilder.UseArguments(['test']);
  FBuilder.Parse;
  ShellExecute := @MockShell;
  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.lpr']), 'TTestPascRunner = class(TTestRunner)');
  SaveFileContent(ConcatPaths([FWorkingFolder, FExecutable]), 'just for test');
  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.xml']), TestResultsXml('OK'));

  ExitCode := 0;
  TestCommand(FBuilder);
  LExitCode := ExitCode;
  ExitCode := 0;

  AssertEquals('exit code should be 0 when all tests pass. Check: ' + MockOutputCaptured, 0, LExitCode);
end;

procedure TTestCommandTest.TestFirstBuildError;
begin
  // the compiler error among the hints and the lazbuild messages
  AssertEquals('TestCommandGreet.pas(11,3) Fatal: Can''t find unit Command.Interfaces used by TestCommandGreet',
    FirstBuildError(
      'Hint: (lazarus) Missing state file of TestRunner' + LineEnding +
      'Param[1]="-MObjFPC"' + LineEnding +
      '/ws/apps/cmd/tests/TestCommandGreet.pas(11,3) Fatal: (10022) Can''t find unit Command.Interfaces used by TestCommandGreet' + LineEnding +
      'Fatal: (1018) Compilation aborted' + LineEnding +
      'Error: (lazbuild) Failed compiling of project "/ws/apps/cmd/tests/Testcmd.lpi"'));
  AssertEquals('an error of the compiler for a file', 'Main.pas(3,1) Error: Identifier not found "x"',
    FirstBuildError('/ws/src/Main.pas(3,1) Error: (5000) Identifier not found "x"'));
  AssertEquals('an error of lazbuild itself', 'Error: (lazbuild) Invalid Lazarus directory "": directory lcl not found',
    FirstBuildError('Hint: (lazbuild) Primary config path' + LineEnding +
      'Error: (lazbuild) Invalid Lazarus directory "": directory lcl not found'));
  AssertEquals('no error', '', FirstBuildError('Hint: (lazarus) nothing to do'));
end;

initialization
  RegisterTest(TTestCommandTest);
  
end.
