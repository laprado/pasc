/// <summary> Unit which checks the layout of a project or package against its file: the folders
/// with units that are not in the search paths of every build mode, and for a package the
/// units that are not in its files and the files that no longer exist, and the search paths
/// that do not exist, like the modules folder of a workspace that was moved or not installed.
/// FPC does not search the unit folders recursively and a package only compiles the units it
/// lists, so each case would only fail later, with "Can't find unit" at the first uses that
/// reaches it, or not at all while the old .ppu files are still in lib.
/// </summary>
unit Utils.Check;

{$MODE DELPHI}{$H+}

interface

type

  /// <summary> The search paths of a build mode. </summary>
  TBuildModePaths = record
    /// <summary> Build mode name, empty for a package or a project without build modes.
    /// </summary>
    Name: string;
    /// <summary> Absolute folders of the OtherUnitFiles, without the ones with macros.
    /// </summary>
    Paths: TArray<string>;
    /// <summary> Absolute folders of the IncludeFiles, without the ones with macros.
    /// </summary>
    IncludePaths: TArray<string>;
  end;

  TBuildModesPaths = TArray<TBuildModePaths>;

  /// <summary> Returns the search paths of each build mode of a .lpi, or the search paths of a
  /// .lpk. A build mode without compiler options of its own uses the ones of the project.
  /// </summary>
  /// <param name="AProjectFile"> .lpi or .lpk file. </param>
  function GetBuildModesPaths(const AProjectFile: string): TBuildModesPaths;

  /// <summary> Returns the folders under the project folder that have units (.pas or .pp), not
  /// the project folder itself, which is always searched. Hidden, lib, backup, modules and tests
  /// folders are skipped, and so are the folders with a project or package of their own.
  /// </summary>
  /// <param name="AProjectDir"> Project or package folder. </param>
  function GetUnitFolders(const AProjectDir: string): TArray<string>;

  /// <summary> Returns the absolute files listed in the Files of a .lpk. </summary>
  /// <param name="APackageFile"> .lpk file. </param>
  function GetPackageFiles(const APackageFile: string): TArray<string>;

  /// <summary> Checks a project or package and returns one warning per problem found, with the
  /// paths relative to ABaseDir. A search path under the modules folder of ABaseDir that does
  /// not exist comes with the hint to run pasc deps. Returns empty when there is nothing to
  /// fix. </summary>
  /// <param name="AProjectFile"> .lpi or .lpk file. </param>
  /// <param name="ABaseDir"> Folder the paths of the warnings are relative to, like the
  /// workspace root. </param>
  function CheckProject(const AProjectFile, ABaseDir: string): TArray<string>;

  /// <summary> Checks the modules folder of a workspace and returns one warning per problem
  /// found: a modules folder out of place, under apps, packages or a member, where pasc deps
  /// does not install the dependencies; no modules folder at the root while boss.json has
  /// dependencies; and modules recorded in boss-lock.json that are not in the modules folder.
  /// </summary>
  /// <param name="AWorkspaceDir"> Workspace root folder. </param>
  /// <param name="AMemberDirs"> Folders of the workspace members. </param>
  function CheckWorkspaceModules(const AWorkspaceDir: string; const AMemberDirs: TArray<string>): TArray<string>;

implementation

uses
  Classes,
  SysUtils,
  StrUtils,
  DOM,
  XMLRead,
  fpjson,
  jsonparser,
  Utils.IO,
  Utils.Workspace;

const
  UNIT_EXTENSIONS: array[0..1] of string = ('.pas', '.pp');
  SKIPPED_FOLDERS: array[0..3] of string = ('lib', 'backup', 'modules', 'tests');

function NormalizeDir(const ADir: string): string;
begin
  Result := ExcludeTrailingPathDelimiter(ExpandFileName(ADir));
end;

function ResolvePath(const ABaseDir, APath: string): string;
begin
  Result := SetDirSeparators(Trim(APath));
  if not (StartsStr(PathDelim, Result) {$IF DEFINED(WINDOWS)} or (ExtractFileDrive(Result) <> ''){$ENDIF}) then
    Result := ConcatPaths([ABaseDir, Result]);
  Result := NormalizeDir(Result);
end;

function RelativePath(const ABaseDir, APath: string): string;
begin
  Result := StringReplace(
    ExcludeTrailingPathDelimiter(ExtractRelativePath(IncludeTrailingPathDelimiter(ABaseDir), APath)),
    '\', '/', [rfReplaceAll]);
end;

function ChildElement(ANode: TDOMNode; const AName: string): TDOMElement;
var
  LNode: TDOMNode;
begin
  Result := nil;
  if not Assigned(ANode) then
    Exit;
  LNode := ANode.FirstChild;
  while Assigned(LNode) do
  begin
    if (LNode.NodeType = ELEMENT_NODE) and SameText(UTF8Encode(LNode.NodeName), AName) then
      Exit(TDOMElement(LNode));
    LNode := LNode.NextSibling;
  end;
end;

/// <summary> Item elements of a list, like Files or BuildModes. Old files number them, Item1,
/// Item2, newer ones repeat Item. </summary>
function ItemElements(ANode: TDOMNode): TArray<TDOMElement>;
var
  LNode: TDOMNode;
begin
  Result := [];
  if not Assigned(ANode) then
    Exit;
  LNode := ANode.FirstChild;
  while Assigned(LNode) do
  begin
    if (LNode.NodeType = ELEMENT_NODE) and StartsText('Item', UTF8Encode(LNode.NodeName)) then
      Result := Result + [TDOMElement(LNode)];
    LNode := LNode.NextSibling;
  end;
end;

function ValueOf(AElement: TDOMElement): string;
begin
  Result := '';
  if Assigned(AElement) then
    Result := UTF8Encode(AElement.GetAttribute('Value'));
end;

function SearchPaths(ACompilerOptions: TDOMElement; const AProjectDir, AName: string): TArray<string>;
var
  LEntries: TStringList;
  LEntry: string;
begin
  Result := [];
  LEntries := TStringList.Create;
  try
    LEntries.StrictDelimiter := True;
    LEntries.Delimiter := ';';
    LEntries.DelimitedText := ValueOf(ChildElement(ChildElement(ACompilerOptions, 'SearchPaths'), AName));
    for LEntry in LEntries do
      // a macro, like $(LazarusDir), can not be resolved here
      if (Trim(LEntry) <> '') and not ContainsStr(LEntry, '$(') then
        Result := Result + [ResolvePath(AProjectDir, LEntry)];
  finally
    LEntries.Free;
  end;
end;

function BuildModePaths(const AName: string; ACompilerOptions: TDOMElement; const AProjectDir: string): TBuildModePaths;
begin
  Result.Name := AName;
  Result.Paths := SearchPaths(ACompilerOptions, AProjectDir, 'OtherUnitFiles');
  Result.IncludePaths := SearchPaths(ACompilerOptions, AProjectDir, 'IncludeFiles');
end;

function GetBuildModesPaths(const AProjectFile: string): TBuildModesPaths;
var
  LDocument: TXMLDocument = nil;
  LRoot, LCompilerOptions: TDOMElement;
  LItem: TDOMElement;
  LProjectDir: string;
begin
  Result := [];
  LProjectDir := ExtractFileDir(ExpandFileName(AProjectFile));
  ReadXMLFile(LDocument, AProjectFile);
  try
    LRoot := LDocument.DocumentElement;
    if Assigned(ChildElement(LRoot, 'Package')) then
      Exit([BuildModePaths('', ChildElement(ChildElement(LRoot, 'Package'), 'CompilerOptions'), LProjectDir)]);

    for LItem in ItemElements(ChildElement(ChildElement(LRoot, 'ProjectOptions'), 'BuildModes')) do
    begin
      LCompilerOptions := ChildElement(LItem, 'CompilerOptions');
      if not Assigned(LCompilerOptions) then
        LCompilerOptions := ChildElement(LRoot, 'CompilerOptions');
      Result := Result + [BuildModePaths(UTF8Encode(LItem.GetAttribute('Name')), LCompilerOptions, LProjectDir)];
    end;
    if Length(Result) = 0 then
      Result := [BuildModePaths('', ChildElement(LRoot, 'CompilerOptions'), LProjectDir)];
  finally
    LDocument.Free;
  end;
end;

function HasUnits(const ADir: string): Boolean;
var
  LSearch: TSearchRec;
begin
  Result := False;
  if FindFirst(ConcatPaths([ADir, AllFilesMask]), faAnyFile, LSearch) = 0 then
    try
      repeat
        if ((LSearch.Attr and faDirectory) = 0) and AnsiMatchText(ExtractFileExt(LSearch.Name), UNIT_EXTENSIONS) then
          Exit(True);
      until FindNext(LSearch) <> 0;
    finally
      FindClose(LSearch);
    end;
end;

function HasProject(const ADir: string): Boolean;
var
  LSearch: TSearchRec;
begin
  Result := False;
  if FindFirst(ConcatPaths([ADir, AllFilesMask]), faAnyFile, LSearch) = 0 then
    try
      repeat
        if ((LSearch.Attr and faDirectory) = 0) and AnsiMatchText(ExtractFileExt(LSearch.Name), ['.lpi', '.lpk']) then
          Exit(True);
      until FindNext(LSearch) <> 0;
    finally
      FindClose(LSearch);
    end;
end;

function SubFolders(const ADir: string): TArray<string>;
var
  LSearch: TSearchRec;
  LList: TStringList;
begin
  Result := [];
  LList := TStringList.Create;
  try
    if FindFirst(ConcatPaths([ADir, AllFilesMask]), faDirectory, LSearch) = 0 then
      try
        repeat
          if ((LSearch.Attr and faDirectory) <> 0) and not StartsStr('.', LSearch.Name) and
             not AnsiMatchText(LSearch.Name, SKIPPED_FOLDERS) then
            LList.Add(ConcatPaths([ADir, LSearch.Name]));
        until FindNext(LSearch) <> 0;
      finally
        FindClose(LSearch);
      end;
    LList.Sort;
    Result := LList.ToStringArray;
  finally
    LList.Free;
  end;
end;

procedure AddUnitFolders(var AFolders: TArray<string>; const ADir: string);
var
  LSubFolder: string;
begin
  for LSubFolder in SubFolders(ADir) do
  begin
    // another project or package, like a sample, has its own search paths
    if HasProject(LSubFolder) then
      Continue;
    if HasUnits(LSubFolder) then
      AFolders := AFolders + [LSubFolder];
    AddUnitFolders(AFolders, LSubFolder);
  end;
end;

function GetUnitFolders(const AProjectDir: string): TArray<string>;
begin
  Result := [];
  AddUnitFolders(Result, NormalizeDir(AProjectDir));
end;

procedure AddUnitFiles(var AFiles: TArray<string>; const ADir: string);
var
  LSearch: TSearchRec;
  LList: TStringList;
  LName: string;
begin
  LList := TStringList.Create;
  try
    if FindFirst(ConcatPaths([ADir, AllFilesMask]), faAnyFile, LSearch) = 0 then
      try
        repeat
          if ((LSearch.Attr and faDirectory) = 0) and AnsiMatchText(ExtractFileExt(LSearch.Name), UNIT_EXTENSIONS) then
            LList.Add(ConcatPaths([ADir, LSearch.Name]));
        until FindNext(LSearch) <> 0;
      finally
        FindClose(LSearch);
      end;
    LList.Sort;
    for LName in LList do
      AFiles := AFiles + [LName];
  finally
    LList.Free;
  end;
end;

function GetPackageFiles(const APackageFile: string): TArray<string>;
var
  LDocument: TXMLDocument = nil;
  LItem: TDOMElement;
  LValue, LPackageDir: string;
begin
  Result := [];
  LPackageDir := ExtractFileDir(ExpandFileName(APackageFile));
  ReadXMLFile(LDocument, APackageFile);
  try
    for LItem in ItemElements(ChildElement(ChildElement(LDocument.DocumentElement, 'Package'), 'Files')) do
    begin
      LValue := ValueOf(ChildElement(LItem, 'Filename'));
      if (LValue <> '') and not ContainsStr(LValue, '$(') then
        Result := Result + [ResolvePath(LPackageDir, LValue)];
    end;
  finally
    LDocument.Free;
  end;
end;

function ContainsPath(const APaths: TArray<string>; const APath: string): Boolean;
var
  LPath: string;
begin
  Result := False;
  for LPath in APaths do
    if SameFileName(LPath, APath) then
      Exit(True);
end;

function IsInside(const APath, AFolder: string): Boolean;
begin
  Result := SameFileName(NormalizeDir(APath), NormalizeDir(AFolder)) or
    StartsStr(IncludeTrailingPathDelimiter(NormalizeDir(AFolder)), NormalizeDir(APath));
end;

function CheckProject(const AProjectFile, ABaseDir: string): TArray<string>;
var
  LProjectDir, LProjectName, LFolder, LFile, LMissing, LBaseDir: string;
  LModes: TBuildModesPaths;
  LMode: TBuildModePaths;
  LListed, LUnits: TArray<string>;
  LIsPackage: Boolean;
  LMissingCount, I, J, LGroupCount: Integer;
  LMissingPaths, LMissingModes: TArray<string>;
  LGroup: string;
  LInModules: Boolean;
begin
  Result := [];
  LProjectDir := NormalizeDir(ExtractFileDir(AProjectFile));
  LProjectName := ExtractFileName(AProjectFile);
  LBaseDir := NormalizeDir(ABaseDir);
  LIsPackage := SameText(ExtractFileExt(AProjectFile), '.lpk');
  LModes := GetBuildModesPaths(AProjectFile);

  for LFolder in GetUnitFolders(LProjectDir) do
  begin
    LMissing := '';
    LMissingCount := 0;
    for LMode in LModes do
      if not ContainsPath(LMode.Paths, LFolder) then
      begin
        Inc(LMissingCount);
        if LMode.Name <> '' then
          LMissing := LMissing + IfThen(LMissing <> '', ', ', '') + LMode.Name;
      end;
    if LMissingCount = 0 then
      Continue;
    Result := Result + [Format('%s has units but is not in the search paths of %s%s, add %s to its OtherUnitFiles', [
      RelativePath(LBaseDir, LFolder), LProjectName, IfThen(LMissing <> '', ' (' + LMissing + ')', ''),
      RelativePath(LProjectDir, LFolder)])];
  end;

  // each search path that does not exist, once, with the build modes that have it
  LMissingPaths := [];
  LMissingModes := [];
  for LMode in LModes do
    for LFolder in LMode.Paths + LMode.IncludePaths do
    begin
      if DirectoryExists(LFolder) then
        Continue;
      I := 0;
      while (I < Length(LMissingPaths)) and not SameFileName(LMissingPaths[I], LFolder) do
        Inc(I);
      if I = Length(LMissingPaths) then
      begin
        LMissingPaths := LMissingPaths + [LFolder];
        LMissingModes := LMissingModes + [''];
      end;
      if (LMode.Name <> '') and not ContainsText(', ' + LMissingModes[I] + ', ', ', ' + LMode.Name + ', ') then
        LMissingModes[I] := LMissingModes[I] + IfThen(LMissingModes[I] <> '', ', ', '') + LMode.Name;
    end;
  // one warning for the paths missing from the same build modes, like the modules of a
  // workspace that were not installed
  for I := 0 to High(LMissingPaths) do
  begin
    if LMissingPaths[I] = '' then
      Continue;
    LGroup := RelativePath(LProjectDir, LMissingPaths[I]);
    LGroupCount := 1;
    LInModules := IsInside(LMissingPaths[I], ConcatPaths([LBaseDir, 'modules']));
    for J := I + 1 to High(LMissingPaths) do
      if (LMissingPaths[J] <> '') and SameText(LMissingModes[J], LMissingModes[I]) then
      begin
        LGroup := LGroup + ', ' + RelativePath(LProjectDir, LMissingPaths[J]);
        Inc(LGroupCount);
        LInModules := LInModules or IsInside(LMissingPaths[J], ConcatPaths([LBaseDir, 'modules']));
        LMissingPaths[J] := '';
      end;
    Result := Result + [Format('%s%s: %s %s %s%s', [
      RelativePath(LBaseDir, ExpandFileName(AProjectFile)), IfThen(LMissingModes[I] <> '', ' (' + LMissingModes[I] + ')', ''),
      IfThen(LGroupCount = 1, 'search path', 'search paths'), LGroup,
      IfThen(LGroupCount = 1, 'does not exist', 'do not exist'),
      IfThen(LInModules, ', run pasc deps to install the dependencies', '')])];
  end;

  if not LIsPackage then
    Exit;

  LListed := GetPackageFiles(AProjectFile);
  for LFile in LListed do
    if not FileExists(LFile) then
      Result := Result + [Format('the Files of %s list %s, which does not exist, remove it from the package', [
        LProjectName, RelativePath(LBaseDir, LFile)])];

  // the units of the package folder, of its subfolders with units and of its search paths
  LUnits := [];
  AddUnitFiles(LUnits, LProjectDir);
  for LFolder in GetUnitFolders(LProjectDir) do
    AddUnitFiles(LUnits, LFolder);
  for LFile in LUnits do
  begin
    // the main unit of the package is written by lazbuild from the Files
    if SameFileName(LFile, ChangeFileExt(ExpandFileName(AProjectFile), '.pas')) then
      Continue;
    if not ContainsPath(LListed, LFile) then
      Result := Result + [Format('%s is not in the Files of %s, add it to the package', [
        RelativePath(LBaseDir, LFile), LProjectName])];
  end;
end;

function HasDependencies(const ABossFile: string): Boolean;
var
  LJson: TJSONData;
begin
  Result := False;
  if not FileExists(ABossFile) then
    Exit;
  LJson := GetJSON(GetFileContent(ABossFile));
  try
    Result := (LJson is TJSONObject) and (TJSONObject(LJson).Find('dependencies') is TJSONObject) and
      (TJSONObject(TJSONObject(LJson).Find('dependencies')).Count > 0);
  finally
    LJson.Free;
  end;
end;

function CheckWorkspaceModules(const AWorkspaceDir: string; const AMemberDirs: TArray<string>): TArray<string>;
var
  LBaseDir, LModulesDir, LDir, LCandidate: string;
  LCandidates: TStringList;
  LMissing: TArray<string>;
begin
  Result := [];
  LBaseDir := NormalizeDir(AWorkspaceDir);
  LModulesDir := ConcatPaths([LBaseDir, 'modules']);

  // a modules folder anywhere else was installed or moved to the wrong folder
  LCandidates := TStringList.Create;
  try
    LCandidates.Sorted := True;
    LCandidates.Duplicates := dupIgnore;
    LCandidates.Add(ConcatPaths([LBaseDir, WORKSPACE_APPS_DIR, 'modules']));
    LCandidates.Add(ConcatPaths([LBaseDir, WORKSPACE_PACKAGES_DIR, 'modules']));
    for LDir in AMemberDirs do
      LCandidates.Add(ConcatPaths([NormalizeDir(LDir), 'modules']));
    for LCandidate in LCandidates do
      if DirectoryExists(LCandidate) then
        Result := Result + [Format('%s is out of place: pasc deps installs the dependencies in the modules ' +
          'folder at the root. Move it there, or remove it and run pasc deps', [RelativePath(LBaseDir, LCandidate)])];
  finally
    LCandidates.Free;
  end;

  if not DirectoryExists(LModulesDir) then
  begin
    if HasDependencies(ConcatPaths([LBaseDir, 'boss.json'])) then
      Result := Result + ['boss.json has dependencies but there is no modules folder at the root of the workspace, ' +
        'run pasc deps to install them'];
    Exit;
  end;

  LMissing := GetModulesMissingFromLock(LBaseDir);
  if Length(LMissing) > 0 then
    Result := Result + ['boss-lock.json records modules that are not in modules: ' + string.Join(', ', LMissing) +
      '. Run pasc deps to install them; if the warning stays, the lock was written by another boss version'];
end;

end.
