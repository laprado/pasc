unit TestUtilsIO;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, 
  SysUtils, 
  fpcunit,
  testregistry,
  Utils.IO;

type

  TTestUtilsIO = class(TTestCase)
  private
    FExePath: string;
    FCurrentDir: string;
  public
    procedure Setup; override;
  published
    procedure TestGetFileContent;
    procedure TestGetJsonFileContentWithOutComments;
    procedure TestSaveFileContent;
    procedure TestFindInCodeFile;
    procedure TestFindFile;
    procedure TestFindProjectFile;
    procedure TestFindSourceFile;
  end;

implementation

uses
  StrUtils;

procedure TTestUtilsIO.Setup;
begin
  FExePath := ExtractFilePath(ParamStr(0));
  FCurrentDir := GetCurrentDir;
end;

procedure TTestUtilsIO.TestFindFile;
begin
  AssertTrue(
    'Should find the file in the specified path',
    ContainsText(
      FindFile(FExePath, ExtractFileName(ParamStr(0))),
      ExtractFileName(ParamStr(0))
    )
  );
end;

procedure TTestUtilsIO.TestFindInCodeFile;
var
  LContent: TStringList;
  LTextToFind, LExpected, LActual: string;
begin
  // arrange
  LTextToFind := 'TextToBeFound';
  LExpected := '2:1';

  // act
  LContent := TStringList.Create;
  try
    LContent.Add('first line');
    LContent.Add('second line: "TextToBeFound" - filler text ');
    LContent.Add('last line');
    LActual := FindInCodeFile(LContent, LTextToFind);
  finally
    LContent.Free;
  end;

  // assert
  AssertEquals(LExpected, LActual);
end;

procedure TTestUtilsIO.TestGetFileContent;
var
  LActual: string;
begin
  LActual := GetFileContent(ConcatPaths([FExePath, 'TestPasc.lpr']));

  AssertTrue('File should have content', Length(LActual) > 0);
end;

procedure TTestUtilsIO.TestGetJsonFileContentWithOutComments;
var
  LActual: string;
begin
  LActual := GetFileContent(ConcatPaths([FCurrentDir, '.vscode/tasks.json']));

  AssertTrue('Json file tasks.josn should have content', Length(LActual) > 0);
end;

procedure TTestUtilsIO.TestSaveFileContent;
var
  LContent, LFile, LActualContent: string;
  LExists: Boolean;
begin
  // arrange
  LContent := 'sample content - can be deleted';
  LFile := ConcatPaths([FExePath, 'TestSaveFileContent.log']);

  // act
  SaveFileContent(LFile, LContent);
  LActualContent := GetFileContent(LFile);
  LExists := FileExists(LFile);
  if LExists then
    DeleteFile(LFile);

  // assert
  AssertTrue('File was not created', LExists);
  AssertTrue('Text should be returned by GetFileContent function.', ContainsText(LActualContent, LContent));
end;

procedure TTestUtilsIO.TestFindProjectFile;
var
  LPath: string;
begin
  LPath := FCurrentDir;
  if not ((EndsText('tests', LPath) or EndsText('tests' + PathDelim, LPath))) then
    LPath := ConcatPaths([LPath, 'tests']);

  AssertEquals(
    ChangeFileExt(ParamStr(0), '.lpr'), 
    FindProjectFile(LPath, ''));

  AssertEquals(
    ChangeFileExt(ParamStr(0), '.lpr'), 
    FindProjectFile(LPath, 'TestRunner'));
end;

procedure TTestUtilsIO.TestFindSourceFile;
begin
  AssertTrue('Source file shoud exsits', FindSourceFile(FCurrentDir) <> '');
end;

initialization
  RegisterTest(TTestUtilsIO);

end.
