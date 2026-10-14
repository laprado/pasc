unit TestCommandClean;

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

  TTestCommandClean= class(TTestCase)
  private
    FBuilder: ICommandBuilder;
    FExeName: string;
    FCheckFile: string;
    FCurrentDir: string;
    procedure AnswerCancel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCheckAnswer;
    procedure TestCheckAnswerAll;
    procedure TestCheckAnswerCancel;
    procedure TestDeleteFolder;
    procedure TestCleanForce;
    procedure TestCleanMockInput;
    procedure TestCleanCommandRegistry;
  end;

implementation

uses
  StrUtils,
  MockCommandBuilder,
  Command.Clean,
  Utils.IO;

procedure TTestCommandClean.SetUp;
var
  LTempDir: string;
begin
  FCurrentDir := GetCurrentDir;
  FExeName := ExtractFileName(ParamStr(0));
  FBuilder := TCommandBuilder.Create(FExeName);
  MockSetup(FBuilder);
  Command.Clean.Registry(FBuilder);
  AnsweredAll := False;

  SetCurrentDir(GetTempDir);
  LTempDir := ConcatPaths([GetTempDir, 'TestPasc']);
  if not DirectoryExists(LTempDir) then
    CreateDir('TestPasc');
  SetCurrentDir(LTempDir);

  if not DirectoryExists(ConcatPaths([LTempDir, 'lib'])) then
    CreateDir('lib');

  FCheckFile := ConcatPaths([LTempDir, 'lib', 'test.txt']);

  SaveFileContent(FCheckFile, 'test content');  
end;

procedure TTestCommandClean.TearDown;
begin
  SetCurrentDir(FCurrentDir);
  //AnsweredAll := False;
end;

procedure TTestCommandClean.TestCheckAnswer;
begin
  MockInputLnResult := 'y';
  CheckAnswer(FBuilder);

  AssertFalse('AnsweredAll should be false', AnsweredAll);
end;

procedure TTestCommandClean.TestCheckAnswerAll;
begin
  MockInputLnResult := 'a';
  CheckAnswer(FBuilder);

  AssertTrue('AnsweredAll should be true', AnsweredAll);  
end;

procedure TTestCommandClean.AnswerCancel;
begin
  CheckAnswer(FBuilder);  
end;

procedure TTestCommandClean.TestCheckAnswerCancel;
begin
  MockInputLnResult := 'c';
  AssertException('raise exception to abort', Exception, AnswerCancel);
end;

procedure TTestCommandClean.TestCleanForce;
begin
  FBuilder.UseArguments(['clean', '--force']);
  FBuilder.Parse;

  CleanCommand(FBuilder);

  // assert
  AssertTrue(
    'File should not exist.', 
    not FileExists(FCheckFile));
end;

procedure TTestCommandClean.TestCleanMockInput;
begin
  FBuilder.UseArguments(['clean']);
  FBuilder.Parse;

  MockInputLnResult := 'y';
  CleanCommand(FBuilder);

  // assert
  AssertTrue('Should ask for confirmation', ContainsText(MockOutputCaptured, 'Are you sure?'));
  AssertTrue(
    'File should not exist.', 
    not FileExists(FCheckFile));
end;

procedure TTestCommandClean.TestDeleteFolder;
begin
  MockInputLnResult := 'a';
  DeleteFolder(FBuilder, GetCurrentDir, 'lib');

  AssertFalse('Folder should not exist', DirectoryExists(ConcatPaths([GetCurrentDir, 'lib'])));
end;

procedure TTestCommandClean.TestCleanCommandRegistry;
begin
  AssertEquals('clean', FBuilder.Commands[0].Name);
end;

initialization

  RegisterTest(TTestCommandClean);
end.

