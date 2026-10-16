unit TestUtilsLint;

{$MODE DELPHI}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpcunit,
  testregistry;

type

  TTestUtilsLint = class(TTestCase)
  private
    FDir: string;
  protected
    procedure SetUp; override;
  published
    procedure TestParseCompilerMessages;
    procedure TestParseCompilerMessagesRelativeFile;
    procedure TestParseCompilerMessagesSkipsToolchain;
    procedure TestFilterMemberMessages;
    procedure TestDefaultLintConfig;
    procedure TestLoadLintConfig;
    procedure TestLoadLintConfigMember;
    procedure TestLoadLintConfigInvalid;
    procedure TestErrorsAlwaysFail;
  end;

implementation

uses
  StrUtils,
  FileUtil,
  Utils.IO,
  Utils.Lint;

procedure TTestUtilsLint.SetUp;
begin
  FDir := ConcatPaths([GetTempDir, '.TestUtilsLint', TestName]);
  if DirectoryExists(FDir) then
    DeleteDirectory(FDir, False);
  ForceDirectories(FDir);
end;

function Message(const AFileName: string; const AKind: TLintKind; const AId: Integer): TLintMessage;
begin
  Result := Default(TLintMessage);
  Result.FileName := AFileName;
  Result.Line := 1;
  Result.Column := 1;
  Result.Kind := AKind;
  Result.Id := AId;
  Result.Text := 'text';
end;

function Names(const AMessages: TLintMessages): string;
var
  LMessage: TLintMessage;
begin
  Result := '';
  for LMessage in AMessages do
    Result := Result + LMessage.FileName + ' | ';
end;

procedure TTestUtilsLint.TestParseCompilerMessages;
var
  LMessages: TLintMessages;
  LFile: string;
begin
  LFile := ConcatPaths([FDir, 'src', 'Command.Count.pas']);
  LMessages := ParseCompilerMessages(
    'Hint: (lazarus) Missing state file of Command.Count' + LineEnding +
    '(3104) Compiling ./src/commands/Command.Count.pas' + LineEnding +
    // the units found from the project folder have a ./ in the middle
    ConcatPaths([FDir, '.', 'src', 'Command.Count.pas']) + '(38,19) Warning: (5093) function result variable of a managed type does not seem to be initialized' + LineEnding +
    ConcatPaths([FDir, 'src', 'Health.Routes.pas']) + '(21,64) Hint: (5024) Parameter "ANext" not used' + LineEnding +
    ConcatPaths([FDir, 'src', 'Main.pas']) + '(11,3) Fatal: (10022) Can''t find unit Command.Interfaces used by Main' + LineEnding +
    'Error: (lazbuild) Failed compiling of project', FDir);

  AssertEquals('only the messages with a file and a position', 3, Length(LMessages));
  AssertEquals('the ./ is removed', LFile, LMessages[0].FileName);
  AssertEquals(38, LMessages[0].Line);
  AssertEquals(19, LMessages[0].Column);
  AssertTrue(LMessages[0].Kind = lkWarning);
  AssertEquals(5093, LMessages[0].Id);
  AssertEquals('function result variable of a managed type does not seem to be initialized', LMessages[0].Text);
  AssertTrue(LMessages[1].Kind = lkHint);
  AssertEquals('Parameter "ANext" not used', LMessages[1].Text);
  AssertTrue('a fatal is an error', LMessages[2].Kind = lkError);
  AssertEquals(10022, LMessages[2].Id);
end;

procedure TTestUtilsLint.TestParseCompilerMessagesRelativeFile;
var
  LMessages: TLintMessages;
begin
  LMessages := ParseCompilerMessages('src/Main.pas(3,1) Note: (5025) Local variable "I" not used', FDir);

  AssertEquals(1, Length(LMessages));
  AssertEquals('resolved from the project folder', ConcatPaths([FDir, 'src', 'Main.pas']), LMessages[0].FileName);
  AssertTrue(LMessages[0].Kind = lkNote);
end;

procedure TTestUtilsLint.TestParseCompilerMessagesSkipsToolchain;
var
  LMessages: TLintMessages;
begin
  LMessages := ParseCompilerMessages(
    ConcatPaths([FDir, 'app.lpr']) + '(46,1) Warning: (9034) "crtbeginS.o" not found, this will probably cause a linking failure',
    FDir);

  AssertEquals('the messages of the linker are not about the code', 0, Length(LMessages));
end;

procedure TTestUtilsLint.TestFilterMemberMessages;
var
  LMessages: TLintMessages;
  LMember: string;
begin
  LMember := ConcatPaths([FDir, 'apps', 'web']);
  LMessages := FilterMemberMessages([
    Message(ConcatPaths([LMember, 'src', 'Build.pas']), lkHint, 5024),
    Message(ConcatPaths([LMember, 'tests', 'TestBuild.pas']), lkWarning, 5037),
    // the same unit compiled by the app and by its test project
    Message(ConcatPaths([LMember, 'src', 'Build.pas']), lkHint, 5024),
    Message(ConcatPaths([FDir, 'modules', 'horse', 'src', 'Horse.Commons.pas']), lkWarning, 4105),
    Message(ConcatPaths([LMember, 'modules', 'lib', 'Lib.pas']), lkWarning, 4105),
    Message(ConcatPaths([LMember, 'lib', 'x86_64-linux', 'Generated.pas']), lkNote, 6058),
    Message(ConcatPaths([FDir, 'apps', 'webapp', 'src', 'Other.pas']), lkWarning, 5093),
    // an error stops the build wherever it is
    Message(ConcatPaths([FDir, 'modules', 'horse', 'src', 'Horse.pas']), lkError, 10022)], LMember);

  AssertEquals('the sources of the member once, and the error. Check: ' + Names(LMessages), 3, Length(LMessages));
  AssertEquals(ConcatPaths([LMember, 'src', 'Build.pas']), LMessages[0].FileName);
  AssertEquals(ConcatPaths([LMember, 'tests', 'TestBuild.pas']), LMessages[1].FileName);
  AssertTrue(LMessages[2].Kind = lkError);
end;

procedure TTestUtilsLint.TestDefaultLintConfig;
var
  LConfig: TLintConfig;
begin
  LConfig := LoadLintConfig('', 'web', 'apps/web');

  AssertTrue('warnings fail', IsFailing(LConfig, Message('a.pas', lkWarning, 5093)));
  AssertFalse('notes do not fail', IsFailing(LConfig, Message('a.pas', lkNote, 5025)));
  AssertFalse('hints are not ignored', IsIgnored(LConfig, Message('a.pas', lkHint, 5024)));

  AssertTrue('the same without pasc.json', IsFailing(LoadLintConfig(FDir, 'web', 'apps/web'), Message('a.pas', lkWarning, 5093)));
end;

procedure TTestUtilsLint.TestLoadLintConfig;
var
  LConfig: TLintConfig;
begin
  SaveFileContent(ConcatPaths([FDir, 'pasc.json']),
    '{ "members": ["apps/*"], "lint": { "ignore": [5024, "note"], "fail": ["hint", 5091] } }');

  LConfig := LoadLintConfig(FDir, 'web', 'apps/web');

  AssertTrue('a number is ignored', IsIgnored(LConfig, Message('a.pas', lkHint, 5024)));
  AssertTrue('a kind is ignored', IsIgnored(LConfig, Message('a.pas', lkNote, 6058)));
  AssertTrue('fail replaces the default, a kind fails', IsFailing(LConfig, Message('a.pas', lkHint, 5023)));
  AssertTrue('a number fails', IsFailing(LConfig, Message('a.pas', lkNote, 5091)));
  AssertFalse('warnings are no longer in fail', IsFailing(LConfig, Message('a.pas', lkWarning, 5093)));
end;

procedure TTestUtilsLint.TestLoadLintConfigMember;
var
  LConfig: TLintConfig;
begin
  SaveFileContent(ConcatPaths([FDir, 'pasc.json']),
    '{ "lint": { "ignore": [5023], "members": {' +
    '"web": { "ignore": [5024] }, "apps/cmd": { "fail": ["note"] } } } }');

  LConfig := LoadLintConfig(FDir, 'web', 'apps/web');
  AssertTrue('the ignore of the workspace', IsIgnored(LConfig, Message('a.pas', lkHint, 5023)));
  AssertTrue('and the one of the member, by name', IsIgnored(LConfig, Message('a.pas', lkHint, 5024)));
  AssertTrue('the fail of the workspace', IsFailing(LConfig, Message('a.pas', lkWarning, 5093)));

  LConfig := LoadLintConfig(FDir, 'cmd', 'apps/cmd');
  AssertFalse('the other member does not ignore it', IsIgnored(LConfig, Message('a.pas', lkHint, 5024)));
  AssertTrue('the fail of the member, by folder', IsFailing(LConfig, Message('a.pas', lkNote, 5025)));
  AssertFalse('replaces the one of the workspace', IsFailing(LConfig, Message('a.pas', lkWarning, 5093)));
end;

procedure TTestUtilsLint.TestLoadLintConfigInvalid;
begin
  SaveFileContent(ConcatPaths([FDir, 'pasc.json']), '{ "lint": { "fail": ["wrning"] } }');
  try
    LoadLintConfig(FDir, 'web', 'apps/web');
    Fail('should raise an exception for a kind that does not exist');
  except
    on E: Exception do
      AssertTrue(E.Message, ContainsText(E.Message, '"wrning", which is not error, warning, note, hint'));
  end;
end;

procedure TTestUtilsLint.TestErrorsAlwaysFail;
var
  LConfig: TLintConfig;
begin
  SaveFileContent(ConcatPaths([FDir, 'pasc.json']), '{ "lint": { "ignore": ["error", 10022], "fail": [] } }');

  LConfig := LoadLintConfig(FDir, 'web', 'apps/web');

  AssertFalse('an error can not be ignored', IsIgnored(LConfig, Message('a.pas', lkError, 10022)));
  AssertTrue('an error always fails', IsFailing(LConfig, Message('a.pas', lkError, 10022)));
  AssertFalse('nothing else fails', IsFailing(LConfig, Message('a.pas', lkWarning, 5093)));
end;

initialization
  RegisterTest(TTestUtilsLint);

end.
