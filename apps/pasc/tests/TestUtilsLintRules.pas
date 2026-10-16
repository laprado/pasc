unit TestUtilsLintRules;

{$MODE DELPHI}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpcunit,
  testregistry;

type

  TTestUtilsLintRules = class(TTestCase)
  private
    FDir: string;
    function Check(const ASource: string): string;
  protected
    procedure SetUp; override;
  published
    procedure TestCleanUnit;
    procedure TestWith;
    procedure TestEmptyExcept;
    procedure TestHandlerWithAStatement;
    procedure TestDestructorWithoutInherited;
    procedure TestLongRoutine;
    procedure TestParameters;
    procedure TestNesting;
    procedure TestNestedRoutine;
    procedure TestProgramAndInitialization;
    procedure TestFormResource;
    procedure TestParseError;
    procedure TestLimits;
    procedure TestSuppressed;
  end;

implementation

uses
  StrUtils,
  FileUtil,
  Utils.IO,
  Utils.Lint,
  Utils.LintRules;

procedure TTestUtilsLintRules.SetUp;
begin
  FDir := ConcatPaths([GetTempDir, '.TestUtilsLintRules', TestName]);
  if DirectoryExists(FDir) then
    DeleteDirectory(FDir, False);
  ForceDirectories(FDir);
end;

/// <summary> The findings for a unit, as rule:line, separated by spaces. </summary>
function Findings(const AMessages: TLintMessages): string;
var
  LMessage: TLintMessage;
begin
  Result := '';
  for LMessage in AMessages do
    Result := Result + IfThen(Result <> '', ' ', '') + LMessage.Rule + ':' + IntToStr(LMessage.Line);
end;

function TTestUtilsLintRules.Check(const ASource: string): string;
var
  LFile: string;
begin
  LFile := ConcatPaths([FDir, 'sample.pas']);
  SaveFileContent(LFile, ASource);
  Result := Findings(CheckRules(LFile, DefaultLintConfig));
end;

const
  UNIT_START =
    'unit sample;' + LineEnding +                // 1
    '{$MODE DELPHI}' + LineEnding +              // 2
    'interface' + LineEnding +                   // 3
    'implementation' + LineEnding;               // 4

procedure TTestUtilsLintRules.TestCleanUnit;
begin
  AssertEquals('', Check(UNIT_START +
    'procedure Run(A: Integer);' + LineEnding +
    'begin' + LineEnding +
    '  try' + LineEnding +
    '    if A > 0 then Dec(A);' + LineEnding +
    '  finally' + LineEnding +
    '  end;' + LineEnding +
    'end;' + LineEnding +
    'end.'));
end;

procedure TTestUtilsLintRules.TestWith;
var
  LMessages: TLintMessages;
  LFile: string;
begin
  LFile := ConcatPaths([FDir, 'sample.pas']);
  SaveFileContent(LFile, UNIT_START +
    'uses Classes;' + LineEnding +                // 5
    'procedure Run;' + LineEnding +               // 6
    'begin' + LineEnding +                        // 7
    '  with TStringList.Create do' + LineEnding + // 8
    '    Free;' + LineEnding +
    'end;' + LineEnding +
    'end.');

  LMessages := CheckRules(LFile, DefaultLintConfig);

  AssertEquals('PL001:8', Findings(LMessages));
  AssertTrue('a with is a note', LMessages[0].Kind = lkNote);
  AssertEquals('at column 1, the tree has no column', 1, LMessages[0].Column);
  AssertEquals(LFile, LMessages[0].FileName);
end;

procedure TTestUtilsLintRules.TestEmptyExcept;
begin
  AssertEquals('an empty except and an empty handler', 'PL002:8 PL002:13', Check(UNIT_START +
    'uses SysUtils;' + LineEnding +              // 5
    'procedure Run;' + LineEnding +              // 6
    'begin' + LineEnding +                       // 7
    '  try Abort; except' + LineEnding +         // 8
    '  end;' + LineEnding +
    '  try' + LineEnding +                       // 10
    '    Abort;' + LineEnding +
    '  except' + LineEnding +                    // 12
    '    on E: EAbort do ;' + LineEnding +       // 13
    '  end;' + LineEnding +
    'end;' + LineEnding +
    'end.'));
end;

procedure TTestUtilsLintRules.TestHandlerWithAStatement;
begin
  AssertEquals('a handler with a single statement or a block is not empty', '', Check(UNIT_START +
    'uses SysUtils;' + LineEnding +
    'procedure Run;' + LineEnding +
    'begin' + LineEnding +
    '  try' + LineEnding +
    '    Abort;' + LineEnding +
    '  except' + LineEnding +
    '    on E: EAbort do WriteLn(E.Message);' + LineEnding +
    '    on E: Exception do begin WriteLn(E.Message); end;' + LineEnding +
    '  end;' + LineEnding +
    'end;' + LineEnding +
    'end.'));
end;

procedure TTestUtilsLintRules.TestDestructorWithoutInherited;
begin
  AssertEquals('only the destructor without inherited, not one with it in a comment', 'PL003:10', Check(
    'unit sample;' + LineEnding +                // 1
    '{$MODE DELPHI}' + LineEnding +
    'interface' + LineEnding +
    'type' + LineEnding +
    '  TA = class destructor Destroy; override; end;' + LineEnding +  // 5
    '  TB = class destructor Destroy; override; end;' + LineEnding +
    'implementation' + LineEnding +              // 7
    'destructor TA.Destroy; begin inherited Destroy; end;' + LineEnding +
    '' + LineEnding +
    'destructor TB.Destroy;' + LineEnding +      // 10
    'begin' + LineEnding +
    '  // inherited Destroy;' + LineEnding +
    'end;' + LineEnding +
    'end.'));
end;

procedure TTestUtilsLintRules.TestLongRoutine;
var
  LSource: string;
  I: Integer;
begin
  LSource := UNIT_START + 'procedure Run(var A: Integer);' + LineEnding + 'begin' + LineEnding;  // 5, 6
  // the header, the begin, the statements and the end: the limit
  for I := 1 to DEFAULT_MAX_ROUTINE_LINES - 3 do
    LSource := LSource + '  Inc(A);' + LineEnding;
  AssertEquals('one line more than the limit', 'PL004:5', Check(LSource + '  Inc(A);' + LineEnding + 'end;' + LineEnding + 'end.'));
  AssertEquals('at the limit', '', Check(LSource + 'end;' + LineEnding + 'end.'));
end;

procedure TTestUtilsLintRules.TestParameters;
begin
  AssertEquals('PL005:5', Check(UNIT_START +
    'procedure Run(A, B, C, D, E, F, G: Integer);' + LineEnding +  // 5
    'begin end;' + LineEnding +
    'procedure Ok(A, B, C, D, E, F: Integer);' + LineEnding +
    'begin end;' + LineEnding +
    'end.'));
end;

procedure TTestUtilsLintRules.TestNesting;
begin
  AssertEquals('once, at the first statement deeper than 4', 'PL006:11', Check(UNIT_START +
    'procedure Run(A: Integer);' + LineEnding +  // 5
    'begin' + LineEnding +
    '  if A > 0 then' + LineEnding +             // 1
    '    while A > 0 do' + LineEnding +          // 2
    '      for A := 1 to 2 do' + LineEnding +    // 3
    '        repeat' + LineEnding +              // 4
    '          case A of' + LineEnding +         // 5, line 11, more than 4
    '            1: if A > 1 then Dec(A);' + LineEnding +  // 6
    '          end;' + LineEnding +
    '        until A = 0;' + LineEnding +
    'end;' + LineEnding +
    'end.'));
end;

procedure TTestUtilsLintRules.TestNestedRoutine;
begin
  AssertEquals('the routines declared inside a routine', 'PL001:9', Check(UNIT_START +
    'procedure Run;' + LineEnding +              // 5
    '  procedure Inner;' + LineEnding +          // 6
    '  var L: TObject;' + LineEnding +
    '  begin' + LineEnding +
    '    with L do Free;' + LineEnding +         // 9
    '  end;' + LineEnding +
    'begin' + LineEnding +
    '  Inner;' + LineEnding +
    'end;' + LineEnding +
    'end.'));
end;

procedure TTestUtilsLintRules.TestProgramAndInitialization;
begin
  AssertEquals('the routines of a program and its main block', 'PL001:4 PL001:7', Check(
    'program sample;' + LineEnding +             // 1
    'procedure Run;' + LineEnding +
    'var L: TObject;' + LineEnding +
    'begin with L do Free; end;' + LineEnding +  // 4
    'var L: TObject;' + LineEnding +
    'begin' + LineEnding +
    '  with L do Free;' + LineEnding +           // 7
    'end.'));
end;

procedure TTestUtilsLintRules.TestFormResource;
begin
  AssertEquals('{$R *.lfm} of a form does not stop the parser', 'PL001:9', Check(UNIT_START +
    '{$R *.lfm}' + LineEnding +                  // 5
    'procedure Run;' + LineEnding +
    'var L: TObject;' + LineEnding +
    'begin' + LineEnding +
    '  with L do Free;' + LineEnding +           // 9
    'end;' + LineEnding +
    'end.'));
end;

procedure TTestUtilsLintRules.TestParseError;
var
  LMessages: TLintMessages;
  LFile: string;
begin
  LFile := ConcatPaths([FDir, 'sample.pas']);
  SaveFileContent(LFile, UNIT_START + 'procedure Run; begin if then; end;' + LineEnding + 'end.');

  LMessages := CheckRules(LFile, DefaultLintConfig);

  AssertEquals(1, Length(LMessages));
  AssertEquals(RULE_PARSE, LMessages[0].Rule);
  AssertTrue('a note, so it does not fail', LMessages[0].Kind = lkNote);
  AssertTrue(LMessages[0].Text, StartsStr('could not be parsed by the rules of pasc lint: ', LMessages[0].Text));
  AssertEquals('a file that does not exist has nothing to check', 0,
    Length(CheckRules(ConcatPaths([FDir, 'missing.pas']), DefaultLintConfig)));
end;

procedure TTestUtilsLintRules.TestLimits;
var
  LConfig: TLintConfig;
  LFile: string;
begin
  LFile := ConcatPaths([FDir, 'sample.pas']);
  SaveFileContent(LFile, UNIT_START +
    'procedure Run(A, B: Integer);' + LineEnding +  // 5
    'begin' + LineEnding +
    '  if A > B then' + LineEnding +
    '    if B > 0 then Dec(A);' + LineEnding +
    'end;' + LineEnding +
    'end.');
  SaveFileContent(ConcatPaths([FDir, 'pasc.json']),
    '{ "lint": { "rules": { "PL004": { "max": 4 }, "PL005": { "max": 1 }, "PL006": { "max": 1 } } } }');
  LConfig := LoadLintConfig(FDir, 'app', 'app');

  AssertEquals('the limits of pasc.json', 'PL004:5 PL005:5 PL006:8', Findings(CheckRules(LFile, LConfig)));
end;

procedure TTestUtilsLintRules.TestSuppressed;
var
  LMessage: TLintMessage;
  LLines: TArray<string>;
begin
  LLines := [
    'begin',
    '  with L do Free; // pasc-lint: ignore PL001',
    '  { pasc-lint: ignore PL002, 5024 }',
    '  try except end;',
    '  with L do Free;'];
  LMessage := Default(TLintMessage);

  LMessage.Line := 2;
  LMessage.Rule := 'PL001';
  AssertTrue('on the same line', IsSuppressed(LMessage, LLines));
  LMessage.Line := 4;
  LMessage.Rule := 'PL002';
  AssertTrue('on the line above, in a { } comment', IsSuppressed(LMessage, LLines));
  LMessage.Rule := '';
  LMessage.Id := 5024;
  AssertTrue('a message of the compiler, by number', IsSuppressed(LMessage, LLines));
  LMessage.Id := 0;
  LMessage.Rule := 'PL003';
  AssertFalse('another rule', IsSuppressed(LMessage, LLines));
  LMessage.Line := 5;
  LMessage.Rule := 'PL001';
  AssertFalse('two lines below', IsSuppressed(LMessage, LLines));
end;

initialization
  RegisterTest(TTestUtilsLintRules);

end.
