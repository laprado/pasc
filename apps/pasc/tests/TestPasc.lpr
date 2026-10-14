program TestPasc;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, 
  SysUtils,
  consoletestrunner, 
  Resources,
  TestUtilsIO,
  TestUtilsLeak,
  TestUtilsAdopt,
  TestUtilsBoss,
  TestUtilsOutput,
  TestUtilsResources,
  TestUtilsShell,
  TestUtilsTests,
  TestUtilsWatcher,
  TestUtilsWorkspace,
  TestCommandAdd,
  TestCommandBuild,
  TestCommandClean,
  TestCommandDeps,
  TestCommandInstall,
  TestCommandNew,
  TestCommandTest, 
  TestCommandWatch,
  MockCommandBuilder;

type

  { TTestPascRunner }

  TTestPascRunner = class(TTestRunner)
  protected
  // override the protected methods of TTestRunner to customize its behavior
  end;

{$R *.res}

var
  Application: TTestPascRunner;
  HeapFileName: string;

begin
  {$IF DECLARED(UseHeapTrace)}
  HeapFileName := ConcatPaths([ExtractFilePath(ParamStr(0)), 'heap.trc']);
  if FileExists(HeapFileName) then
    DeleteFile(HeapFileName);
  SetHeapTraceOutput(HeapFileName);
  {$ENDIF}
  Application := TTestPascRunner.Create(nil);
  Application.Initialize;
  Application.Title := 'pasc console test runner';
  Application.Run;
  Application.Free;
end.
