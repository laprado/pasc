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

  /// <summary> Returns the complete paths of the source folders of the boss modules installed
  /// in the modules folder of the workspace. Like boss, each folder of the "mainsrc" of the
  /// module boss.json (separated by ";", or the module root without it) is searched
  /// recursively, and every folder with .pas, .pp or .inc files is returned. </summary>
  /// <param name="AWorkspaceDir"> Workspace root folder. </param>
  function GetModuleSourceDirs(const AWorkspaceDir: string): TArray<string>;

  /// <summary> Replaces, in every OtherUnitFiles of a .lpi or .lpk file, the paths that point
  /// to the workspace modules folder by the given module source folders, relative to the file
  /// folder. Other paths are kept. The file is changed as text to preserve its formatting.
  /// Returns true if the file was changed. </summary>
  /// <param name="AProjectFile"> .lpi or .lpk file. </param>
  /// <param name="AWorkspaceDir"> Workspace root folder. </param>
  /// <param name="AModuleDirs"> Complete paths of the module source folders. </param>
  function SyncModulePaths(const AProjectFile, AWorkspaceDir: string;
    const AModuleDirs: TArray<string>): Boolean;

  /// <summary> Returns the folders under the src folder of a member, src included, that have
  /// Pascal sources (.pas, .pp or .inc), sorted. lib and backup folders are not included.
  /// Returns empty if the member has no src folder. </summary>
  /// <param name="AMemberDir"> Member folder. </param>
  function GetMemberSourceDirs(const AMemberDir: string): TArray<string>;

  /// <summary> Adds the source folders missing from every OtherUnitFiles of a project, in all
  /// its build modes, relative to the project and with / as separator. The existing entries are
  /// kept, so it only adds. Returns true if the project file was changed. </summary>
  /// <param name="AProjectFile"> .lpi file to update. </param>
  /// <param name="ASourceDirs"> Absolute source folders, like the ones of
  /// GetMemberSourceDirs. </param>
  function AddSourcePaths(const AProjectFile: string; const ASourceDirs: TArray<string>): Boolean;

  /// <summary> Returns the .lpi of the test project of a member, or empty if the member has
  /// no test project. </summary>
  /// <param name="AMemberDir"> Member folder. </param>
  function GetMemberTestProject(const AMemberDir: string): string;

  /// <summary> Returns the module folders recorded in boss-lock.json that are not in the
  /// workspace modules folder. The folder name depends on the boss version (3.x uses
  /// github_com_user_repo, older versions the repository name), so a difference means the lock
  /// was written by another boss version, and the search paths synced from this machine do not
  /// match it. Returns empty without a lock or a modules folder. </summary>
  /// <param name="AWorkspaceDir"> Workspace root folder. </param>
  function GetModulesMissingFromLock(const AWorkspaceDir: string): TArray<string>;

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
    '      <%0:s>' + LineEnding +
    '        <PackageName Value="%1:s"/>' + LineEnding +
    '        <DefaultFilename Value="%2:s" Prefer="True"/>' + LineEnding +
    '      </%0:s>' + LineEnding;
var
  LContent, LPackageName, LRelative, LTag, LItemTag, LCount: string;
  LReference: string;
  LPos, LTagEnd, LCountValue: Integer;
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

  LIsPackage := SameText(ExtractFileExt(AProjectFile), '.lpk');
  LTag := IfThen(LIsPackage, 'RequiredPkgs', 'RequiredPackages');

  LContent := GetFileContent(AProjectFile);
  LItemTag := 'Item';
  LPos := Pos('<' + LTag + '>', LContent);
  if LPos > 0 then
    LTagEnd := LPos + Length('<' + LTag + '>')
  else
  begin
    // older lazarus files number the items and keep their count: <RequiredPackages Count="1"><Item1>
    LPos := Pos('<' + LTag + ' Count="', LContent);
    if LPos > 0 then
    begin
      LTagEnd := PosEx('"', LContent, LPos + Length('<' + LTag + ' Count="'));
      LCount := Copy(LContent, LPos + Length('<' + LTag + ' Count="'),
        LTagEnd - LPos - Length('<' + LTag + ' Count="'));
      LCountValue := StrToIntDef(LCount, 0) + 1;
      Delete(LContent, LPos, LTagEnd - LPos + 1);
      Insert('<' + LTag + ' Count="' + IntToStr(LCountValue) + '"', LContent, LPos);
      LTagEnd := PosEx('>', LContent, LPos) + 1;
      LItemTag := 'Item' + IntToStr(LCountValue);
      // the new numbered item goes after the last one, before the closing tag
      LTagEnd := PosEx('    </' + LTag + '>', LContent, LTagEnd);
    end;
  end;

  if LPos > 0 then
  begin
    if LItemTag = 'Item' then
      // keep the item after the line break of the opening tag
      while (LTagEnd <= Length(LContent)) and (LContent[LTagEnd] in [#13, #10]) do
        Inc(LTagEnd);
    if LTagEnd = 0 then
      raise Exception.Create('Unexpected format, could not add the package to ' + AProjectFile);
    Insert(Format(ITEM, [LItemTag, LPackageName, LRelative]), LContent, LTagEnd);
  end
  else
  begin
    // no required packages yet: a new section before the units (.lpi) or files (.lpk)
    LPos := Pos(IfThen(LIsPackage, '    <Files', '    <Units'), LContent);
    if LPos = 0 then
      raise Exception.Create('Unexpected format, could not add the package to ' + AProjectFile);
    Insert('    <' + LTag + '>' + LineEnding + Format(ITEM, ['Item', LPackageName, LRelative]) +
      '    </' + LTag + '>' + LineEnding, LContent, LPos);
  end;

  SaveFileContent(AProjectFile, LContent);
  Result := True;
end;

function HasSourceFiles(const ADir: string): Boolean;
var
  LSearch: TSearchRec;
begin
  Result := False;
  if FindFirst(ConcatPaths([ADir, AllFilesMask]), faAnyFile, LSearch) = 0 then
    try
      repeat
        if ((LSearch.Attr and faDirectory) = 0) and
           AnsiMatchText(ExtractFileExt(LSearch.Name), ['.pas', '.pp', '.inc']) then
          Exit(True);
      until FindNext(LSearch) <> 0;
    finally
      FindClose(LSearch);
    end;
end;

procedure AddSourceDirs(var ADirs: TArray<string>; const ADir: string);
var
  LSearch: TSearchRec;
  LSubDirs: TStringList;
  LSubDir, LExisting: string;
  LFound: Boolean;
begin
  if HasSourceFiles(ADir) then
  begin
    LFound := False;
    for LExisting in ADirs do
      if SameFileName(LExisting, ADir) then
        LFound := True;
    if not LFound then
      ADirs := ADirs + [ADir];
  end;

  LSubDirs := TStringList.Create;
  try
    if FindFirst(ConcatPaths([ADir, AllFilesMask]), faDirectory, LSearch) = 0 then
      try
        repeat
          // hidden folders like .git have no sources, lib has compiled units and backup has
          // the copies of the Lazarus IDE
          if ((LSearch.Attr and faDirectory) <> 0) and not StartsStr('.', LSearch.Name) and
             not AnsiMatchText(LSearch.Name, ['lib', 'backup']) then
            LSubDirs.Add(ConcatPaths([ADir, LSearch.Name]));
        until FindNext(LSearch) <> 0;
      finally
        FindClose(LSearch);
      end;
    LSubDirs.Sort;
    for LSubDir in LSubDirs do
      AddSourceDirs(ADirs, LSubDir);
  finally
    LSubDirs.Free;
  end;
end;

function GetModuleSourceDirs(const AWorkspaceDir: string): TArray<string>;
var
  LModulesDir, LModuleDir, LMainSrc, LBossFile, LDir: string;
  LSearch: TSearchRec;
  LDirs, LMainSrcs: TStringList;
  LJson: TJSONData;
  LHasMainSrc: Boolean;
begin
  Result := [];
  LModulesDir := ConcatPaths([AWorkspaceDir, 'modules']);
  LDirs := TStringList.Create;
  LMainSrcs := TStringList.Create;
  try
    LMainSrcs.StrictDelimiter := True;
    LMainSrcs.Delimiter := ';';

    if FindFirst(ConcatPaths([LModulesDir, AllFilesMask]), faDirectory, LSearch) = 0 then
      try
        repeat
          // .bin, .dcp, .dcu and .bpl are boss folders for Delphi binaries
          if ((LSearch.Attr and faDirectory) <> 0) and not StartsStr('.', LSearch.Name) then
            LDirs.Add(LSearch.Name);
        until FindNext(LSearch) <> 0;
      finally
        FindClose(LSearch);
      end;
    LDirs.Sort;

    for LModuleDir in LDirs do
    begin
      LMainSrc := '';
      LBossFile := ConcatPaths([LModulesDir, LModuleDir, 'boss.json']);
      if FileExists(LBossFile) then
      begin
        LJson := GetJSON(GetFileContent(LBossFile));
        try
          if LJson is TJSONObject then
            LMainSrc := TJSONObject(LJson).Get('mainsrc', '');
        finally
          LJson.Free;
        end;
      end;

      // like boss: "mainsrc" may have several folders separated by ";", each one is searched
      // recursively and every folder with sources is used; without it the module root is used
      LMainSrcs.DelimitedText := LMainSrc;
      LHasMainSrc := False;
      for LDir in LMainSrcs do
        if Trim(LDir) <> '' then
        begin
          LHasMainSrc := True;
          AddSourceDirs(Result, ExcludeTrailingPathDelimiter(
            ExpandFileName(ConcatPaths([LModulesDir, LModuleDir, NormalizePath(Trim(LDir))]))));
        end;
      if not LHasMainSrc then
        AddSourceDirs(Result, ConcatPaths([LModulesDir, LModuleDir]));
    end;
  finally
    LDirs.Free;
    LMainSrcs.Free;
  end;
end;

function IsInsideFolder(const AFileName, AFolder: string): Boolean;
var
  LFolder: string;
begin
  LFolder := IncludeTrailingPathDelimiter(ExpandFileName(AFolder));
  Result := SameFileName(IncludeTrailingPathDelimiter(ExpandFileName(AFileName)), LFolder) or
    StartsStr(LFolder, ExpandFileName(AFileName));
end;

function SyncModulePaths(const AProjectFile, AWorkspaceDir: string;
  const AModuleDirs: TArray<string>): Boolean;
const
  TAG = '<OtherUnitFiles Value="';
var
  LContent, LProjectDir, LModulesDir, LValue, LEntry, LResolved, LNewValue: string;
  LEntries: TStringList;
  LModuleDir: string;
  LStart, LEnd, LOffset: Integer;
begin
  LContent := GetFileContent(AProjectFile);
  LProjectDir := IncludeTrailingPathDelimiter(ExtractFileDir(ExpandFileName(AProjectFile)));
  LModulesDir := ConcatPaths([AWorkspaceDir, 'modules']);
  Result := False;
  LEntries := TStringList.Create;
  try
    LEntries.StrictDelimiter := True;
    LEntries.Delimiter := ';';
    LOffset := 1;
    repeat
      LStart := PosEx(TAG, LContent, LOffset);
      if LStart = 0 then
        Break;
      Inc(LStart, Length(TAG));
      LEnd := PosEx('"', LContent, LStart);
      if LEnd = 0 then
        Break;
      LValue := Copy(LContent, LStart, LEnd - LStart);

      // keeps the paths that do not point to the workspace modules
      LEntries.DelimitedText := LValue;
      LNewValue := '';
      for LEntry in LEntries do
      begin
        if Trim(LEntry) = '' then
          Continue;
        if not ContainsStr(LEntry, '$(') then
        begin
          LResolved := NormalizePath(LEntry);
          if not IsAbsolutePath(LResolved) then
            LResolved := ConcatPaths([LProjectDir, LResolved]);
          if IsInsideFolder(LResolved, LModulesDir) then
            Continue;
        end;
        LNewValue := LNewValue + IfThen(LNewValue <> '', ';', '') + LEntry;
      end;

      for LModuleDir in AModuleDirs do
        LNewValue := LNewValue + IfThen(LNewValue <> '', ';', '') +
          StringReplace(ExtractRelativePath(LProjectDir, LModuleDir), '\', '/', [rfReplaceAll]);

      if LNewValue <> LValue then
      begin
        Delete(LContent, LStart, LEnd - LStart);
        Insert(LNewValue, LContent, LStart);
        LEnd := LStart + Length(LNewValue);
        Result := True;
      end;
      LOffset := LEnd + 1;
    until False;
  finally
    LEntries.Free;
  end;

  if Result then
    SaveFileContent(AProjectFile, LContent);
end;

function GetMemberSourceDirs(const AMemberDir: string): TArray<string>;
var
  LSrcDir: string;
begin
  Result := [];
  LSrcDir := ConcatPaths([ExcludeTrailingPathDelimiter(ExpandFileName(AMemberDir)), 'src']);
  if DirectoryExists(LSrcDir) then
    AddSourceDirs(Result, LSrcDir);
end;

function AddSourcePaths(const AProjectFile: string; const ASourceDirs: TArray<string>): Boolean;
const
  TAG = '<OtherUnitFiles Value="';
var
  LContent, LProjectDir, LValue, LEntry, LResolved, LNewValue, LSourceDir: string;
  LEntries: TStringList;
  LStart, LEnd, LOffset: Integer;
  LFound: Boolean;
begin
  LContent := GetFileContent(AProjectFile);
  LProjectDir := IncludeTrailingPathDelimiter(ExtractFileDir(ExpandFileName(AProjectFile)));
  Result := False;
  LEntries := TStringList.Create;
  try
    LEntries.StrictDelimiter := True;
    LEntries.Delimiter := ';';
    LOffset := 1;
    repeat
      LStart := PosEx(TAG, LContent, LOffset);
      if LStart = 0 then
        Break;
      Inc(LStart, Length(TAG));
      LEnd := PosEx('"', LContent, LStart);
      if LEnd = 0 then
        Break;
      LValue := Copy(LContent, LStart, LEnd - LStart);
      LEntries.DelimitedText := LValue;
      LNewValue := LValue;

      for LSourceDir in ASourceDirs do
      begin
        LFound := False;
        for LEntry in LEntries do
        begin
          if (Trim(LEntry) = '') or ContainsStr(LEntry, '$(') then
            Continue;
          LResolved := NormalizePath(Trim(LEntry));
          if not IsAbsolutePath(LResolved) then
            LResolved := ConcatPaths([LProjectDir, LResolved]);
          if SameFileName(ExcludeTrailingPathDelimiter(ExpandFileName(LResolved)),
            ExcludeTrailingPathDelimiter(ExpandFileName(LSourceDir))) then
          begin
            LFound := True;
            Break;
          end;
        end;
        if not LFound then
          LNewValue := LNewValue + IfThen(Trim(LNewValue) <> '', ';', '') + StringReplace(
            ExcludeTrailingPathDelimiter(ExtractRelativePath(LProjectDir, IncludeTrailingPathDelimiter(LSourceDir))),
            '\', '/', [rfReplaceAll]);
      end;

      if LNewValue <> LValue then
      begin
        Delete(LContent, LStart, LEnd - LStart);
        Insert(LNewValue, LContent, LStart);
        LEnd := LStart + Length(LNewValue);
        Result := True;
      end;
      LOffset := LEnd + 1;
    until False;
  finally
    LEntries.Free;
  end;

  if Result then
    SaveFileContent(AProjectFile, LContent);
end;

function GetModulesMissingFromLock(const AWorkspaceDir: string): TArray<string>;
var
  LLockFile, LModulesDir, LName: string;
  LJson: TJSONData;
  LModules: TJSONObject;
  I: Integer;
begin
  Result := [];
  LLockFile := ConcatPaths([AWorkspaceDir, 'boss-lock.json']);
  LModulesDir := ConcatPaths([AWorkspaceDir, 'modules']);
  if not FileExists(LLockFile) or not DirectoryExists(LModulesDir) then
    Exit;

  LJson := GetJSON(GetFileContent(LLockFile));
  try
    if not (LJson is TJSONObject) or not (TJSONObject(LJson).Find('installedModules') is TJSONObject) then
      Exit;
    LModules := TJSONObject(TJSONObject(LJson).Find('installedModules'));
    for I := 0 to LModules.Count - 1 do
    begin
      if not (LModules.Items[I] is TJSONObject) then
        Continue;
      LName := TJSONObject(LModules.Items[I]).Get('name', '');
      if (LName <> '') and not DirectoryExists(ConcatPaths([LModulesDir, LName])) then
        Result := Result + [LName];
    end;
  finally
    LJson.Free;
  end;
end;

function GetMemberTestProject(const AMemberDir: string): string;
begin
  Result := FindFileByExt(ConcatPaths([AMemberDir, 'tests']), '.lpi');
end;

end.
