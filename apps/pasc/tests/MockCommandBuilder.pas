unit MockCommandBuilder;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, 
  StrUtils,
  Classes,
  rtti, 
  typinfo,
  Command.Interfaces,
  Utils.Interfaces;

  procedure MockSetup(ABuilder: ICommandBuilder);
  procedure MockCommand(ABuilder: ICommandBuilder);
  function MockInputLn: string;
  procedure MockOutput(const AMessage: string);
  procedure MockOutputColor(const AMessage: string; const AColor: byte);
  function MockShell(const AProgram: string; AParams: TArray<string>; out AExitCode: Integer): string;
  function MockWatchExecute(const AContent: string; const AEvent: TWatcherEvent): Boolean;

var
  MockCommandCapture, MockInputLnResult, MockOutputCaptured, MockShellCapture, 
  MockCaptureWatchExecute: string;
  MockStart, MockTimeout: QWord;
  MockShellExitCodeCapture: Integer;

implementation

procedure MockSetup(ABuilder: ICommandBuilder);
begin
  MockCommandCapture := '';
  MockInputLnResult := '';
  MockOutputCaptured := '';
  MockShellCapture := '';
  ABuilder.InputLn := MockInputLn;
  ABuilder.Output := MockOutput;
  ABuilder.OutputColor := MockOutputColor;
  MockStart := GetTickCount64;
  MockTimeout := 1000;
end;

procedure MockCommand(ABuilder: ICommandBuilder);
begin  
  if not Assigned(ABuilder) then
    MockCommandCapture := 'ABuilder not assigned'
  else
    MockCommandCapture := 'executed';
end;

function MockInputLn: string;
begin
  Result := MockInputLnResult;
  if (GetTickCount64 - MockStart) > MockTimeout then
    raise Exception.Create('Timeout of ' + IntToStr(MockTimeout) + ' exceeded');
end;

procedure MockOutput(const AMessage: string);
begin
  MockOutputCaptured := MockOutputCaptured + #13#10 + AMessage;
end;

procedure MockOutputColor(const AMessage: string; const AColor: byte);
begin
  MockOutputCaptured := MockOutputCaptured + AMessage;
end;

function MockShell(const AProgram: string; AParams: TArray<string>; out AExitCode: Integer): string;
var
  LParam: string;
begin
  MockShellExitCodeCapture := AExitCode;
  MockShellCapture := IfThen(MockShellCapture <> '', MockShellCapture + #13#10, '') + AProgram;
  for LParam in AParams do
    MockShellCapture := MockShellCapture + ' ' + LParam;
  Result := MockShellCapture;
end;

function MockWatchExecute(const AContent: string; const AEvent: TWatcherEvent): Boolean;
begin
  MockCaptureWatchExecute := 
    IfThen(MockCaptureWatchExecute <> '', MockCaptureWatchExecute + #13#10, '') + 
    AContent;
  Result := not (AEvent = weFirstRun);
end;

end.