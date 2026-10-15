/// <summary> Unit which checks the layout of a project or package against its file: the folders
/// with units that are not in the search paths of every build mode, and for a package the
/// units that are not in its files and the files that no longer exist. FPC does not search the
/// unit folders recursively and a package only compiles the units it lists, so each case would
/// only fail later, with "Can't find unit" at the first uses that reaches it.
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
  /// paths relative to ABaseDir. Returns empty when there is nothing to fix. </summary>
  /// <param name="AProjectFile"> .lpi or .lpk file. </param>
  /// <param name="ABaseDir"> Folder the paths of the warnings are relative to, like the
  /// workspace root. </param>
  function CheckProject(const AProjectFile, ABaseDir: string): TArray<string>;

implementation

uses
  Classes,
  SysUtils,
  StrUtils,
  DOM,
  XMLRead;

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

function UnitPaths(ACompilerOptions: TDOMElement; const AProjectDir: string): TArray<string>;
var
  LEntries: TStringList;
  LEntry: string;
begin
  Result := [];
  LEntries := TStringList.Create;
  try
    LEntries.StrictDelimiter := True;
    LEntries.Delimiter := ';';
    LEntries.DelimitedText := ValueOf(ChildElement(ChildElement(ACompilerOptions, 'SearchPaths'), 'OtherUnitFiles'));
    for LEntry in LEntries do
      // a macro, like $(LazarusDir), can not be resolved here
      if (Trim(LEntry) <> '') and not ContainsStr(LEntry, '$(') then
        Result := Result + [ResolvePath(AProjectDir, LEntry)];
  finally
    LEntries.Free;
  end;
end;

function BuildModePaths(const AName: string; const APaths: TArray<string>): TBuildModePaths;
begin
  Result.Name := AName;
  Result.Paths := APaths;
end;

function GetBuildModesPaths(const AProjectFile: string): TBuildModesPaths;
var
  LDocument: TXMLDocument = nil;
  LRoot, LCompilerOptions: TDOMElement;
  LItem: TDOMElement;
  LProjectDir: string;
  LProjectPaths: TArray<string>;
begin
  Result := [];
  LProjectDir := ExtractFileDir(ExpandFileName(AProjectFile));
  ReadXMLFile(LDocument, AProjectFile);
  try
    LRoot := LDocument.DocumentElement;
    if Assigned(ChildElement(LRoot, 'Package')) then
      Exit([BuildModePaths('', UnitPaths(ChildElement(ChildElement(LRoot, 'Package'), 'CompilerOptions'), LProjectDir))]);

    LProjectPaths := UnitPaths(ChildElement(LRoot, 'CompilerOptions'), LProjectDir);
    for LItem in ItemElements(ChildElement(ChildElement(LRoot, 'ProjectOptions'), 'BuildModes')) do
    begin
      LCompilerOptions := ChildElement(LItem, 'CompilerOptions');
      if Assigned(LCompilerOptions) then
        Result := Result + [BuildModePaths(UTF8Encode(LItem.GetAttribute('Name')), UnitPaths(LCompilerOptions, LProjectDir))]
      else
        Result := Result + [BuildModePaths(UTF8Encode(LItem.GetAttribute('Name')), LProjectPaths)];
    end;
    if Length(Result) = 0 then
      Result := [BuildModePaths('', LProjectPaths)];
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

function CheckProject(const AProjectFile, ABaseDir: string): TArray<string>;
var
  LProjectDir, LProjectName, LFolder, LFile, LMissing, LBaseDir: string;
  LModes: TBuildModesPaths;
  LMode: TBuildModePaths;
  LListed, LUnits: TArray<string>;
  LIsPackage: Boolean;
  LMissingCount: Integer;
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

end.
