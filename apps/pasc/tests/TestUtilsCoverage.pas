unit TestUtilsCoverage;

{$MODE DELPHI}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpcunit,
  testregistry;

type

  TTestUtilsCoverage = class(TTestCase)
  private
    FDir: string;
    function ProjectFile: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAddCoverageBuildMode;
    procedure TestAddCoverageBuildModeTwice;
    procedure TestAddCoverageBuildModeWithoutBuildModes;
    procedure TestAddCoverageBuildModeOldFormat;
    procedure TestAddCoverageBuildModeKeepsSearchPathsInSync;
    procedure TestGetCoverageExecutable;
    procedure TestReadCoverageReport;
    procedure TestCoveragePercent;
    procedure TestHasCode;
    procedure TestGetUnitsNotInReport;
    procedure TestIgnorePaths;
  end;

implementation

uses
  StrUtils,
  FileUtil,
  Utils.Check,
  Utils.Coverage,
  Utils.IO,
  Utils.Shell,
  Utils.Workspace;

const
  PROJECT_START =
    '<?xml version="1.0" encoding="UTF-8"?>' + LineEnding +
    '<CONFIG>' + LineEnding +
    '  <ProjectOptions>' + LineEnding +
    '    <Version Value="12"/>' + LineEnding +
    '    <PathDelim Value="\"/>' + LineEnding;

  BUILD_MODES =
    '    <BuildModes>' + LineEnding +
    '      <Item Name="Default" Default="True"/>' + LineEnding +
    '    </BuildModes>' + LineEnding;

  PROJECT_END =
    '    <Units>' + LineEnding +
    '      <Unit>' + LineEnding +
    '        <Filename Value="TestSample.lpr"/>' + LineEnding +
    '        <IsPartOfProject Value="True"/>' + LineEnding +
    '      </Unit>' + LineEnding +
    '    </Units>' + LineEnding +
    '  </ProjectOptions>' + LineEnding +
    '  <CompilerOptions>' + LineEnding +
    '    <Version Value="11"/>' + LineEnding +
    '    <PathDelim Value="\"/>' + LineEnding +
    '    <Target>' + LineEnding +
    '      <Filename Value="TestSample"/>' + LineEnding +
    '    </Target>' + LineEnding +
    '    <SearchPaths>' + LineEnding +
    '      <IncludeFiles Value="$(ProjOutDir)"/>' + LineEnding +
    '      <OtherUnitFiles Value="../src;../../../modules/pascli/src"/>' + LineEnding +
    '      <UnitOutputDirectory Value="lib\$(TargetCPU)-$(TargetOS)"/>' + LineEnding +
    '    </SearchPaths>' + LineEnding +
    '    <Linking>' + LineEnding +
    '      <Debugging>' + LineEnding +
    '        <DebugInfoType Value="dsDwarf3"/>' + LineEnding +
    '        <UseHeaptrc Value="True"/>' + LineEnding +
    '      </Debugging>' + LineEnding +
    '    </Linking>' + LineEnding +
    '  </CompilerOptions>' + LineEnding +
    '</CONFIG>' + LineEnding;

procedure TTestUtilsCoverage.SetUp;
begin
  FDir := ConcatPaths([GetTempDir, '.TestUtilsCoverage', TestName]);
  if DirectoryExists(FDir) then
    DeleteDirectory(FDir, False);
  ForceDirectories(ConcatPaths([FDir, 'tests']));
  SaveFileContent(ProjectFile, PROJECT_START + BUILD_MODES + PROJECT_END);
end;

procedure TTestUtilsCoverage.TearDown;
begin
  ShellExecute := @ShellCommand;
end;

function TTestUtilsCoverage.ProjectFile: string;
begin
  Result := ConcatPaths([FDir, 'tests', 'TestSample.lpi']);
end;

procedure TTestUtilsCoverage.TestAddCoverageBuildMode;
var
  LContent, LMode: string;
begin
  AssertFalse('should not have the build mode yet', HasBuildMode(ProjectFile, COVERAGE_BUILD_MODE));

  AssertTrue('should add the build mode', AddCoverageBuildMode(ProjectFile));

  AssertTrue('should have the build mode', HasBuildMode(ProjectFile, COVERAGE_BUILD_MODE));
  LContent := GetFileContent(ProjectFile);
  AssertTrue('the rest of the file should be kept. Check: ' + LContent,
    StartsStr(PROJECT_START + '    <BuildModes>' + LineEnding + '      <Item Name="Default" Default="True"/>' + LineEnding +
    '      <Item Name="Coverage">' + LineEnding + '        <CompilerOptions>' + LineEnding, LContent));
  AssertTrue('the rest of the file should be kept', EndsStr('    </BuildModes>' + LineEnding + PROJECT_END, LContent));

  LMode := Copy(LContent, Pos('<Item Name="Coverage">', LContent), Pos('</BuildModes>', LContent) - Pos('<Item Name="Coverage">', LContent));
  AssertTrue('the executable should stay in the folder of the tests. Check: ' + LMode, ContainsStr(LMode, '<Filename Value="TestSample-coverage"/>'));
  AssertTrue('the units should go to lib/coverage', ContainsStr(LMode, '<UnitOutputDirectory Value="lib\coverage\$(TargetCPU)-$(TargetOS)"/>'));
  AssertTrue('the search paths should be copied', ContainsStr(LMode, '<OtherUnitFiles Value="../src;../../../modules/pascli/src"/>'));
  AssertTrue('should have debug info', ContainsStr(LMode, '<DebugInfoType Value="dsDwarf3"/>'));
  AssertTrue('should not optimize', ContainsStr(LMode, '<OptimizationLevel Value="0"/>'));
  AssertFalse('should not use heaptrc', ContainsStr(LMode, 'UseHeaptrc'));
end;

procedure TTestUtilsCoverage.TestAddCoverageBuildModeTwice;
var
  LContent: string;
begin
  AddCoverageBuildMode(ProjectFile);
  LContent := GetFileContent(ProjectFile);

  AssertFalse('should not add the build mode again', AddCoverageBuildMode(ProjectFile));
  AssertEquals('should not change the file', LContent, GetFileContent(ProjectFile));
end;

procedure TTestUtilsCoverage.TestAddCoverageBuildModeWithoutBuildModes;
var
  LContent: string;
begin
  SaveFileContent(ProjectFile, PROJECT_START + PROJECT_END);

  AssertTrue('should add the build mode', AddCoverageBuildMode(ProjectFile));

  LContent := GetFileContent(ProjectFile);
  AssertTrue('should have the build mode', HasBuildMode(ProjectFile, COVERAGE_BUILD_MODE));
  AssertTrue('should keep the options of the project as the Default build mode. Check: ' + LContent,
    ContainsStr(LContent, '<Item Name="Default" Default="True"/>'));
end;

procedure TTestUtilsCoverage.TestAddCoverageBuildModeOldFormat;
var
  LContent: string;
begin
  SaveFileContent(ProjectFile, PROJECT_START +
    '    <BuildModes Count="1">' + LineEnding +
    '      <Item1 Name="Default" Default="True"/>' + LineEnding +
    '    </BuildModes>' + LineEnding + PROJECT_END);

  AssertTrue('should add the build mode', AddCoverageBuildMode(ProjectFile));

  LContent := GetFileContent(ProjectFile);
  AssertTrue('should number the item. Check: ' + LContent, ContainsStr(LContent, '<Item2 Name="Coverage">'));
  AssertTrue('should update the count', ContainsStr(LContent, '<BuildModes Count="2">'));
  AssertTrue('should have the build mode', HasBuildMode(ProjectFile, COVERAGE_BUILD_MODE));
end;

procedure TTestUtilsCoverage.TestAddCoverageBuildModeKeepsSearchPathsInSync;
var
  LModes: TBuildModesPaths;
begin
  AddCoverageBuildMode(ProjectFile);
  ForceDirectories(ConcatPaths([FDir, 'src', 'features']));

  // pasc deps and pasc build update every OtherUnitFiles, so the Coverage mode gets the new
  // folders too
  AssertTrue('should add the folder', AddSourcePaths(ProjectFile, [ConcatPaths([FDir, 'src', 'features'])]));

  LModes := GetBuildModesPaths(ProjectFile);
  AssertEquals('should have two build modes', 2, Length(LModes));
  AssertEquals(COVERAGE_BUILD_MODE, LModes[1].Name);
  AssertEquals('the Coverage mode should have the same paths', Length(LModes[0].Paths), Length(LModes[1].Paths));
  AssertTrue('the Coverage mode should have the new folder',
    ContainsStr(GetFileContent(ProjectFile), '../src;../../../modules/pascli/src;../src/features"/>' + LineEnding +
    '            <UnitOutputDirectory Value="lib\coverage'));
end;

procedure TTestUtilsCoverage.TestGetCoverageExecutable;
begin
  AssertEquals('should be empty without the build mode', '', GetCoverageExecutable(ProjectFile));

  AddCoverageBuildMode(ProjectFile);

  AssertEquals(ConcatPaths([FDir, 'tests', 'TestSample-coverage']){$IF DEFINED(WINDOWS)} + '.exe'{$ENDIF},
    GetCoverageExecutable(ProjectFile));
end;

procedure TTestUtilsCoverage.TestReadCoverageReport;
var
  LReport: TCoverageReport;
  LFileName: string;
begin
  // kcov writes the numbers of each file as strings, and the totals as numbers
  LFileName := ConcatPaths([FDir, 'coverage.json']);
  SaveFileContent(LFileName,
    '{"files": [' +
    '{"file": "/ws/src/b.pas", "percent_covered": "100.00", "covered_lines": "21", "total_lines": "21"},' +
    '{"file": "/ws/src/a.pas", "percent_covered": "89.66", "covered_lines": "26", "total_lines": "29"}],' +
    '"percent_covered": "94.00", "covered_lines": 47, "total_lines": 50}');

  LReport := ReadCoverageReport(LFileName);

  AssertEquals(47, LReport.Covered);
  AssertEquals(50, LReport.Total);
  AssertEquals(2, Length(LReport.Files));
  AssertEquals('the files should be sorted', '/ws/src/a.pas', LReport.Files[0].FileName);
  AssertEquals(26, LReport.Files[0].Covered);
  AssertEquals(29, LReport.Files[0].Total);
  AssertEquals('/ws/src/b.pas', LReport.Files[1].FileName);
end;

procedure TTestUtilsCoverage.TestCoveragePercent;
begin
  AssertEquals('94.00%', FormatPercent(CoveragePercent(47, 50)));
  AssertEquals('89.66%', FormatPercent(CoveragePercent(26, 29)));
  AssertEquals('should be zero without lines', '0.00%', FormatPercent(CoveragePercent(0, 0)));
end;

procedure TTestUtilsCoverage.TestHasCode;
begin
  AssertTrue('a routine has code', HasCode(
    'unit A; interface function F: Integer; implementation function F: Integer; begin Result := 1; end; end.'));
  AssertTrue('an initialization has code', HasCode(
    'unit A; interface var V: Integer; implementation initialization V := 1; end.'));
  AssertTrue('an include may have the code', HasCode(
    'unit A; interface procedure P; implementation {$I a.inc} end.'));
  AssertFalse('only declarations have no code', HasCode(
    'unit A; interface type TPoint = record X, Y: Integer; end; const C = 1; implementation end.'));
  AssertFalse('a begin in a comment or a string is not code', HasCode(
    'unit A; interface const S = ''begin''; implementation { begin } (* begin *) // begin' + LineEnding +
    '{$IFDEF X} end.'));
end;

procedure TTestUtilsCoverage.TestGetUnitsNotInReport;
var
  LReport: TCoverageReport;
  LSrcDir: string;
  LUnits: TArray<string>;
begin
  LSrcDir := ConcatPaths([FDir, 'src']);
  ForceDirectories(LSrcDir);
  SaveFileContent(ConcatPaths([LSrcDir, 'used.pas']), 'unit Used; interface implementation begin end.');
  SaveFileContent(ConcatPaths([LSrcDir, 'unused.pas']), 'unit Unused; interface procedure P; implementation procedure P; begin end; end.');
  SaveFileContent(ConcatPaths([LSrcDir, 'types.pas']), 'unit Types; interface type TId = Integer; implementation end.');
  SaveFileContent(ConcatPaths([LSrcDir, 'code.inc']), 'begin end;');

  LReport := Default(TCoverageReport);
  SetLength(LReport.Files, 1);
  LReport.Files[0].FileName := ConcatPaths([LSrcDir, 'used.pas']);

  LUnits := GetUnitsNotInReport([LSrcDir], LReport);

  AssertEquals('only the unit with code that is not in the report', 1, Length(LUnits));
  AssertEquals(ConcatPaths([LSrcDir, 'unused.pas']), LUnits[0]);
end;

procedure TTestUtilsCoverage.TestIgnorePaths;
var
  LExitCode: Integer = 0;
  LGitIgnore: string;
  LAdded: TArray<string>;
begin
  ShellExecute := @ShellCommand;
  AssertEquals('should do nothing outside a git repository', 0, Length(IgnorePaths(FDir, ['coverage/'])));

  ShellExecute('git', ['init', '-q', FDir], LExitCode);
  AssertEquals('git init should work', 0, LExitCode);
  LGitIgnore := ConcatPaths([FDir, '.gitignore']);
  SaveFileContent(LGitIgnore, '**/lib/');

  LAdded := IgnorePaths(FDir, ['coverage/', 'tests/lib/coverage/TestSample.xml', 'tests/TestSample-coverage']);

  AssertEquals('should add the paths not ignored yet', 2, Length(LAdded));
  AssertEquals('/coverage/', LAdded[0]);
  AssertEquals('/tests/TestSample-coverage', LAdded[1]);
  AssertEquals('should keep the lines', '**/lib/' + LineEnding + '/coverage/' + LineEnding +
    '/tests/TestSample-coverage' + LineEnding, GetFileContent(LGitIgnore));
  AssertEquals('should do nothing when the paths are already ignored', 0,
    Length(IgnorePaths(FDir, ['coverage/', 'tests/TestSample-coverage'])));
end;

initialization
  RegisterTest(TTestUtilsCoverage);

end.
