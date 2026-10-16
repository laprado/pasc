/// <summary> Unit which has the functions used by pasc lint: the messages of the compiler, kept
/// only for the sources of a member, and the configuration in pasc.json that says which ones
/// are ignored and which ones fail.
///
/// The dependencies that boss installs in modules are compiled from source with the project, so
/// a build with warnings as errors stops in code that is not ours. The messages are filtered by
/// file after the compiler runs instead.
/// </summary>
unit Utils.Lint;

{$MODE DELPHI}{$H+}

interface

const
  /// <summary> Default limit of rule PL004, in lines of a routine, its header included.
  /// </summary>
  DEFAULT_MAX_ROUTINE_LINES = 80;
  /// <summary> Default limit of rule PL005, in parameters of a routine. </summary>
  DEFAULT_MAX_PARAMETERS = 6;
  /// <summary> Default limit of rule PL006, in nested if, case, loops, try and with. </summary>
  DEFAULT_MAX_NESTING = 4;

type

  /// <summary> Kind of a message of the compiler. </summary>
  TLintKind = (lkError, lkWarning, lkNote, lkHint);

  TLintKinds = set of TLintKind;

  /// <summary> A message of the compiler for a source file. </summary>
  TLintMessage = record
    /// <summary> Complete file name. </summary>
    FileName: string;
    Line: Integer;
    Column: Integer;
    Kind: TLintKind;
    /// <summary> Message number, like 5093, or 0 when the compiler shows none. </summary>
    Id: Integer;
    /// <summary> Id of an own rule of pasc lint, like PL001, or empty for a message of the
    /// compiler. </summary>
    Rule: string;
    Text: string;
  end;

  TLintMessages = TArray<TLintMessage>;

  /// <summary> What is ignored and what fails, by kind or by message number. Errors always
  /// fail. </summary>
  TLintConfig = record
    IgnoreKinds: TLintKinds;
    IgnoreIds: TArray<Integer>;
    IgnoreRules: TArray<string>;
    FailKinds: TLintKinds;
    FailIds: TArray<Integer>;
    FailRules: TArray<string>;
    /// <summary> Limits of the rules PL004, PL005 and PL006. </summary>
    MaxRoutineLines: Integer;
    MaxParameters: Integer;
    MaxNesting: Integer;
  end;

  /// <summary> Returns the id of a message as the output shows it: the number of a message of
  /// the compiler, like 5093, or the id of a rule, like PL001; empty when there is none.
  /// </summary>
  /// <param name="AMessage"> Message of the compiler or of a rule. </param>
  function LintMessageId(const AMessage: TLintMessage): string;

  /// <summary> Returns the name of a kind, like warning. </summary>
  /// <param name="AKind"> Message kind. </param>
  function LintKindName(const AKind: TLintKind): string;

  /// <summary> Parses the output of lazbuild and returns the messages of the compiler with a
  /// file and a position, like file(line,col) Warning: (5093) text. A relative file name is
  /// resolved from the last Working Directory that lazbuild wrote, the one of the project or
  /// of a package it compiles, or from ABaseDir before the first one. Messages of the linker, the assembler and the resources, numbered
  /// from 9000 to 9999, are not about the code and are left out. </summary>
  /// <param name="AOutput"> Output of lazbuild. </param>
  /// <param name="ABaseDir"> Folder of the project, for relative file names. </param>
  function ParseCompilerMessages(const AOutput, ABaseDir: string): TLintMessages;

  /// <summary> Returns the messages for the sources of a member: files in its folder, not in
  /// its lib, backup or modules folders. Each message is returned once, also when two projects
  /// of the member compile the same unit. Errors are always kept, wherever they are, because
  /// they stop the build. </summary>
  /// <param name="AMessages"> Messages of the compiler. </param>
  /// <param name="AMemberDir"> Member folder. </param>
  function FilterMemberMessages(const AMessages: TLintMessages; const AMemberDir: string): TLintMessages;

  /// <summary> Parses the output of lazbuild and returns the source files the compiler
  /// compiled, from its lines (3104) Compiling file, without the resources. A relative file
  /// name is resolved like in ParseCompilerMessages. </summary>
  /// <param name="AOutput"> Output of lazbuild. </param>
  /// <param name="ABaseDir"> Folder of the project, for relative file names. </param>
  function ParseCompiledFiles(const AOutput, ABaseDir: string): TArray<string>;

  /// <summary> Returns the files that are sources of a member, the ones FilterMemberMessages
  /// keeps, each one once. </summary>
  /// <param name="AFiles"> Complete file names. </param>
  /// <param name="AMemberDir"> Member folder. </param>
  function FilterMemberFiles(const AFiles: TArray<string>; const AMemberDir: string): TArray<string>;

  /// <summary> Returns the default configuration: warnings fail, notes and hints are shown.
  /// </summary>
  function DefaultLintConfig: TLintConfig;

  /// <summary> Reads the lint configuration of a member from the pasc.json of the workspace:
  ///
  /// "lint": { "ignore": [5024, "PL001"], "fail": ["warning", 5091],
  ///           "rules": { "PL004": { "max": 60 } },
  ///           "members": { "web": { "ignore": [5024] } } }
  ///
  /// ignore and fail take kinds (error, warning, note, hint), message numbers and ids of rules.
  /// rules has the limits of the rules that have one. A member, by name or by folder relative
  /// to the root, adds its ignore to the one of the workspace and, when it has fail, replaces
  /// it; its rules replace the limits it has. Without pasc.json or lint, the default is
  /// returned. Raises an exception for a value that is not a kind, a number or a rule.
  /// </summary>
  /// <param name="AWorkspaceDir"> Workspace root folder, or empty outside a workspace. </param>
  /// <param name="AMemberName"> Member name. </param>
  /// <param name="AMemberPath"> Member folder relative to the root, like apps/web. </param>
  function LoadLintConfig(const AWorkspaceDir, AMemberName, AMemberPath: string): TLintConfig;

  /// <summary> Returns true if the configuration ignores the message. </summary>
  /// <param name="AConfig"> Lint configuration. </param>
  /// <param name="AMessage"> Message of the compiler. </param>
  function IsIgnored(const AConfig: TLintConfig; const AMessage: TLintMessage): Boolean;

  /// <summary> Returns true if the message makes pasc lint fail: an error, a kind in fail or
  /// a number in fail. </summary>
  /// <param name="AConfig"> Lint configuration. </param>
  /// <param name="AMessage"> Message of the compiler. </param>
  function IsFailing(const AConfig: TLintConfig; const AMessage: TLintMessage): Boolean;

implementation

uses
  Classes,
  SysUtils,
  StrUtils,
  fpjson,
  jsonparser,
  Utils.IO;

const
  KIND_NAMES: array[TLintKind] of string = ('error', 'warning', 'note', 'hint');
  // as the compiler writes them; a Fatal, like Can't find unit, stops the build as an error
  LABELS: array[0..4] of string = ('Fatal', 'Error', 'Warning', 'Note', 'Hint');
  LABEL_KINDS: array[0..4] of TLintKind = (lkError, lkError, lkWarning, lkNote, lkHint);
  // the messages of the linker, the assembler and the resources
  FIRST_TOOLCHAIN_ID = 9000;
  LAST_TOOLCHAIN_ID = 9999;
  // folders of a member that are not its sources. A typed constant, because FPC 3.2.2 cuts
  // each string of a for-in over a literal to the length of the first one
  SKIPPED_FOLDERS: array[0..2] of string = ('lib', 'backup', 'modules');

function LintKindName(const AKind: TLintKind): string;
begin
  Result := KIND_NAMES[AKind];
end;

function LintMessageId(const AMessage: TLintMessage): string;
begin
  Result := AMessage.Rule;
  if (Result = '') and (AMessage.Id > 0) then
    Result := IntToStr(AMessage.Id);
end;

function IsRuleId(const AValue: string): Boolean;
var
  LChar: Char;
begin
  // PL and three digits, like PL001
  Result := (Length(AValue) = 5) and SameText(Copy(AValue, 1, 2), 'PL');
  if Result then
    for LChar in Copy(AValue, 3, 3) do
      if not (LChar in ['0'..'9']) then
        Exit(False);
end;

function ResolveFile(const AFileName, ABaseDir: string): string;
begin
  Result := SetDirSeparators(Trim(AFileName));
  if not (StartsStr(PathDelim, Result) {$IF DEFINED(WINDOWS)} or (ExtractFileDrive(Result) <> ''){$ENDIF}) then
    Result := ConcatPaths([ABaseDir, Result]);
  // ExpandFileName also removes the ./ of the units found from the project folder
  Result := ExpandFileName(Result);
end;

function ParseLine(const ALine, ABaseDir: string; out AMessage: TLintMessage): Boolean;
var
  I, LPos, LOpen, LComma, LEnd: Integer;
  LText: string;
begin
  Result := False;
  AMessage := Default(TLintMessage);
  for I := Low(LABELS) to High(LABELS) do
  begin
    LPos := Pos(') ' + LABELS[I] + ': ', ALine);
    if LPos = 0 then
      Continue;
    // file(line,col): the position is the last parentheses before the kind
    LOpen := RPos('(', Copy(ALine, 1, LPos));
    if LOpen <= 1 then
      Exit;
    LComma := PosEx(',', ALine, LOpen);
    if (LComma = 0) or (LComma > LPos) then
      Exit;
    AMessage.Line := StrToIntDef(Copy(ALine, LOpen + 1, LComma - LOpen - 1), -1);
    AMessage.Column := StrToIntDef(Copy(ALine, LComma + 1, LPos - LComma - 1), -1);
    if (AMessage.Line < 0) or (AMessage.Column < 0) then
      Exit;
    AMessage.FileName := ResolveFile(Copy(ALine, 1, LOpen - 1), ABaseDir);
    AMessage.Kind := LABEL_KINDS[I];

    LText := Copy(ALine, LPos + Length(LABELS[I]) + 4, MaxInt);
    if StartsStr('(', LText) then
    begin
      LEnd := Pos(') ', LText);
      if LEnd > 0 then
      begin
        AMessage.Id := StrToIntDef(Copy(LText, 2, LEnd - 2), 0);
        if AMessage.Id > 0 then
          Delete(LText, 1, LEnd + 1);
      end;
    end;
    AMessage.Text := Trim(LText);
    Exit(True);
  end;
end;

/// <summary> Updates the folder the compiler runs in, from the line lazbuild writes before each
/// compilation, of the project or of a package: Info: (lazarus) Working Directory="folder".
/// The relative file names of the compiler are relative to it. </summary>
procedure UpdateWorkingDir(const ALine: string; var ABaseDir: string);
const
  WORKING_DIR = 'Working Directory="';
var
  LStart, LEnd: Integer;
begin
  LStart := Pos(WORKING_DIR, ALine);
  if LStart = 0 then
    Exit;
  Inc(LStart, Length(WORKING_DIR));
  LEnd := PosEx('"', ALine, LStart);
  if LEnd > LStart then
    ABaseDir := ExcludeTrailingPathDelimiter(SetDirSeparators(Copy(ALine, LStart, LEnd - LStart)));
end;

function ParseCompilerMessages(const AOutput, ABaseDir: string): TLintMessages;
var
  LLines: TStringList;
  LLine, LBaseDir: string;
  LMessage: TLintMessage;
begin
  Result := [];
  LBaseDir := ABaseDir;
  LLines := TStringList.Create;
  try
    LLines.Text := AOutput;
    for LLine in LLines do
    begin
      UpdateWorkingDir(LLine, LBaseDir);
      if ParseLine(LLine, LBaseDir, LMessage) and
         not ((LMessage.Id >= FIRST_TOOLCHAIN_ID) and (LMessage.Id <= LAST_TOOLCHAIN_ID)) then
        Result := Result + [LMessage];
    end;
  finally
    LLines.Free;
  end;
end;

function ParseCompiledFiles(const AOutput, ABaseDir: string): TArray<string>;
const
  COMPILING = 'Compiling ';
var
  LLines: TStringList;
  LLine, LText, LBaseDir: string;
begin
  Result := [];
  LBaseDir := ABaseDir;
  LLines := TStringList.Create;
  try
    LLines.Text := AOutput;
    for LLine in LLines do
    begin
      UpdateWorkingDir(LLine, LBaseDir);
      LText := Trim(LLine);
      // (3104) Compiling file, with the message numbers of -vq
      if StartsStr('(3104) ', LText) then
        Delete(LText, 1, Length('(3104) '));
      if not StartsStr(COMPILING, LText) or StartsStr(COMPILING + 'resource', LText) then
        Continue;
      Result := Result + [ResolveFile(Copy(LText, Length(COMPILING) + 1, MaxInt), LBaseDir)];
    end;
  finally
    LLines.Free;
  end;
end;

function IsInside(const AFileName, AFolder: string): Boolean;
begin
  Result := StartsStr(IncludeTrailingPathDelimiter(ExpandFileName(AFolder)), ExpandFileName(AFileName));
end;

function IsMemberSource(const AFileName, AMemberDir: string): Boolean;
var
  LFolder: string;
begin
  Result := IsInside(AFileName, AMemberDir);
  if Result then
    for LFolder in SKIPPED_FOLDERS do
      if IsInside(AFileName, ConcatPaths([AMemberDir, LFolder])) then
        Exit(False);
end;

function FilterMemberFiles(const AFiles: TArray<string>; const AMemberDir: string): TArray<string>;
var
  LFile, LKept: string;
  LKeep: Boolean;
begin
  Result := [];
  for LFile in AFiles do
  begin
    LKeep := IsMemberSource(LFile, AMemberDir);
    for LKept in Result do
      if LKeep and SameFileName(LKept, LFile) then
        LKeep := False;
    if LKeep then
      Result := Result + [LFile];
  end;
end;

function SameMessage(const A, B: TLintMessage): Boolean;
begin
  Result := SameFileName(A.FileName, B.FileName) and (A.Line = B.Line) and (A.Column = B.Column) and
    (A.Kind = B.Kind) and (A.Id = B.Id) and (A.Rule = B.Rule) and (A.Text = B.Text);
end;

function FilterMemberMessages(const AMessages: TLintMessages; const AMemberDir: string): TLintMessages;
var
  LMessage, LKept: TLintMessage;
  LKeep: Boolean;
begin
  Result := [];
  for LMessage in AMessages do
  begin
    LKeep := (LMessage.Kind = lkError) or IsMemberSource(LMessage.FileName, AMemberDir);
    if not LKeep then
      Continue;
    for LKept in Result do
      if SameMessage(LKept, LMessage) then
      begin
        LKeep := False;
        Break;
      end;
    if LKeep then
      Result := Result + [LMessage];
  end;
end;

function DefaultLintConfig: TLintConfig;
begin
  Result := Default(TLintConfig);
  Result.FailKinds := [lkWarning];
  Result.MaxRoutineLines := DEFAULT_MAX_ROUTINE_LINES;
  Result.MaxParameters := DEFAULT_MAX_PARAMETERS;
  Result.MaxNesting := DEFAULT_MAX_NESTING;
end;

procedure ReadList(AData: TJSONData; const AName: string; out AKinds: TLintKinds; out AIds: TArray<Integer>;
  out ARules: TArray<string>);
var
  LArray: TJSONArray;
  LKind: TLintKind;
  LFound: Boolean;
  I: Integer;
begin
  AKinds := [];
  AIds := [];
  ARules := [];
  if not (AData is TJSONArray) then
    raise Exception.Create('lint ' + AName + ' in pasc.json should be a list of kinds, message numbers and rules');
  LArray := TJSONArray(AData);
  for I := 0 to LArray.Count - 1 do
    case LArray.Items[I].JSONType of
      jtNumber:
        AIds := AIds + [LArray.Items[I].AsInteger];
      jtString:
        begin
          LFound := IsRuleId(LArray.Items[I].AsString);
          if LFound then
            ARules := ARules + [UpperCase(LArray.Items[I].AsString)];
          for LKind := Low(TLintKind) to High(TLintKind) do
            if SameText(LArray.Items[I].AsString, KIND_NAMES[LKind]) then
            begin
              Include(AKinds, LKind);
              LFound := True;
            end;
          if not LFound then
            raise Exception.CreateFmt('lint %s in pasc.json has "%s", which is not error, warning, note, hint, ' +
              'a message number or a rule like PL001', [AName, LArray.Items[I].AsString]);
        end;
    else
      raise Exception.CreateFmt('lint %s in pasc.json has %s, which is not a kind, a message number or a rule',
        [AName, LArray.Items[I].AsJSON]);
    end;
end;

procedure ReadLimit(ARules: TJSONObject; const ARule: string; var ALimit: Integer);
var
  LRule: TJSONData;
begin
  LRule := ARules.Find(ARule);
  if not Assigned(LRule) then
    Exit;
  if not (LRule is TJSONObject) or not (TJSONObject(LRule).Find('max') is TJSONNumber) or
     (TJSONObject(LRule).Find('max').AsInteger < 1) then
    raise Exception.CreateFmt('lint rules %s in pasc.json should be like { "max": %d }', [ARule, ALimit]);
  ALimit := TJSONObject(LRule).Find('max').AsInteger;
end;

procedure ApplySection(ASection: TJSONObject; var AConfig: TLintConfig);
var
  LKinds: TLintKinds;
  LIds: TArray<Integer>;
  LRules: TArray<string>;
  LLimits: TJSONObject;
  I: Integer;
begin
  if Assigned(ASection.Find('ignore')) then
  begin
    ReadList(ASection.Find('ignore'), 'ignore', LKinds, LIds, LRules);
    AConfig.IgnoreKinds := AConfig.IgnoreKinds + LKinds;
    AConfig.IgnoreIds := AConfig.IgnoreIds + LIds;
    AConfig.IgnoreRules := AConfig.IgnoreRules + LRules;
  end;
  if Assigned(ASection.Find('fail')) then
  begin
    ReadList(ASection.Find('fail'), 'fail', LKinds, LIds, LRules);
    AConfig.FailKinds := LKinds;
    AConfig.FailIds := LIds;
    AConfig.FailRules := LRules;
  end;
  if ASection.Find('rules') is TJSONObject then
  begin
    LLimits := TJSONObject(ASection.Find('rules'));
    for I := 0 to LLimits.Count - 1 do
      if not AnsiMatchText(LLimits.Names[I], ['PL004', 'PL005', 'PL006']) then
        raise Exception.CreateFmt('lint rules in pasc.json has %s, which has no limit; the rules with one are ' +
          'PL004, PL005 and PL006', [LLimits.Names[I]]);
    ReadLimit(LLimits, 'PL004', AConfig.MaxRoutineLines);
    ReadLimit(LLimits, 'PL005', AConfig.MaxParameters);
    ReadLimit(LLimits, 'PL006', AConfig.MaxNesting);
  end;
end;

function LoadLintConfig(const AWorkspaceDir, AMemberName, AMemberPath: string): TLintConfig;
var
  LFileName, LKey: string;
  LJson: TJSONData;
  LLint, LMembers: TJSONObject;
  I: Integer;
begin
  Result := DefaultLintConfig;
  if AWorkspaceDir = '' then
    Exit;
  LFileName := ConcatPaths([AWorkspaceDir, 'pasc.json']);
  if not FileExists(LFileName) then
    Exit;

  LJson := GetJSON(GetJsonFileContentWithOutComments(LFileName));
  try
    if not (LJson is TJSONObject) or not (TJSONObject(LJson).Find('lint') is TJSONObject) then
      Exit;
    LLint := TJSONObject(TJSONObject(LJson).Find('lint'));
    ApplySection(LLint, Result);

    if not (LLint.Find('members') is TJSONObject) then
      Exit;
    LMembers := TJSONObject(LLint.Find('members'));
    for I := 0 to LMembers.Count - 1 do
    begin
      LKey := StringReplace(LMembers.Names[I], '\', '/', [rfReplaceAll]);
      if (SameText(LKey, AMemberName) or SameText(ExcludeTrailingPathDelimiter(LKey), AMemberPath)) and
         (LMembers.Items[I] is TJSONObject) then
        ApplySection(TJSONObject(LMembers.Items[I]), Result);
    end;
  finally
    LJson.Free;
  end;
end;

function HasId(const AIds: TArray<Integer>; const AId: Integer): Boolean;
var
  LId: Integer;
begin
  Result := False;
  for LId in AIds do
    if LId = AId then
      Exit(True);
end;

function HasRule(const ARules: TArray<string>; const ARule: string): Boolean;
var
  LRule: string;
begin
  Result := False;
  if ARule <> '' then
    for LRule in ARules do
      if SameText(LRule, ARule) then
        Exit(True);
end;

function IsIgnored(const AConfig: TLintConfig; const AMessage: TLintMessage): Boolean;
begin
  // an error stops the build, it can not be ignored
  Result := (AMessage.Kind <> lkError) and
    ((AMessage.Kind in AConfig.IgnoreKinds) or ((AMessage.Id > 0) and HasId(AConfig.IgnoreIds, AMessage.Id)) or
     HasRule(AConfig.IgnoreRules, AMessage.Rule));
end;

function IsFailing(const AConfig: TLintConfig; const AMessage: TLintMessage): Boolean;
begin
  Result := (AMessage.Kind = lkError) or (AMessage.Kind in AConfig.FailKinds) or
    ((AMessage.Id > 0) and HasId(AConfig.FailIds, AMessage.Id)) or HasRule(AConfig.FailRules, AMessage.Rule);
end;

end.
