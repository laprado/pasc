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

initialization
  RegisterTest(TTestCommandTest);
  
end.
