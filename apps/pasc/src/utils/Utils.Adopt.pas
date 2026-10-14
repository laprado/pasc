/// <summary> Unit which contains functions to convert an existing project to the workspace
/// layout. The project is first analyzed into a plan, that can be shown without changing
/// anything, and then the plan is applied.
///
/// Supported layouts:
/// - an app with a .lpi and .lpr at the root (created by pasc new, with a src folder, or a
///   plain lazarus app with its units at the root): it is moved to apps/name, while boss files
///   stay at the root as the workspace manifest;
/// - a repository with several projects or packages (or a .lpg project group): it is adopted
///   in place, pasc.json lists the existing folders as members and nothing is moved.
/// A boss library (sources consumed by other repositories through its "mainsrc") is refused,
/// since it should stay in its own repository.
/// </summary>
unit Utils.Adopt;

{$MODE DELPHI}{$H+}

interface

type
  /// <summary> Layout detected in the project to adopt. </summary>
  TAdoptKind = (
    /// <summary> The project cannot be adopted, see the plan Reason. </summary>
    akRefused,
    /// <summary> An app with a src folder, as created by pasc new. </summary>
    akApp,
    /// <summary> A lazarus app with its units at the root. </summary>
    akPlainApp,
    /// <summary> Several projects or packages, adopted in place. </summary>
    akMultiProject);

  /// <summary> A file or folder moved by the adoption, relative to the root. </summary>
  TAdoptMove = record
    Source: string;
    Target: string;
  end;

  /// <summary> A required package without a DefaultFilename in a member project. </summary>
  TAdoptReference = record
    /// <summary> Complete file name of the .lpi or .lpk that requires the package. </summary>
    ProjectFile: string;
    /// <summary> Name of the required package. </summary>
    PackageName: string;
    /// <summary> Complete file name of the package .lpk found in the repository. </summary>
    PackageFile: string;
  end;

  /// <summary> Result of the analysis of a project, applied by ApplyAdoption. </summary>
  TAdoptPlan = record
    Kind: TAdoptKind;
    /// <summary> Complete path of the project root. </summary>
    Root: string;
    /// <summary> App name, for akApp and akPlainApp. </summary>
    Name: string;
    /// <summary> Why the project cannot be adopted, for akRefused. </summary>
    Reason: string;
    Moves: TArray<TAdoptMove>;
    /// <summary> Member folders relative to the root, for akMultiProject. </summary>
    Members: TArray<string>;
    References: TArray<TAdoptReference>;
    /// <summary> Root entries that are not part of the app and stay at the root. </summary>
    LeftAtRoot: TArray<string>;
    Warnings: TArray<string>;
  end;

  /// <summary> Analyzes a project and returns the plan to convert it to a workspace. Nothing is
  /// changed. </summary>
  /// <param name="ARoot"> Project root folder. </param>
  /// <param name="AForce"> Accepts a git working tree with uncommitted changes. </param>
  function AnalyzeAdoption(const ARoot: string; const AForce: Boolean): TAdoptPlan;

  /// <summary> Applies a plan returned by AnalyzeAdoption. Returns the description of each
  /// change. Tracked files are moved with git mv to keep their history. </summary>
  /// <param name="APlan"> Plan to apply, of kind akApp, akPlainApp or akMultiProject. </param>
  function ApplyAdoption(const APlan: TAdoptPlan): TArray<string>;

  /// <summary> Returns the given relative path, of an entry of a project file that was at
  /// AOldDir and is now at ANewDir, so that it still points to the same place. Paths that point
  /// inside one of the moved folders or files are kept, as they moved together. Lazarus macros
  /// are kept. </summary>
  /// <param name="AEntry"> Path as written in the project file. </param>
  /// <param name="AOldDir"> Previous folder of the project file. </param>
  /// <param name="ANewDir"> Current folder of the project file. </param>
  /// <param name="AMovedPaths"> Complete previous paths of everything that was moved. </param>
  function RebasePath(const AEntry, AOldDir, ANewDir: string; const AMovedPaths: TArray<string>): string;

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
  Utils.Resources,
  Utils.Shell,
  Utils.Workspace;

const
  // folders and files of the root that belong to the workspace, not to the app
  ROOT_ENTRIES: array[0..10] of string = (
    '.git', '.gitignore', 'boss.json', 'boss-lock.json', 'modules', 'lib', 'backup',
    WORKSPACE_FILE, WORKSPACE_APPS_DIR, WORKSPACE_PACKAGES_DIR, '.gitattributes');

function Git(const ARoot: string; AParams: TArray<string>; out AOutput: string): Integer;
var
  LExitCode: Integer = 0;
begin
  try
    AOutput := ShellExecute('git', ['-C', ARoot] + AParams, LExitCode);
    Result := LExitCode;
  except
    on E: Exception do
    begin
      AOutput := E.Message;
      Result := -1;
    end;
  end;
end;

function ToSlash(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
end;

function IsInside(const APath, AFolderOrFile: string): Boolean;
begin
  Result := SameFileName(ExcludeTrailingPathDelimiter(APath), ExcludeTrailingPathDelimiter(AFolderOrFile)) or
    StartsStr(IncludeTrailingPathDelimiter(AFolderOrFile), APath);
end;

function ListEntries(const ADir, AMask: string; const ADirectories: Boolean): TArray<string>;
var
  LSearch: TSearchRec;
  LList: TStringList;
  LIsDir: Boolean;
  LName: string;
begin
  Result := [];
  LList := TStringList.Create;
  try
    if FindFirst(ConcatPaths([ADir, AMask]), faAnyFile or faDirectory, LSearch) = 0 then
      try
        repeat
          if (LSearch.Name = '.') or (LSearch.Name = '..') then
            Continue;
          LIsDir := (LSearch.Attr and faDirectory) <> 0;
          if LIsDir = ADirectories then
            LList.Add(LSearch.Name);
        until FindNext(LSearch) <> 0;
      finally
        FindClose(LSearch);
      end;
    LList.Sort;
    for LName in LList do
      Result := Result + [LName];
  finally
    LList.Free;
  end;
end;

function HasSegment(const ARelativePath: string; const ASegments: array of string): Boolean;
var
  LSegment: string;
begin
  Result := False;
  for LSegment in SplitString(ToSlash(ARelativePath), '/') do
    if AnsiMatchText(LSegment, ASegments) then
      Exit(True);
end;

/// projects and packages in subfolders, relative to the root, ignoring tests, samples and
/// folders that are not part of the sources
procedure FindSubProjects(const ARoot, ADir: string; var AProjects: TArray<string>);
var
  LName, LRelative: string;
begin
  for LName in ListEntries(ADir, '*', False) do
    if AnsiMatchText(ExtractFileExt(LName), ['.lpi', '.lpk']) then
    begin
      LRelative := ToSlash(ExtractRelativePath(IncludeTrailingPathDelimiter(ARoot), ConcatPaths([ADir, LName])));
      if Pos('/', LRelative) > 0 then
        AProjects := AProjects + [LRelative];
    end;

  for LName in ListEntries(ADir, '*', True) do
    if not StartsStr('.', LName) and
       not AnsiMatchText(LName, ['modules', 'lib', 'backup', 'tests', 'test', 'samples', 'examples']) then
      FindSubProjects(ARoot, ConcatPaths([ADir, LName]), AProjects);
end;

function ReadXml(const AFileName: string): TXMLDocument;
begin
  Result := nil;
  ReadXMLFile(Result, AFileName);
end;

function AttributeOf(ANode: TDOMNode; const AAttribute: string): string;
begin
  Result := '';
  if Assigned(ANode) and (ANode is TDOMElement) then
    Result := UTF8Encode(TDOMElement(ANode).GetAttribute(UnicodeString(AAttribute)));
end;

/// files of the project units, relative to the project folder
function GetProjectUnits(const AProjectFile: string): TArray<string>;
var
  LDocument: TXMLDocument;
  LUnits, LUnit: TDOMNode;
begin
  Result := [];
  LDocument := ReadXml(AProjectFile);
  try
    LUnits := LDocument.DocumentElement.FindNode('ProjectOptions');
    if Assigned(LUnits) then
      LUnits := LUnits.FindNode('Units');
    if not Assigned(LUnits) then
      Exit;
    LUnit := LUnits.FirstChild;
    while Assigned(LUnit) do
    begin
      if LUnit is TDOMElement then
        if AttributeOf(LUnit.FindNode('Filename'), 'Value') <> '' then
          Result := Result + [AttributeOf(LUnit.FindNode('Filename'), 'Value')];
      LUnit := LUnit.NextSibling;
    end;
  finally
    LDocument.Free;
  end;
end;

/// target files of a .lpg project group, relative to the root
function GetProjectGroupTargets(const AGroupFile: string): TArray<string>;
var
  LDocument: TXMLDocument;
  LTargets, LTarget: TDOMNode;
begin
  Result := [];
  LDocument := ReadXml(AGroupFile);
  try
    LTargets := LDocument.DocumentElement.FindNode('ProjectGroup');
    if Assigned(LTargets) then
      LTargets := LTargets.FindNode('Targets');
    if not Assigned(LTargets) then
      Exit;
    LTarget := LTargets.FirstChild;
    while Assigned(LTarget) do
    begin
      if AttributeOf(LTarget, 'FileName') <> '' then
        Result := Result + [ToSlash(AttributeOf(LTarget, 'FileName'))];
      LTarget := LTarget.NextSibling;
    end;
  finally
    LDocument.Free;
  end;
end;

/// required packages without a DefaultFilename that are packages of the repository
procedure FindMissingReferences(var APlan: TAdoptPlan);
var
  LMember, LName, LPackage: string;
  LMembers: TWorkspaceMembers;
  LInfo, LFound: TWorkspaceMember;
  LDocument: TXMLDocument;
  LNodes: TDOMNodeList;
  LReference: TAdoptReference;
  I: Integer;
begin
  LMembers := [];
  for LMember in APlan.Members do
  begin
    LInfo := Default(TWorkspaceMember);
    LInfo.Dir := ConcatPaths([APlan.Root, LMember]);
    LInfo.ProjectFile := '';
    for LName in ListEntries(LInfo.Dir, '*', False) do
      if AnsiMatchText(ExtractFileExt(LName), ['.lpk', '.lpi']) and (LInfo.ProjectFile = '') then
        LInfo.ProjectFile := ConcatPaths([LInfo.Dir, LName]);
    if LInfo.ProjectFile = '' then
      Continue;
    LInfo.IsPackage := SameText(ExtractFileExt(LInfo.ProjectFile), '.lpk');
    LInfo.Name := ChangeFileExt(ExtractFileName(LInfo.ProjectFile), '');
    LMembers := LMembers + [LInfo];
  end;

  for LInfo in LMembers do
  begin
    LDocument := ReadXml(LInfo.ProjectFile);
    try
      LNodes := LDocument.GetElementsByTagName('PackageName');
      try
        for I := 0 to LNodes.Count - 1 do
        begin
          if Assigned(LNodes[I].ParentNode.FindNode('DefaultFilename')) then
            Continue;
          LPackage := AttributeOf(LNodes[I], 'Value');
          LFound := FindMember(LMembers, LPackage);
          if LFound.IsPackage and not SameFileName(LFound.ProjectFile, LInfo.ProjectFile) then
          begin
            LReference.ProjectFile := LInfo.ProjectFile;
            LReference.PackageName := LPackage;
            LReference.PackageFile := LFound.ProjectFile;
            APlan.References := APlan.References + [LReference];
          end;
        end;
      finally
        LNodes.Free;
      end;
    finally
      LDocument.Free;
    end;
  end;
end;

procedure AnalyzeMultiProject(var APlan: TAdoptPlan; const AGroupFile: string;
  const ASubProjects: TArray<string>);
var
  LProject, LDir, LExisting: string;
  LProjects: TArray<string>;
  LFound: Boolean;
begin
  APlan.Kind := akMultiProject;
  if AGroupFile <> '' then
    LProjects := GetProjectGroupTargets(AGroupFile)
  else
    LProjects := ASubProjects;

  for LProject in LProjects do
  begin
    LDir := ToSlash(ExtractFileDir(LProject));
    // test projects are run from their member by pasc test
    if (LDir = '') or HasSegment(LDir, ['tests', 'test']) then
      Continue;
    LFound := False;
    for LExisting in APlan.Members do
      if SameText(LExisting, LDir) then
        LFound := True;
    if not LFound then
      APlan.Members := APlan.Members + [LDir];
  end;

  if Length(APlan.Members) = 0 then
  begin
    APlan.Kind := akRefused;
    APlan.Reason := 'No project or package found to be a workspace member.';
    Exit;
  end;

  FindMissingReferences(APlan);
end;

procedure AddMove(var APlan: TAdoptPlan; const ASource: string);
var
  LMove: TAdoptMove;
begin
  LMove.Source := ASource;
  LMove.Target := WORKSPACE_APPS_DIR + '/' + APlan.Name + '/' + ToSlash(ASource);
  APlan.Moves := APlan.Moves + [LMove];
end;

function IsMoved(const APlan: TAdoptPlan; const AEntry: string): Boolean;
var
  LMove: TAdoptMove;
begin
  Result := False;
  for LMove in APlan.Moves do
    if SameFileName(LMove.Source, AEntry) then
      Exit(True);
end;

procedure AnalyzeApp(var APlan: TAdoptPlan; const AProjectFile: string; const ASubProjects: TArray<string>);
var
  LUnit, LEntry, LExt, LSubProject: string;
begin
  APlan.Name := ChangeFileExt(ExtractFileName(AProjectFile), '');
  if not IsValidIdent(APlan.Name) then
  begin
    APlan.Kind := akRefused;
    APlan.Reason := '"' + APlan.Name + '" is not a valid pascal identifier to be the app name.';
    Exit;
  end;

  if not FileExists(ConcatPaths([APlan.Root, APlan.Name + '.lpr'])) then
  begin
    APlan.Kind := akRefused;
    APlan.Reason := APlan.Name + '.lpr not found next to ' + ExtractFileName(AProjectFile) + '.';
    Exit;
  end;

  if DirectoryExists(ConcatPaths([APlan.Root, 'src'])) then
    APlan.Kind := akApp
  else
    APlan.Kind := akPlainApp;

  for LExt in ['.lpi', '.lpr', '.res', '.ico', '.manifest'] do
    if FileExists(ConcatPaths([APlan.Root, APlan.Name + LExt])) then
      AddMove(APlan, APlan.Name + LExt);
  if DirectoryExists(ConcatPaths([APlan.Root, 'src'])) then
    AddMove(APlan, 'src');
  if DirectoryExists(ConcatPaths([APlan.Root, 'tests'])) then
    AddMove(APlan, 'tests');

  // units of the project at the root, with their forms (a plain lazarus app)
  for LUnit in GetProjectUnits(AProjectFile) do
    if (ExtractFileDir(LUnit) = '') and FileExists(ConcatPaths([APlan.Root, LUnit])) and not IsMoved(APlan, LUnit) then
    begin
      AddMove(APlan, LUnit);
      for LExt in ['.lfm', '.lrs'] do
        if FileExists(ConcatPaths([APlan.Root, ChangeFileExt(LUnit, LExt)])) and
           not IsMoved(APlan, ChangeFileExt(LUnit, LExt)) then
          AddMove(APlan, ChangeFileExt(LUnit, LExt));
    end;

  for LEntry in ListEntries(APlan.Root, '*', False) + ListEntries(APlan.Root, '*', True) do
    if not IsMoved(APlan, LEntry) and not AnsiMatchText(LEntry, ROOT_ENTRIES) and
       // build output and session files of the app
       not AnsiMatchText(LEntry, [APlan.Name, APlan.Name + '.exe', APlan.Name + '.lps', APlan.Name + '.app']) then
      APlan.LeftAtRoot := APlan.LeftAtRoot + [LEntry];

  if DirectoryExists(ConcatPaths([APlan.Root, '.vscode'])) then
    APlan.Warnings := APlan.Warnings + [
      '.vscode tasks and launch files reference the previous project path, update them to ' +
      WORKSPACE_APPS_DIR + '/' + APlan.Name + '.'];
  for LSubProject in ASubProjects do
    APlan.Warnings := APlan.Warnings + [
      LSubProject + ' is not moved and is not a member, add its folder to ' + WORKSPACE_FILE + ' if needed.'];
end;

function GetMainSrcDirs(const ARoot: string): TArray<string>;
var
  LJson: TJSONData;
  LMainSrc, LDir: string;
begin
  Result := [];
  if not FileExists(ConcatPaths([ARoot, 'boss.json'])) then
    Exit;
  LJson := GetJSON(GetFileContent(ConcatPaths([ARoot, 'boss.json'])));
  try
    if LJson is TJSONObject then
      LMainSrc := TJSONObject(LJson).Get('mainsrc', '')
    else
      LMainSrc := '';
  finally
    LJson.Free;
  end;
  for LDir in SplitString(LMainSrc, ';') do
    if Trim(LDir) <> '' then
      Result := Result + [Trim(LDir)];
end;

function AnalyzeAdoption(const ARoot: string; const AForce: Boolean): TAdoptPlan;
var
  LOutput, LDir, LWorkspace: string;
  LProjects, LPackages, LGroups, LDelphi, LSubProjects: TArray<string>;
begin
  Result := Default(TAdoptPlan);
  Result.Kind := akRefused;
  Result.Root := ExcludeTrailingPathDelimiter(ExpandFileName(ARoot));

  LWorkspace := FindWorkspaceRoot(Result.Root);
  if LWorkspace <> '' then
  begin
    Result.Reason := 'Already inside the workspace ' + LWorkspace + '.';
    Exit;
  end;

  if HasSegment(Result.Root, ['modules']) then
  begin
    Result.Reason := 'The folder is inside a boss modules folder.';
    Exit;
  end;

  if (Git(Result.Root, ['rev-parse', '--is-inside-work-tree'], LOutput) <> 0) or
     not ContainsText(LOutput, 'true') then
  begin
    Result.Reason := 'The folder is not in a git repository, files are moved with git mv to keep their history.';
    Exit;
  end;

  if (Git(Result.Root, ['status', '--porcelain'], LOutput) = 0) and (Trim(LOutput) <> '') and not AForce then
  begin
    Result.Reason := 'The git working tree has uncommitted changes. Commit or stash them, ' +
      'so the conversion is easy to review or revert, or use --force.';
    Exit;
  end;

  LProjects := ListEntries(Result.Root, '*.lpi', False);
  LPackages := ListEntries(Result.Root, '*.lpk', False);
  LGroups := ListEntries(Result.Root, '*.lpg', False);
  LDelphi := ListEntries(Result.Root, '*.dproj', False);
  LSubProjects := [];
  FindSubProjects(Result.Root, Result.Root, LSubProjects);

  if (Length(LGroups) > 0) or
     ((Length(LProjects) = 0) and (Length(LPackages) = 0) and (Length(LSubProjects) >= 2)) then
  begin
    if Length(LGroups) > 0 then
      AnalyzeMultiProject(Result, ConcatPaths([Result.Root, LGroups[0]]), LSubProjects)
    else
      AnalyzeMultiProject(Result, '', LSubProjects);
    Exit;
  end;

  if Length(LProjects) > 1 then
  begin
    Result.Reason := 'More than one .lpi at the root, the app to move is ambiguous.';
    Exit;
  end;

  if Length(LProjects) = 1 then
  begin
    AnalyzeApp(Result, ConcatPaths([Result.Root, LProjects[0]]), LSubProjects);
    Exit;
  end;

  if Length(LPackages) > 0 then
  begin
    Result.Reason := 'A package at the root is not supported yet, create a workspace and move it to ' +
      WORKSPACE_PACKAGES_DIR + '/' + ChangeFileExt(LPackages[0], '') + '.';
    Exit;
  end;

  for LDir in GetMainSrcDirs(Result.Root) do
    if DirectoryExists(ConcatPaths([Result.Root, LDir])) then
    begin
      Result.Reason := 'This looks like a boss library: other repositories use its sources through ' +
        'boss.json "mainsrc" (' + LDir + '), and moving them would change what they get. A library ' +
        'published with boss should stay in its own repository.';
      Exit;
    end;

  if Length(LDelphi) > 0 then
    Result.Reason := 'Delphi project without a .lpi or .lpk, pasc works with lazbuild.'
  else
    Result.Reason := 'No pascal project found: no .lpi, .lpk or .lpg file.';
end;

function RebasePath(const AEntry, AOldDir, ANewDir: string; const AMovedPaths: TArray<string>): string;
var
  LPath, LMoved: string;
begin
  Result := AEntry;
  if (Trim(AEntry) = '') or ContainsStr(AEntry, '$(') then
    Exit;

  LPath := SetDirSeparators(AEntry);
  {$IF DEFINED(WINDOWS)}
  if (ExtractFileDrive(LPath) <> '') or StartsStr(PathDelim, LPath) then
  {$ELSE}
  if StartsStr(PathDelim, LPath) then
  {$ENDIF}
    Exit;

  LPath := ExpandFileName(ConcatPaths([AOldDir, LPath]));
  for LMoved in AMovedPaths do
    if IsInside(LPath, LMoved) then
      Exit;

  Result := ToSlash(ExtractRelativePath(IncludeTrailingPathDelimiter(ANewDir), LPath));
  if Result = '' then
    Result := '.';
end;

/// rebases the paths of OtherUnitFiles, IncludeFiles and DefaultFilename of a moved project file
function RebaseProjectFile(const AProjectFile, AOldDir: string; const AMovedPaths: TArray<string>): Boolean;
const
  TAGS: array[0..2] of string = ('<OtherUnitFiles Value="', '<IncludeFiles Value="', '<DefaultFilename Value="');
var
  LContent, LValue, LNewValue, LEntry, LTag, LNewDir: string;
  LStart, LEnd, LOffset: Integer;
begin
  Result := False;
  LContent := GetFileContent(AProjectFile);
  LNewDir := ExtractFileDir(ExpandFileName(AProjectFile));
  for LTag in TAGS do
  begin
    LOffset := 1;
    repeat
      LStart := PosEx(LTag, LContent, LOffset);
      if LStart = 0 then
        Break;
      Inc(LStart, Length(LTag));
      LEnd := PosEx('"', LContent, LStart);
      if LEnd = 0 then
        Break;
      LValue := Copy(LContent, LStart, LEnd - LStart);

      LNewValue := '';
      for LEntry in SplitString(LValue, ';') do
        LNewValue := LNewValue + IfThen(LNewValue <> '', ';', '') +
          RebasePath(LEntry, AOldDir, LNewDir, AMovedPaths);

      if LNewValue <> LValue then
      begin
        Delete(LContent, LStart, LEnd - LStart);
        Insert(LNewValue, LContent, LStart);
        LEnd := LStart + Length(LNewValue);
        Result := True;
      end;
      LOffset := LEnd + 1;
    until False;
  end;
  if Result then
    SaveFileContent(AProjectFile, LContent);
end;

function IsTracked(const ARoot, APath: string): Boolean;
var
  LOutput: string;
begin
  Result := (Git(ARoot, ['ls-files', '--', APath], LOutput) = 0) and (Trim(LOutput) <> '');
end;

/// moves what is left in a folder (untracked files) to the target folder
procedure MoveRemaining(const ASource, ATarget: string);
var
  LName: string;
begin
  ForceDirectories(ATarget);
  for LName in ListEntries(ASource, '*', True) do
    MoveRemaining(ConcatPaths([ASource, LName]), ConcatPaths([ATarget, LName]));
  for LName in ListEntries(ASource, '*', False) do
    if not RenameFile(ConcatPaths([ASource, LName]), ConcatPaths([ATarget, LName])) then
      raise Exception.Create('Could not move ' + ConcatPaths([ASource, LName]) + ' to ' + ATarget + '.');
  RemoveDir(ASource);
end;

procedure MoveEntry(const ARoot: string; const AMove: TAdoptMove);
var
  LOutput, LSource, LTarget: string;
begin
  LSource := ConcatPaths([ARoot, SetDirSeparators(AMove.Source)]);
  LTarget := ConcatPaths([ARoot, SetDirSeparators(AMove.Target)]);
  ForceDirectories(ExtractFileDir(LTarget));
  if IsTracked(ARoot, AMove.Source) then
  begin
    if Git(ARoot, ['mv', AMove.Source, AMove.Target], LOutput) <> 0 then
      raise Exception.Create('git mv ' + AMove.Source + ' failed: ' + Trim(LOutput));
    // anything git mv left behind, like untracked files, goes to the same place
    if DirectoryExists(LSource) then
      MoveRemaining(LSource, LTarget);
  end
  else if not RenameFile(LSource, LTarget) then
    raise Exception.Create('Could not move ' + AMove.Source + ' to ' + AMove.Target + '.');
end;

/// executables of the app at the root in .gitignore now live in its member folder
function UpdateGitIgnore(const APlan: TAdoptPlan): Boolean;
var
  LFile, LLine, LBase: string;
  LLines: TStringList;
  I: Integer;
  LFound: Boolean = False;
begin
  Result := False;
  LFile := ConcatPaths([APlan.Root, '.gitignore']);
  if not FileExists(LFile) then
    Exit;
  LBase := '/' + WORKSPACE_APPS_DIR + '/' + APlan.Name + '/';
  LLines := TStringList.Create;
  try
    LLines.Text := GetFileContent(LFile);
    for I := 0 to LLines.Count - 1 do
    begin
      LLine := Trim(LLines[I]);
      if AnsiMatchStr(LLine, ['/' + APlan.Name, APlan.Name]) then
      begin
        LLines[I] := LBase + APlan.Name;
        LFound := True;
      end
      else if AnsiMatchStr(LLine, ['/tests/Test' + APlan.Name, 'tests/Test' + APlan.Name]) then
        LLines[I] := LBase + 'tests/Test' + APlan.Name;
    end;
    if not LFound then
    begin
      LLines.Add('# ' + APlan.Name + ' executables');
      LLines.Add(LBase + APlan.Name);
      LLines.Add(LBase + 'tests/Test' + APlan.Name);
    end;
    SaveFileContent(LFile, LLines.Text);
    Result := True;
  finally
    LLines.Free;
  end;
end;

/// boss "mainsrc" pointing to a moved folder follows it
function UpdateBossMainSrc(const APlan: TAdoptPlan): string;
var
  LFile, LContent, LValue, LNewValue, LDir, LNormalized, LReplaced: string;
  LStart, LEnd: Integer;
  LMove: TAdoptMove;
begin
  Result := '';
  LFile := ConcatPaths([APlan.Root, 'boss.json']);
  if not FileExists(LFile) then
    Exit;
  LContent := GetFileContent(LFile);
  LStart := Pos('"mainsrc"', LContent);
  if LStart = 0 then
    Exit;
  LStart := PosEx('"', LContent, LStart + Length('"mainsrc"')) + 1;
  LEnd := PosEx('"', LContent, LStart);
  if (LStart <= 1) or (LEnd = 0) then
    Exit;
  LValue := Copy(LContent, LStart, LEnd - LStart);

  LNewValue := '';
  for LDir in SplitString(LValue, ';') do
  begin
    LNormalized := ToSlash(Trim(LDir));
    if StartsStr('./', LNormalized) then
      LNormalized := Copy(LNormalized, 3, Length(LNormalized));
    while EndsStr('/', LNormalized) do
      LNormalized := Copy(LNormalized, 1, Length(LNormalized) - 1);

    LReplaced := LDir;
    for LMove in APlan.Moves do
      if (LNormalized <> '') and SameFileName(LNormalized, LMove.Source) then
        LReplaced := LMove.Target + '/';
    LNewValue := LNewValue + IfThen(LNewValue <> '', ';', '') + LReplaced;
  end;

  if LNewValue <> LValue then
  begin
    Delete(LContent, LStart, LEnd - LStart);
    Insert(LNewValue, LContent, LStart);
    SaveFileContent(LFile, LContent);
    Result := LNewValue;
  end;
end;

/// adds the DefaultFilename after the PackageName of a required package
procedure AddDefaultFilename(const AReference: TAdoptReference);
var
  LContent, LTag, LIndent, LRelative: string;
  LStart, LLineStart, LLineEnd: Integer;
begin
  LContent := GetFileContent(AReference.ProjectFile);
  LTag := '<PackageName Value="' + AReference.PackageName + '"/>';
  LStart := Pos(LTag, LContent);
  if LStart = 0 then
    Exit;
  LLineStart := LStart;
  while (LLineStart > 1) and not (LContent[LLineStart - 1] in [#10, #13]) do
    Dec(LLineStart);
  LIndent := Copy(LContent, LLineStart, LStart - LLineStart);
  LLineEnd := LStart + Length(LTag);
  LRelative := ToSlash(ExtractRelativePath(
    IncludeTrailingPathDelimiter(ExtractFileDir(AReference.ProjectFile)), AReference.PackageFile));
  Insert(LineEnding + LIndent + '<DefaultFilename Value="' + LRelative + '" Prefer="True"/>',
    LContent, LLineEnd);
  SaveFileContent(AReference.ProjectFile, LContent);
end;

function MembersJson(const AMembers: TArray<string>): string;
var
  LMember: string;
begin
  Result := '';
  for LMember in AMembers do
    Result := Result + IfThen(Result <> '', ', ', '') + '"' + LMember + '"';
  Result := '{' + LineEnding + '  "members": [' + Result + ']' + LineEnding + '}' + LineEnding;
end;

function ApplyAdoption(const APlan: TAdoptPlan): TArray<string>;
var
  LMove: TAdoptMove;
  LMovedPaths: TArray<string>;
  LReference: TAdoptReference;
  LAppDir, LTestProject, LMainSrc: string;
begin
  Result := [];
  if APlan.Kind = akRefused then
    raise Exception.Create(APlan.Reason);

  if APlan.Kind = akMultiProject then
  begin
    SaveFileContent(ConcatPaths([APlan.Root, WORKSPACE_FILE]), MembersJson(APlan.Members));
    Result := Result + [WORKSPACE_FILE + ' created with ' + IntToStr(Length(APlan.Members)) + ' members'];
    for LReference in APlan.References do
    begin
      AddDefaultFilename(LReference);
      Result := Result + [ExtractFileName(LReference.ProjectFile) + ' requires ' +
        LReference.PackageName + ' by relative path'];
    end;
    Exit;
  end;

  LMovedPaths := [];
  for LMove in APlan.Moves do
    LMovedPaths := LMovedPaths + [ConcatPaths([APlan.Root, SetDirSeparators(LMove.Source)])];

  ForceDirectories(ConcatPaths([APlan.Root, WORKSPACE_PACKAGES_DIR]));
  for LMove in APlan.Moves do
  begin
    MoveEntry(APlan.Root, LMove);
    Result := Result + [LMove.Source + ' moved to ' + LMove.Target];
  end;

  // the project files moved with their folders, paths to what stayed at the root need ../../
  LAppDir := ConcatPaths([APlan.Root, WORKSPACE_APPS_DIR, APlan.Name]);
  if RebaseProjectFile(ConcatPaths([LAppDir, APlan.Name + '.lpi']), APlan.Root, LMovedPaths) then
    Result := Result + [APlan.Name + '.lpi paths updated'];
  LTestProject := GetMemberTestProject(LAppDir);
  if (LTestProject <> '') and
     RebaseProjectFile(LTestProject, ConcatPaths([APlan.Root, 'tests']), LMovedPaths) then
    Result := Result + [ExtractFileName(LTestProject) + ' paths updated'];

  SaveFileContent(ConcatPaths([APlan.Root, WORKSPACE_FILE]), GetResource('pascjson'));
  Result := Result + [WORKSPACE_FILE + ' created'];

  if UpdateGitIgnore(APlan) then
    Result := Result + ['.gitignore updated with the app executables'];

  LMainSrc := UpdateBossMainSrc(APlan);
  if LMainSrc <> '' then
    Result := Result + ['boss.json "mainsrc" updated to ' + LMainSrc];
end;

end.
