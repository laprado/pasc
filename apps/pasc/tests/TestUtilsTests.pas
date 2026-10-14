unit TestUtilsTests;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, 
  SysUtils, 
  fpcunit,
  testregistry,
  Command.Interfaces,
  Command.Builder,
  Utils.Tests;

type

  { TTestUtilsTests }

  TTestUtilsTests = class(TTestCase)
  private
    FBuilder: ICommandBuilder;
    FTestReport: TTestReport;
    FXmlFile: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;

    procedure TryParseInvalidXml;
  published
    procedure TestAddItem;
    procedure TestParseXml;
    procedure TestParseXmlInvalid;
    procedure TestParseXmlNoTests;
    procedure TestParseXmlError;
    procedure TestOutputStructure;
    procedure TestOutputItemsMatchesSummary;
  end;

implementation

uses
  StrUtils,
  Resources,
  XMLRead;

var
  CapturedOutput: string;

procedure MockOutput(const AMessage: string);
begin
  CapturedOutput := CapturedOutput + AMessage + #13#10;
end;

procedure MockOutputColor(const AMessage: string; const AColor: Byte);
begin
  CapturedOutput := CapturedOutput + AMessage;
end;

procedure TTestUtilsTests.SetUp;
begin
  FBuilder := TCommandBuilder.Create(ParamStr(0));
  FBuilder.Output := MockOutput;
  FBuilder.OutputColor := MockOutputColor;
  CapturedOutput := '';  
  FTestReport := TTestReport.New(FBuilder, ExtractFilePath(ParamStr(0)));
  FXmlFile := ConcatPaths([ExtractFilePath(ParamStr(0)), 'xml', 'TestSample.xml']);
end;

procedure TTestUtilsTests.TearDown;
begin
  FTestReport.Free;
end;

procedure TTestUtilsTests.TestAddItem;
var
  LItem: TTestCaseItem;
begin
  LItem := TTestCaseItem.New('TestsSuite', 'TestBasic');
  LItem.Status := 'OK';
  LItem.Time := '0.01';
  FTestReport.AddItem(LItem);

  AssertTrue('Should have an item on LeakData array', Length(FTestReport.TestCaseData) = 1);
  AssertEquals('OK', FTestReport.TestCaseData[0].Status);
  AssertEquals('0.01', FTestReport.TestCaseData[0].Time);
end;

procedure TTestUtilsTests.TestParseXml;
var
  I: Integer;
  LFailedFound: Boolean = false;
begin
  FTestReport.ParseXmlTestsFile('TestApp', FXmlFile);
  AssertEquals('Should report one leak', 23, Length(FTestReport.TestCaseData));
  AssertEquals(22, FTestReport.TestsPassed);
  AssertEquals(1, FTestReport.TestsFailed);
  AssertEquals(6, FTestReport.TestSuiteCount);

  AssertEquals('OK', FTestReport.TestCaseData[0].Status);
  AssertEquals('00:00:00.000', FTestReport.TestCaseData[0].Time);
  AssertEquals('TTestCommandTest', FTestReport.TestCaseData[0].TestSuite);
  AssertEquals('TestHookUp', FTestReport.TestCaseData[0].TestCase);
  
  for I := 0 to Length(FTestReport.TestCaseData) - 1 do
    if SameText('Failed', FTestReport.TestCaseData[I].Status) then
    begin
      LFailedFound := True;
      AssertEquals('Failed', FTestReport.TestCaseData[I].Status);
      AssertEquals('00:00:00.002', FTestReport.TestCaseData[I].Time);
      AssertEquals('TTestUtilsLeak', FTestReport.TestCaseData[I].TestSuite);
      AssertEquals('TestOutput', FTestReport.TestCaseData[I].TestCase);
      break;
    end;

  AssertTrue('Should find at least one failed test.', LFailedFound);

end;

procedure TTestUtilsTests.TryParseInvalidXml;
var
  LXmlFile: string;
begin
  LXmlFile := ConcatPaths([ExtractFilePath(ParamStr(0)), 'xml', 'TestInvalid.xml']);
  FTestReport.ParseXmlTestsFile('TestApp', LXmlFile);
end;

procedure TTestUtilsTests.TestParseXmlInvalid;
begin
  AssertException(
    'Should raise an exception when try to parse an invalid xml file', 
    EXMLReadError,
    TryParseInvalidXml);
end;

procedure TTestUtilsTests.TestParseXmlNoTests;
var
  LXmlFile: string;
begin
  LXmlFile := ConcatPaths([ExtractFilePath(ParamStr(0)), 'xml', 'TestEmpty.xml']);
  FTestReport.ParseXmlTestsFile('TestApp', LXmlFile);

  AssertEquals(0, FTestReport.TestCaseCount);
  AssertEquals(0, FTestReport.TestSuiteCount);
  AssertEquals(0, FTestReport.TestsPassed);
  AssertEquals(0, FTestReport.TestsFailed);
end;

procedure TTestUtilsTests.TestParseXmlError;
var
  LXmlFile: string;
begin
  LXmlFile := ConcatPaths([ExtractFilePath(ParamStr(0)), 'xml', 'TestError.xml']);
  FTestReport.ParseXmlTestsFile('TestApp', LXmlFile);
  AssertEquals(2, FTestReport.TestsFailed);
end;

procedure TTestUtilsTests.TestOutputStructure;
begin
  FTestReport.ParseXmlTestsFile('TestApp', FXmlFile);
  FTestReport.Output;

  AssertTrue(
    'Must contain text "Executable TestApp"',
    ContainsText(CapturedOutput, 'Executable TestApp'));

  AssertTrue(
    'Must contain text "Starting"',
    ContainsText(CapturedOutput, 'Starting'));    

  AssertTrue(
    'Must contain text "OK ["',
    ContainsText(CapturedOutput, 'OK ['));

  AssertTrue(
    'Must contain text "Summary ["',
    ContainsText(CapturedOutput, 'Summary ['));    

end;

procedure TTestUtilsTests.TestOutputItemsMatchesSummary;
var
  LOutput: TStringList;
  I, LTestCaseCount, LTestPassed, LTestFailed, LTestSuiteCount: Integer;
  LText, LSuite: string;
  LTestSuites: string = '';

  function GetNextStringOf(const AText: string; const AField: string): string;
  var
    LIndex: Integer;
    LValue: string;
  begin
    LIndex := Pos(AField, AText);
    if LIndex <= 0 then
      exit('');

    LIndex := LIndex + Length(AField);
    LValue := Trim(Copy(AText, LIndex));
    Result := LValue.Split([' ', '.'])[0];
  end;

begin
  FTestReport.ParseXmlTestsFile('TestApp', FXmlFile);
  FTestReport.Output;

  LOutput := TStringList.Create;
  try
    LOutput.Text := CapturedOutput;

    LTestCaseCount := 0;
    LTestPassed := 0;
    LTestFailed := 0;
    LTestSuiteCount := 0;

    for I := 0 to LOutput.Count -1 do
    begin
      LText := LOutput.Strings[I];

      if ContainsText(LText, 'OK [') then
      begin
        Inc(LTestCaseCount);
        Inc(LTestPassed);

        LSuite := GetNextStringOf(LText, ']');
        if not ContainsText(LTestSuites, LSuite) then
          LTestSuites := LTestSuites + LSuite + ',';
      end;

      if ContainsText(LText, 'Failed [') then
      begin
        Inc(LTestCaseCount);
        Inc(LTestFailed);

        LSuite := GetNextStringOf(LText, ']');
        if not ContainsText(LTestSuites, LSuite) then
          LTestSuites := LTestSuites + LSuite + ',';
      end;
    end;
    LTestSuiteCount := WordCount(LTestSuites, [',']) + 1;
  finally
    LOutput.Free;
  end;

  // matches report variables
  AssertEquals(FTestReport.TestSuiteCount, LTestSuiteCount);
  AssertEquals(FTestReport.TestCaseCount, LTestCaseCount);
  AssertEquals(FTestReport.TestsPassed, LTestPassed);
  AssertEquals(FTestReport.TestsFailed, LTestFailed);

  // matches strings from output
  LText := Format(
    'Starting %d test cases across %d test suites', 
    [LTestCaseCount, LTestSuiteCount]);
  AssertTrue(
    'Starting text should match quantities => ' + LText,
    ContainsText(CapturedOutput, LText));

  // matches strings "28 tests cases run: 28 passed, 0 failed.""
  LText := Format(
    '%d tests cases run: %d passed, %d failed', 
    [LTestCaseCount, LTestPassed, LTestFailed]);
  AssertTrue(
    'Summary text should match quantities => ' + LText,
    ContainsText(CapturedOutput, LText));
  
end;

initialization
  RegisterTest(TTestUtilsTests);

end.
