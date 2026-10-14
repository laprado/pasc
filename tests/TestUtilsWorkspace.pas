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
  protected
    procedure SetUp; override;
  published
    procedure TestFindWorkspaceRootAtRoot;
    procedure TestFindWorkspaceRootFromMember;
    procedure TestFindWorkspaceRootOutsideWorkspace;
  end;

implementation

uses
  Utils.IO,
  Utils.Workspace;

procedure TTestUtilsWorkspace.SetUp;
begin
  FWorkingFolder := ConcatPaths([GetTempDir, '.TestUtilsWorkspace']);
  ForceDirectories(ConcatPaths([FWorkingFolder, 'ws', 'apps', 'cli', 'src']));
  ForceDirectories(ConcatPaths([FWorkingFolder, 'other']));
  SaveFileContent(ConcatPaths([FWorkingFolder, 'ws', WORKSPACE_FILE]), '{}');
end;

procedure TTestUtilsWorkspace.TestFindWorkspaceRootAtRoot;
begin
  AssertEquals(
    ConcatPaths([FWorkingFolder, 'ws']),
    FindWorkspaceRoot(ConcatPaths([FWorkingFolder, 'ws'])));
end;

procedure TTestUtilsWorkspace.TestFindWorkspaceRootFromMember;
begin
  AssertEquals(
    ConcatPaths([FWorkingFolder, 'ws']),
    FindWorkspaceRoot(ConcatPaths([FWorkingFolder, 'ws', 'apps', 'cli', 'src'])));
end;

procedure TTestUtilsWorkspace.TestFindWorkspaceRootOutsideWorkspace;
begin
  AssertEquals('', FindWorkspaceRoot(ConcatPaths([FWorkingFolder, 'other'])));
end;

initialization
  RegisterTest(TTestUtilsWorkspace);
  
end.
