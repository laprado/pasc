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
    procedure TestSortMembersByDependency;
    procedure TestSortMembersCircularReference;
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

initialization
  RegisterTest(TTestUtilsWorkspace);

end.
