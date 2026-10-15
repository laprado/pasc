unit TestCommandDocs;

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

  TTestCommandDocs= class(TTestCase)
  private
    FBuilder: ICommandBuilder;
    FExeName: string;
    FCurrentDir: string;
    FRoot: string;
    function CreateApp(const ADir, AName: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCommandDocsRegistry;
    procedure TestGetDocsPages;
    procedure TestGetDocsSourcesApp;
    procedure TestGetDocsSourcesWorkspace;
    procedure TestOrganizeNavigation;
    procedure TestOrganizeNavigationWithoutMenu;
    procedure TestDocsCommandWithoutPages;
    procedure TestDocsCommandArguments;
  end;

implementation

uses
  StrUtils,
  MockCommandBuilder,
  Command.Docs,
  Utils.IO,
  Utils.Shell,
  Utils.Workspace;

const
  APP_LPI =
    '<?xml version="1.0" encoding="UTF-8"?>' + LineEnding +
    '<CONFIG>' + LineEnding +
    '  <CompilerOptions>' + LineEnding +
    '    <SearchPaths>' + LineEnding +
    '      <OtherUnitFiles Value="src;../../modules/github_com_a_lib/src;$(LazarusDir)/x"/>' + LineEnding +
    '    </SearchPaths>' + LineEnding +
    '  </CompilerOptions>' + LineEnding +
    '</CONFIG>' + LineEnding;

  // the menu as pasdoc 1.0 generates it: the reference first, every page flat
  MENU_HTML =
    '<html><body><ul class="nav flex-column px-3">' +
    '<li class="nav-item"><a class="nav-link px-2 py-1" href="AllUnits.html">Units</a></li>' +
    '<li class="nav-item"><a class="nav-link px-2 py-1" href="ClassHierarchy.html">Class Hierarchy</a></li>' +
    '<li class="nav-item"><a class="nav-link px-2 py-1" href="install.html">Install</a></li>' +
    '<li class="nav-item"><a class="nav-link px-2 py-1" href="commandadd.html">Add</a></li>' +
    '<li class="nav-item"><a class="nav-link px-2 py-1" href="quickstart.html">Quick start</a></li>' +
    '<li class="nav-item pt-2 px-2"><form>search</form></li>' +
    '</ul><p>content</p></body></html>';

procedure RemoveFolder(const ADir: string);
var
  LSearch: TSearchRec;
  LPath: string;
begin
  if FindFirst(ConcatPaths([ADir, AllFilesMask]), faAnyFile or faDirectory, LSearch) = 0 then
    try
      repeat
        if (LSearch.Name = '.') or (LSearch.Name = '..') then
          Continue;
        LPath := ConcatPaths([ADir, LSearch.Name]);
        if (LSearch.Attr and faDirectory) <> 0 then
          RemoveFolder(LPath)
        else
          DeleteFile(LPath);
      until FindNext(LSearch) <> 0;
    finally
      FindClose(LSearch);
    end;
  RemoveDir(ADir);
end;

procedure TTestCommandDocs.SetUp;
begin
  FCurrentDir := GetCurrentDir;
  FExeName := ExtractFileName(ParamStr(0));
  FBuilder := TCommandBuilder.Create(FExeName);
  MockSetup(FBuilder);
  Command.Docs.Registry(FBuilder);
  FRoot := ConcatPaths([GetTempDir, '.TestCommandDocs', TestName]);
  if DirectoryExists(FRoot) then
    RemoveFolder(FRoot);
  ForceDirectories(FRoot);
  ExitCode := 0;
end;

procedure TTestCommandDocs.TearDown;
begin
  SetCurrentDir(FCurrentDir);
  ShellExecute := @ShellCommand;
  ExitCode := 0;
end;

function TTestCommandDocs.CreateApp(const ADir, AName: string): string;
begin
  ForceDirectories(ConcatPaths([ADir, 'src']));
  ForceDirectories(ConcatPaths([ADir, '..', '..', 'modules', 'github_com_a_lib', 'src']));
  Result := ConcatPaths([ADir, AName + '.lpi']);
  SaveFileContent(Result, APP_LPI);
  SaveFileContent(ConcatPaths([ADir, AName + '.lpr']), 'program ' + AName + ';');
  SaveFileContent(ConcatPaths([ADir, 'src', 'b.pp']), 'unit b;');
  SaveFileContent(ConcatPaths([ADir, 'src', 'a.pas']), 'unit a;');
  SaveFileContent(ConcatPaths([ADir, '..', '..', 'modules', 'github_com_a_lib', 'src', 'lib.pas']), 'unit lib;');
end;

procedure TTestCommandDocs.TestCommandDocsRegistry;
begin
  AssertEquals('docs', FBuilder.Commands[0].Name);
end;

procedure TTestCommandDocs.TestGetDocsPages;
var
  LPage: string;
  LPages: string = '';
begin
  for LPage in ['introduction', 'conclusion', 'quickstart', 'commandbuild', 'install', 'commandadd', 'workspace'] do
    SaveFileContent(ConcatPaths([FRoot, LPage + '.txt']), '@title(' + LPage + ')');

  for LPage in GetDocsPages(FRoot) do
    LPages := LPages + ChangeFileExt(ExtractFileName(LPage), '') + ' ';

  AssertEquals(
    'guides by name, then commands by name, without introduction and conclusion',
    'install quickstart workspace commandadd commandbuild ', LPages);
end;

procedure TTestCommandDocs.TestGetDocsSourcesApp;
var
  LApp: string;
  LSources: TArray<string>;
begin
  LApp := ConcatPaths([FRoot, 'apps', 'cli']);
  CreateApp(LApp, 'cli');

  LSources := GetDocsSources(LApp);

  AssertEquals('sources count. Check: ' + string.Join(' ', LSources), 3, Length(LSources));
  AssertEquals(ConcatPaths([LApp, 'src', 'a.pas']), LSources[0]);
  AssertEquals(ConcatPaths([LApp, 'src', 'b.pp']), LSources[1]);
  AssertEquals('the main program', ConcatPaths([LApp, 'cli.lpr']), LSources[2]);
end;

procedure TTestCommandDocs.TestGetDocsSourcesWorkspace;
var
  LSources: string;
begin
  SaveFileContent(ConcatPaths([FRoot, WORKSPACE_FILE]), '{ "members": ["apps/*"] }');
  CreateApp(ConcatPaths([FRoot, 'apps', 'cli']), 'cli');

  LSources := string.Join(' ', GetDocsSources(FRoot));

  AssertTrue('member sources. Check: ' + LSources, ContainsText(LSources, ConcatPaths(['apps', 'cli', 'src', 'a.pas'])));
  AssertTrue('member program. Check: ' + LSources, ContainsText(LSources, ConcatPaths(['apps', 'cli', 'cli.lpr'])));
  AssertFalse('boss modules are not documented. Check: ' + LSources, ContainsText(LSources, 'lib.pas'));
end;

procedure TTestCommandDocs.TestOrganizeNavigation;
var
  LHtml: string;
begin
  LHtml := OrganizeNavigation(MENU_HTML);

  AssertTrue('guides first, in their order. Check: ' + LHtml,
    Pos('href="install.html"', LHtml) < Pos('href="quickstart.html"', LHtml));
  AssertTrue('commands after the guides',
    Pos('href="quickstart.html"', LHtml) < Pos('>Commands<', LHtml));
  AssertTrue('the commands group has its pages',
    Pos('>Commands<', LHtml) < Pos('href="commandadd.html"', LHtml));
  AssertTrue('reference after the commands',
    (Pos('href="commandadd.html"', LHtml) < Pos('>Reference<', LHtml)) and
    (Pos('>Reference<', LHtml) < Pos('href="AllUnits.html"', LHtml)) and
    (Pos('href="AllUnits.html"', LHtml) < Pos('href="ClassHierarchy.html"', LHtml)));
  AssertTrue('other items, like the search box, at the end',
    Pos('href="ClassHierarchy.html"', LHtml) < Pos('<form>search</form>', LHtml));
  AssertTrue('the rest of the page is kept', ContainsText(LHtml, '</ul><p>content</p></body></html>'));
  AssertEquals('applying it again changes nothing', LHtml, OrganizeNavigation(LHtml));
end;

procedure TTestCommandDocs.TestOrganizeNavigationWithoutMenu;
begin
  AssertEquals('<html><body>no menu</body></html>', OrganizeNavigation('<html><body>no menu</body></html>'));
end;

procedure TTestCommandDocs.TestDocsCommandWithoutPages;
var
  LExitCode: Integer;
begin
  CreateApp(FRoot, 'cli');
  SetCurrentDir(FRoot);
  FBuilder.UseArguments(['docs']);
  FBuilder.Parse;
  ShellExecute := @MockShell;

  DocsCommand(FBuilder);
  LExitCode := ExitCode;
  ExitCode := 0;

  AssertTrue('should ask to run pasc add --docs. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, 'pasc add --docs'));
  AssertEquals('exit code', 1, LExitCode);
  AssertEquals('pasdoc should not run', '', MockShellCapture);
end;

procedure TTestCommandDocs.TestDocsCommandArguments;
begin
  CreateApp(FRoot, 'cli');
  ForceDirectories(ConcatPaths([FRoot, 'docs', 'generate']));
  SaveFileContent(ConcatPaths([FRoot, 'docs', 'generate', 'introduction.txt']), '@title(Overview)');
  SaveFileContent(ConcatPaths([FRoot, 'docs', 'generate', 'commandadd.txt']), '@title(Add)');
  SetCurrentDir(FRoot);
  FBuilder.UseArguments(['docs']);
  FBuilder.Parse;
  ShellExecute := @MockShell;

  DocsCommand(FBuilder);

  AssertTrue('pasdoc should run. Check: ' + MockShellCapture, StartsText('pasdoc', MockShellCapture));
  AssertTrue('introduction', ContainsText(MockShellCapture,
    '--introduction=' + ConcatPaths([FRoot, 'docs', 'generate', 'introduction.txt'])));
  AssertTrue('additional page', ContainsText(MockShellCapture,
    '--additional=' + ConcatPaths([FRoot, 'docs', 'generate', 'commandadd.txt'])));
  AssertTrue('output', ContainsText(MockShellCapture, '--output=' + ConcatPaths([FRoot, 'docs'])));
  AssertTrue('sources', ContainsText(MockShellCapture, ConcatPaths([FRoot, 'src', 'a.pas'])));
  AssertFalse('no custom style without custom.css', ContainsText(MockShellCapture, '--css'));
  AssertEquals('exit code', 0, ExitCode);
end;

initialization
  RegisterTest(TTestCommandDocs);
  
end.
