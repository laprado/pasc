/// <summary> Unit which has the own rules of pasc lint, the ones the compiler does not have. The
/// sources are parsed with fcl-passrc, the parser that comes with FPC, also used by fpdoc and
/// pas2js, and the rules walk the tree of each routine. The resolver of fcl-passrc is not used
/// yet, so the rules only need the syntax.
///
/// Each rule has an id, like PL001, and its findings are messages like the ones of the
/// compiler, so they go through the same ignore and fail of pasc.json and the same output.
/// The tree has the line of each element but not its column, so a finding is at column 1.
/// </summary>
unit Utils.LintRules;

{$MODE DELPHI}{$H+}

interface

uses
  Utils.Lint;

const
  /// <summary> A source that fcl-passrc could not parse. </summary>
  RULE_PARSE = 'PL000';
  /// <summary> A with statement, which hides where each identifier comes from. </summary>
  RULE_WITH = 'PL001';
  /// <summary> An except block, or an on handler, without statements, which hides the error.
  /// </summary>
  RULE_EMPTY_EXCEPT = 'PL002';
  /// <summary> A destructor that does not call inherited, which leaks what the parent frees.
  /// </summary>
  RULE_DESTRUCTOR_INHERITED = 'PL003';
  /// <summary> A routine with more lines than the limit. </summary>
  RULE_LONG_ROUTINE = 'PL004';
  /// <summary> A routine with more parameters than the limit. </summary>
  RULE_PARAMETERS = 'PL005';
  /// <summary> Statements nested deeper than the limit. </summary>
  RULE_NESTING = 'PL006';

  /// <summary> Parses a source file with fcl-passrc and returns the findings of the rules. A
  /// source that can not be parsed gives a single PL000 note with the reason. The resources of
  /// {$R} are ignored, and the includes are searched in the folder of the file. </summary>
  /// <param name="AFileName"> Complete file name of a unit, program or library. </param>
  /// <param name="AConfig"> Lint configuration, for the limits of the rules. </param>
  function CheckRules(const AFileName: string; const AConfig: TLintConfig): TLintMessages;

  /// <summary> Returns true if the line of the message, or the line above it, has a comment
  /// pasc-lint: ignore with the id of the message, like // pasc-lint: ignore PL001, 5024.
  /// </summary>
  /// <param name="AMessage"> Message of the compiler or of a rule. </param>
  /// <param name="ALines"> Lines of the file of the message. </param>
  function IsSuppressed(const AMessage: TLintMessage; const ALines: TArray<string>): Boolean;

implementation

uses
  Classes,
  SysUtils,
  StrUtils,
  PasTree,
  PScanner,
  PParser;

type
  /// <summary> Creates the elements of the tree for the parser, without a resolver. </summary>
  TLintEngine = class(TPasTreeContainer)
  public
    function CreateElement(AClass: TPTreeElement; const AName: String; AParent: TPasElement;
      AVisibility: TPasMemberVisibility; const ASourceFilename: String;
      ASourceLinenumber: Integer): TPasElement; override;
    function FindElement(const AName: String): TPasElement; override;
  end;

  /// <summary> The scanner of fcl-passrc raises an error for {$R *.lfm}, which a unit with a
  /// form has; the resources are not needed by the rules. </summary>
  TLintScanner = class(TPascalScanner)
  protected
    procedure HandleResource(Param: string); override;
  end;

  /// <summary> What the rules need while they walk the tree of a file. </summary>
  TRuleContext = record
    FileName: string;
    Source: TStringList;
    Config: TLintConfig;
    Messages: TLintMessages;
  end;

function TLintEngine.CreateElement(AClass: TPTreeElement; const AName: String; AParent: TPasElement;
  AVisibility: TPasMemberVisibility; const ASourceFilename: String; ASourceLinenumber: Integer): TPasElement;
begin
  Result := AClass.Create(AName, AParent);
  Result.Visibility := AVisibility;
  Result.SourceFilename := ASourceFilename;
  Result.SourceLinenumber := ASourceLinenumber;
end;

function TLintEngine.FindElement(const AName: String): TPasElement;
begin
  Result := nil;
end;

procedure TLintScanner.HandleResource(Param: string);
begin
end;

procedure AddFinding(var AContext: TRuleContext; const ALine: Integer; const AKind: TLintKind;
  const ARule, AText: string);
var
  LMessage, LKept: TLintMessage;
begin
  LMessage := Default(TLintMessage);
  LMessage.FileName := AContext.FileName;
  LMessage.Line := ALine;
  LMessage.Column := 1;
  LMessage.Kind := AKind;
  LMessage.Rule := ARule;
  LMessage.Text := AText;
  for LKept in AContext.Messages do
    if (LKept.Line = ALine) and (LKept.Rule = ARule) then
      Exit;
  AContext.Messages := AContext.Messages + [LMessage];
end;

/// <summary> True if the lines of the source, without comments and strings, have the word.
/// </summary>
function HasWord(ASource: TStringList; const AFirstLine, ALastLine: Integer; const AWord: string): Boolean;
var
  LText, LToken: string;
  I, LStart, LLength: Integer;
begin
  Result := False;
  LText := '';
  for I := AFirstLine - 1 to ALastLine - 1 do
    if (I >= 0) and (I < ASource.Count) then
      LText := LText + ASource[I] + #10;
  LLength := Length(LText);
  I := 1;
  while I <= LLength do
  begin
    case LText[I] of
      '{':
        while (I <= LLength) and (LText[I] <> '}') do
          Inc(I);
      '(':
        if (I < LLength) and (LText[I + 1] = '*') then
        begin
          Inc(I, 2);
          while (I < LLength) and not ((LText[I] = '*') and (LText[I + 1] = ')')) do
            Inc(I);
          Inc(I);
        end;
      '/':
        if (I < LLength) and (LText[I + 1] = '/') then
          while (I <= LLength) and (LText[I] <> #10) do
            Inc(I);
      '''':
        begin
          Inc(I);
          while (I <= LLength) and (LText[I] <> '''') do
            Inc(I);
        end;
      'A'..'Z', 'a'..'z', '_':
        begin
          LStart := I;
          while (I <= LLength) and (LText[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
            Inc(I);
          LToken := Copy(LText, LStart, I - LStart);
          if SameText(LToken, AWord) then
            Exit(True);
          Continue;
        end;
    end;
    Inc(I);
  end;
end;

/// <summary> No statement, or a begin..end without statements. A single statement, like the
/// TPasImplSimple of a call, is a TPasImplBlock without elements too, so only the begin..end
/// block is checked for its elements. </summary>
function IsEmptyBlock(AElement: TPasElement): Boolean;
begin
  Result := (AElement = nil) or ((AElement is TPasImplBeginBlock) and (TPasImplBeginBlock(AElement).Elements.Count = 0));
end;

/// <summary> The statements that add a level of nesting. A begin..end block does not. </summary>
function IsNesting(AElement: TPasElement): Boolean;
begin
  Result := (AElement is TPasImplIfElse) or (AElement is TPasImplWhileDo) or (AElement is TPasImplForLoop) or
    (AElement is TPasImplRepeatUntil) or (AElement is TPasImplCaseOf) or (AElement is TPasImplTry) or
    (AElement is TPasImplWithDo);
end;

procedure CheckStatement(var AContext: TRuleContext; AElement: TPasElement; const ADepth: Integer;
  var ANestingFound: Boolean);
var
  LDepth, I: Integer;
begin
  if AElement = nil then
    Exit;

  if AElement is TPasImplWithDo then
    AddFinding(AContext, AElement.SourceLinenumber, lkNote, RULE_WITH,
      'with statement, it hides where each identifier comes from');
  if (AElement is TPasImplTryExcept) and (TPasImplTryExcept(AElement).Elements.Count = 0) then
    AddFinding(AContext, AElement.SourceLinenumber, lkWarning, RULE_EMPTY_EXCEPT,
      'empty except block, the exception is silently ignored');
  if (AElement is TPasImplExceptOn) and IsEmptyBlock(TPasImplExceptOn(AElement).Body) then
    AddFinding(AContext, AElement.SourceLinenumber, lkWarning, RULE_EMPTY_EXCEPT,
      'empty exception handler, the exception is silently ignored');

  LDepth := ADepth;
  if IsNesting(AElement) then
  begin
    Inc(LDepth);
    // once per routine, at the first statement deeper than the limit
    if (LDepth > AContext.Config.MaxNesting) and not ANestingFound then
    begin
      ANestingFound := True;
      AddFinding(AContext, AElement.SourceLinenumber, lkHint, RULE_NESTING,
        Format('statements nested %d levels deep, more than %d', [LDepth, AContext.Config.MaxNesting]));
    end;
  end;

  // every child is in Elements, but the except or finally part and the else of a try
  if AElement is TPasImplBlock then
    for I := 0 to TPasImplBlock(AElement).Elements.Count - 1 do
      CheckStatement(AContext, TPasElement(TPasImplBlock(AElement).Elements[I]), LDepth, ANestingFound);
  if AElement is TPasImplTry then
  begin
    CheckStatement(AContext, TPasImplTry(AElement).FinallyExcept, LDepth, ANestingFound);
    CheckStatement(AContext, TPasImplTry(AElement).ElseBranch, LDepth, ANestingFound);
  end;
end;

procedure CheckDeclarations(var AContext: TRuleContext; ADeclarations: TFPList); forward;

procedure CheckProcedure(var AContext: TRuleContext; AProcedure: TPasProcedure);
var
  LLines: Integer;
  LNestingFound: Boolean;
begin
  // only the routines with a body, so a method is checked once, where it is implemented
  if not Assigned(AProcedure.Body) then
    Exit;

  LLines := AProcedure.SourceEndLinenumber - AProcedure.SourceLinenumber + 1;
  if LLines > AContext.Config.MaxRoutineLines then
    AddFinding(AContext, AProcedure.SourceLinenumber, lkHint, RULE_LONG_ROUTINE,
      Format('%s has %d lines, more than %d', [AProcedure.Name, LLines, AContext.Config.MaxRoutineLines]));
  if Assigned(AProcedure.ProcType) and (AProcedure.ProcType.Args.Count > AContext.Config.MaxParameters) then
    AddFinding(AContext, AProcedure.SourceLinenumber, lkHint, RULE_PARAMETERS,
      Format('%s has %d parameters, more than %d', [AProcedure.Name, AProcedure.ProcType.Args.Count,
        AContext.Config.MaxParameters]));
  if (AProcedure is TPasDestructor) and
     not HasWord(AContext.Source, AProcedure.SourceLinenumber, AProcedure.SourceEndLinenumber, 'inherited') then
    AddFinding(AContext, AProcedure.SourceLinenumber, lkWarning, RULE_DESTRUCTOR_INHERITED,
      Format('destructor %s does not call inherited', [AProcedure.Name]));

  LNestingFound := False;
  CheckStatement(AContext, AProcedure.Body.Body, 0, LNestingFound);
  // the routines declared inside this one
  CheckDeclarations(AContext, AProcedure.Body.Declarations);
end;

procedure CheckDeclarations(var AContext: TRuleContext; ADeclarations: TFPList);
var
  I: Integer;
begin
  if not Assigned(ADeclarations) then
    Exit;
  for I := 0 to ADeclarations.Count - 1 do
    if TObject(ADeclarations[I]) is TPasProcedure then
      CheckProcedure(AContext, TPasProcedure(ADeclarations[I]));
end;

procedure CheckSection(var AContext: TRuleContext; ASection: TPasImplBlock);
var
  LNestingFound: Boolean;
begin
  LNestingFound := False;
  CheckStatement(AContext, ASection, 0, LNestingFound);
end;

function ParseModule(AEngine: TLintEngine; const AFileName: string): TPasModule;
var
  LResolver: TFileResolver;
  LScanner: TLintScanner;
  LParser: TPasParser;
  LTarget: string;
begin
  Result := nil;
  LResolver := TFileResolver.Create;
  LScanner := nil;
  LParser := nil;
  try
    LResolver.UseStreams := True;
    LResolver.AddIncludePath(ExtractFilePath(AFileName));
    LScanner := TLintScanner.Create(LResolver);
    // the defines of ParseSource for the platform pasc runs on, so the {$IFDEF} branches are
    // the ones of the lint build
    LScanner.AddDefine('FPK');
    LScanner.AddDefine('FPC');
    LTarget := UpperCase({$I %FPCTARGETOS%});
    LScanner.AddDefine(LTarget);
    if AnsiMatchText(LTarget, ['LINUX', 'FREEBSD', 'NETBSD', 'OPENBSD', 'DARWIN', 'SUNOS', 'BEOS', 'QNX']) then
      LScanner.AddDefine('UNIX');
    if AnsiMatchText(LTarget, ['FREEBSD', 'NETBSD', 'OPENBSD', 'DARWIN']) then
      LScanner.AddDefine('BSD');
    if AnsiMatchText(LTarget, ['WIN32', 'WIN64']) then
      LScanner.AddDefine('WINDOWS');
    LScanner.AddDefine('CPU' + UpperCase({$I %FPCTARGETCPU%}));
    {$IF DEFINED(CPU64)}
    LScanner.AddDefine('CPU64');
    {$ELSE}
    LScanner.AddDefine('CPU32');
    {$ENDIF}
    LParser := TPasParser.Create(LScanner, LResolver, AEngine);
    LScanner.OpenFile(AFileName);
    try
      LParser.ParseMain(Result);
    except
      // the parser creates the module before an error, and does not release it
      if Assigned(Result) then
        Result.Release{$IFDEF CheckPasTreeRefCount}('ParseModule'){$ENDIF};
      raise;
    end;
  finally
    LParser.Free;
    LScanner.Free;
    LResolver.Free;
  end;
end;

function CheckRules(const AFileName: string; const AConfig: TLintConfig): TLintMessages;
var
  LEngine: TLintEngine;
  LModule: TPasModule;
  LContext: TRuleContext;
begin
  // a file that was compiled and then removed has nothing to check
  if not FileExists(AFileName) then
    Exit([]);
  LContext := Default(TRuleContext);
  LContext.FileName := AFileName;
  LContext.Config := AConfig;
  LContext.Source := TStringList.Create;
  LEngine := TLintEngine.Create;
  LModule := nil;
  try
    LContext.Source.LoadFromFile(AFileName);
    try
      LModule := ParseModule(LEngine, AFileName);
    except
      on E: Exception do
      begin
        AddFinding(LContext, 1, lkNote, RULE_PARSE, 'could not be parsed by the rules of pasc lint: ' + E.Message);
        Exit(LContext.Messages);
      end;
    end;

    if LModule is TPasProgram then
      CheckDeclarations(LContext, TPasProgram(LModule).ProgramSection.Declarations)
    else if Assigned(LModule.ImplementationSection) then
      CheckDeclarations(LContext, LModule.ImplementationSection.Declarations);
    CheckSection(LContext, LModule.InitializationSection);
    CheckSection(LContext, LModule.FinalizationSection);
    Result := LContext.Messages;
  finally
    if Assigned(LModule) then
      LModule.Release{$IFDEF CheckPasTreeRefCount}('CheckRules'){$ENDIF};
    LEngine.Free;
    LContext.Source.Free;
  end;
end;

function IsSuppressed(const AMessage: TLintMessage; const ALines: TArray<string>): Boolean;
const
  MARKER = 'pasc-lint: ignore';
var
  LLine, LCodes, LCode: string;
  LIndex, LPos: Integer;
  LParts: TStringArray;
begin
  Result := False;
  for LIndex := AMessage.Line - 2 to AMessage.Line - 1 do
  begin
    if (LIndex < 0) or (LIndex > High(ALines)) then
      Continue;
    LLine := ALines[LIndex];
    LPos := Pos(LowerCase(MARKER), LowerCase(LLine));
    if LPos = 0 then
      Continue;
    LCodes := Copy(LLine, LPos + Length(MARKER), MaxInt);
    // the end of a { } or (* *) comment
    LCodes := StringReplace(StringReplace(LCodes, '}', ' ', [rfReplaceAll]), '*)', ' ', [rfReplaceAll]);
    LParts := LCodes.Split([' ', ',', #9], TStringSplitOptions.ExcludeEmpty);
    for LCode in LParts do
      if ((AMessage.Rule <> '') and SameText(LCode, AMessage.Rule)) or
         ((AMessage.Id > 0) and (LCode = IntToStr(AMessage.Id))) then
        Exit(True);
  end;
end;

end.
