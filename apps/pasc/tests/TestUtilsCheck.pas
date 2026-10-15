unit TestUtilsCheck;

{$MODE DELPHI}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpcunit,
  testregistry;

type

  TTestUtilsCheck = class(TTestCase)
  private
    FDir: string;
    function CreateApp(const AProjectPaths, AReleasePaths: string): string;
    function CreatePackage(const AFiles: string): string;
    procedure CreateUnit(const AFileName: string);
  protected
    procedure SetUp; override;
  published
    procedure TestGetBuildModesPaths;
    procedure TestGetBuildModesPathsPackage;
    procedure TestGetUnitFolders;
    procedure TestCheckProjectClean;
    procedure TestCheckProjectFolderMissingInOneMode;
    procedure TestCheckProjectFolderMissingInEveryMode;
    procedure TestCheckPackageUnlistedUnit;
    procedure TestCheckPackageMissingFile;
    procedure TestCheckPackageNumberedItems;
    procedure TestCheckProjectMissingSearchPath;
    procedure TestCheckProjectMissingModules;
    procedure TestCheckProjectMissingIncludePath;
    procedure TestCheckWorkspaceModulesOutOfPlace;
    procedure TestCheckWorkspaceModulesMissing;
    procedure TestCheckWorkspaceModulesMissingFromLock;
  end;

implementation

uses
  StrUtils,
  FileUtil,
  Utils.IO,
  Utils.Check;

procedure TTestUtilsCheck.SetUp;
begin
  FDir := ConcatPaths([GetTempDir, '.TestUtilsCheck', TestName]);
  if DirectoryExists(FDir) then
    DeleteDirectory(FDir, False);
  ForceDirectories(FDir);
end;

// a project with a Debug mode that uses the project options and a Release mode with its own
function TTestUtilsCheck.CreateApp(const AProjectPaths, AReleasePaths: string): string;
begin
  Result := ConcatPaths([FDir, 'app.lpi']);
  SaveFileContent(Result,
    '<?xml version="1.0" encoding="UTF-8"?>' + LineEnding +
    '<CONFIG>' + LineEnding +
    '  <ProjectOptions>' + LineEnding +
    '    <BuildModes>' + LineEnding +
    '      <Item Name="Debug" Default="True"/>' + LineEnding +
    '      <Item Name="Release">' + LineEnding +
    '        <CompilerOptions><SearchPaths>' + LineEnding +
    '          <OtherUnitFiles Value="' + AReleasePaths + '"/>' + LineEnding +
    '        </SearchPaths></CompilerOptions>' + LineEnding +
    '      </Item>' + LineEnding +
    '    </BuildModes>' + LineEnding +
    '  </ProjectOptions>' + LineEnding +
    '  <CompilerOptions><SearchPaths>' + LineEnding +
    '    <OtherUnitFiles Value="' + AProjectPaths + '"/>' + LineEnding +
    '  </SearchPaths></CompilerOptions>' + LineEnding +
    '</CONFIG>');
end;

function TTestUtilsCheck.CreatePackage(const AFiles: string): string;
begin
  Result := ConcatPaths([FDir, 'core.lpk']);
  SaveFileContent(Result,
    '<?xml version="1.0" encoding="UTF-8"?>' + LineEnding +
    '<CONFIG>' + LineEnding +
    '  <Package Version="5">' + LineEnding +
    '    <Name Value="core"/>' + LineEnding +
    '    <CompilerOptions><SearchPaths>' + LineEnding +
    '      <OtherUnitFiles Value="src"/>' + LineEnding +
    '    </SearchPaths></CompilerOptions>' + LineEnding +
    '    <Files>' + AFiles + '</Files>' + LineEnding +
    '  </Package>' + LineEnding +
    '</CONFIG>');
end;

procedure TTestUtilsCheck.CreateUnit(const AFileName: string);
var
  LFile: string;
begin
  LFile := ConcatPaths([FDir, SetDirSeparators(AFileName)]);
  ForceDirectories(ExtractFileDir(LFile));
  SaveFileContent(LFile, 'unit ' + ChangeFileExt(ExtractFileName(LFile), '') + ';');
end;

procedure TTestUtilsCheck.TestGetBuildModesPaths;
var
  LModes: TBuildModesPaths;
begin
  LModes := GetBuildModesPaths(CreateApp('src;src\features;$(LazarusDir)/x', 'src'));

  AssertEquals('one entry per build mode', 2, Length(LModes));
  AssertEquals('Debug', LModes[0].Name);
  AssertEquals('Debug uses the project options, the macro is skipped', 2, Length(LModes[0].Paths));
  AssertEquals(ConcatPaths([FDir, 'src', 'features']), LModes[0].Paths[1]);
  AssertEquals('Release', LModes[1].Name);
  AssertEquals('Release has its own options', 1, Length(LModes[1].Paths));
end;

procedure TTestUtilsCheck.TestGetBuildModesPathsPackage;
var
  LModes: TBuildModesPaths;
begin
  LModes := GetBuildModesPaths(CreatePackage(''));

  AssertEquals('a package has a single entry', 1, Length(LModes));
  AssertEquals('', LModes[0].Name);
  AssertEquals(ConcatPaths([FDir, 'src']), LModes[0].Paths[0]);
end;

procedure TTestUtilsCheck.TestGetUnitFolders;
var
  LFolders: TArray<string>;
begin
  CreateUnit('app.pas');
  CreateUnit('src/Main.pas');
  CreateUnit('src/features/issues/Issues.Routes.pp');
  CreateUnit('src/lib/Old.pas');
  CreateUnit('backup/Main.pas');
  CreateUnit('modules/lib/src/Lib.pas');
  CreateUnit('tests/TestMain.pas');
  CreateUnit('.hidden/Hidden.pas');
  CreateUnit('samples/demo/Demo.pas');
  SaveFileContent(ConcatPaths([FDir, 'samples', 'demo', 'demo.lpi']), '<CONFIG/>');

  LFolders := GetUnitFolders(FDir);

  AssertEquals('only src and its folder with units. Check: ' + string.Join(', ', LFolders), 2, Length(LFolders));
  AssertEquals(ConcatPaths([FDir, 'src']), LFolders[0]);
  AssertEquals(ConcatPaths([FDir, 'src', 'features', 'issues']), LFolders[1]);
end;

procedure TTestUtilsCheck.TestCheckProjectClean;
var
  LWarnings: TArray<string>;
begin
  CreateUnit('src/Main.pas');
  LWarnings := CheckProject(CreateApp('src', 'src'), FDir);
  AssertEquals('no warnings. Check: ' + string.Join(', ', LWarnings), 0, Length(LWarnings));
end;

procedure TTestUtilsCheck.TestCheckProjectFolderMissingInOneMode;
var
  LWarnings: TArray<string>;
begin
  CreateUnit('src/Main.pas');
  CreateUnit('extra/Extra.pas');

  LWarnings := CheckProject(CreateApp('src;extra', 'src'), FDir);

  AssertEquals(1, Length(LWarnings));
  AssertEquals(
    'extra has units but is not in the search paths of app.lpi (Release), add extra to its OtherUnitFiles',
    LWarnings[0]);
end;

procedure TTestUtilsCheck.TestCheckProjectFolderMissingInEveryMode;
var
  LWarnings: TArray<string>;
begin
  CreateUnit('src/features/issues/Issues.Routes.pas');

  LWarnings := CheckProject(CreateApp('src', 'src'), ExtractFileDir(FDir));

  AssertEquals(1, Length(LWarnings));
  AssertTrue('the folder should be relative to the base folder, and the path to add to the project. Check: ' + LWarnings[0],
    StartsStr(TestName + '/src/features/issues has units but is not in the search paths of app.lpi (Debug, Release), ' +
      'add src/features/issues', LWarnings[0]));
end;

procedure TTestUtilsCheck.TestCheckPackageUnlistedUnit;
var
  LWarnings: TArray<string>;
begin
  CreateUnit('src/core.hello.pas');
  CreateUnit('src/core.rules.pas');
  // the main unit, written by lazbuild
  CreateUnit('core.pas');

  LWarnings := CheckProject(CreatePackage(
    '<Item><Filename Value="src/core.hello.pas"/><UnitName Value="core.Hello"/></Item>'), FDir);

  AssertEquals('only the unlisted unit. Check: ' + string.Join(', ', LWarnings), 1, Length(LWarnings));
  AssertEquals('src/core.rules.pas is not in the Files of core.lpk, add it to the package', LWarnings[0]);
end;

procedure TTestUtilsCheck.TestCheckPackageMissingFile;
var
  LWarnings: TArray<string>;
begin
  CreateUnit('src/core.rules.pas');

  LWarnings := CheckProject(CreatePackage(
    '<Item><Filename Value="src/core.hello.pas"/></Item>' +
    '<Item><Filename Value="src/core.rules.pas"/></Item>'), FDir);

  AssertEquals(1, Length(LWarnings));
  AssertEquals('the Files of core.lpk list src/core.hello.pas, which does not exist, remove it from the package',
    LWarnings[0]);
end;

procedure TTestUtilsCheck.TestCheckPackageNumberedItems;
var
  LWarnings: TArray<string>;
begin
  CreateUnit('src/core.hello.pas');

  // older Lazarus versions number the items
  LWarnings := CheckProject(CreatePackage(
    '<Count Value="1"/><Item1><Filename Value="src/core.hello.pas"/></Item1>'), FDir);

  AssertEquals('a numbered item is a listed file. Check: ' + string.Join(', ', LWarnings), 0, Length(LWarnings));
end;

procedure TTestUtilsCheck.TestCheckProjectMissingSearchPath;
var
  LWarnings: TArray<string>;
begin
  CreateUnit('src/Main.pas');

  LWarnings := CheckProject(CreateApp('src;gone', 'src;gone;old'), FDir);

  AssertEquals('one warning per set of build modes. Check: ' + string.Join(' | ', LWarnings), 2, Length(LWarnings));
  AssertEquals('app.lpi (Debug, Release): search path gone does not exist', LWarnings[0]);
  AssertEquals('app.lpi (Release): search path old does not exist', LWarnings[1]);
end;

procedure TTestUtilsCheck.TestCheckProjectMissingModules;
var
  LWarnings: TArray<string>;
begin
  CreateUnit('src/Main.pas');

  LWarnings := CheckProject(CreateApp('src;modules/a/src;modules/b/src', 'src;modules/a/src;modules/b/src'), FDir);

  AssertEquals('the missing modules in a single warning. Check: ' + string.Join(' | ', LWarnings), 1, Length(LWarnings));
  AssertEquals('app.lpi (Debug, Release): search paths modules/a/src, modules/b/src do not exist, ' +
    'run pasc deps to install the dependencies', LWarnings[0]);
end;

procedure TTestUtilsCheck.TestCheckProjectMissingIncludePath;
var
  LWarnings: TArray<string>;
  LProject: string;
begin
  CreateUnit('src/Main.pas');
  LProject := ConcatPaths([FDir, 'app.lpi']);
  SaveFileContent(LProject,
    '<?xml version="1.0" encoding="UTF-8"?><CONFIG><ProjectOptions/><CompilerOptions><SearchPaths>' +
    '<IncludeFiles Value="$(ProjOutDir);inc"/><OtherUnitFiles Value="src"/>' +
    '</SearchPaths></CompilerOptions></CONFIG>');

  LWarnings := CheckProject(LProject, FDir);

  AssertEquals('the include path without the macro. Check: ' + string.Join(' | ', LWarnings), 1, Length(LWarnings));
  AssertEquals('app.lpi: search path inc does not exist', LWarnings[0]);
end;

procedure TTestUtilsCheck.TestCheckWorkspaceModulesOutOfPlace;
var
  LWarnings: TArray<string>;
begin
  ForceDirectories(ConcatPaths([FDir, 'modules']));
  ForceDirectories(ConcatPaths([FDir, 'apps', 'modules']));
  ForceDirectories(ConcatPaths([FDir, 'packages', 'core', 'modules']));

  LWarnings := CheckWorkspaceModules(FDir, [ConcatPaths([FDir, 'apps', 'web']), ConcatPaths([FDir, 'packages', 'core'])]);

  AssertEquals('each modules folder out of place. Check: ' + string.Join(' | ', LWarnings), 2, Length(LWarnings));
  AssertTrue(LWarnings[0], StartsStr('apps/modules is out of place', LWarnings[0]));
  AssertTrue(LWarnings[1], StartsStr('packages/core/modules is out of place', LWarnings[1]));
end;

procedure TTestUtilsCheck.TestCheckWorkspaceModulesMissing;
var
  LWarnings: TArray<string>;
begin
  SaveFileContent(ConcatPaths([FDir, 'boss.json']), '{"name": "ws", "dependencies": {}}');
  AssertEquals('nothing to install without dependencies', 0, Length(CheckWorkspaceModules(FDir, [])));

  SaveFileContent(ConcatPaths([FDir, 'boss.json']), '{"name": "ws", "dependencies": {"github.com/HashLoad/horse": "^3.0.0"}}');

  LWarnings := CheckWorkspaceModules(FDir, []);

  AssertEquals(1, Length(LWarnings));
  AssertEquals('boss.json has dependencies but there is no modules folder at the root of the workspace, ' +
    'run pasc deps to install them', LWarnings[0]);
end;

procedure TTestUtilsCheck.TestCheckWorkspaceModulesMissingFromLock;
var
  LWarnings: TArray<string>;
begin
  ForceDirectories(ConcatPaths([FDir, 'modules', 'github_com_HashLoad_horse']));
  SaveFileContent(ConcatPaths([FDir, 'boss-lock.json']),
    '{"installedModules": {' +
    '"github.com/hashload/horse": {"name": "github_com_HashLoad_horse"},' +
    '"github.com/laprado/pascli": {"name": "github_com_laprado_pascli"}}}');

  LWarnings := CheckWorkspaceModules(FDir, []);

  AssertEquals(1, Length(LWarnings));
  AssertTrue('should name the module missing. Check: ' + LWarnings[0],
    StartsStr('boss-lock.json records modules that are not in modules: github_com_laprado_pascli. Run pasc deps', LWarnings[0]));
end;

initialization
  RegisterTest(TTestUtilsCheck);

end.
