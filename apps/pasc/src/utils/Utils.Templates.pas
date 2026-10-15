/// <summary> Unit which has the app templates used by pasc new --template. A template is a set
/// of files embedded as resources, written to the app folder with the app name in place of
/// {APPNAME}, and the boss dependencies the app needs.
/// </summary>
unit Utils.Templates;

{$MODE DELPHI}{$H+}

interface

type

  /// <summary> A file of a template: the resource with its content and the path where it is
  /// written, relative to the app folder, with / as separator and {APPNAME} in place of the
  /// app name. </summary>
  TTemplateFile = record
    Resource: string;
    Target: string;
  end;

  /// <summary> An app template. </summary>
  TTemplate = record
    /// <summary> Name given to --template. </summary>
    Name: string;
    /// <summary> One line description, shown in the help. </summary>
    Description: string;
    /// <summary> boss dependencies installed in the workspace for the app. </summary>
    Dependencies: TArray<string>;
    /// <summary> Paths ignored by git, relative to the app folder, besides its executables.
    /// </summary>
    Ignore: TArray<string>;
    Files: TArray<TTemplateFile>;
  end;

  TTemplates = TArray<TTemplate>;

  /// <summary> Returns the available templates. </summary>
  function GetTemplates: TTemplates;

  /// <summary> Finds a template by its name, ignoring case. Returns false if there is none.
  /// </summary>
  /// <param name="AName"> Template name. </param>
  /// <param name="ATemplate"> Returns the template found. </param>
  function FindTemplate(const AName: string; out ATemplate: TTemplate): Boolean;

  /// <summary> Returns the names of the available templates, separated by commas. </summary>
  function GetTemplateNames: string;

  /// <summary> Writes the files of the template to the app folder, creating the subfolders,
  /// with the app name in place of {APPNAME}. Returns the files written. </summary>
  /// <param name="ATemplate"> Template whose files are written. </param>
  /// <param name="AAppDir"> App folder. </param>
  /// <param name="AAppName"> App name. </param>
  function WriteTemplateFiles(const ATemplate: TTemplate; const AAppDir, AAppName: string): TArray<string>;

implementation

uses
  SysUtils,
  Utils.IO,
  Utils.Resources;

const
  APP_NAME_PLACEHOLDER = '{APPNAME}';

function TemplateFile(const AResource, ATarget: string): TTemplateFile;
begin
  Result.Resource := AResource;
  Result.Target := ATarget;
end;

function CliTemplate: TTemplate;
begin
  Result.Name := 'cli';
  Result.Description := 'command line app with pascli';
  Result.Dependencies := ['github.com/leandro-lprsoft/pascli'];
  Result.Ignore := [];
  Result.Files := [
    TemplateFile('clilpr', '{APPNAME}.lpr'),
    TemplateFile('clilpi', '{APPNAME}.lpi'),
    TemplateFile('clicommandgreet', 'src/commands/Command.Greet.pas'),
    TemplateFile('clicommandcount', 'src/commands/Command.Count.pas'),
    TemplateFile('clitestlpi', 'tests/Test{APPNAME}.lpi'),
    TemplateFile('clitestlpr', 'tests/Test{APPNAME}.lpr'),
    TemplateFile('clitestoutput', 'tests/TestOutput.pas'),
    TemplateFile('clitestcommandgreet', 'tests/TestCommandGreet.pas'),
    TemplateFile('clitestcommandcount', 'tests/TestCommandCount.pas')];
end;

function WebTemplate: TTemplate;
begin
  Result.Name := 'web';
  Result.Description := 'web API with horse and SQLite';
  Result.Dependencies := ['github.com/HashLoad/horse'];
  // the SQLite database created next to the executable
  Result.Ignore := ['*.db'];
  Result.Files := [
    TemplateFile('weblpr', '{APPNAME}.lpr'),
    TemplateFile('weblpi', '{APPNAME}.lpi'),
    TemplateFile('webbuild', 'src/Build.pas'),
    TemplateFile('webshutdown', 'src/Shutdown.pas'),
    TemplateFile('webhealthroutes', 'src/features/health/Health.Routes.pas'),
    TemplateFile('webcustomersroutes', 'src/features/customers/Customers.Routes.pas'),
    TemplateFile('webcustomerspayloads', 'src/features/customers/Customers.Payloads.pas'),
    TemplateFile('webcustomersservice', 'src/features/customers/Customers.Service.pas'),
    TemplateFile('webrepoconfig', 'src/repo/Repo.Config.pas'),
    TemplateFile('webrepomodels', 'src/repo/Repo.Models.pas'),
    TemplateFile('webrepocustomers', 'src/repo/Repo.Customers.pas'),
    TemplateFile('webtestlpi', 'tests/Test{APPNAME}.lpi'),
    TemplateFile('webtestlpr', 'tests/Test{APPNAME}.lpr'),
    TemplateFile('webtestfakerepository', 'tests/FakeCustomerRepository.pas'),
    TemplateFile('webtestcustomersservice', 'tests/TestCustomersService.pas'),
    TemplateFile('webtestcustomerspayloads', 'tests/TestCustomersPayloads.pas')];
end;

function GetTemplates: TTemplates;
begin
  Result := [CliTemplate, WebTemplate];
end;

function FindTemplate(const AName: string; out ATemplate: TTemplate): Boolean;
var
  LTemplate: TTemplate;
begin
  ATemplate := Default(TTemplate);
  for LTemplate in GetTemplates do
    if SameText(LTemplate.Name, Trim(AName)) then
    begin
      ATemplate := LTemplate;
      Exit(True);
    end;
  Result := False;
end;

function GetTemplateNames: string;
var
  LTemplate: TTemplate;
begin
  Result := '';
  for LTemplate in GetTemplates do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + LTemplate.Name;
  end;
end;

function WriteTemplateFiles(const ATemplate: TTemplate; const AAppDir, AAppName: string): TArray<string>;
var
  LFile: TTemplateFile;
  LTarget: string;
begin
  Result := [];
  for LFile in ATemplate.Files do
  begin
    LTarget := StringReplace(LFile.Target, APP_NAME_PLACEHOLDER, AAppName, [rfReplaceAll]);
    LTarget := ConcatPaths([AAppDir, SetDirSeparators(LTarget)]);
    ForceDirectories(ExtractFileDir(LTarget));
    SaveFileContent(
      LTarget,
      StringReplace(GetResource(LFile.Resource), APP_NAME_PLACEHOLDER, AAppName, [rfReplaceAll]));
    Result := Result + [LTarget];
  end;
end;

end.
