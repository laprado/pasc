unit TestUtilsAdopt;

{$MODE DELPHI}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpcunit,
  testregistry;

type

  TTestUtilsAdopt= class(TTestCase)
  private
    FRoot: string;
    procedure Git(AParams: TArray<string>);
    procedure Commit;
    procedure CreateApp(const AName: string; const AWithSrc: Boolean);
  protected
    procedure SetUp; override;
  published
    procedure TestRebasePath;
    procedure TestRefuseNotGitRepository;
    procedure TestRefuseUncommittedChanges;
    procedure TestRefuseInsideWorkspace;
    procedure TestRefuseBossLibrary;
    procedure TestRefuseNoProject;
    procedure TestAnalyzeApp;
    procedure TestAnalyzePlainApp;
    procedure TestApplyApp;
    procedure TestApplyMultiProject;
    procedure TestAppLeftovers;
  end;

implementation

uses
  StrUtils,
  Utils.Adopt,
  Utils.IO,
  Utils.Shell,
  Utils.Workspace;

const
  APP_LPI =
    '<?xml version="1.0" encoding="UTF-8"?>' + LineEnding +
    '<CONFIG>' + LineEnding +
    '  <ProjectOptions>' + LineEnding +
    '    <Units>' + LineEnding +
    '      <Unit>' + LineEnding +
    '        <Filename Value="%0:s.lpr"/>' + LineEnding +
    '      </Unit>' + LineEnding +
    '      <Unit>' + LineEnding +
    '        <Filename Value="greet.pas"/>' + LineEnding +
    '      </Unit>' + LineEnding +
    '    </Units>' + LineEnding +
    '  </ProjectOptions>' + LineEnding +
    '  <CompilerOptions>' + LineEnding +
    '    <SearchPaths>' + LineEnding +
    '      <OtherUnitFiles Value="src;shared;$(LazarusDir)/x"/>' + LineEnding +
    '    </SearchPaths>' + LineEnding +
    '  </CompilerOptions>' + LineEnding +
    '</CONFIG>' + LineEnding;

  TEST_LPI =
    '<?xml version="1.0" encoding="UTF-8"?>' + LineEnding +
    '<CONFIG>' + LineEnding +
    '  <CompilerOptions>' + LineEnding +
    '    <SearchPaths>' + LineEnding +
    '      <OtherUnitFiles Value="../src;../shared"/>' + LineEnding +
    '    </SearchPaths>' + LineEnding +
    '  </CompilerOptions>' + LineEnding +
    '</CONFIG>' + LineEnding;

  PACKAGE_LPK =
    '<?xml version="1.0" encoding="UTF-8"?>' + LineEnding +
    '<CONFIG>' + LineEnding +
    '  <Package Version="5">' + LineEnding +
    '    <Name Value="%s"/>' + LineEnding +
    '    <Files>' + LineEnding +
    '    </Files>' + LineEnding +
    '    <RequiredPkgs>' + LineEnding +
    '%s' +
    '    </RequiredPkgs>' + LineEnding +
    '  </Package>' + LineEnding +
    '</CONFIG>' + LineEnding;

procedure RemoveFolder(const ADir: string);
var
  LSearch: TSearchRec;
  LPath: string;
begin
  if FindFirst(ConcatPaths([ADir, AllFilesMask]), faAnyFile or faDirectory, LSearch) = 0 then
    try
      repeat
        if (LSearch.Name = '.') or (LSearch.Name = '..') then
          Continue;
        LPath := ConcatPaths([ADir, LSearch.Name]);
        if (LSearch.Attr and faDirectory) <> 0 then
          RemoveFolder(LPath)
        else
          DeleteFile(LPath);
      until FindNext(LSearch) <> 0;
    finally
      FindClose(LSearch);
    end;
  RemoveDir(ADir);
end;

procedure TTestUtilsAdopt.SetUp;
begin
  // other tests replace the shell function with a mock
  ShellExecute := @ShellCommand;
  FRoot := ConcatPaths([GetTempDir, '.TestUtilsAdopt', TestName]);
  if DirectoryExists(FRoot) then
    RemoveFolder(FRoot);
  ForceDirectories(FRoot);
end;

procedure TTestUtilsAdopt.Git(AParams: TArray<string>);
var
  LExitCode: Integer = 0;
  LOutput: string;
begin
  LOutput := ShellCommand('git', ['-C', FRoot, '-c', 'user.name=test', '-c', 'user.email=test@test'] + AParams, LExitCode);
  if LExitCode <> 0 then
    raise Exception.Create('git failed: ' + LOutput);
end;

procedure TTestUtilsAdopt.Commit;
begin
  Git(['add', '-A']);
  Git(['commit', '-q', '-m', 'test']);
end;

procedure TTestUtilsAdopt.CreateApp(const AName: string; const AWithSrc: Boolean);
begin
  Git(['init', '-q']);
  SaveFileContent(ConcatPaths([FRoot, AName + '.lpi']), Format(APP_LPI, [AName]));
  SaveFileContent(ConcatPaths([FRoot, AName + '.lpr']), 'program ' + AName + ';');
  SaveFileContent(ConcatPaths([FRoot, 'greet.pas']), 'unit greet;');
  SaveFileContent(ConcatPaths([FRoot, 'README.md']), '# ' + AName);
  SaveFileContent(ConcatPaths([FRoot, '.gitignore']), '/' + AName + LineEnding + '/tests/Test' + AName + LineEnding);
  SaveFileContent(ConcatPaths([FRoot, 'boss.json']), '{ "mainsrc": "./src", "dependencies": {} }');
  ForceDirectories(ConcatPaths([FRoot, 'shared']));
  SaveFileContent(ConcatPaths([FRoot, 'shared', 'shared.pas']), 'unit shared;');
  if AWithSrc then
  begin
    ForceDirectories(ConcatPaths([FRoot, 'src']));
    SaveFileContent(ConcatPaths([FRoot, 'src', 'core.pas']), 'unit core;');
    ForceDirectories(ConcatPaths([FRoot, 'tests']));
    SaveFileContent(ConcatPaths([FRoot, 'tests', 'Test' + AName + '.lpi']), TEST_LPI);
  end;
  Commit;
end;

procedure TTestUtilsAdopt.TestRebasePath;
var
  LOld, LNew: string;
begin
  LOld := ConcatPaths([FRoot]);
  LNew := ConcatPaths([FRoot, 'apps', 'cli']);
  AssertEquals('inside a moved folder', 'src', RebasePath('src', LOld, LNew, [ConcatPaths([FRoot, 'src'])]));
  AssertEquals('outside, with \', '../../modules/x/src',
    RebasePath('modules\x\src', LOld, LNew, [ConcatPaths([FRoot, 'src'])]));
  AssertEquals('macros are kept', '$(LazarusDir)/x', RebasePath('$(LazarusDir)/x', LOld, LNew, []));
  AssertEquals('absolute paths are kept', PathDelim + 'opt' + PathDelim + 'x',
    RebasePath(PathDelim + 'opt' + PathDelim + 'x', LOld, LNew, []));
end;

procedure TTestUtilsAdopt.TestRefuseNotGitRepository;
var
  LPlan: TAdoptPlan;
begin
  SaveFileContent(ConcatPaths([FRoot, 'cli.lpi']), Format(APP_LPI, ['cli']));
  LPlan := AnalyzeAdoption(FRoot, False);
  AssertTrue('should be refused', LPlan.Kind = akRefused);
  AssertTrue('reason. Check: ' + LPlan.Reason, ContainsText(LPlan.Reason, 'not in a git repository'));
end;

procedure TTestUtilsAdopt.TestRefuseUncommittedChanges;
var
  LPlan: TAdoptPlan;
begin
  CreateApp('cli', True);
  SaveFileContent(ConcatPaths([FRoot, 'new.pas']), 'unit new;');

  LPlan := AnalyzeAdoption(FRoot, False);
  AssertTrue('should be refused', LPlan.Kind = akRefused);
  AssertTrue('reason. Check: ' + LPlan.Reason, ContainsText(LPlan.Reason, 'uncommitted changes'));

  LPlan := AnalyzeAdoption(FRoot, True);
  AssertTrue('--force accepts it. Check: ' + LPlan.Reason, LPlan.Kind = akApp);
end;

procedure TTestUtilsAdopt.TestRefuseInsideWorkspace;
var
  LPlan: TAdoptPlan;
begin
  CreateApp('cli', True);
  SaveFileContent(ConcatPaths([FRoot, WORKSPACE_FILE]), '{ "members": [] }');
  Commit;

  LPlan := AnalyzeAdoption(FRoot, False);
  AssertTrue('should be refused', LPlan.Kind = akRefused);
  AssertTrue('reason. Check: ' + LPlan.Reason, ContainsText(LPlan.Reason, 'Already inside the workspace'));
end;

procedure TTestUtilsAdopt.TestRefuseBossLibrary;
var
  LPlan: TAdoptPlan;
begin
  Git(['init', '-q']);
  ForceDirectories(ConcatPaths([FRoot, 'src']));
  SaveFileContent(ConcatPaths([FRoot, 'src', 'lib.pas']), 'unit lib;');
  SaveFileContent(ConcatPaths([FRoot, 'boss.json']), '{ "mainsrc": "src/" }');
  Commit;

  LPlan := AnalyzeAdoption(FRoot, False);
  AssertTrue('should be refused', LPlan.Kind = akRefused);
  AssertTrue('reason. Check: ' + LPlan.Reason, ContainsText(LPlan.Reason, 'boss library'));
end;

procedure TTestUtilsAdopt.TestRefuseNoProject;
var
  LPlan: TAdoptPlan;
begin
  Git(['init', '-q']);
  SaveFileContent(ConcatPaths([FRoot, 'README.md']), 'nothing');
  Commit;

  LPlan := AnalyzeAdoption(FRoot, False);
  AssertTrue('should be refused', LPlan.Kind = akRefused);
  AssertTrue('reason. Check: ' + LPlan.Reason, ContainsText(LPlan.Reason, 'No pascal project found'));
end;

procedure TTestUtilsAdopt.TestAnalyzeApp;
var
  LPlan: TAdoptPlan;
  LMove: TAdoptMove;
  LMoves: string = '';
begin
  CreateApp('cli', True);
  SaveFileContent(ConcatPaths([FRoot, 'cli.manifest']), '<assembly/>');
  Commit;

  LPlan := AnalyzeAdoption(FRoot, False);

  AssertTrue('kind. Check: ' + LPlan.Reason, LPlan.Kind = akApp);
  AssertEquals('cli', LPlan.Name);
  for LMove in LPlan.Moves do
    LMoves := LMoves + LMove.Source + '>' + LMove.Target + ';';
  AssertTrue('moves. Check: ' + LMoves, ContainsText(LMoves, 'cli.lpi>apps/cli/cli.lpi;'));
  AssertTrue('the files named after the app, the last one too. Check: ' + LMoves,
    ContainsText(LMoves, 'cli.manifest>apps/cli/cli.manifest;'));
  AssertTrue('moves. Check: ' + LMoves, ContainsText(LMoves, 'src>apps/cli/src;'));
  AssertTrue('moves. Check: ' + LMoves, ContainsText(LMoves, 'tests>apps/cli/tests;'));
  AssertTrue('a unit of the project at the root moves too. Check: ' + LMoves, ContainsText(LMoves, 'greet.pas>apps/cli/greet.pas;'));
  AssertFalse('shared is not part of the app. Check: ' + LMoves, ContainsText(LMoves, 'shared'));
  AssertTrue('README stays at the root', AnsiMatchText('README.md', LPlan.LeftAtRoot));
  AssertTrue('shared stays at the root', AnsiMatchText('shared', LPlan.LeftAtRoot));
end;

procedure TTestUtilsAdopt.TestAnalyzePlainApp;
var
  LPlan: TAdoptPlan;
begin
  CreateApp('cli', False);
  LPlan := AnalyzeAdoption(FRoot, False);
  AssertTrue('kind. Check: ' + LPlan.Reason, LPlan.Kind = akPlainApp);
end;

procedure TTestUtilsAdopt.TestApplyApp;
var
  LPlan: TAdoptPlan;
  LApp: string;
  LOutput: string;
  LExitCode: Integer = 0;
begin
  CreateApp('cli', True);
  LPlan := AnalyzeAdoption(FRoot, False);
  ApplyAdoption(LPlan);

  LApp := ConcatPaths([FRoot, 'apps', 'cli']);
  AssertTrue('lpi moved', FileExists(ConcatPaths([LApp, 'cli.lpi'])));
  AssertTrue('src moved', FileExists(ConcatPaths([LApp, 'src', 'core.pas'])));
  AssertFalse('src left the root', DirectoryExists(ConcatPaths([FRoot, 'src'])));
  AssertTrue('pasc.json created', FileExists(ConcatPaths([FRoot, WORKSPACE_FILE])));
  AssertTrue('boss.json stays at the root', FileExists(ConcatPaths([FRoot, 'boss.json'])));
  AssertTrue(
    'app paths rebased. Check: ' + GetFileContent(ConcatPaths([LApp, 'cli.lpi'])),
    ContainsText(GetFileContent(ConcatPaths([LApp, 'cli.lpi'])),
      '<OtherUnitFiles Value="src;../../shared;$(LazarusDir)/x"/>'));
  AssertTrue(
    'test paths rebased. Check: ' + GetFileContent(ConcatPaths([LApp, 'tests', 'Testcli.lpi'])),
    ContainsText(GetFileContent(ConcatPaths([LApp, 'tests', 'Testcli.lpi'])),
      '<OtherUnitFiles Value="../src;../../../shared"/>'));
  AssertTrue(
    '.gitignore updated. Check: ' + GetFileContent(ConcatPaths([FRoot, '.gitignore'])),
    ContainsText(GetFileContent(ConcatPaths([FRoot, '.gitignore'])), '/apps/cli/cli' + LineEnding + '/apps/cli/tests/Testcli'));
  AssertTrue(
    'boss mainsrc follows src. Check: ' + GetFileContent(ConcatPaths([FRoot, 'boss.json'])),
    ContainsText(GetFileContent(ConcatPaths([FRoot, 'boss.json'])), '"mainsrc": "apps/cli/src/"'));

  // git sees the moves as renames, keeping the history
  LOutput := ShellCommand('git', ['-C', FRoot, 'status', '--porcelain'], LExitCode);
  // RM: renamed in the index, then its paths changed in the working tree
  AssertTrue('git rename. Check: ' + LOutput, ContainsText(LOutput, 'RM cli.lpi -> apps/cli/cli.lpi'));
end;

procedure TTestUtilsAdopt.TestApplyMultiProject;
var
  LPlan: TAdoptPlan;
  LUtil: string;
begin
  Git(['init', '-q']);
  ForceDirectories(ConcatPaths([FRoot, 'core']));
  ForceDirectories(ConcatPaths([FRoot, 'util']));
  SaveFileContent(ConcatPaths([FRoot, 'core', 'core.lpk']), Format(PACKAGE_LPK, ['core', '']));
  // util requires core by name only, relying on a global package registration
  LUtil := ConcatPaths([FRoot, 'util', 'util.lpk']);
  SaveFileContent(LUtil, Format(PACKAGE_LPK, ['util',
    '      <Item>' + LineEnding +
    '        <PackageName Value="core"/>' + LineEnding +
    '      </Item>' + LineEnding]));
  Commit;

  LPlan := AnalyzeAdoption(FRoot, False);
  AssertTrue('kind. Check: ' + LPlan.Reason, LPlan.Kind = akMultiProject);
  AssertEquals('members', 2, Length(LPlan.Members));
  AssertEquals('missing reference', 1, Length(LPlan.References));

  ApplyAdoption(LPlan);

  AssertTrue(
    'pasc.json lists the members. Check: ' + GetFileContent(ConcatPaths([FRoot, WORKSPACE_FILE])),
    ContainsText(GetFileContent(ConcatPaths([FRoot, WORKSPACE_FILE])), '"members": ["core", "util"]'));
  AssertTrue(
    'util requires core by relative path. Check: ' + GetFileContent(LUtil),
    ContainsText(GetFileContent(LUtil),
      '        <PackageName Value="core"/>' + LineEnding +
      '        <DefaultFilename Value="../core/core.lpk" Prefer="True"/>'));
  AssertTrue('nothing is moved', FileExists(ConcatPaths([FRoot, 'core', 'core.lpk'])));
end;

procedure TTestUtilsAdopt.TestAppLeftovers;
var
  LPlan: TAdoptPlan;
begin
  CreateApp('cli', True);
  // a previous build at the root: ignored by git, so the working tree is clean
  SaveFileContent(ConcatPaths([FRoot, '.gitignore']),
    GetFileContent(ConcatPaths([FRoot, '.gitignore'])) + 'lib/' + LineEnding + 'backup/' + LineEnding);
  Commit;
  SaveFileContent(ConcatPaths([FRoot, 'cli']), 'executable');
  ForceDirectories(ConcatPaths([FRoot, 'lib', 'x86_64-linux']));
  SaveFileContent(ConcatPaths([FRoot, 'lib', 'x86_64-linux', 'cli.o']), 'object');
  ForceDirectories(ConcatPaths([FRoot, 'backup']));
  SaveFileContent(ConcatPaths([FRoot, 'backup', 'cli.lpr']), 'program cli;');

  LPlan := AnalyzeAdoption(FRoot, False);

  AssertTrue('kind. Check: ' + LPlan.Reason, LPlan.Kind = akApp);
  AssertTrue('the executable is a leftover', AnsiMatchText('cli', LPlan.Leftovers));
  AssertTrue('lib is a leftover', AnsiMatchText('lib', LPlan.Leftovers));
  AssertFalse('backup is not removed', AnsiMatchText('backup', LPlan.Leftovers));
  AssertTrue(
    'backup is reported',
    ContainsText(string.Join(' ', LPlan.Warnings), 'backup has the Lazarus IDE backup copies'));

  ApplyAdoption(LPlan);

  AssertFalse('the executable was removed', FileExists(ConcatPaths([FRoot, 'cli'])));
  AssertFalse('lib was removed', DirectoryExists(ConcatPaths([FRoot, 'lib'])));
  AssertTrue('backup was kept', FileExists(ConcatPaths([FRoot, 'backup', 'cli.lpr'])));
  AssertTrue('the app moved', FileExists(ConcatPaths([FRoot, 'apps', 'cli', 'cli.lpi'])));
end;

initialization
  RegisterTest(TTestUtilsAdopt);

end.
