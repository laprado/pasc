/// <summary> This unit contains procedures to configure and execute a command to create 
/// dipslay unit tests colored output. Also should display source code location for each
/// failed test. 
/// 
/// If a heap trace file is found on test project directory an output with possible leaks
/// is generated.
/// </summary>
unit Command.Test;

{$MODE DELPHI}{$H+}

interface

uses
  Command.Interfaces;

type
  /// <summary> Result of a test project execution. </summary>
  TTestRunResult = record
    /// <summary> True if the test project was built (when requested) and executed. </summary>
    Ran: Boolean;
    Passed: Integer;
    Failed: Integer;
    /// <summary> Why the tests did not run, like the first error of the compiler, or empty.
    /// </summary>
    Error: string;
  end;

  /// <summary> This command searches for a fpcunit test project in the current folder or in
  /// a tests subfolder, builds it using lazbuild and runs it. At the end of the execution, an xml file with 
  /// the same name as the test project is expected to be read. From this reading, a result
  /// is generated with the objective of highlighting the tests that failed, formatting the 
  /// name of the source code file with a line and column in a format that vscode is able to 
  /// understand and providing the developer with a link for quick navigation through the code.
  ///
  /// If a memory leak trace file named heap.trc is found, the command also outputs 
  /// information with details about the possible memory leaks in a format that vscode can 
  /// provide easy navigation through the code.
  /// </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output user instructions about the execution state of this command. </param>
  procedure TestCommand(ABuilder: ICommandBuilder);

  /// <summary> Runs the test project found from the current directory and outputs the report.
  /// If ABuild is true the test project is built with lazbuild before running. Returns whether
  /// the tests ran and how many passed and failed. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output user instructions about the execution state of this command. </param>
  /// <param name="ABuild"> Builds the test project before running it. </param>
  function RunTests(ABuilder: ICommandBuilder; const ABuild: Boolean): TTestRunResult;

  /// <summary> Builds the test project using lazbuild. The .lpi file with the same name of
  /// the project file is preferred if it exists. Returns true if the build succeeded. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output the build result in case of failure. </param>
  /// <param name="AProjectFile"> Test project file (.lpr or .lpi). </param>
  /// <param name="ABuildMode"> Build mode passed to lazbuild, empty for the default one.
  /// </param>
  function BuildTestProject(ABuilder: ICommandBuilder; const AProjectFile: string;
    const ABuildMode: string = ''): Boolean; overload;

  /// <summary> Builds the test project like the other BuildTestProject, and returns in AError
  /// the first error of the compiler when the build fails, for a summary. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output the build result in case of failure. </param>
  /// <param name="AProjectFile"> Test project file (.lpr or .lpi). </param>
  /// <param name="ABuildMode"> Build mode passed to lazbuild, empty for the default one.
  /// </param>
  /// <param name="AError"> Returns the first error, or empty if the build succeeded. </param>
  function BuildTestProject(ABuilder: ICommandBuilder; const AProjectFile, ABuildMode: string;
    out AError: string): Boolean; overload;

  /// <summary> Returns the first error in the output of lazbuild, the line that explains the
  /// failure among the hints and the lazbuild messages, like
  /// TestCommandGreet.pas(11,3) Fatal: Can't find unit Command.Interfaces used by TestCommandGreet.
  /// The folder of the file and the message number are removed. Returns empty if there is no
  /// error. </summary>
  /// <param name="AOutput"> Output of lazbuild. </param>
  function FirstBuildError(const AOutput: string): string;

  /// <summary> Registry a test command using the command builder from pascli. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// registry the command. </param>
  procedure Registry(ABuilder: ICommandBuilder);

  /// <summary> From the current directory it tries to locate an fpcunit compatible test 
  /// project, in the current folder or in a tests subfolder. Returns the complete test project
  /// file name, or empty if the project does not exist or is not of the expected type.
  /// </summary>  
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output info about the existence of the test project and whether it is valid. </param>
  /// <param name="AQuiet"> Does not output a message when the project is not found. </param>
  function FindTestProject(ABuilder: ICommandBuilder; const AQuiet: Boolean = False): string;

  /// <summary> From the current directory it tries to locate an fpcunit compatible test 
  /// project that has been previously compiled. Returns complete test file executable name.
  /// If the function returns empty, the project does not exist or is not of the expected type.
  /// </summary>  
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output info about the existence of the test project and whether it is valid. </param>
  function GetTestExecutable(ABuilder: ICommandBuilder): string;

implementation

uses
  Classes,
  SysUtils,
  StrUtils,
  Math,
  Command.Check,
  Utils.Interfaces,
  Utils.Tests,
  Utils.Leak,
  Utils.Shell,
  Utils.IO,
  Utils.Output,
  Utils.Workspace;

function FindTestProject(ABuilder: ICommandBuilder; const AQuiet: Boolean = False): string;
begin
  Result := FindProjectFile(GetCurrentDir, 'TestRunner');
  if Result = '' then
    Result := FindProjectFile(ConcatPaths([GetCurrentDir, 'tests']), 'TestRunner');

  if (Result = '') and (not AQuiet) then
    ABuilder.Output(
      'A test project was not found in the current path or in a tests subfolder. '#13#10 +
      'The test project must be based on the fpcunit test framework.');
end;

function FirstBuildError(const AOutput: string): string;
var
  LLines: TStringList;
  LLine, LMessage, LFile: string;
  LPos: Integer;

  function WithoutNumber(const AText: string): string;
  var
    LStart, LEnd: Integer;
  begin
    // Fatal: (10022) Can't find unit -> Fatal: Can't find unit
    Result := AText;
    LStart := Pos(': (', Result);
    if LStart = 0 then
      Exit;
    LEnd := PosEx(') ', Result, LStart);
    if (LEnd > 0) and (StrToIntDef(Copy(Result, LStart + 3, LEnd - LStart - 3), -1) >= 0) then
      Delete(Result, LStart + 2, LEnd - LStart);
  end;

begin
  Result := '';
  LLines := TStringList.Create;
  try
    LLines.Text := AOutput;
    // a message of the compiler for a source file: file(line,column) Fatal: or Error:
    for LLine in LLines do
    begin
      LPos := Pos(') Fatal: ', LLine);
      if LPos = 0 then
        LPos := Pos(') Error: ', LLine);
      if (LPos = 0) or (RPos('(', Copy(LLine, 1, LPos)) = 0) then
        Continue;
      LFile := Copy(LLine, 1, LPos);
      LMessage := Copy(LLine, LPos + 2, MaxInt);
      Exit(ExtractFileName(LFile) + ' ' + WithoutNumber(LMessage));
    end;
    // otherwise the first error, like one of lazbuild itself
    for LLine in LLines do
      if StartsStr('Fatal: ', Trim(LLine)) or StartsStr('Error: ', Trim(LLine)) then
        Exit(WithoutNumber(Trim(LLine)));
  finally
    LLines.Free;
  end;
end;

function BuildTestProject(ABuilder: ICommandBuilder; const AProjectFile: string;
  const ABuildMode: string = ''): Boolean;
var
  LError: string;
begin
  Result := BuildTestProject(ABuilder, AProjectFile, ABuildMode, LError);
end;

function BuildTestProject(ABuilder: ICommandBuilder; const AProjectFile, ABuildMode: string;
  out AError: string): Boolean;
var
  LProjectFile, LOutput: string;
  LExitCode: Integer = 0;
begin
  LProjectFile := ChangeFileExt(AProjectFile, '.lpi');
  if not FileExists(LProjectFile) then
    LProjectFile := AProjectFile;

  try
    if ABuildMode <> '' then
      LOutput := ShellExecute('lazbuild', ['--bm=' + ABuildMode, LProjectFile], LExitCode)
    else
      LOutput := ShellExecute('lazbuild', [LProjectFile], LExitCode);
  except
    on E: Exception do
    begin
      ABuilder.Output('lazbuild does not exist or its path is not configured in the PATH environment.');
      AError := 'lazbuild was not found';
      ExitCode := 1;
      Exit(False);
    end;
  end;

  AError := '';
  Result := (LExitCode = 0) and (not ContainsText(LOutput, 'Error: '));
  if not Result then
  begin
    AError := FirstBuildError(LOutput);
    if AError = '' then
      AError := 'the build failed';
    ABuilder.Output('Error building the test project ' + LProjectFile + ':' + #13#10 + LOutput);
    ExitCode := IfThen(LExitCode = 0, 1, LExitCode);
  end;
end;

function GetTestExecutable(ABuilder: ICommandBuilder): string;
var
  LProjectFile, LExeFile: string;
begin
  Result := '';

  LProjectFile := FindTestProject(ABuilder);
  if LProjectFile = '' then
    exit;
    
  LExeFile := ChangeFileExt(LProjectFile, {$IF DEFINED(WINDOWS)}'.exe'{$ELSE}''{$ENDIF});
  if not FileExists(LExeFile) then
  begin
    ABuilder.Output('Executable test not found: ' + LExeFile);
    exit;
  end;

  Result := LExeFile;
end;

procedure TestWorkspace(ABuilder: ICommandBuilder; const AWorkspaceDir: string);
var
  LMember: TWorkspaceMember;
  LResult: TTestRunResult;
  LCurrentDir: string;
  LTested: Integer = 0;
  LPassed: Integer = 0;
  LFailed: Integer = 0;
  LNotRun: TArray<string> = [];
  LWithoutTests: string = '';
  LLine: string;
begin
  LCurrentDir := GetCurrentDir;
  try
    PrepareWorkspace(ABuilder, AWorkspaceDir);
    for LMember in SortMembersByDependency(GetWorkspaceMembers(AWorkspaceDir)) do
    begin
      SetCurrentDir(LMember.Dir);
      if FindTestProject(ABuilder, True) = '' then
      begin
        LWithoutTests := LWithoutTests + IfThen(LWithoutTests <> '', ', ', '') + LMember.Name;
        Continue;
      end;

      OutputInfo(ABuilder, 'Testing', ExtractRelativePath(
        IncludeTrailingPathDelimiter(AWorkspaceDir), LMember.Dir));
      LResult := RunTests(ABuilder, True);
      if not LResult.Ran then
      begin
        LNotRun := LNotRun + [LMember.Name + IfThen(LResult.Error <> '', ': ' + LResult.Error, '')];
        Continue;
      end;
      Inc(LTested);
      Inc(LPassed, LResult.Passed);
      Inc(LFailed, LResult.Failed);
    end;
  finally
    SetCurrentDir(LCurrentDir);
  end;

  OutputInfo(ABuilder, 'Workspace', Format('%d members tested: %d passed, %d failed.', [LTested, LPassed, LFailed]));
  // one line per member, with the reason
  for LLine in LNotRun do
    OutputError(ABuilder, 'Not run', LLine);
  if LWithoutTests <> '' then
    OutputInfo(ABuilder, 'No tests', LWithoutTests);

  if (LFailed > 0) or (Length(LNotRun) > 0) then
    ExitCode := 1;
end;

procedure TestCommand(ABuilder: ICommandBuilder);
var
  LWorkspaceDir: string;
  LResult: TTestRunResult;
begin
  // at the root of a workspace, without a test project of its own, tests every member
  LWorkspaceDir := FindWorkspaceRoot(GetCurrentDir);
  if (LWorkspaceDir <> '') and SameFileName(LWorkspaceDir, ExcludeTrailingPathDelimiter(GetCurrentDir)) and
     (FindTestProject(ABuilder, True) = '') then
  begin
    try
      TestWorkspace(ABuilder, LWorkspaceDir);
    except
      on E: Exception do
      begin
        OutputError(ABuilder, 'Workspace', E.Message);
        ExitCode := 1;
      end;
    end;
    Exit;
  end;

  // exit code 1 when the tests could not run or any of them failed, like the workspace,
  // so scripts and CI can rely on it
  LResult := RunTests(ABuilder, True);
  if (not LResult.Ran) or (LResult.Failed > 0) then
    if ExitCode = 0 then
      ExitCode := 1;
end;

function RunTests(ABuilder: ICommandBuilder; const ABuild: Boolean): TTestRunResult;
var
  LProjectFile, LExeFile, LExeOnly, LXmlFile, LTestCase, LOutput: string;
  LReport: TTestReport;
  LLeak: ILeakReport;
  LExitCode: Integer = 0;
begin
  Result := Default(TTestRunResult);
  if ABuild then
  begin
    LProjectFile := FindTestProject(ABuilder);
    if LProjectFile = '' then
    begin
      Result.Error := 'no test project';
      Exit;
    end;
    if not BuildTestProject(ABuilder, LProjectFile, '', Result.Error) then
      Exit;
  end;

  LExeFile := GetTestExecutable(ABuilder);
  if LExeFile.IsEmpty then
  begin
    Result.Error := 'the test executable was not found';
    Exit;
  end;
  LExeOnly := ExtractFileName(LExeFile);
  LXmlFile := ChangeFileExt(LExeFile, '.xml');
  LTestCase := '';
  if ABuilder.CheckOption('test-case', LTestCase) then
    LOutput := ShellExecute(LExeFile, ['--suite=' + LTestCase, '--file=' + LXmlFile], LExitCode)
  else
    LOutput := ShellExecute(LExeFile, ['-a', '--file=' + LXmlFile], LExitCode);

  if LExitCode > 10 then
  begin
    ABuilder.Output('Test execution failed with exit code ' + IntToStr(LExitCode));
    ABuilder.Output('Output from test execution:' + #13#10 + LOutput);
    Result.Error := 'the tests stopped with exit code ' + IntToStr(LExitCode);
    ExitCode := LExitCode;
    Exit;
  end;

  LReport := TTestReport.New(ABuilder, ExtractFilePath(LExeFile));
  try
    LReport.Executable := LExeOnly;
    LReport.ParseXmlTestsFile(LExeOnly, LXmlFile);
    LReport.Output;
    Result.Ran := True;
    Result.Passed := LReport.TestsPassed;
    Result.Failed := LReport.TestsFailed;
  finally
    LReport.Free;
  end;

  LLeak := TLeakReport.New(ABuilder, ExtractFilePath(LExeFile));
  LLeak.Executable := LExeOnly;
  LLeak.ParseHeapTrace('');
  LLeak.Output;
end;

procedure Registry(ABuilder: ICommandBuilder);
begin
  ABuilder
    .AddCommand(
      'test',
      'run the tests and display a nice report, with links to testing methods.'#13#10 +
      ''#13#10 +
      'This command searches for a fpcunit test project in the current folder or in '#13#10 +
      'a tests subfolder, builds it using lazbuild and runs it. At the end of the execution, an xml '#13#10 +
      'file with the same name as the test project is expected to be read. From '#13#10 + 
      'this reading, a result is generated with the objective of highlighting '#13#10 +
      'the tests that failed, formatting the name of the source code file with '#13#10 + 
      'a line and column in a format that vscode is able to understand and '#13#10 +
      'providing the developer with a link for quick navigation through the code.'#13#10 +
      ''#13#10 +
      'If a memory leak trace file named heap.trc is found, the command also outputs '#13#10 + 
      'information with details about the possible memory leaks in a format that vscode can '#13#10 + 
      'provide easy navigation through the code. '#13#10 +
      ''#13#10 +
      'At the root of a workspace it runs the tests of every member that has a '#13#10 +
      'tests folder and outputs a summary.'#13#10 +
      'The exit code is 1 if the tests could not run or any of them failed.'#13#10 +
      ''#13#10 +
      'Ex: ' + ABuilder.ExeName + ' test'#13#10 +
      'Ex: ' + ABuilder.ExeName + ' test=TTestCaseSuite',
      @TestCommand,
      [ccNoParameters])
      .AddOption(
        't',
        'test-case',
        'run only the specified test case or test suite.',
        [],
        ocOptionalValue);
end;

end.