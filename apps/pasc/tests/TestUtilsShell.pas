unit TestUtilsShell;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, 
  SysUtils, 
  StrUtils,
  fpcunit,
  testregistry,
  Utils.Shell;

type

  TTestUtilsShell = class(TTestCase)
  private
    FExePath: string;
  public
    procedure Setup; override;
  published
    procedure TestShellCommand;
    procedure TestShellCommandNotExists;
    {$IF DEFINED(UNIX)}
    procedure TestShellCommandLongOutput;
    {$ENDIF}
    procedure TestGetParametersFromDoubleQuotes;
    procedure TestGetParametersFromSingleQuotes;
  end;

implementation

procedure TTestUtilsShell.Setup;
begin
  FExePath := ExtractFilePath(ParamStr(0));
end;

procedure TTestUtilsShell.TestShellCommand;
var
  LActual, LExpected: string;
  LExitCode: Integer = 0;

  function PreparePathToCompare(const APath: string): string;
  begin
    Result := DelChars(APath, '/');
    Result := DelChars(Result, '\');
    Result := DelChars(Result, ':');
    Result := LowerCase(Result);
  end;

begin
  LActual := PreparePathToCompare(StringReplace(ShellCommand('pwd', [], LExitCode), #13#10, '', [rfReplaceAll]));
  LExpected := PreparePathToCompare(GetCurrentDir);
  AssertEquals(LExpected, LActual);
end;

procedure TTestUtilsShell.TestShellCommandNotExists;
var
  LActual: string;
  LExitCode: Integer = 0;
begin
  LActual := StringReplace(ShellCommand('not_exists_command', [], LExitCode), #13#10, '', [rfReplaceAll]);
  AssertTrue('Should return an error message: "Error when executing', ContainsText(LActual, 'Error when executing'));
  AssertTrue(
    #13#10 +
    'Exit code should be different of 0'#13#10 +
    'Output from ShellCommand: '#13#10 +
    LActual, 
    0 <> LExitCode);
end;

{$IF DEFINED(UNIX)}
procedure TTestUtilsShell.TestShellCommandLongOutput;
var
  LLines: TStringList;
  LExitCode: Integer = 0;
  I: Integer;
begin
  // much more than one read of the pipe: the lines must not break where a read ends
  LLines := TStringList.Create;
  try
    LLines.Text := ShellCommand('/bin/sh', ['-c',
      'i=0; while [ $i -lt 300 ]; do echo "line $i ' + StringOfChar('x', 100) + '"; i=$((i+1)); done'], LExitCode);
    AssertEquals('exit code', 0, LExitCode);
    AssertEquals('every line once', 300, LLines.Count);
    for I := 0 to LLines.Count - 1 do
      AssertEquals('line ' + IntToStr(I), 'line ' + IntToStr(I) + ' ' + StringOfChar('x', 100), LLines[I]);
  finally
    LLines.Free;
  end;
end;
{$ENDIF}

procedure TTestUtilsShell.TestGetParametersFromDoubleQuotes;
var
  LArray: TArray<string> = [];
  LParams: string;
begin
  // arrange
  LParams := 'command "hello world!"';

  // act
  LArray := GetParametersFrom(LParams);

  // assert
  AssertEquals(2, Length(LArray));
  AssertEquals('command', LArray[0]);
  AssertEquals('"hello world!"', LArray[1]);
end;

procedure TTestUtilsShell.TestGetParametersFromSingleQuotes;
var
  LArray: TArray<string> = [];
  LParams: string;
begin
  // arrange
  LParams := 'command ''hello world!''';

  // act
  LArray := GetParametersFrom(LParams);

  // assert
  AssertEquals(2, Length(LArray));
  AssertEquals('command', LArray[0]);
  AssertEquals('"hello world!"', LArray[1]);
end;


initialization
  RegisterTest(TTestUtilsShell);

end.
