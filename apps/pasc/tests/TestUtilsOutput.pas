unit TestUtilsOutput;

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

  TTestUtilsOutput= class(TTestCase)
  private
    FBuilder: ICommandBuilder;
    FExeName: string;
  protected
    procedure SetUp; override;
  published
    procedure TestUtilsOutputInfo;
    procedure TestUtilsOutputError;
  end;

implementation

uses
  StrUtils,
  MockCommandBuilder,
  Command.Build,
  Utils.Output;

procedure TTestUtilsOutput.SetUp;
begin
  FExeName := ExtractFileName(ParamStr(0));
  FBuilder := TCommandBuilder.Create(FExeName);
  MockSetup(FBuilder);
end;

procedure TTestUtilsOutput.TestUtilsOutputInfo;
begin
  // act
  OutputInfo(FBuilder, 'info_title', 'this a test info');

  // assert
  AssertTrue(
    'Output should contain keyword: "info_title" ',
    ContainsText(MockOutputCaptured, 'info_title'));
  AssertTrue(
    'Output should contain keyword: "this a test info" ',
    ContainsText(MockOutputCaptured, 'this a test info'));
end;

procedure TTestUtilsOutput.TestUtilsOutputError;
begin
  // act
  OutputError(FBuilder, 'error_title', 'this a error message');

  // assert
  AssertTrue(
    'Output should contain keyword: "error_title" ',
    ContainsText(MockOutputCaptured, 'error_title'));
  AssertTrue(
    'Output should contain keyword: "this a error message" ',
    ContainsText(MockOutputCaptured, 'this a error message'));
end;

initialization
  RegisterTest(TTestUtilsOutput);
 
end.