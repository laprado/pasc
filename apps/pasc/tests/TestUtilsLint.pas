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
    procedure TestParseCompiledFiles;
    procedure TestParsePackageWorkingDirectory;
    procedure TestDefaultLintConfig;
    procedure TestLoadLintConfig;
    procedure TestLoadLintConfigMember;
    procedure TestLoadLintConfigInvalid;
    procedure TestErrorsAlwaysFail;
    procedure TestLoadLintConfigRules;
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

procedure TTestUtilsLint.TestParseCompiledFiles;
var
  LFiles: TArray<string>;
begin
  LFiles := FilterMemberFiles(ParseCompiledFiles(
    '(3104) Compiling app.lpr' + LineEnding +
    '(3104) Compiling ./src/Main.pas' + LineEnding +
    '(3104) Compiling ' + ConcatPaths([FDir, 'modules', 'lib', 'Lib.pas']) + LineEnding +
    '(9022) Compiling resource ' + ConcatPaths([FDir, 'lib', 'app.or']) + LineEnding +
    'Compiling ' + ConcatPaths([FDir, 'src', 'Main.pas']) + LineEnding +
    '(3104) Compiling /usr/lib/fpc/src/rtl/objpas/sysutils.pp', FDir), FDir);

  AssertEquals('the sources of the member, once. Check: ' + string.Join(' | ', LFiles), 2, Length(LFiles));
  AssertEquals(ConcatPaths([FDir, 'app.lpr']), LFiles[0]);
  AssertEquals('the ./ is removed', ConcatPaths([FDir, 'src', 'Main.pas']), LFiles[1]);
end;

procedure TTestUtilsLint.TestParsePackageWorkingDirectory;
var
  LOutput, LPackageDir: string;
  LFiles: TArray<string>;
  LMessages: TLintMessages;
begin
  // lazbuild compiles a package, like the LCL on Windows, in its folder, so its relative file
  // names are not files of the member
  LPackageDir := ConcatPaths([ExtractFileDir(FDir), 'lazarus', 'lcl', 'interfaces']);
  LOutput :=
    'Info: (lazarus) Working Directory="' + IncludeTrailingPathDelimiter(LPackageDir) + '"' + LineEnding +
    '(3104) Compiling lcl.pas' + LineEnding +
    '(3104) Compiling win32/interfaces.pp' + LineEnding +
    'win32/win32int.pp(10,3) Note: (5025) Local variable "I" not used' + LineEnding +
    'Info: (lazarus) Working Directory="' + IncludeTrailingPathDelimiter(FDir) + '"' + LineEnding +
    '(3104) Compiling app.lpr' + LineEnding +
    'src/Main.pas(3,1) Hint: (5024) Parameter "A" not used';

  LFiles := ParseCompiledFiles(LOutput, FDir);
  AssertEquals(3, Length(LFiles));
  AssertEquals('from the folder of the package', ConcatPaths([LPackageDir, 'win32', 'interfaces.pp']), LFiles[1]);
  AssertEquals('from the folder of the project', ConcatPaths([FDir, 'app.lpr']), LFiles[2]);
  LFiles := FilterMemberFiles(LFiles, FDir);
  AssertEquals('only the file of the project is in the member', 1, Length(LFiles));
  AssertEquals(ConcatPaths([FDir, 'app.lpr']), LFiles[0]);

  LMessages := ParseCompilerMessages(LOutput, FDir);
  AssertEquals(2, Length(LMessages));
  AssertEquals(ConcatPaths([LPackageDir, 'win32', 'win32int.pp']), LMessages[0].FileName);
  AssertEquals(ConcatPaths([FDir, 'src', 'Main.pas']), LMessages[1].FileName);
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

procedure TTestUtilsLint.TestLoadLintConfigRules;
var
  LConfig: TLintConfig;
  LRule: TLintMessage;
begin
  AssertEquals('default limit of PL004', DEFAULT_MAX_ROUTINE_LINES, DefaultLintConfig.MaxRoutineLines);

  SaveFileContent(ConcatPaths([FDir, 'pasc.json']),
    '{ "lint": { "ignore": ["PL001"], "fail": ["warning", "pl004"], "rules": { "PL004": { "max": 60 } },' +
    '  "members": { "web": { "rules": { "PL006": { "max": 6 } } } } } }');

  LConfig := LoadLintConfig(FDir, 'web', 'apps/web');

  LRule := Message('a.pas', lkNote, 0);
  LRule.Rule := 'PL001';
  AssertTrue('a rule is ignored by its id', IsIgnored(LConfig, LRule));
  LRule := Message('a.pas', lkHint, 0);
  LRule.Rule := 'PL004';
  AssertTrue('a rule fails by its id, in any case', IsFailing(LConfig, LRule));
  AssertEquals('PL004', LintMessageId(LRule));
  AssertEquals('5093', LintMessageId(Message('a.pas', lkWarning, 5093)));
  AssertEquals('the limit of the workspace', 60, LConfig.MaxRoutineLines);
  AssertEquals('the limit of the member', 6, LConfig.MaxNesting);
  AssertEquals('the default limit', DEFAULT_MAX_PARAMETERS, LConfig.MaxParameters);

  SaveFileContent(ConcatPaths([FDir, 'pasc.json']), '{ "lint": { "rules": { "PL001": { "max": 1 } } } }');
  try
    LoadLintConfig(FDir, 'web', 'apps/web');
    Fail('PL001 has no limit');
  except
    on E: Exception do
      AssertTrue(E.Message, ContainsText(E.Message, 'PL001, which has no limit'));
  end;
end;

initialization
  RegisterTest(TTestUtilsLint);

end.
