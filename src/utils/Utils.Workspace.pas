/// <summary> Unit which contains functions to handle a pasc workspace: a repository with
/// multiple apps and internal packages described by a pasc.json file at its root.
///
/// Members reference each other as lazarus packages: the .lpi of an app (or the .lpk of a
/// package) lists the required package with a relative DefaultFilename, so lazbuild builds
/// it without a global registration.
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

type
  /// <summary> A workspace member: an app (.lpi) or a lazarus package (.lpk). </summary>
  TWorkspaceMember = record
    /// <summary> Member name, the project or package file name without extension. </summary>
    Name: string;
    /// <summary> Complete path of the member folder. </summary>
    Dir: string;
    /// <summary> Complete file name of the .lpi or .lpk file. </summary>
    ProjectFile: string;
    /// <summary> True if the member is a lazarus package. </summary>
    IsPackage: Boolean;
  end;

  TWorkspaceMembers = TArray<TWorkspaceMember>;

  /// <summary> Searches for a workspace manifest from the given directory up to the file system
  /// root. Returns the workspace root directory, or empty if the directory is not inside a
  /// workspace. </summary>
  /// <param name="AStartDir"> Directory from which the search starts. </param>
  function FindWorkspaceRoot(const AStartDir: string): string;

  /// <summary> Returns the members of the workspace listed in pasc.json. A member pattern is a
  /// folder relative to the root, or a folder followed by /* for each of its subfolders. Folders
  /// without a .lpk or .lpi file are ignored. </summary>
  /// <param name="AWorkspaceDir"> Workspace root folder. </param>
  function GetWorkspaceMembers(const AWorkspaceDir: string): TWorkspaceMembers;

  /// <summary> Returns the members sorted so that each package comes before the members that
  /// require it. Raises an exception if there is a circular reference. </summary>
  /// <param name="AMembers"> Workspace members. </param>
  function SortMembersByDependency(const AMembers: TWorkspaceMembers): TWorkspaceMembers;

  /// <summary> Returns the complete file names of the packages required by a .lpi or .lpk file
  /// through a DefaultFilename, resolved relative to the file folder. </summary>
  /// <param name="AProjectFile"> .lpi or .lpk file name. </param>
  function GetPackageReferences(const AProjectFile: string): TArray<string>;

  /// <summary> Adds a required package with a relative DefaultFilename to a .lpi or .lpk file.
  /// The file is changed as text to preserve its formatting. Returns false if the package was
  /// already required. </summary>
  /// <param name="AProjectFile"> .lpi or .lpk file that will require the package. </param>
  /// <param name="APackageFile"> Complete file name of the required .lpk. </param>
  function AddPackageReference(const AProjectFile, APackageFile: string): Boolean;

  /// <summary> Returns the member with the given name, or a member with an empty name if it
  /// was not found. </summary>
  /// <param name="AMembers"> Workspace members. </param>
  /// <param name="AName"> Member name. </param>
  function FindMember(const AMembers: TWorkspaceMembers; const AName: string): TWorkspaceMember;

implementation

uses
  Classes,
  SysUtils,
  StrUtils,
  DOM,
  XMLRead,
  fpjson,
  jsonparser,
  Utils.IO;

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

function FindFileByExt(const ADir, AExt: string): string;
var
  LSearch: TSearchRec;
begin
  Result := '';
  if FindFirst(ConcatPaths([ADir, '*' + AExt]), faAnyFile, LSearch) = 0 then
    try
      repeat
        if SameText(ExtractFileExt(LSearch.Name), AExt) then
          Exit(ConcatPaths([ADir, LSearch.Name]));
      until FindNext(LSearch) <> 0;
    finally
      FindClose(LSearch);
    end;
end;

procedure AddMember(var AMembers: TWorkspaceMembers; const ADir: string);
var
  LMember: TWorkspaceMember;
  LExisting: TWorkspaceMember;
begin
  LMember.Dir := ExcludeTrailingPathDelimiter(ExpandFileName(ADir));
  LMember.ProjectFile := FindFileByExt(LMember.Dir, '.lpk');
  LMember.IsPackage := LMember.ProjectFile <> '';
  if not LMember.IsPackage then
    LMember.ProjectFile := FindFileByExt(LMember.Dir, '.lpi');
  if LMember.ProjectFile = '' then
    Exit;

  for LExisting in AMembers do
    if SameFileName(LExisting.Dir, LMember.Dir) then
      Exit;

  LMember.Name := ChangeFileExt(ExtractFileName(LMember.ProjectFile), '');
  AMembers := AMembers + [LMember];
end;

procedure AddSubfolders(var AMembers: TWorkspaceMembers; const ADir: string);
var
  LSearch: TSearchRec;
  LDirs: TStringList;
  LDir: string;
begin
  LDirs := TStringList.Create;
  try
    if FindFirst(ConcatPaths([ADir, AllFilesMask]), faDirectory, LSearch) = 0 then
      try
        repeat
          if ((LSearch.Attr and faDirectory) <> 0) and (LSearch.Name <> '.') and (LSearch.Name <> '..') then
            LDirs.Add(ConcatPaths([ADir, LSearch.Name]));
        until FindNext(LSearch) <> 0;
      finally
        FindClose(LSearch);
      end;

    // a stable order, the file system order is not predictable
    LDirs.Sort;
    for LDir in LDirs do
      AddMember(AMembers, LDir);
  finally
    LDirs.Free;
  end;
end;

function GetWorkspaceMembers(const AWorkspaceDir: string): TWorkspaceMembers;
var
  LJson: TJSONData;
  LPatterns: TJSONArray;
  LPattern: string;
  I: Integer;
begin
  Result := [];
  LJson := GetJSON(GetFileContent(ConcatPaths([AWorkspaceDir, WORKSPACE_FILE])));
  try
    if not (LJson is TJSONObject) or not (TJSONObject(LJson).Find('members') is TJSONArray) then
      raise Exception.Create(WORKSPACE_FILE + ' must have a "members" array.');

    LPatterns := TJSONArray(TJSONObject(LJson).Find('members'));
    for I := 0 to LPatterns.Count - 1 do
    begin
      LPattern := StringReplace(LPatterns.Strings[I], '\', '/', [rfReplaceAll]);
      if EndsStr('/*', LPattern) then
        AddSubfolders(Result, ConcatPaths([AWorkspaceDir, Copy(LPattern, 1, Length(LPattern) - 2)]))
      else
        AddMember(Result, ConcatPaths([AWorkspaceDir, LPattern]));
    end;
  finally
    LJson.Free;
  end;
end;

function NormalizePath(const AFileName: string): string;
begin
  Result := SetDirSeparators(AFileName);
end;

function IsAbsolutePath(const AFileName: string): Boolean;
begin
  {$IF DEFINED(WINDOWS)}
  Result := (ExtractFileDrive(AFileName) <> '') or StartsStr(PathDelim, AFileName);
  {$ELSE}
  Result := StartsStr(PathDelim, AFileName);
  {$ENDIF}
end;

function GetPackageReferences(const AProjectFile: string): TArray<string>;
var
  LDocument: TXMLDocument = nil;
  LNodes: TDOMNodeList;
  LValue: string;
  I: Integer;
begin
  Result := [];
  ReadXMLFile(LDocument, AProjectFile);
  try
    LNodes := LDocument.GetElementsByTagName('DefaultFilename');
    try
      for I := 0 to LNodes.Count - 1 do
      begin
        LValue := UTF8Encode(TDOMElement(LNodes[I]).GetAttribute('Value'));
        if LValue = '' then
          Continue;
        LValue := NormalizePath(LValue);
        if not IsAbsolutePath(LValue) then
          LValue := ConcatPaths([ExtractFileDir(AProjectFile), LValue]);
        Result := Result + [ExpandFileName(LValue)];
      end;
    finally
      LNodes.Free;
    end;
  finally
    LDocument.Free;
  end;
end;

function FindMember(const AMembers: TWorkspaceMembers; const AName: string): TWorkspaceMember;
var
  LMember: TWorkspaceMember;
begin
  Result := Default(TWorkspaceMember);
  for LMember in AMembers do
    if SameText(LMember.Name, AName) then
      Exit(LMember);
end;

function SortMembersByDependency(const AMembers: TWorkspaceMembers): TWorkspaceMembers;
var
  LState: TArray<Integer>; // 0 not visited, 1 visiting, 2 done
  I: Integer;
  LSorted: TWorkspaceMembers;

  function IndexOfProjectFile(const AFileName: string): Integer;
  var
    J: Integer;
  begin
    Result := -1;
    for J := 0 to Length(AMembers) - 1 do
      if SameFileName(AMembers[J].ProjectFile, AFileName) then
        Exit(J);
  end;

  procedure Visit(AIndex: Integer);
  var
    LReference: string;
    LDependency: Integer;
  begin
    if LState[AIndex] = 2 then
      Exit;
    if LState[AIndex] = 1 then
      raise Exception.Create('Circular reference between workspace members: ' + AMembers[AIndex].Name);

    LState[AIndex] := 1;
    for LReference in GetPackageReferences(AMembers[AIndex].ProjectFile) do
    begin
      LDependency := IndexOfProjectFile(LReference);
      if LDependency >= 0 then
        Visit(LDependency);
    end;
    LState[AIndex] := 2;
    LSorted := LSorted + [AMembers[AIndex]];
  end;

begin
  LSorted := [];
  SetLength(LState, Length(AMembers));
  for I := 0 to Length(AMembers) - 1 do
    LState[I] := 0;
  for I := 0 to Length(AMembers) - 1 do
    Visit(I);
  Result := LSorted;
end;

function AddPackageReference(const AProjectFile, APackageFile: string): Boolean;
const
  ITEM =
    '      <Item>' + LineEnding +
    '        <PackageName Value="%s"/>' + LineEnding +
    '        <DefaultFilename Value="%s" Prefer="True"/>' + LineEnding +
    '      </Item>' + LineEnding;
var
  LContent, LPackageName, LRelative, LTag, LItem: string;
  LReference: string;
  LPos: Integer;
  LIsPackage: Boolean;
begin
  for LReference in GetPackageReferences(AProjectFile) do
    if SameFileName(LReference, ExpandFileName(APackageFile)) then
      Exit(False);

  LPackageName := ChangeFileExt(ExtractFileName(APackageFile), '');
  LRelative := ExtractRelativePath(
    IncludeTrailingPathDelimiter(ExtractFileDir(ExpandFileName(AProjectFile))),
    ExpandFileName(APackageFile));
  // lazarus project files use / on every platform
  LRelative := StringReplace(LRelative, '\', '/', [rfReplaceAll]);
  LItem := Format(ITEM, [LPackageName, LRelative]);

  LIsPackage := SameText(ExtractFileExt(AProjectFile), '.lpk');
  LTag := IfThen(LIsPackage, 'RequiredPkgs', 'RequiredPackages');

  LContent := GetFileContent(AProjectFile);
  LPos := Pos('<' + LTag + '>', LContent);
  if LPos > 0 then
  begin
    LPos := LPos + Length('<' + LTag + '>');
    // keep the item after the line break of the opening tag
    while (LPos <= Length(LContent)) and (LContent[LPos] in [#13, #10]) do
      Inc(LPos);
    Insert(LItem, LContent, LPos);
  end
  else
  begin
    // no required packages yet: a new section before the units (.lpi) or files (.lpk)
    LPos := Pos(IfThen(LIsPackage, '    <Files>', '    <Units>'), LContent);
    if LPos = 0 then
      raise Exception.Create('Unexpected format, could not add the package to ' + AProjectFile);
    Insert('    <' + LTag + '>' + LineEnding + LItem + '    </' + LTag + '>' + LineEnding, LContent, LPos);
  end;

  SaveFileContent(AProjectFile, LContent);
  Result := True;
end;

end.
