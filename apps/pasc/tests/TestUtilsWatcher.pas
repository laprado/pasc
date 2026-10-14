unit TestUtilsWatcher;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, 
  SysUtils, 
  StrUtils,
  fpcunit,
  testregistry,
  Command.Interfaces,  
  Utils.Interfaces,
  Utils.Watcher;

type

  TTestUtilsWatcher = class(TTestCase)
  private
    FCurrentDir: string;
    FExeName: string;
    FWorkingFolder: string;
    FBuilder: ICommandBuilder;
  public
    procedure Setup; override;
    procedure TearDown; override;
  published
    procedure TestBasicWatch;
    procedure TestIgnoreStartText;
    procedure TestIgnoreFolder;
    procedure TestIgnoreFile;
    procedure TestIgnoreExtension;
    procedure TestTimeout;
  end;

implementation

uses
  Command.Builder,
  Command.Clean,
  Utils.IO,
  MockCommandBuilder;

var
  Finished, CustomTimeout: LongInt;
  CustomIgnoreFolder, CustomIgnoreStartsText, CustomIgnoreFiles, CustomIgnoreExtensions: TArray<string>;

procedure RunWatcher;
var
  LWatcher: IPathWatcher;
  LPath, LExeName: string;
begin
  try
    LExeName := ExtractFileName(ParamStr(0));
    LPath := ConcatPaths([GetTempDir, '.' + ChangeFileExt(LExeName, '')]);
    LWatcher := 
      TPathWatcher
        .New
        .Path(LPath)
        .Ignore(ikStartsText, CustomIgnoreStartsText)        
        .Ignore(ikFolder, CustomIgnoreFolder)
        .Ignore(ikFile, CustomIgnoreFiles)
        .Ignore(ikExtension, CustomIgnoreExtensions)
        .Timeout(CustomTimeout)
        .Run(MockWatchExecute);

    LWatcher.Start;
  finally
    InterLockedIncrement(Finished);
  end;
end;

procedure AppendToArray(var AArray: TArray<string>; const AText: string);
begin
  SetLength(AArray, Length(AArray) + 1);
  AArray[Length(AArray) - 1] := AText;
end;

procedure TTestUtilsWatcher.Setup;
begin
  FCurrentDir := GetCurrentDir;
  FExeName := ExtractFileName(ParamStr(0));
  FBuilder := TCommandBuilder.Create(FExeName);
  MockSetup(FBuilder);

  MockCaptureWatchExecute := '';
  Finished := 0;
  CustomTimeout := 3000;

  SetLength(CustomIgnoreFolder, 0);
  SetLength(CustomIgnoreStartsText, 0);
  SetLength(CustomIgnoreFiles, 0);
  SetLength(CustomIgnoreExtensions, 0);

  AppendToArray(CustomIgnoreFolder, '.');
  AppendToArray(CustomIgnoreFolder, '..');

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

procedure TTestUtilsWatcher.TearDown;
begin
  SetCurrentDir(FCurrentDir);
  AnsweredAll := False;
end;

procedure TTestUtilsWatcher.TestBasicWatch;
var
  LThread: TThread;
begin
  CustomTimeout := 500;

  LThread := TThread.CreateAnonymousThread(RunWatcher);
  LThread.FreeOnTerminate := True;
  LThread.Start;

  Sleep(50);

  // change working folder
  SaveFileContent(ConcatPaths([FWorkingFolder, 'test_for_watch.txt']), 'test content');

  while Finished = 0 do
    Sleep(50);

  // check for CaptureWatchExecute
  AssertTrue(
    'shoud detect change for test_for_watch.txt ' + MockCaptureWatchExecute, 
    ContainsText(MockCaptureWatchExecute, 'test_for_watch.txt'));
end;

procedure TTestUtilsWatcher.TestIgnoreStartText;
var
  LThread: TThread;
begin
  AppendToArray(CustomIgnoreStartsText, 'samp');
  CustomTimeout := 50;

  LThread := TThread.CreateAnonymousThread(RunWatcher);
  LThread.FreeOnTerminate := True;
  LThread.Start;

  // change working folder
  SaveFileContent(ConcatPaths([FWorkingFolder, 'samp_for_watch.txt']), 'test content');

  while Finished = 0 do
    Sleep(50);

  AssertFalse(
    'shoud not detect change for samp_for_watch.txt', 
    ContainsText(MockCaptureWatchExecute, 'samp_for_watch.txt'));
end;

procedure TTestUtilsWatcher.TestIgnoreFolder;
var
  LThread: TThread;
begin
  AppendToArray(CustomIgnoreFolder, 'newfolder');
  CustomTimeout := 50;

  LThread := TThread.CreateAnonymousThread(RunWatcher);
  LThread.FreeOnTerminate := True;
  LThread.Start;

  // change working folder
  CreateDir('newfolder');
  SaveFileContent(ConcatPaths([FWorkingFolder, 'newfolder', 'new_file.txt']), 'test content');

  while Finished = 0 do
    Sleep(50);

  AssertFalse(
    'shoud not detect change creation on newfolder ' + MockCaptureWatchExecute, 
    ContainsText(MockCaptureWatchExecute, 'new_file.txt'));
end;

procedure TTestUtilsWatcher.TestIgnoreFile;
var
  LThread: TThread;
begin
  AppendToArray(CustomIgnoreFiles, 'ignore_file.txt');
  CustomTimeout := 50;

  LThread := TThread.CreateAnonymousThread(RunWatcher);
  LThread.FreeOnTerminate := True;
  LThread.Start;

  // change working folder
  SaveFileContent(ConcatPaths([FWorkingFolder, 'ignore_file.txt']), 'test content');

  while Finished = 0 do
    Sleep(50);

  AssertFalse(
    'shoud not detect change creation on ignore_file.txt ' + MockCaptureWatchExecute, 
    ContainsText(MockCaptureWatchExecute, 'ignore_file.txt')); 
end;

procedure TTestUtilsWatcher.TestIgnoreExtension;
var
  LThread: TThread;
begin
  AppendToArray(CustomIgnoreExtensions, '.txt');
  CustomTimeout := 50;

  LThread := TThread.CreateAnonymousThread(RunWatcher);
  LThread.FreeOnTerminate := True;
  LThread.Start;

  // change working folder
  SaveFileContent(ConcatPaths([FWorkingFolder, 'ignore_file.txt']), 'test content');

  while Finished = 0 do
    Sleep(50);

  AssertFalse(
    'shoud not detect change creation on ignore_file.txt ' + MockCaptureWatchExecute, 
    ContainsText(MockCaptureWatchExecute, 'ignore_file.txt')); 
end;

procedure TTestUtilsWatcher.TestTimeout;
var
  LThread: TThread;
begin
  CustomTimeout := 50;

  LThread := TThread.CreateAnonymousThread(RunWatcher);
  LThread.FreeOnTerminate := True;
  LThread.Start;

  while Finished = 0 do
    Sleep(100);

  AssertTrue(
    'shoud detect timeout exceeded', 
    ContainsText(MockCaptureWatchExecute, 'timeout exceeded'));    
end;

initialization
  RegisterTest(TTestUtilsWatcher);

end.