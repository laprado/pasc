unit TestCommandWatch;

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

  TTestCommandWatch= class(TTestCase)
  private
    FExeName: string;
    FWorkingFolder: string;
    FCurrentDir: string;

  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCommandWatchRegistry;    
    procedure TestCommandWatchCheckIfWatcherCallbackIsCalled;
    procedure TestCommandWatchCheckIfShellExecuteCallbackIsCalled;
    procedure TestCommandWatchCheckIfShellExecuteIsCalledWithSuite;
  end;

implementation

uses
  Resources,
  StrUtils,
  MockCommandBuilder,
  Command.Clean,
  Command.Watch,
  Command.Test,
  Utils.IO,
  Utils.Shell;

var
  Finished: LongInt = 0;
  Builder: ICommandBuilder;

procedure RunWatchBasic;
var
  LBuilder: ICommandBuilder;
begin
  LBuilder := TCommandBuilder.Create(ExtractFileName(ParamStr(0)));
  try
    MockSetup(LBuilder);
    ShellExecute := @MockShell;
    Command.Watch.Registry(LBuilder);
    LBuilder.UseArguments(['watch', '.']);
    LBuilder.Parse;
    WatchCommand(LBuilder);
  finally
    InterLockedIncrement(Finished);
  end;
end;

procedure RunWatchCommand;
var
  LBuilder: ICommandBuilder;
begin
  LBuilder := TCommandBuilder.Create(ExtractFileName(ParamStr(0)));
  try
    MockSetup(LBuilder);
    ShellExecute := @MockShell;
    Command.Watch.Registry(LBuilder);
    Command.Test.Registry(LBuilder);
    LBuilder.UseArguments(['watch', '--build', '--test=TTestCommandAdd', '.']);
    LBuilder.Parse;
    WatchCommand(LBuilder);
  finally
    InterLockedIncrement(Finished);
  end;
end;

procedure TTestCommandWatch.SetUp;
begin
  FCurrentDir := GetCurrentDir;
  FExeName := ExtractFileName(ParamStr(0));
  Builder := TCommandBuilder.Create(FExeName);
  MockSetup(Builder);
  Command.Watch.Registry(Builder);

  MockCaptureWatchExecute := '';
  MockShellCapture := '';
  CommandWatchTimeout := 3000;
  Finished := 0;
  Builder := Builder;

  FWorkingFolder := ConcatPaths([GetTempDir, ChangeFileExt(FExeName, '')]);
  
  AnsweredAll := True;
    
  // clean old data
  if DirectoryExists(FWorkingFolder) then
    DeleteFolder(Builder, GetTempDir, ChangeFileExt(FExeName, ''));

  // create new working folder
  SetCurrentDir(GetTempDir);
  CreateDir(ChangeFileExt(FExeName, ''));
  SetCurrentDir(FWorkingFolder);
end;

procedure TTestCommandWatch.TearDown;
begin
  AnsweredAll := False;
  SetCurrentDir(FCurrentDir);
  ShellExecute := @ShellCommand;
  RunWatcherCallback := @RunUserCommandAsRequested;
  Builder := nil;
end;

procedure TTestCommandWatch.TestCommandWatchRegistry;
begin
  AssertEquals('watch', Builder.Commands[0].Name);
end;

procedure TTestCommandWatch.TestCommandWatchCheckIfWatcherCallbackIsCalled;
var
  LThread: TThread;
begin
  // arrange
  Builder.UseArguments(['watch', '.']);
  Builder.Parse;

  // cannot call TestPasc again because it would produce recursive calls indenitely
  // so we need to change ShellCommand and check if it's being called.
  ShellExecute := @MockShell;
  RunWatcherCallback := @MockWatchExecute;

  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.lpr']), 'test content');
  
  LThread := TThread.CreateAnonymousThread(RunWatchBasic);
  LThread.FreeOnTerminate := True;
  LThread.Start;

  Sleep(50);
  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.txt']), 'test content');

  while Finished = 0 do
    Sleep(50);
      
  // assert
  //AssertEquals('a', MockCaptureWatchExecute);
  AssertTrue(
    'Output should contain keyword: "test_for_watch.txt" ' + MockCaptureWatchExecute,
     ContainsText(MockCaptureWatchExecute, 'test_for_watch.txt'));
end;

procedure TTestCommandWatch.TestCommandWatchCheckIfShellExecuteCallbackIsCalled;
var
  LThread: TThread;
  LExecutable: string = 'test_for_watch.exe';
begin
  // arrange
  CommandWatchTimeout := 1000;
  Builder.UseArguments(['watch', '--build', '--test', '.']);
  Builder.Parse;
  
  // cannot call TestPasc again because it would produce recursive calls indenitely
  // so we need to change ShellCommand and check if it's being called.
  ShellExecute := @MockShell;
  RunWatcherCallback := @RunUserCommandAsRequested; // original callback

  {$IFDEF UNIX}
  LExecutable := 'test_for_watch';
  {$ENDIF}

  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.lpr']), 'TTestPascRunner = class(TTestRunner)');
  SaveFileContent(ConcatPaths([FWorkingFolder, LExecutable]), 'just for test');
  
  LThread := TThread.CreateAnonymousThread(RunWatchCommand);
  LThread.FreeOnTerminate := True;
  LThread.Start;

  Sleep(50);
  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.txt']), 'test content');

  while Finished = 0 do
    Sleep(50);
      
  // assert
  AssertTrue(
    'Output should contain keyword: "lazbuild" ' + #13#10 +
    ' - Check capture: ' + MockShellCapture + #13#10 + 
    ' - Check Console: ' + MockOutputCaptured,
     ContainsText(MockShellCapture, 'lazbuild'));
  AssertTrue(
    'Output should contain keyword: "' + LExecutable + ' " '#13#10 +
    ' - Check capture: ' + MockShellCapture + #13#10 + 
    ' - Check Console: ' + MockOutputCaptured,
     ContainsText(MockShellCapture, LExecutable + ' '));  
end;

procedure TTestCommandWatch.TestCommandWatchCheckIfShellExecuteIsCalledWithSuite;
var
  LThread: TThread;
  LExecutable: string = 'test_for_watch.exe';
  LValue: string;
begin
  // arrange
  CommandWatchTimeout := 1000;
  Builder.UseArguments(['watch', '--test=TTestCommandAdd', '.']);
  Builder.Parse;
  
  // cannot call TestPasc again because it would produce recursive calls indenitely
  // so we need to change ShellCommand and check if it's being called.
  ShellExecute := @MockShell;
  RunWatcherCallback := @RunUserCommandAsRequested; // original callback

  {$IFDEF UNIX}
  LExecutable := 'test_for_watch';
  {$ENDIF}

  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.lpr']), 'TTestPascRunner = class(TTestRunner)');
  SaveFileContent(ConcatPaths([FWorkingFolder, LExecutable]), 'just for test');
  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.xml']), 'just for test');
  
  LThread := TThread.CreateAnonymousThread(RunWatchCommand);
  LThread.FreeOnTerminate := True;
  LThread.Start;

  Sleep(50);
  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.txt']), 'test content');

  while Finished = 0 do
    Sleep(50);
      
  // assert
  AssertTrue(
    'Output should contain keyword: "--suite=TTestCommandAdd" - Check capture: ' + MockShellCapture,
     ContainsText(MockShellCapture, '--suite=TTestCommandAdd'));
end;

initialization
  RegisterTest(TTestCommandWatch);
  
end.
