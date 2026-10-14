/// <summary> Unit which contains functions to handle a pasc workspace: a repository with
/// multiple apps and internal packages described by a pasc.json file at its root.
/// </summary>
unit Utils.Workspace;

{$MODE DELPHI}{$H+}

interface

const
  /// <summary> Workspace manifest file name. </summary>
  WORKSPACE_FILE = 'pasc.json';

  /// <summary> Folder of the workspace apps, relative to the workspace root. </summary>
  WORKSPACE_APPS_DIR = 'apps';

  /// <summary> Folder of the workspace packages, relative to the workspace root. </summary>
  WORKSPACE_PACKAGES_DIR = 'packages';

  /// <summary> Searches for a workspace manifest from the given directory up to the file system
  /// root. Returns the workspace root directory, or empty if the directory is not inside a
  /// workspace. </summary>
  /// <param name="AStartDir"> Directory from which the search starts. </param>
  function FindWorkspaceRoot(const AStartDir: string): string;

implementation

uses
  SysUtils;

function FindWorkspaceRoot(const AStartDir: string): string;
var
  LDir, LParent: string;
begin
  Result := '';
  LDir := ExcludeTrailingPathDelimiter(ExpandFileName(AStartDir));
  while LDir <> '' do
  begin
    if FileExists(ConcatPaths([LDir, WORKSPACE_FILE])) then
      Exit(LDir);

    LParent := ExcludeTrailingPathDelimiter(ExtractFileDir(LDir));
    if (LParent = LDir) or (LParent = '') then
      Exit;
    LDir := LParent;
  end;
end;

end.
