unit TestUtilsTemplates;

{$MODE DELPHI}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpcunit,
  testregistry;

type

  TTestUtilsTemplates = class(TTestCase)
  private
    FTempDir: string;
  protected
    procedure SetUp; override;
  published
    procedure TestGetTemplateNames;
    procedure TestFindTemplate;
    procedure TestFindTemplateIgnoresCase;
    procedure TestFindTemplateUnknown;
    procedure TestTemplateResourcesExist;
    procedure TestWriteTemplateFiles;
  end;

implementation

uses
  StrUtils,
  FileUtil,
  Utils.IO,
  Utils.Resources,
  Utils.Templates;

procedure TTestUtilsTemplates.SetUp;
begin
  FTempDir := ConcatPaths([GetTempDir, '.TestUtilsTemplates', TestName]);
  if DirectoryExists(FTempDir) then
    DeleteDirectory(FTempDir, False);
  ForceDirectories(FTempDir);
end;

procedure TTestUtilsTemplates.TestGetTemplateNames;
begin
  AssertEquals('cli, web', GetTemplateNames);
end;

procedure TTestUtilsTemplates.TestFindTemplate;
var
  LTemplate: TTemplate;
begin
  AssertTrue('web should be found', FindTemplate('web', LTemplate));
  AssertEquals('web', LTemplate.Name);
  AssertEquals('github.com/HashLoad/horse', LTemplate.Dependencies[0]);
end;

procedure TTestUtilsTemplates.TestFindTemplateIgnoresCase;
var
  LTemplate: TTemplate;
begin
  AssertTrue('CLI should be found', FindTemplate(' CLI ', LTemplate));
  AssertEquals('cli', LTemplate.Name);
  AssertEquals('github.com/laprado/pascli', LTemplate.Dependencies[0]);
end;

procedure TTestUtilsTemplates.TestFindTemplateUnknown;
var
  LTemplate: TTemplate;
begin
  AssertFalse('an unknown template should not be found', FindTemplate('desktop', LTemplate));
end;

procedure TTestUtilsTemplates.TestTemplateResourcesExist;
var
  LTemplate: TTemplate;
  LFile: TTemplateFile;
begin
  for LTemplate in GetTemplates do
    for LFile in LTemplate.Files do
      AssertTrue(
        'resource ' + LFile.Resource + ' of ' + LTemplate.Name + ' should not be empty',
        GetResource(LFile.Resource) <> '');
end;

procedure TTestUtilsTemplates.TestWriteTemplateFiles;
var
  LTemplate: TTemplate;
  LFiles: TArray<string>;
  LFile, LAppDir: string;
begin
  for LTemplate in GetTemplates do
  begin
    LAppDir := ConcatPaths([FTempDir, LTemplate.Name]);
    LFiles := WriteTemplateFiles(LTemplate, LAppDir, 'sample');

    AssertEquals(Length(LTemplate.Files), Length(LFiles));
    AssertTrue(LTemplate.Name + ' project should be named after the app',
      FileExists(ConcatPaths([LAppDir, 'sample.lpi'])));
    AssertTrue(LTemplate.Name + ' test project should be named after the app',
      FileExists(ConcatPaths([LAppDir, 'tests', 'Testsample.lpi'])));
    AssertTrue(LTemplate.Name + ' program should be named after the app',
      ContainsStr(GetFileContent(ConcatPaths([LAppDir, 'sample.lpr'])), 'program sample;'));
    for LFile in LFiles do
    begin
      AssertTrue(LFile + ' should exist', FileExists(LFile));
      AssertFalse(LFile + ' should not have the placeholder',
        ContainsStr(GetFileContent(LFile), '{APPNAME}'));
    end;
  end;

  AssertTrue('web features should be in their own folders', FileExists(
    ConcatPaths([FTempDir, 'web', 'src', 'features', 'customers', 'Customers.Service.pas'])));
end;

initialization
  RegisterTest(TTestUtilsTemplates);

end.
