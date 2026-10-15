/// <summary> Unit which has the functions used by pasc coverage: the Coverage build mode of a
/// test project, the report that kcov writes and the units that the report does not have.
///
/// kcov needs no instrumentation: it reads the DWARF line info of the executable and sets a
/// breakpoint on each line. The Coverage build mode has the options of the Default one, with
/// debug info, no optimization, so lines are not merged or removed, and no heaptrc. Its units
/// go to lib/coverage, so they do not get mixed with the Default build, and its executable
/// stays next to the Default one, with -coverage at the end of the name, because tests often
/// find their files from the folder of the executable.
/// </summary>
unit Utils.Coverage;

{$MODE DELPHI}{$H+}

interface

const
  /// <summary> Name of the build mode added to the test projects. </summary>
  COVERAGE_BUILD_MODE = 'Coverage';

  /// <summary> Folder of the reports, at the root of the workspace or project. </summary>
  COVERAGE_DIR = 'coverage';

  /// <summary> Added to the name of the test executable for the Coverage build mode. </summary>
  COVERAGE_SUFFIX = '-coverage';

type

  /// <summary> Coverage of a source file. </summary>
  TCoverageFile = record
    /// <summary> Complete file name. </summary>
    FileName: string;
    Covered: Integer;
    Total: Integer;
  end;

  /// <summary> Coverage of a test run, read from the coverage.json of kcov. </summary>
  TCoverageReport = record
    Covered: Integer;
    Total: Integer;
    /// <summary> Files sorted by name. </summary>
    Files: TArray<TCoverageFile>;
  end;

  /// <summary> Returns true if a .lpi has a build mode with the given name, ignoring case.
  /// </summary>
  /// <param name="AProjectFile"> .lpi file. </param>
  /// <param name="AName"> Build mode name. </param>
  function HasBuildMode(const AProjectFile, AName: string): Boolean;

  /// <summary> Adds the Coverage build mode to a test project, if it does not have it, with the
  /// compiler options of the project: the same search paths, so pasc deps keeps them in sync,
  /// DWARF 3 debug info, no optimization, no heaptrc, the units in lib/coverage and the
  /// executable next to the Default one, with -coverage at the end of its name. Only the new
  /// build mode is written, the rest of the file is kept as it is.
  /// Returns false if the project already had the build mode. </summary>
  /// <param name="AProjectFile"> .lpi file of the test project. </param>
  function AddCoverageBuildMode(const AProjectFile: string): Boolean;

  /// <summary> Returns the complete file name of the executable of the Coverage build mode of
  /// a .lpi, or empty if it has no such build mode. </summary>
  /// <param name="AProjectFile"> .lpi file of the test project. </param>
  function GetCoverageExecutable(const AProjectFile: string): string;

  /// <summary> Reads the coverage.json written by kcov. </summary>
  /// <param name="AFileName"> coverage.json file. </param>
  function ReadCoverageReport(const AFileName: string): TCoverageReport;

  /// <summary> Returns the coverage as a percentage, zero when there are no lines. </summary>
  /// <param name="ACovered"> Covered lines. </param>
  /// <param name="ATotal"> Lines with code. </param>
  function CoveragePercent(const ACovered, ATotal: Integer): Double;

  /// <summary> Formats a percentage with two decimals and a dot, like 94.00%. </summary>
  /// <param name="APercent"> Percentage. </param>
  function FormatPercent(const APercent: Double): string;

  /// <summary> Returns true if the source of a unit has code after its implementation: a
  /// begin, an asm, an initialization or an include. A unit with only declarations has no line
  /// for kcov, even when a test uses it. Comments and strings are skipped. </summary>
  /// <param name="ASource"> Source of the unit. </param>
  function HasCode(const ASource: string): Boolean;

  /// <summary> Returns the units (.pas or .pp) of the given folders, not of their subfolders,
  /// that have code but are not in the report: no test uses them, so kcov does not see them
  /// and they are not counted. Sorted. </summary>
  /// <param name="ASourceDirs"> Source folders of the member. </param>
  /// <param name="AReport"> Coverage report of the member tests. </param>
  function GetUnitsNotInReport(const ASourceDirs: TArray<string>; const AReport: TCoverageReport): TArray<string>;

  /// <summary> Appends to the .gitignore of a folder the paths that git does not ignore yet,
  /// when the folder is in a git repository, like /coverage/. The .gitignore is created if
  /// needed, and its lines are kept. Returns the lines added. </summary>
  /// <param name="ARootDir"> Folder of the .gitignore. </param>
  /// <param name="APaths"> Paths relative to the folder, with / as separator and a / at the
  /// end of a folder. </param>
  function IgnorePaths(const ARootDir: string; const APaths: TArray<string>): TArray<string>;

implementation

uses
  Classes,
  SysUtils,
  StrUtils,
  DOM,
  XMLRead,
  XMLWrite,
  fpjson,
  jsonparser,
  Utils.IO,
  Utils.Shell;

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

/// <summary> The child element with the given name, appended if it does not exist. </summary>
function EnsureElement(AParent: TDOMElement; const AName: string): TDOMElement;
begin
  Result := ChildElement(AParent, AName);
  if not Assigned(Result) then
    Result := TDOMElement(AParent.AppendChild(AParent.OwnerDocument.CreateElement(UTF8Decode(AName))));
end;

procedure SetValue(AParent: TDOMElement; const APath: array of string; const AValue: string);
var
  LElement: TDOMElement;
  LName: string;
begin
  LElement := AParent;
  for LName in APath do
    LElement := EnsureElement(LElement, LName);
  LElement.SetAttribute('Value', UTF8Decode(AValue));
end;

procedure RemoveChild(AParent: TDOMElement; const AName: string);
var
  LElement: TDOMElement;
begin
  LElement := ChildElement(AParent, AName);
  if Assigned(LElement) then
    AParent.RemoveChild(LElement).Free;
end;

function FindBuildMode(ADocument: TXMLDocument; const AName: string): TDOMElement;
var
  LNode: TDOMNode;
begin
  Result := nil;
  LNode := ChildElement(ChildElement(ADocument.DocumentElement, 'ProjectOptions'), 'BuildModes');
  if not Assigned(LNode) then
    Exit;
  LNode := LNode.FirstChild;
  while Assigned(LNode) do
  begin
    // old files number the items, Item1, Item2, newer ones repeat Item
    if (LNode.NodeType = ELEMENT_NODE) and StartsText('Item', UTF8Encode(LNode.NodeName)) and
       SameText(UTF8Encode(TDOMElement(LNode).GetAttribute('Name')), AName) then
      Exit(TDOMElement(LNode));
    LNode := LNode.NextSibling;
  end;
end;

function HasBuildMode(const AProjectFile, AName: string): Boolean;
var
  LDocument: TXMLDocument;
begin
  ReadXMLFile(LDocument, AProjectFile);
  try
    Result := Assigned(FindBuildMode(LDocument, AName));
  finally
    LDocument.Free;
  end;
end;

/// <summary> The Coverage build mode item, as text indented for the BuildModes of a .lpi.
/// </summary>
function CoverageItem(ADocument: TXMLDocument; const AProjectFile, AItemTag, ALineEnding: string): string;
var
  LOptions, LDebugging: TDOMElement;
  LDelim, LName, LLine: string;
  LStream: TStringStream;
  LLines: TStringList;
begin
  LOptions := ChildElement(ADocument.DocumentElement, 'CompilerOptions');
  if Assigned(LOptions) then
    LOptions := TDOMElement(LOptions.CloneNode(True))
  else
    LOptions := ADocument.CreateElement('CompilerOptions');
  try
    LDelim := '\';
    if Assigned(ChildElement(LOptions, 'PathDelim')) and
       (ChildElement(LOptions, 'PathDelim').GetAttribute('Value') = '/') then
      LDelim := '/';

    LName := UTF8Encode(EnsureElement(EnsureElement(LOptions, 'Target'), 'Filename').GetAttribute('Value'));
    if LName = '' then
      LName := ChangeFileExt(ExtractFileName(AProjectFile), '');
    SetValue(LOptions, ['Target', 'Filename'], LName + COVERAGE_SUFFIX);
    SetValue(LOptions, ['SearchPaths', 'UnitOutputDirectory'],
      'lib' + LDelim + COVERAGE_DIR + LDelim + '$(TargetCPU)-$(TargetOS)');
    // no optimization, so kcov sees every line where the source has it
    SetValue(LOptions, ['CodeGeneration', 'Optimizations', 'OptimizationLevel'], '0');

    // kcov reads the DWARF line info of the executable itself
    LDebugging := EnsureElement(EnsureElement(LOptions, 'Linking'), 'Debugging');
    RemoveChild(LDebugging, 'GenerateDebugInfo');
    RemoveChild(LDebugging, 'StripSymbols');
    RemoveChild(LDebugging, 'UseExternalDbgSyms');
    RemoveChild(LDebugging, 'UseHeaptrc');
    SetValue(LDebugging, ['DebugInfoType'], 'dsDwarf3');

    LStream := TStringStream.Create('');
    LLines := TStringList.Create;
    try
      WriteXML(LOptions, LStream);
      LLines.Text := LStream.DataString;
      Result := '      <' + AItemTag + ' Name="' + COVERAGE_BUILD_MODE + '">' + ALineEnding;
      for LLine in LLines do
        if Trim(LLine) <> '' then
          Result := Result + '        ' + TrimRight(LLine) + ALineEnding;
      Result := Result + '      </' + AItemTag + '>' + ALineEnding;
    finally
      LLines.Free;
      LStream.Free;
    end;
  finally
    LOptions.Free;
  end;
end;

function AddCoverageBuildMode(const AProjectFile: string): Boolean;
var
  LDocument: TXMLDocument;
  LBuildModes: TDOMElement;
  LContent, LLineEnding, LItemTag, LCount: string;
  LPos, LLineStart: Integer;
begin
  LContent := GetFileContent(AProjectFile);
  LLineEnding := IfThen(ContainsStr(LContent, #13#10), #13#10, #10);
  ReadXMLFile(LDocument, AProjectFile);
  try
    if Assigned(FindBuildMode(LDocument, COVERAGE_BUILD_MODE)) then
      Exit(False);
    if not Assigned(ChildElement(LDocument.DocumentElement, 'ProjectOptions')) then
      raise Exception.Create(AProjectFile + ' is not a project file.');

    LBuildModes := ChildElement(ChildElement(LDocument.DocumentElement, 'ProjectOptions'), 'BuildModes');
    LItemTag := 'Item';
    LCount := '';
    if Assigned(LBuildModes) and LBuildModes.HasAttribute('Count') then
    begin
      // old format: <BuildModes Count="1"><Item1 .../></BuildModes>
      LCount := UTF8Encode(LBuildModes.GetAttribute('Count'));
      LItemTag := 'Item' + IntToStr(StrToIntDef(LCount, 0) + 1);
    end;

    if Assigned(LBuildModes) then
    begin
      LPos := Pos('</BuildModes>', LContent);
      if LPos = 0 then
        raise Exception.Create('Unexpected format, could not add the Coverage build mode to ' + AProjectFile);
      LLineStart := LPos;
      while (LLineStart > 1) and (LContent[LLineStart - 1] in [' ', #9]) do
        Dec(LLineStart);
      Insert(CoverageItem(LDocument, AProjectFile, LItemTag, LLineEnding), LContent, LLineStart);
      if LCount <> '' then
        LContent := StringReplace(LContent, '<BuildModes Count="' + LCount + '"',
          '<BuildModes Count="' + IntToStr(StrToIntDef(LCount, 0) + 1) + '"', []);
    end
    else
    begin
      // without build modes the options of the project are the Default build mode
      LPos := Pos('</ProjectOptions>', LContent);
      if LPos = 0 then
        raise Exception.Create('Unexpected format, could not add the Coverage build mode to ' + AProjectFile);
      LLineStart := LPos;
      while (LLineStart > 1) and (LContent[LLineStart - 1] in [' ', #9]) do
        Dec(LLineStart);
      Insert(
        '    <BuildModes>' + LLineEnding +
        '      <Item Name="Default" Default="True"/>' + LLineEnding +
        CoverageItem(LDocument, AProjectFile, 'Item', LLineEnding) +
        '    </BuildModes>' + LLineEnding,
        LContent, LLineStart);
    end;
  finally
    LDocument.Free;
  end;

  SaveFileContent(AProjectFile, LContent);
  Result := True;
end;

function GetCoverageExecutable(const AProjectFile: string): string;
var
  LDocument: TXMLDocument;
  LMode, LFilename: TDOMElement;
begin
  Result := '';
  ReadXMLFile(LDocument, AProjectFile);
  try
    LMode := FindBuildMode(LDocument, COVERAGE_BUILD_MODE);
    if not Assigned(LMode) then
      Exit;
    LFilename := ChildElement(ChildElement(ChildElement(LMode, 'CompilerOptions'), 'Target'), 'Filename');
    if Assigned(LFilename) then
      Result := UTF8Encode(LFilename.GetAttribute('Value'))
    else
      Result := ChangeFileExt(ExtractFileName(AProjectFile), '') + COVERAGE_SUFFIX;
  finally
    LDocument.Free;
  end;
  if Result = '' then
    Exit;
  Result := SetDirSeparators(StringReplace(Result, '\', '/', [rfReplaceAll]));
  Result := ExpandFileName(ConcatPaths([ExtractFileDir(ExpandFileName(AProjectFile)), Result]))
    {$IF DEFINED(WINDOWS)} + '.exe'{$ENDIF};
end;

function JsonInteger(AObject: TJSONObject; const AName: string): Integer;
var
  LData: TJSONData;
begin
  // kcov writes the numbers of each file as strings
  Result := 0;
  LData := AObject.Find(AName);
  if Assigned(LData) and (LData.JSONType in [jtNumber, jtString]) then
    Result := StrToIntDef(LData.AsString, 0);
end;

function ReadCoverageReport(const AFileName: string): TCoverageReport;
var
  LJson: TJSONData;
  LFiles: TJSONArray;
  LFile: TCoverageFile;
  LList: TStringList;
  I: Integer;
begin
  Result := Default(TCoverageReport);
  LJson := GetJSON(GetFileContent(AFileName));
  LList := TStringList.Create;
  try
    if not (LJson is TJSONObject) then
      raise Exception.Create(AFileName + ' is not a kcov report.');
    Result.Covered := JsonInteger(TJSONObject(LJson), 'covered_lines');
    Result.Total := JsonInteger(TJSONObject(LJson), 'total_lines');

    if TJSONObject(LJson).Find('files') is TJSONArray then
    begin
      LFiles := TJSONArray(TJSONObject(LJson).Find('files'));
      for I := 0 to LFiles.Count - 1 do
        if LFiles.Items[I] is TJSONObject then
          LList.AddObject(TJSONObject(LFiles.Items[I]).Get('file', ''), TObject(PtrInt(I)));
      LList.Sort;
      for I := 0 to LList.Count - 1 do
      begin
        LFile.FileName := LList[I];
        LFile.Covered := JsonInteger(TJSONObject(LFiles.Items[PtrInt(LList.Objects[I])]), 'covered_lines');
        LFile.Total := JsonInteger(TJSONObject(LFiles.Items[PtrInt(LList.Objects[I])]), 'total_lines');
        Result.Files := Result.Files + [LFile];
      end;
    end;
  finally
    LList.Free;
    LJson.Free;
  end;
end;

function CoveragePercent(const ACovered, ATotal: Integer): Double;
begin
  Result := 0;
  if ATotal > 0 then
    Result := ACovered * 100 / ATotal;
end;

function FormatPercent(const APercent: Double): string;
var
  LSettings: TFormatSettings;
begin
  LSettings := DefaultFormatSettings;
  LSettings.DecimalSeparator := '.';
  Result := FormatFloat('0.00', APercent, LSettings) + '%';
end;

function HasCode(const ASource: string): Boolean;
var
  I, LStart, LLength: Integer;
  LWord: string;
  LImplementation: Boolean;
begin
  Result := False;
  LImplementation := False;
  LLength := Length(ASource);
  I := 1;
  while I <= LLength do
  begin
    case ASource[I] of
      '{':
        begin
          // an include after the implementation may have the code
          if LImplementation and SameText(Copy(ASource, I + 1, 2), '$I') and (I + 3 <= LLength) and
             (ASource[I + 3] in [' ', 'n', 'N']) then
            Exit(True);
          while (I <= LLength) and (ASource[I] <> '}') do
            Inc(I);
        end;
      '(':
        if (I < LLength) and (ASource[I + 1] = '*') then
        begin
          Inc(I, 2);
          while (I < LLength) and not ((ASource[I] = '*') and (ASource[I + 1] = ')')) do
            Inc(I);
          Inc(I);
        end;
      '/':
        if (I < LLength) and (ASource[I + 1] = '/') then
          while (I <= LLength) and not (ASource[I] in [#10, #13]) do
            Inc(I);
      '''':
        begin
          Inc(I);
          while (I <= LLength) and (ASource[I] <> '''') do
            Inc(I);
        end;
      'A'..'Z', 'a'..'z', '_':
        begin
          LStart := I;
          while (I <= LLength) and (ASource[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
            Inc(I);
          LWord := LowerCase(Copy(ASource, LStart, I - LStart));
          if LWord = 'implementation' then
            LImplementation := True
          else if LImplementation and AnsiMatchStr(LWord, ['begin', 'asm', 'initialization']) then
            Exit(True);
          Continue;
        end;
    end;
    Inc(I);
  end;
end;

function GetUnitsNotInReport(const ASourceDirs: TArray<string>; const AReport: TCoverageReport): TArray<string>;
var
  LDir, LFileName: string;
  LFile: TCoverageFile;
  LSearch: TSearchRec;
  LFound: Boolean;
  LUnits: TStringList;
begin
  LUnits := TStringList.Create;
  try
    for LDir in ASourceDirs do
      if FindFirst(ConcatPaths([LDir, AllFilesMask]), faAnyFile, LSearch) = 0 then
        try
          repeat
            if ((LSearch.Attr and faDirectory) <> 0) or
               not AnsiMatchText(ExtractFileExt(LSearch.Name), ['.pas', '.pp']) then
              Continue;
            LFileName := ExpandFileName(ConcatPaths([LDir, LSearch.Name]));
            LFound := False;
            for LFile in AReport.Files do
              if SameFileName(ExpandFileName(LFile.FileName), LFileName) then
              begin
                LFound := True;
                Break;
              end;
            if not LFound and HasCode(GetFileContent(LFileName)) then
              LUnits.Add(LFileName);
          until FindNext(LSearch) <> 0;
        finally
          FindClose(LSearch);
        end;
    LUnits.Sort;
    Result := LUnits.ToStringArray;
  finally
    LUnits.Free;
  end;
end;

function IgnorePaths(const ARootDir: string; const APaths: TArray<string>): TArray<string>;
var
  LExitCode: Integer;
  LGitIgnore, LContent, LPath: string;
begin
  Result := [];
  for LPath in APaths do
  begin
    LExitCode := 0;
    try
      // 0 when the path is ignored, 1 when it is not, 128 outside a git repository
      ShellExecute('git', ['-C', ARootDir, 'check-ignore', '-q', LPath], LExitCode);
    except
      // without git there is nothing to ignore
      Exit;
    end;
    if LExitCode = 1 then
      Result := Result + ['/' + LPath];
  end;
  if Length(Result) = 0 then
    Exit;

  LGitIgnore := ConcatPaths([ARootDir, '.gitignore']);
  LContent := '';
  if FileExists(LGitIgnore) then
    LContent := GetFileContent(LGitIgnore);
  if (LContent <> '') and not (LContent[Length(LContent)] in [#10, #13]) then
    LContent := LContent + LineEnding;
  for LPath in Result do
    LContent := LContent + LPath + LineEnding;
  SaveFileContent(LGitIgnore, LContent);
end;

end.
