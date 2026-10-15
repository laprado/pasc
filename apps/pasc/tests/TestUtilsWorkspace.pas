unit TestUtilsWorkspace;

{$MODE DELPHI}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpcunit,
  testregistry;

type

  TTestUtilsWorkspace= class(TTestCase)
  private
    FWorkingFolder: string;
    function CreatePackage(const AName: string): string;
    function CreateApp(const AName: string): string;
  protected
    procedure SetUp; override;
  published
    procedure TestFindWorkspaceRootAtRoot;
    procedure TestFindWorkspaceRootFromMember;
    procedure TestFindWorkspaceRootOutsideWorkspace;
    procedure TestGetWorkspaceMembers;
    procedure TestGetWorkspaceMembersLiteralFolder;
    procedure TestAddPackageReferenceToApp;
    procedure TestAddPackageReferenceToPackage;
    procedure TestAddPackageReferenceAlreadyRequired;
    procedure TestAddPackageReferenceNumberedItems;
    procedure TestSortMembersByDependency;
    procedure TestSortMembersCircularReference;
    procedure TestGetModuleSourceDirs;
    procedure TestGetModuleSourceDirsMultipleMainSrc;
    procedure TestGetModuleSourceDirsSubfolders;
    procedure TestSyncModulePaths;
    procedure TestSyncModulePathsReplacesOldModules;
    procedure TestGetMemberSourceDirs;
    procedure TestAddSourcePaths;
    procedure TestAddSourcePathsTestProject;
    procedure TestGetModulesMissingFromLock;
  end;

implementation

uses
  StrUtils,
  Utils.IO,
  Utils.Workspace;

const
  APP_LPI =
    '<?xml version="1.0" encoding="UTF-8"?>' + LineEnding +
    '<CONFIG>' + LineEnding +
    '  <ProjectOptions>' + LineEnding +
    '    <Units>' + LineEnding +
    '    </Units>' + LineEnding +
    '  </ProjectOptions>' + LineEnding +
    '</CONFIG>' + LineEnding;

  PACKAGE_LPK =
    '<?xml version="1.0" encoding="UTF-8"?>' + LineEnding +
    '<CONFIG>' + LineEnding +
    '  <Package Version="5">' + LineEnding +
    '    <Name Value="%s"/>' + LineEnding +
    '    <Files>' + LineEnding +
    '    </Files>' + LineEnding +
    '    <RequiredPkgs>' + LineEnding +
    '      <Item>' + LineEnding +
    '        <PackageName Value="FCL"/>' + LineEnding +
    '      </Item>' + LineEnding +
    '    </RequiredPkgs>' + LineEnding +
    '  </Package>' + LineEnding +
    '</CONFIG>' + LineEnding;

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

procedure TTestUtilsWorkspace.SetUp;
begin
  FWorkingFolder := ConcatPaths([GetTempDir, '.TestUtilsWorkspace']);
  if DirectoryExists(FWorkingFolder) then
    RemoveFolder(FWorkingFolder);
  ForceDirectories(ConcatPaths([FWorkingFolder, 'ws', 'apps']));
  ForceDirectories(ConcatPaths([FWorkingFolder, 'ws', 'packages']));
  ForceDirectories(ConcatPaths([FWorkingFolder, 'other']));
  SaveFileContent(
    ConcatPaths([FWorkingFolder, 'ws', WORKSPACE_FILE]),
    '{ "members": ["packages/*", "apps/*"] }');
end;

function TTestUtilsWorkspace.CreatePackage(const AName: string): string;
begin
  ForceDirectories(ConcatPaths([FWorkingFolder, 'ws', 'packages', AName]));
  Result := ConcatPaths([FWorkingFolder, 'ws', 'packages', AName, AName + '.lpk']);
  SaveFileContent(Result, Format(PACKAGE_LPK, [AName]));
end;

function TTestUtilsWorkspace.CreateApp(const AName: string): string;
begin
  ForceDirectories(ConcatPaths([FWorkingFolder, 'ws', 'apps', AName, 'src']));
  Result := ConcatPaths([FWorkingFolder, 'ws', 'apps', AName, AName + '.lpi']);
  SaveFileContent(Result, APP_LPI);
end;

procedure TTestUtilsWorkspace.TestFindWorkspaceRootAtRoot;
begin
  AssertEquals(
    ConcatPaths([FWorkingFolder, 'ws']),
    FindWorkspaceRoot(ConcatPaths([FWorkingFolder, 'ws'])));
end;

procedure TTestUtilsWorkspace.TestFindWorkspaceRootFromMember;
begin
  CreateApp('cli');
  AssertEquals(
    ConcatPaths([FWorkingFolder, 'ws']),
    FindWorkspaceRoot(ConcatPaths([FWorkingFolder, 'ws', 'apps', 'cli', 'src'])));
end;

procedure TTestUtilsWorkspace.TestFindWorkspaceRootOutsideWorkspace;
begin
  AssertEquals('', FindWorkspaceRoot(ConcatPaths([FWorkingFolder, 'other'])));
end;

procedure TTestUtilsWorkspace.TestGetWorkspaceMembers;
var
  LMembers: TWorkspaceMembers;
begin
  CreatePackage('core');
  CreateApp('server');
  CreateApp('cli');
  // a folder without a project file is not a member
  ForceDirectories(ConcatPaths([FWorkingFolder, 'ws', 'apps', 'empty']));

  LMembers := GetWorkspaceMembers(ConcatPaths([FWorkingFolder, 'ws']));

  AssertEquals('members count', 3, Length(LMembers));
  AssertEquals('packages come first, as in pasc.json', 'core', LMembers[0].Name);
  AssertTrue('core is a package', LMembers[0].IsPackage);
  AssertEquals('apps are sorted by name', 'cli', LMembers[1].Name);
  AssertFalse('cli is an app', LMembers[1].IsPackage);
  AssertEquals('server', LMembers[2].Name);
  AssertEquals(
    ConcatPaths([FWorkingFolder, 'ws', 'apps', 'cli', 'cli.lpi']),
    LMembers[1].ProjectFile);
end;

procedure TTestUtilsWorkspace.TestGetWorkspaceMembersLiteralFolder;
var
  LMembers: TWorkspaceMembers;
begin
  CreatePackage('core');
  CreateApp('cli');
  SaveFileContent(
    ConcatPaths([FWorkingFolder, 'ws', WORKSPACE_FILE]),
    '{ "members": ["apps/cli"] }');

  LMembers := GetWorkspaceMembers(ConcatPaths([FWorkingFolder, 'ws']));

  AssertEquals('members count', 1, Length(LMembers));
  AssertEquals('cli', LMembers[0].Name);
end;

procedure TTestUtilsWorkspace.TestAddPackageReferenceToApp;
var
  LApp, LCore: string;
  LReferences: TArray<string>;
begin
  LCore := CreatePackage('core');
  LApp := CreateApp('cli');

  AssertTrue('reference should be added', AddPackageReference(LApp, LCore));

  AssertTrue(
    'relative path should be written',
    ContainsText(GetFileContent(LApp), '<DefaultFilename Value="../../packages/core/core.lpk" Prefer="True"/>'));
  LReferences := GetPackageReferences(LApp);
  AssertEquals('references count', 1, Length(LReferences));
  AssertEquals('reference should be resolved', LCore, LReferences[0]);
end;

procedure TTestUtilsWorkspace.TestAddPackageReferenceToPackage;
var
  LCore, LUtil: string;
begin
  LCore := CreatePackage('core');
  LUtil := CreatePackage('util');

  AssertTrue('reference should be added', AddPackageReference(LUtil, LCore));

  AssertTrue(
    'reference should be inside RequiredPkgs',
    ContainsText(GetFileContent(LUtil), '<RequiredPkgs>' + LineEnding + '      <Item>' + LineEnding +
      '        <PackageName Value="core"/>'));
  AssertTrue(
    'FCL should still be required',
    ContainsText(GetFileContent(LUtil), '<PackageName Value="FCL"/>'));
  AssertEquals('references count', 1, Length(GetPackageReferences(LUtil)));
end;

procedure TTestUtilsWorkspace.TestAddPackageReferenceAlreadyRequired;
var
  LApp, LCore: string;
begin
  LCore := CreatePackage('core');
  LApp := CreateApp('cli');
  AddPackageReference(LApp, LCore);

  AssertFalse('reference should not be added twice', AddPackageReference(LApp, LCore));
  AssertEquals('references count', 1, Length(GetPackageReferences(LApp)));
end;

procedure TTestUtilsWorkspace.TestSortMembersByDependency;
var
  LMembers: TWorkspaceMembers;
begin
  // "zeta" comes last by name, but "alpha" requires it
  AddPackageReference(CreatePackage('alpha'), CreatePackage('zeta'));
  AddPackageReference(CreateApp('cli'), ConcatPaths([FWorkingFolder, 'ws', 'packages', 'alpha', 'alpha.lpk']));

  LMembers := SortMembersByDependency(GetWorkspaceMembers(ConcatPaths([FWorkingFolder, 'ws'])));

  AssertEquals('members count', 3, Length(LMembers));
  AssertEquals('zeta', LMembers[0].Name);
  AssertEquals('alpha', LMembers[1].Name);
  AssertEquals('cli', LMembers[2].Name);
end;

procedure TTestUtilsWorkspace.TestSortMembersCircularReference;
var
  LAlpha, LBeta: string;
  LRaised: Boolean = False;
begin
  LAlpha := CreatePackage('alpha');
  LBeta := CreatePackage('beta');
  AddPackageReference(LAlpha, LBeta);
  AddPackageReference(LBeta, LAlpha);

  try
    SortMembersByDependency(GetWorkspaceMembers(ConcatPaths([FWorkingFolder, 'ws'])));
  except
    LRaised := True;
  end;

  AssertTrue('a circular reference should raise an exception', LRaised);
end;

procedure TTestUtilsWorkspace.TestGetModuleSourceDirs;
var
  LModules: string;
  LDirs: TArray<string>;
begin
  LModules := ConcatPaths([FWorkingFolder, 'ws', 'modules']);
  ForceDirectories(ConcatPaths([LModules, '.dcu']));
  SaveFileContent(ConcatPaths([LModules, '.dcu', 'ignored.pas']), 'unit ignored;');
  ForceDirectories(ConcatPaths([LModules, 'github_com_a_lib', 'src']));
  SaveFileContent(ConcatPaths([LModules, 'github_com_a_lib', 'boss.json']), '{ "mainsrc": "./src/" }');
  SaveFileContent(ConcatPaths([LModules, 'github_com_a_lib', 'src', 'a.pas']), 'unit a;');
  // without mainsrc the module root is searched
  ForceDirectories(ConcatPaths([LModules, 'github_com_b_nojson']));
  SaveFileContent(ConcatPaths([LModules, 'github_com_b_nojson', 'b.pp']), 'unit b;');

  LDirs := GetModuleSourceDirs(ConcatPaths([FWorkingFolder, 'ws']));

  AssertEquals('dot folders are not modules', 2, Length(LDirs));
  AssertEquals('mainsrc is used', ConcatPaths([LModules, 'github_com_a_lib', 'src']), LDirs[0]);
  AssertEquals('no boss.json is the module root', ConcatPaths([LModules, 'github_com_b_nojson']), LDirs[1]);
end;

procedure TTestUtilsWorkspace.TestGetModuleSourceDirsMultipleMainSrc;
var
  LModule: string;
  LDirs: TArray<string>;
begin
  LModule := ConcatPaths([FWorkingFolder, 'ws', 'modules', 'github_com_a_multi']);
  ForceDirectories(ConcatPaths([LModule, 'core', 'src']));
  ForceDirectories(ConcatPaths([LModule, 'util', 'src']));
  ForceDirectories(ConcatPaths([LModule, 'samples']));
  SaveFileContent(ConcatPaths([LModule, 'boss.json']), '{ "mainsrc": "core/src;util/src/" }');
  SaveFileContent(ConcatPaths([LModule, 'core', 'src', 'core.pas']), 'unit core;');
  SaveFileContent(ConcatPaths([LModule, 'util', 'src', 'util.pas']), 'unit util;');
  SaveFileContent(ConcatPaths([LModule, 'samples', 'sample.pas']), 'unit sample;');

  LDirs := GetModuleSourceDirs(ConcatPaths([FWorkingFolder, 'ws']));

  AssertEquals('only the mainsrc folders. Check: ' + string.Join(';', LDirs), 2, Length(LDirs));
  AssertEquals(ConcatPaths([LModule, 'core', 'src']), LDirs[0]);
  AssertEquals(ConcatPaths([LModule, 'util', 'src']), LDirs[1]);
end;

procedure TTestUtilsWorkspace.TestGetModuleSourceDirsSubfolders;
var
  LModule: string;
  LDirs: TArray<string>;
begin
  LModule := ConcatPaths([FWorkingFolder, 'ws', 'modules', 'github_com_a_deep']);
  ForceDirectories(ConcatPaths([LModule, 'src', 'sub', 'inner']));
  ForceDirectories(ConcatPaths([LModule, 'src', 'empty']));
  SaveFileContent(ConcatPaths([LModule, 'boss.json']), '{ "mainsrc": "src" }');
  SaveFileContent(ConcatPaths([LModule, 'src', 'main.pas']), 'unit main;');
  SaveFileContent(ConcatPaths([LModule, 'src', 'sub', 'inner', 'deep.inc']), '{ include }');

  LDirs := GetModuleSourceDirs(ConcatPaths([FWorkingFolder, 'ws']));

  AssertEquals('folders with sources only. Check: ' + string.Join(';', LDirs), 2, Length(LDirs));
  AssertEquals(ConcatPaths([LModule, 'src']), LDirs[0]);
  AssertEquals('subfolders are searched', ConcatPaths([LModule, 'src', 'sub', 'inner']), LDirs[1]);
end;

procedure TTestUtilsWorkspace.TestSyncModulePaths;
var
  LApp, LWorkspaceDir: string;
begin
  LWorkspaceDir := ConcatPaths([FWorkingFolder, 'ws']);
  LApp := CreateApp('cli');
  SaveFileContent(LApp, StringReplace(GetFileContent(LApp), '    <Units>',
    '    <SearchPaths>' + LineEnding +
    '      <OtherUnitFiles Value="src;$(LazarusDir)/x"/>' + LineEnding +
    '    </SearchPaths>' + LineEnding +
    '    <Units>', []));

  AssertTrue(
    'file should be changed',
    SyncModulePaths(LApp, LWorkspaceDir, [ConcatPaths([LWorkspaceDir, 'modules', 'github_com_a_lib', 'src'])]));
  AssertTrue(
    'module path should be relative to the app, keeping the other paths. Check: ' + GetFileContent(LApp),
    ContainsText(GetFileContent(LApp),
      '<OtherUnitFiles Value="src;$(LazarusDir)/x;../../modules/github_com_a_lib/src"/>'));
  AssertFalse(
    'a second sync should not change the file',
    SyncModulePaths(LApp, LWorkspaceDir, [ConcatPaths([LWorkspaceDir, 'modules', 'github_com_a_lib', 'src'])]));
end;

procedure TTestUtilsWorkspace.TestSyncModulePathsReplacesOldModules;
var
  LApp, LWorkspaceDir: string;
begin
  LWorkspaceDir := ConcatPaths([FWorkingFolder, 'ws']);
  LApp := CreateApp('cli');
  // a removed module, and the root relative paths written by boss "projects"
  SaveFileContent(LApp, StringReplace(GetFileContent(LApp), '    <Units>',
    '    <SearchPaths>' + LineEnding +
    '      <OtherUnitFiles Value="src;../../modules/github_com_old/src;modules/.dcu"/>' + LineEnding +
    '    </SearchPaths>' + LineEnding +
    '    <Units>', []));

  SyncModulePaths(LApp, LWorkspaceDir, [ConcatPaths([LWorkspaceDir, 'modules', 'github_com_new'])]);

  AssertTrue(
    'old module path should be replaced. Check: ' + GetFileContent(LApp),
    ContainsText(GetFileContent(LApp),
      '<OtherUnitFiles Value="src;modules/.dcu;../../modules/github_com_new"/>'));
end;

procedure TTestUtilsWorkspace.TestGetMemberSourceDirs;
var
  LAppDir: string;
  LDirs: TArray<string>;
begin
  LAppDir := ExtractFileDir(CreateApp('server'));
  ForceDirectories(ConcatPaths([LAppDir, 'src', 'features', 'issues']));
  ForceDirectories(ConcatPaths([LAppDir, 'src', 'features', 'empty']));
  ForceDirectories(ConcatPaths([LAppDir, 'src', 'backup']));
  ForceDirectories(ConcatPaths([LAppDir, 'src', 'lib']));
  SaveFileContent(ConcatPaths([LAppDir, 'src', 'Build.pas']), 'unit Build;');
  SaveFileContent(ConcatPaths([LAppDir, 'src', 'features', 'issues', 'Issues.Routes.pas']), 'unit Issues.Routes;');
  SaveFileContent(ConcatPaths([LAppDir, 'src', 'backup', 'Build.pas']), 'unit Build;');
  SaveFileContent(ConcatPaths([LAppDir, 'src', 'lib', 'Build.inc']), '');

  LDirs := GetMemberSourceDirs(LAppDir);

  AssertEquals('src and the folder with units, without backup, lib or empty folders', 2, Length(LDirs));
  AssertEquals(ConcatPaths([LAppDir, 'src']), LDirs[0]);
  AssertEquals(ConcatPaths([LAppDir, 'src', 'features', 'issues']), LDirs[1]);
  AssertEquals('a member without src has no source folders', 0,
    Length(GetMemberSourceDirs(ConcatPaths([FWorkingFolder, 'ws', 'packages']))));
end;

procedure TTestUtilsWorkspace.TestAddSourcePaths;
var
  LApp, LAppDir, LContent: string;
begin
  LApp := CreateApp('server');
  LAppDir := ExtractFileDir(LApp);
  // two build modes, one of them with Windows separators
  SaveFileContent(LApp, StringReplace(GetFileContent(LApp), '    <Units>',
    '    <SearchPaths>' + LineEnding +
    '      <OtherUnitFiles Value="src;src\features\health;$(LazarusDir)/x"/>' + LineEnding +
    '    </SearchPaths>' + LineEnding +
    '    <SearchPaths>' + LineEnding +
    '      <OtherUnitFiles Value="src/features/health;src"/>' + LineEnding +
    '    </SearchPaths>' + LineEnding +
    '    <Units>', []));

  AssertTrue('file should be changed', AddSourcePaths(LApp, [
    ConcatPaths([LAppDir, 'src']),
    ConcatPaths([LAppDir, 'src', 'features', 'health']),
    ConcatPaths([LAppDir, 'src', 'features', 'issues'])]));

  LContent := GetFileContent(LApp);
  AssertTrue('the missing folder should be added to the first mode, keeping the others. Check: ' + LContent,
    ContainsText(LContent, '<OtherUnitFiles Value="src;src\features\health;$(LazarusDir)/x;src/features/issues"/>'));
  AssertTrue('the missing folder should be added to the second mode. Check: ' + LContent,
    ContainsText(LContent, '<OtherUnitFiles Value="src/features/health;src;src/features/issues"/>'));
  AssertFalse('a second call should not change the file',
    AddSourcePaths(LApp, [ConcatPaths([LAppDir, 'src', 'features', 'issues'])]));
end;

procedure TTestUtilsWorkspace.TestAddSourcePathsTestProject;
var
  LApp, LAppDir, LTestProject: string;
begin
  LApp := CreateApp('server');
  LAppDir := ExtractFileDir(LApp);
  ForceDirectories(ConcatPaths([LAppDir, 'tests']));
  LTestProject := ConcatPaths([LAppDir, 'tests', 'Testserver.lpi']);
  SaveFileContent(LTestProject,
    '<CONFIG><CompilerOptions><SearchPaths>' + LineEnding +
    '  <OtherUnitFiles Value="../src"/>' + LineEnding +
    '</SearchPaths></CompilerOptions></CONFIG>');

  AddSourcePaths(LTestProject, [ConcatPaths([LAppDir, 'src']), ConcatPaths([LAppDir, 'src', 'repo'])]);

  AssertTrue('the folder should be relative to the test project. Check: ' + GetFileContent(LTestProject),
    ContainsText(GetFileContent(LTestProject), '<OtherUnitFiles Value="../src;../src/repo"/>'));
end;

procedure TTestUtilsWorkspace.TestAddPackageReferenceNumberedItems;
var
  LApp, LCore, LContent: string;
begin
  LCore := CreatePackage('core');
  LApp := CreateApp('cli');
  // older lazarus format, with a count and numbered items
  SaveFileContent(LApp,
    '<?xml version="1.0" encoding="UTF-8"?>' + LineEnding +
    '<CONFIG>' + LineEnding +
    '  <ProjectOptions>' + LineEnding +
    '    <RequiredPackages Count="1">' + LineEnding +
    '      <Item1>' + LineEnding +
    '        <PackageName Value="LCL"/>' + LineEnding +
    '      </Item1>' + LineEnding +
    '    </RequiredPackages>' + LineEnding +
    '    <Units Count="0">' + LineEnding +
    '    </Units>' + LineEnding +
    '  </ProjectOptions>' + LineEnding +
    '</CONFIG>' + LineEnding);

  AssertTrue('reference should be added', AddPackageReference(LApp, LCore));

  LContent := GetFileContent(LApp);
  AssertTrue('count should be updated. Check: ' + LContent, ContainsText(LContent, '<RequiredPackages Count="2">'));
  AssertTrue('a numbered item should be added', ContainsText(LContent, '<Item2>' + LineEnding +
    '        <PackageName Value="core"/>'));
  AssertEquals('a single section', 1, Length(SplitString(LContent, '<RequiredPackages')) - 1);
  AssertEquals('references count', 1, Length(GetPackageReferences(LApp)));
end;

procedure TTestUtilsWorkspace.TestGetModulesMissingFromLock;
var
  LWorkspaceDir: string;
  LMissing: TArray<string>;
begin
  LWorkspaceDir := ConcatPaths([FWorkingFolder, 'ws']);
  ForceDirectories(ConcatPaths([LWorkspaceDir, 'modules', 'github_com_a_lib']));
  // the second module was recorded by an older boss, which names the folder after the repository
  SaveFileContent(ConcatPaths([LWorkspaceDir, 'boss-lock.json']),
    '{ "installedModules": {' +
    ' "github.com/a/lib": { "name": "github_com_a_lib", "version": "1.0.0" },' +
    ' "github.com/a/other": { "name": "other", "version": "1.0.0" } } }');

  LMissing := GetModulesMissingFromLock(LWorkspaceDir);

  AssertEquals('missing count', 1, Length(LMissing));
  AssertEquals('other', LMissing[0]);
end;

initialization
  RegisterTest(TTestUtilsWorkspace);

end.
