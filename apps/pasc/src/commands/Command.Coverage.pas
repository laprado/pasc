/// <summary> This unit contains procedures to configure and execute a command to measure the
/// coverage of the unit tests with kcov.
///
/// FPC emits no .gcno/.gcda files, so gcov and lcov do not work with its executables. kcov
/// reads the DWARF line info of the test executable instead and sets a breakpoint on each line,
/// so it needs no instrumentation, only a build with debug info and no optimization: the
/// Coverage build mode that the command adds to the test project.
/// </summary>
unit Command.Coverage;

{$MODE DELPHI}{$H+}

interface

uses
  Command.Interfaces;

  /// <summary> This command builds the test project in the current folder, or in its tests
  /// subfolder, with the Coverage build mode, runs it under kcov and outputs the coverage of
  /// each source file of the project, without the tests and the modules. At the root of a
  /// workspace it does the same for every member with a tests folder and outputs the total.
  /// The units with code that no test uses are not seen by kcov, so they are listed as
  /// warnings. The exit code is 1 when the tests could not run, any of them failed or the
  /// coverage is below --min. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output the report. </param>
  procedure CoverageCommand(ABuilder: ICommandBuilder);

  /// <summary> Registry a coverage command using the command builder from pascli. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// registry the command. </param>
  procedure Registry(ABuilder: ICommandBuilder);

implementation

uses
  Classes,
  SysUtils,
  StrUtils,
  Process,
  FileUtil,
  Command.Check,
  Command.Test,
  Utils.Coverage,
  Utils.Output,
  Utils.Shell,
  Utils.Tests,
  Utils.Workspace;

const
  // the folders of kcov --merge. A typed constant, because FPC 3.2.2 cuts each string of a
  // for-in over a literal to the length of the first one
  KCOV_MERGED_DIRS: array[0..1] of string = ('kcov-merged', 'merged-kcov-output');

type
  /// <summary> Result of the coverage of a member. </summary>
  TMemberCoverage = record
    /// <summary> True if the tests ran and kcov wrote the report. </summary>
    Ran: Boolean;
    Failed: Integer;
    Report: TCoverageReport;
    /// <summary> Why the coverage was not measured, or empty. </summary>
    Error: string;
  end;

function DisplayPath(const ABaseDir, AFileName: string): string;
begin
  Result := StringReplace(
    ExtractRelativePath(IncludeTrailingPathDelimiter(ABaseDir), AFileName), '\', '/', [rfReplaceAll]);
end;

/// <summary> The member folder relative to the workspace, or the project folder name outside
/// of one, where the member is the root itself. </summary>
function MemberName(const ARootDir, AMemberDir: string): string;
begin
  if SameFileName(ExcludeTrailingPathDelimiter(ARootDir), ExcludeTrailingPathDelimiter(AMemberDir)) then
    Result := ExtractFileName(ExcludeTrailingPathDelimiter(AMemberDir))
  else
    Result := DisplayPath(ARootDir, AMemberDir);
end;

function FormatLines(const ACovered, ATotal: Integer): string;
begin
  Result := IntToStr(ACovered) + '/' + IntToStr(ATotal);
end;

function KcovInstalled(ABuilder: ICommandBuilder): Boolean;
var
  LExitCode: Integer = 0;
begin
  try
    ShellExecute('kcov', ['--version'], LExitCode);
    Result := LExitCode = 0;
  except
    Result := False;
  end;
  if Result then
    Exit;
  OutputError(ABuilder, 'Coverage', 'kcov was not found in the PATH.');
  ABuilder.Output(
    'pasc coverage runs the tests under kcov (https://github.com/SimonKagstrom/kcov). '#13#10 +
    'Install it with the package manager of the system:'#13#10 +
    '  Arch Linux:        sudo pacman -S kcov'#13#10 +
    '  Debian 13:         sudo apt install kcov'#13#10 +
    '  Fedora:            sudo dnf install kcov'#13#10 +
    '  macOS (Homebrew):  brew install kcov'#13#10 +
    'Other systems can build it from the sources, see the kcov repository.');
end;

function GetMinimum(ABuilder: ICommandBuilder; out AMinimum: Double): Boolean;
var
  LValue: string = '';
  LSettings: TFormatSettings;
begin
  AMinimum := -1;
  Result := True;
  if not ABuilder.CheckOption('min', LValue) then
    Exit;
  LSettings := DefaultFormatSettings;
  LSettings.DecimalSeparator := '.';
  LValue := Trim(StringReplace(LValue, '%', '', []));
  if not TryStrToFloat(LValue, AMinimum, LSettings) or (AMinimum < 0) or (AMinimum > 100) then
  begin
    OutputError(ABuilder, 'Coverage', 'Invalid --min value: ' + LValue + '. Use a percentage from 0 to 100, like --min=80.');
    Result := False;
  end;
end;

procedure OpenReport(const AFileName: string);
var
  LProcess: TProcess;
begin
  // the browser outlives pasc, so it is started without pipes and not waited
  LProcess := TProcess.Create(nil);
  try
    LProcess.Executable := {$IF DEFINED(DARWIN)}'open'{$ELSE}'xdg-open'{$ENDIF};
    LProcess.Parameters.Add(AFileName);
    LProcess.Options := [];
    try
      LProcess.Execute;
    except
      // nothing to open it with: the path of the report is already in the output
    end;
  finally
    LProcess.Free;
  end;
end;

procedure OutputIgnored(ABuilder: ICommandBuilder; const ARootDir, AStartDir: string;
  const APaths: TArray<string>);
var
  LAdded: TArray<string>;
begin
  LAdded := IgnorePaths(ARootDir, APaths);
  if Length(LAdded) > 0 then
    OutputInfo(ABuilder, 'Updating', DisplayPath(AStartDir, ConcatPaths([ARootDir, '.gitignore'])) +
      ' with ' + string.Join(', ', LAdded));
end;

/// <summary> Builds the test project of a member with the Coverage build mode, runs it under
/// kcov and outputs the tests report and the coverage of each file. </summary>
function CoverMember(ABuilder: ICommandBuilder; const AMemberDir, ATestProject, ARootDir,
  AStartDir: string): TMemberCoverage;
var
  LSourceDirs, LExcludeDirs, LParams: TArray<string>;
  LExeFile, LXmlFile, LOutDir, LJsonFile, LOutput, LUnit: string;
  LFile: TCoverageFile;
  LReport: TTestReport;
  LExitCode: Integer = 0;
begin
  Result := Default(TMemberCoverage);
  if not SameText(ExtractFileExt(ATestProject), '.lpi') or not FileExists(ATestProject) then
  begin
    Result.Error := 'the test project needs a .lpi file for the Coverage build mode';
    OutputError(ABuilder, 'Coverage', 'The test project needs a .lpi file for the Coverage build mode: ' +
      DisplayPath(AStartDir, ATestProject));
    Exit;
  end;

  try
    if AddCoverageBuildMode(ATestProject) then
      OutputInfo(ABuilder, 'Updating', DisplayPath(AStartDir, ATestProject) + ' with the ' +
        COVERAGE_BUILD_MODE + ' build mode');
  except
    on E: Exception do
    begin
      Result.Error := E.Message;
      OutputError(ABuilder, 'Coverage', E.Message);
      Exit;
    end;
  end;

  if not BuildTestProject(ABuilder, ATestProject, COVERAGE_BUILD_MODE, Result.Error) then
    Exit;
  LExeFile := GetCoverageExecutable(ATestProject);
  if not FileExists(LExeFile) then
  begin
    Result.Error := 'the test executable was not found';
    OutputError(ABuilder, 'Coverage', 'Executable test not found: ' + DisplayPath(AStartDir, LExeFile));
    Exit;
  end;
  // the reports and the executable should not be left untracked in the repository
  OutputIgnored(ABuilder, ARootDir, AStartDir, [COVERAGE_DIR + '/', DisplayPath(ARootDir, LExeFile)]);

  // only the sources of the member are counted, not the tests or the modules
  LSourceDirs := GetMemberSourceDirs(AMemberDir);
  LExcludeDirs := [];
  if Length(LSourceDirs) = 0 then
  begin
    LSourceDirs := [ExcludeTrailingPathDelimiter(AMemberDir)];
    LExcludeDirs := [ConcatPaths([AMemberDir, 'tests']), ConcatPaths([AMemberDir, 'lib']),
      ConcatPaths([AMemberDir, 'modules']), ConcatPaths([AMemberDir, 'backup'])];
  end;

  // kcov adds each run to the results already in its folder, and does not create the parents
  LOutDir := ConcatPaths([ARootDir, COVERAGE_DIR, ExtractFileName(ExcludeTrailingPathDelimiter(AMemberDir))]);
  if DirectoryExists(LOutDir) then
    DeleteDirectory(LOutDir, False);
  ForceDirectories(LOutDir);
  // the results of the tests go with the units, the Default ones stay next to the executable
  LXmlFile := ConcatPaths([ExtractFileDir(ATestProject), 'lib', COVERAGE_DIR, ExtractFileName(LExeFile) + '.xml']);
  ForceDirectories(ExtractFileDir(LXmlFile));
  if FileExists(LXmlFile) then
    DeleteFile(LXmlFile);

  LParams := ['--include-path=' + string.Join(',', LSourceDirs)];
  if Length(LExcludeDirs) > 0 then
    LParams := LParams + ['--exclude-path=' + string.Join(',', LExcludeDirs)];
  LParams := LParams + [LOutDir, LExeFile, '-a', '--file=' + LXmlFile];
  try
    LOutput := ShellExecute('kcov', LParams, LExitCode);
  except
    on E: Exception do
    begin
      Result.Error := 'kcov could not be executed';
      OutputError(ABuilder, 'Coverage', 'kcov could not be executed: ' + E.Message);
      Exit;
    end;
  end;

  if (LExitCode > 10) or not FileExists(LXmlFile) then
  begin
    ABuilder.Output('Test execution under kcov failed with exit code ' + IntToStr(LExitCode));
    ABuilder.Output('Output from test execution:' + #13#10 + LOutput);
    Result.Error := 'the tests stopped under kcov with exit code ' + IntToStr(LExitCode);
    Exit;
  end;

  LReport := TTestReport.New(ABuilder, ExtractFilePath(ATestProject));
  try
    LReport.Executable := ExtractFileName(LExeFile);
    LReport.ParseXmlTestsFile(ExtractFileName(LExeFile), LXmlFile);
    LReport.Output;
    Result.Failed := LReport.TestsFailed;
  finally
    LReport.Free;
  end;

  LJsonFile := ConcatPaths([LOutDir, ExtractFileName(LExeFile), 'coverage.json']);
  if not FileExists(LJsonFile) then
    LJsonFile := ConcatPaths([LOutDir, 'kcov-merged', 'coverage.json']);
  if not FileExists(LJsonFile) then
  begin
    Result.Error := 'kcov did not write the report';
    OutputError(ABuilder, 'Coverage', 'kcov did not write the report in ' + DisplayPath(AStartDir, LOutDir));
    ABuilder.Output(LOutput);
    Exit;
  end;
  try
    Result.Report := ReadCoverageReport(LJsonFile);
  except
    on E: Exception do
    begin
      Result.Error := E.Message;
      OutputError(ABuilder, 'Coverage', E.Message);
      Exit;
    end;
  end;
  Result.Ran := True;

  ABuilder.Output('');
  OutputInfo(ABuilder, 'Coverage', Format('%s %s (%s lines)', [MemberName(ARootDir, AMemberDir),
    FormatPercent(CoveragePercent(Result.Report.Covered, Result.Report.Total)),
    FormatLines(Result.Report.Covered, Result.Report.Total)]));
  // the files relative to the member, so the lines fit in the console
  for LFile in Result.Report.Files do
    OutputInfo(ABuilder, '', Format('%7s %7s  %s', [FormatPercent(CoveragePercent(LFile.Covered, LFile.Total)),
      FormatLines(LFile.Covered, LFile.Total), DisplayPath(AMemberDir, LFile.FileName)]));
  for LUnit in GetUnitsNotInReport(LSourceDirs, Result.Report) do
    OutputError(ABuilder, 'Not counted', DisplayPath(AMemberDir, LUnit) + ' (no test uses it)');
  OutputInfo(ABuilder, 'Report', DisplayPath(AStartDir, ConcatPaths([LOutDir, 'index.html'])));
end;

function CheckMinimum(ABuilder: ICommandBuilder; const AMinimum: Double; const ACovered, ATotal: Integer): Boolean;
begin
  Result := (AMinimum < 0) or (CoveragePercent(ACovered, ATotal) >= AMinimum);
  if not Result then
    OutputError(ABuilder, 'Coverage', Format('%s is below the minimum of %s', [
      FormatPercent(CoveragePercent(ACovered, ATotal)), FormatPercent(AMinimum)]));
end;

procedure CoverWorkspace(ABuilder: ICommandBuilder; const AWorkspaceDir: string; const AMinimum: Double);
var
  LMember: TWorkspaceMember;
  LResult: TMemberCoverage;
  LCoverageDir, LDir, LTestProject: string;
  LCurrentDir: string;
  LReportDirs: TArray<string> = [];
  LCovered: Integer = 0;
  LTotal: Integer = 0;
  LFailed: Integer = 0;
  LExitCode: Integer = 0;
  LNotRun: TArray<string> = [];
  LLine: string;
  LWithoutTests: string = '';
begin
  LCurrentDir := GetCurrentDir;
  try
    PrepareWorkspace(ABuilder, AWorkspaceDir);
    for LMember in SortMembersByDependency(GetWorkspaceMembers(AWorkspaceDir)) do
    begin
      LTestProject := GetMemberTestProject(LMember.Dir);
      if LTestProject = '' then
      begin
        LWithoutTests := LWithoutTests + IfThen(LWithoutTests <> '', ', ', '') + LMember.Name;
        Continue;
      end;

      // the tests run from the member folder, like pasc test
      SetCurrentDir(LMember.Dir);
      OutputInfo(ABuilder, 'Coverage', DisplayPath(AWorkspaceDir, LMember.Dir));
      LResult := CoverMember(ABuilder, LMember.Dir, LTestProject, AWorkspaceDir, AWorkspaceDir);
      if not LResult.Ran then
      begin
        LNotRun := LNotRun + [LMember.Name + IfThen(LResult.Error <> '', ': ' + LResult.Error, '')];
        Continue;
      end;
      Inc(LCovered, LResult.Report.Covered);
      Inc(LTotal, LResult.Report.Total);
      Inc(LFailed, LResult.Failed);
      LReportDirs := LReportDirs + [ConcatPaths([AWorkspaceDir, COVERAGE_DIR,
        ExtractFileName(ExcludeTrailingPathDelimiter(LMember.Dir))])];
    end;
  finally
    SetCurrentDir(LCurrentDir);
  end;

  // one report with every member, at the root of the coverage folder
  LCoverageDir := ConcatPaths([AWorkspaceDir, COVERAGE_DIR]);
  if Length(LReportDirs) > 0 then
  begin
    for LDir in KCOV_MERGED_DIRS do
      if DirectoryExists(ConcatPaths([LCoverageDir, LDir])) then
        DeleteDirectory(ConcatPaths([LCoverageDir, LDir]), False);
    try
      ShellExecute('kcov', ['--merge', LCoverageDir] + LReportDirs, LExitCode);
    except
      LExitCode := 1;
    end;
  end;

  ABuilder.Output('');
  OutputInfo(ABuilder, 'Workspace', Format('%d members covered: %s (%s lines), %d tests failed.', [
    Length(LReportDirs), FormatPercent(CoveragePercent(LCovered, LTotal)), FormatLines(LCovered, LTotal), LFailed]));
  // one line per member, with the reason
  for LLine in LNotRun do
    OutputError(ABuilder, 'Not run', LLine);
  if LWithoutTests <> '' then
    OutputInfo(ABuilder, 'No tests', LWithoutTests);
  if (Length(LReportDirs) > 0) and (LExitCode = 0) then
  begin
    OutputInfo(ABuilder, 'Report', DisplayPath(LCurrentDir, ConcatPaths([LCoverageDir, 'index.html'])));
    if ABuilder.CheckOption('open') then
      OpenReport(ConcatPaths([LCoverageDir, 'index.html']));
  end;

  if (LFailed > 0) or (Length(LNotRun) > 0) or not CheckMinimum(ABuilder, AMinimum, LCovered, LTotal) then
    ExitCode := 1;
end;

procedure CoverProject(ABuilder: ICommandBuilder; const AMinimum: Double);
var
  LTestProject, LMemberDir, LRootDir: string;
  LResult: TMemberCoverage;
begin
  LTestProject := FindTestProject(ABuilder);
  if LTestProject = '' then
  begin
    ExitCode := 1;
    Exit;
  end;
  LTestProject := ChangeFileExt(LTestProject, '.lpi');

  // the member is the folder of the tests folder, and the reports go to the workspace root
  LMemberDir := ExtractFileDir(LTestProject);
  if SameText(ExtractFileName(LMemberDir), 'tests') then
    LMemberDir := ExtractFileDir(LMemberDir);
  LRootDir := FindWorkspaceRoot(LMemberDir);
  if LRootDir = '' then
    LRootDir := LMemberDir;

  LResult := CoverMember(ABuilder, LMemberDir, LTestProject, LRootDir, GetCurrentDir);
  if LResult.Ran and ABuilder.CheckOption('open') then
    OpenReport(ConcatPaths([LRootDir, COVERAGE_DIR, ExtractFileName(LMemberDir), 'index.html']));

  if (not LResult.Ran) or (LResult.Failed > 0) or
     not CheckMinimum(ABuilder, AMinimum, LResult.Report.Covered, LResult.Report.Total) then
    ExitCode := 1;
end;

procedure CoverageCommand(ABuilder: ICommandBuilder);
var
  LWorkspaceDir: string;
  LMinimum: Double;
begin
  {$IF DEFINED(WINDOWS)}
  OutputError(ABuilder, 'Coverage', 'kcov, which measures the coverage, does not run on Windows. ' +
    'Use pasc coverage on Linux or macOS.');
  ExitCode := 1;
  Exit;
  {$ENDIF}
  if not GetMinimum(ABuilder, LMinimum) or not KcovInstalled(ABuilder) then
  begin
    ExitCode := 1;
    Exit;
  end;

  // at the root of a workspace, without a test project of its own, covers every member
  LWorkspaceDir := FindWorkspaceRoot(GetCurrentDir);
  if (LWorkspaceDir <> '') and SameFileName(LWorkspaceDir, ExcludeTrailingPathDelimiter(GetCurrentDir)) and
     (FindTestProject(ABuilder, True) = '') then
  begin
    try
      CoverWorkspace(ABuilder, LWorkspaceDir, LMinimum);
    except
      on E: Exception do
      begin
        OutputError(ABuilder, 'Workspace', E.Message);
        ExitCode := 1;
      end;
    end;
    Exit;
  end;

  CoverProject(ABuilder, LMinimum);
end;

procedure Registry(ABuilder: ICommandBuilder);
begin
  ABuilder
    .AddCommand(
      'coverage',
      'measures the coverage of the unit tests with kcov.'#13#10 +
      ''#13#10 +
      'This command builds the test project in the current folder, or in a tests'#13#10 +
      'subfolder, with the Coverage build mode (debug info, no optimization, units'#13#10 +
      'in lib/coverage), which it adds to the .lpi when missing. Then it runs the'#13#10 +
      'tests under kcov and outputs the coverage of each source file of the project,'#13#10 +
      'without the tests and the modules, and the path of the HTML report, written'#13#10 +
      'to the coverage folder. The folder and the executable of the Coverage build'#13#10 +
      'mode, Test<name>-coverage, are added to the .gitignore when needed.'#13#10 +
      ''#13#10 +
      'kcov only sees the units that the tests use. A unit with code that no test'#13#10 +
      'uses is listed as a warning, and is not counted.'#13#10 +
      ''#13#10 +
      'At the root of a workspace it covers every member that has a tests folder'#13#10 +
      'and outputs the total. kcov runs on Linux and macOS, not on Windows.'#13#10 +
      'The exit code is 1 if the tests could not run, any of them failed, or the'#13#10 +
      'coverage is below --min.'#13#10 +
      ''#13#10 +
      'Ex: ' + ABuilder.ExeName + ' coverage'#13#10 +
      'Ex: ' + ABuilder.ExeName + ' coverage --min=80',
      @CoverageCommand,
      [ccNoParameters])
      .AddOption(
        'm',
        'min',
        'exits with 1 when the coverage is below this percentage.',
        [],
        ocRequiresValue)
      .AddOption(
        'o',
        'open',
        'opens the HTML report in the browser.',
        [],
        ocNoValue);
end;

end.
