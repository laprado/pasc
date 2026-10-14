unit TestUtilsLeak;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, 
  SysUtils, 
  fpcunit,
  testregistry,
  Command.Interfaces,
  Command.Builder,
  Utils.Interfaces,

  Utils.Leak;

type

  TTestUtilsLeak = class(TTestCase)
  private
    FBuilder: ICommandBuilder;
    FLeakReport: ILeakReport;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAddItem;
    procedure TestAddRelativePath;
    procedure TestCreateLeakItem;
    procedure TestGetNextStringOf;
    procedure TestGetNextStringOfEmpty;
    procedure TestParseContentLeakSimple;
    procedure TestParseContentLeakNone;
    procedure TestParseContentLeakIncompleteInfo;
    procedure TestOutputNoLeak;
    procedure TestOutputMissingLeak;
    procedure TestOutputLeakSimple;
    procedure TestOutputLeakIncomplete;
  end;

implementation

uses
  StrUtils,
  Resources;

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

procedure TTestUtilsLeak.SetUp;
begin
  FBuilder := TCommandBuilder.Create(ParamStr(0));
  FBuilder.Output := MockOutput;
  FBuilder.OutputColor := MockOutputColor;
  CapturedOutput := '';  
  FLeakReport := TLeakReport.New(FBuilder, ExtractFilePath(ParamStr(0)));
end;

procedure TTestUtilsLeak.TearDown;
begin
end;

procedure TTestUtilsLeak.TestAddItem;
var
  LItem: ILeakItem;
begin
  LItem := TLeakItem.New('Leak', '8');
  LItem.Source := 'source';
  FLeakReport.AddItem(LItem);

  AssertTrue('Should have an item on LeakData array', Length(FLeakReport.LeakData) = 1);
  AssertEquals('Leak', FLeakReport.LeakData[0].Status);
  AssertEquals('8', FLeakReport.LeakData[0].Size);
  AssertEquals('source', FLeakReport.LeakData[0].Source);
end;

procedure TTestUtilsLeak.TestAddRelativePath;
var
  LExpected: string;
begin
  LExpected := ConcatPaths(['.', 'tests', 'resources', 'leak_none.txt']);
  if (EndsText('tests', GetCurrentDir) or EndsText('tests' + PathDelim, GetCurrentDir)) then
    LExpected := ConcatPaths(['.', 'resources', 'leak_none.txt']);

  // vscode is not able to open files in the project source path using relative path
  // AssertEquals(
  //   LExpected,
  //   FLeakReport.AddRelativePath('leak_none.txt')    
  // );
end;

procedure TTestUtilsLeak.TestCreateLeakItem;
var
  LContent: TStringList;
begin
  LContent := TStringList.Create;
  try
    LContent.Text := GetTestResource('leak_simple');
    FLeakReport.CreateLeakItem(LContent, 5);
  finally
    LContent.Free;
  end;
  AssertEquals('Should have an item on LeakData array', 1, Length(FLeakReport.LeakData));
  AssertEquals('Leak', FLeakReport.LeakData[0].Status);
  AssertEquals('8', FLeakReport.LeakData[0].Size);
  AssertTrue(
    'Source should contain text CallCalcTest', 
    ContainsText(FLeakReport.LeakData[0].Source, 'CallCalcTest'));
  AssertTrue(
    'Source should contain text 16:1', 
    ContainsText(FLeakReport.LeakData[0].Source, '16:1'));
end;

procedure TTestUtilsLeak.TestGetNextStringOf;
begin
  AssertEquals(
    FLeakReport.GetNextStringOf('Call trace for block $0000000001518E30 size 8', 'size'),
    '8');

  AssertEquals(
    FLeakReport.GetNextStringOf('Call trace for block $0000000001518E30 size 8', 'block'),
    '$0000000001518E30');    
end;

procedure TTestUtilsLeak.TestGetNextStringOfEmpty;
begin
  AssertEquals('', FLeakReport.GetNextStringOf('', ''));
  AssertEquals('', FLeakReport.GetNextStringOf('', 'field'));
  AssertEquals('', FLeakReport.GetNextStringOf('line string with content', 'field'));
  AssertEquals('', FLeakReport.GetNextStringOf('line string with content', ''));
  AssertEquals('', FLeakReport.GetNextStringOf('line string with content field', 'field'));
end;

procedure TTestUtilsLeak.TestParseContentLeakSimple;
begin
  FLeakReport.ParseHeapTrace(GetTestResource('leak_simple'));
  AssertEquals('Should report one leak', 1, Length(FLeakReport.LeakData));
end;

procedure TTestUtilsLeak.TestParseContentLeakNone;
begin
  FLeakReport.ParseHeapTrace(GetTestResource('leak_none'));
  AssertEquals('Should report one leak', 0, Length(FLeakReport.LeakData));
end;

procedure TTestUtilsLeak.TestParseContentLeakIncompleteInfo;
begin
  FLeakReport.ParseHeapTrace(GetTestResource('leak_incomplete'));
  AssertEquals('Should report two leaks', 2, Length(FLeakReport.LeakData));
  AssertTrue('Should contain text that indicates incomplete info', 
    ContainsText(FLeakReport.LeakData[0].Source, 'no details found in heap trace file'))
end;

procedure TTestUtilsLeak.TestOutputNoLeak;
begin
  FLeakReport.ParseHeapTrace(GetTestResource('leak_none'));
  FLeakReport.Output;

  AssertTrue(
    'Must contain text indicating that no memory leak occurred: 0 unfreed memory...',
    ContainsText(CapturedOutput, '0 unfreed memory'));
end;

procedure TTestUtilsLeak.TestOutputMissingLeak;
begin
  FLeakReport.ParseHeapTrace('no file');
  FLeakReport.Output;

  AssertTrue(
    'Must contain text indicating that memory leak info is missing',
    ContainsText(CapturedOutput, 'missing data with leak information'));  
end;

procedure TTestUtilsLeak.TestOutputLeakSimple;
begin
  FLeakReport.ParseHeapTrace(GetTestResource('leak_simple'));
  FLeakReport.Output;

  AssertTrue(
    'Must contain text pointing to a memory leak',
    ContainsText(CapturedOutput, 'Leak ['));    

  AssertTrue(
    'Must contain text indicating the method that caused the leak: CalcTest',
    ContainsText(CapturedOutput, 'CalcTest'));    
end;

procedure TTestUtilsLeak.TestOutputLeakIncomplete;
begin
  FLeakReport.ParseHeapTrace(GetTestResource('leak_incomplete'));
  FLeakReport.Output;

  AssertTrue(
    'Must contain text pointing to incomplete data' + CapturedOutput,
    ContainsText(CapturedOutput, 'no details found in heap trace file'));     
end;

initialization
  RegisterTest(TTestUtilsLeak);

end.

