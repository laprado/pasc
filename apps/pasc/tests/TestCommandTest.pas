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

initialization
  RegisterTest(TTestCommandTest);
  
end.
