/// <summary> This unit contains procedures for setting up and executing a watch command 
/// in the current directory. If there are changes to files in that directory, specified 
/// commands are executed. </sumamry>
unit Command.Watch;

{$MODE DELPHI}{$H+}

interface

uses
  Command.Interfaces,
  Utils.Interfaces;

  /// <summary> This command aims to monitor for changes in the current directory. Changes 
  /// considered are new files, changes to existing files, and file deletions.
  /// 
  /// The ignored folders are the ones that start with ".", the ones named "lib", "modules", 
  /// "backup". Ignored files start with ".", with no extension, .exe, .dll and .trc.
  /// 
  /// Once the change condition is satisfied, the requested commands are executed so that 
  /// their output is generated in the console.
  /// </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output user instructions about the execution state of this command. </param>
  procedure WatchCommand(ABuilder: ICommandBuilder);

  /// <summary> Registry a watch command using the command builder from pascli. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// registry the command. </param>  
  procedure Registry(ABuilder: ICommandBuilder);

  /// <summary> Execute the command requested by the user, it will be passed to IPathWatcher 
  /// so that it executes it. It is prepared to run the project build and tests as long as 
  /// there is a respective executable. . </summary>
  /// <param name="AFile"> Filename that triggered the action change. </param>  
  /// <param name="AEvent">The event that triggered this procedure.</param>
  function RunUserCommandAsRequested(const AFile: string; const AEvent: TWatcherEvent): Boolean;

var
  /// <summary> Allows to define another function to process the changes detected by the 
  /// Watcher. The main purpose is to use this variable to easily implement unit tests.
  /// </summary>
  RunWatcherCallback: TWatcherRunCallback;

  /// <summary> Allows to set a custom timeout to wait for an change event. The main purpose 
  /// is to use this variable to easily implement unit tests.
  /// </summary>
  CommandWatchTimeout: LongInt = 3600000;

implementation

uses
  SysUtils,
  StrUtils,
  Command.Test,
  Command.Build,
  Command.Colors,
  Utils.IO,
  Utils.Shell,
  Utils.Watcher;

var
  Builder: ICommandBuilder;
  Console: TConsoleWatcher;
  ProjectFile, TestCaseSuite, RunRawParams: string;
  IsTest, IsBuild, IsRun: Boolean;

procedure OutputWatcherInfo(const ATitle, AText: string);
begin
  Builder.OutputColor(PadLeft(ATitle + ' ', 13), Builder.ColorTheme.Title);
  Builder.OutputColor(AText + #13#10, Builder.ColorTheme.Other);
end;

procedure OutputWatcherError(const ATitle, AError: string);
begin
  Builder.OutputColor(PadLeft(ATitle + ' ', 13), Builder.ColorTheme.Title);
  Builder.OutputColor(AError + #13#10, Builder.ColorTheme.Error);
end;

procedure OutputWatcherDebug(const ATitle, AText: string);
begin
  Builder.OutputColor(PadLeft(ATitle + ' ', 13), Builder.ColorTheme.Title);
  Builder.OutputColor(AText + #13#10, Builder.ColorTheme.Value);
end;

function GetProjectFileName(ABuilder: ICommandBuilder): string;
var
  LProjectFile: string;
begin
  if ABuilder.CheckOption('test') then
  begin
    LProjectFile := FindProjectFile(GetCurrentDir, 'TestRunner');
    if not FileExists(LProjectFile) then
      LProjectFile := FindProjectFile(ConcatPaths([GetCurrentDir, 'tests']), 'TestRunner');

    if not FileExists(LProjectFile) then
      raise Exception.Create(
        'Test project not found on current dir or tests sub folder. ' +
        'Projet type should use fpcunit');
  end
  else
  begin
    LProjectFile := FindProjectFile(GetCurrentDir, '');
    if not FileExists(LProjectFile) then
      raise Exception.Create('no project found on current path');
  end;
  Result := LProjectFile;
end;

function RunUserCommandAsRequested(const AFile: string; const AEvent: TWatcherEvent): Boolean;
var
  LStart: QWord;
  LExt: string = {$IFDEF UNIX}''{$ELSE}'.exe'{$ENDIF};

  procedure OutputMessage;
  var
    LMessage: string;
  begin
    if (not Assigned(Console)) then exit;
    
    LMessage := Console.GetMessage;
    if LMessage <> '' then
      Builder.OutputColor(LMessage+#13#10, Builder.ColorTheme.Other);
  end;

begin
  LStart := GetTickCount64;

  if AEvent = weNoChange then
  begin
    OutputMessage;
    exit;
  end;

  if AEvent = weTimeout then
  begin
    OutputWatcherError('Watcher', AFile + #13#10);
    exit;
  end;

  if AEvent in [weFirstRun, weFileChanged] then
  begin
    if Assigned(Console) then
    begin
      OutputWatcherInfo('', '');
      OutputWatcherDebug('Watcher', 'killing task that is running'#13#10);
      Console.Stop;
      Console.Terminate;
      FreeAndNil(Console);
    end;
  end;

  OutputWatcherInfo('Event', AFile);
  
  if IsBuild then
  begin
    OutputWatcherInfo('Watcher', 'Build started'#13#10);
    Builder.UseArguments(['build', ProjectFile]);
    Builder.Parse;
    BuildCommand(Builder);

    if Builder.State <> '' then 
    begin
      OutputWatcherInfo('', '');
      OutputWatcherError('Watcher', Builder.State);
      Builder.State := '';
      OutputWatcherInfo('', '');
      exit(false);
    end;

    OutputWatcherInfo('', '');
  end;

  if IsTest then
  begin
    IsRun := False;
    OutputWatcherInfo('Watcher', 'test started'#13#10);
    
    if TestCaseSuite <> '' then
      Builder.UseArguments(['test', '-t=' + TestCaseSuite])
    else
      Builder.UseArguments(['test']);

    Builder.Parse;
    // when --build is set the test project was just built above
    RunTests(Builder, not IsBuild);
  end;

  if IsRun then
  begin
    OutputWatcherInfo('Watcher', 'running ' + ChangeFileExt(ProjectFile, LExt) + ' ' + RunRawParams + #13#10);
    if AEvent in [weFirstRun, weFileChanged] then
    begin
      Console := TConsoleWatcher.Create(ChangeFileExt(ProjectFile, LExt), GetParametersFrom(RunRawParams));
      Console.Start;
      OutputMessage;
    end;
  end;

  OutputWatcherInfo(
    'Watcher', 
    'cycle elapsed time: ' + FloatToStr((GetTickCount64 - LStart) / 1000.0) + ' seconds'#13#10);

  Result := False;
end;

procedure WatchCommand(ABuilder: ICommandBuilder);
var
  LPathWatcher: IPathWatcher;
begin
  Builder := ABuilder;

  OutputWatcherInfo('Watcher', 'started');
  OutputWatcherInfo('Path', GetCurrentDir);

  ProjectFile := GetProjectFileName(Builder);
  IsTest := Builder.CheckOption('test', TestCaseSuite);
  IsBuild := Builder.CheckOption('build');
  IsRun := Builder.CheckOption('run', RunRawParams);
  
  OutputWatcherInfo('Project', ProjectFile);
  
  LPathWatcher := 
    TPathWatcher
      .New
      .Path(GetCurrentDir)
      .Ignore(ikStartsText, ['.'])
      .Ignore(ikFolder, ['lib', 'backup', 'docs'])
      .Ignore(ikExtension, ['.exe', '', '.dll', '.so', '.trc', '.xml', '.res'])
      .Timeout(CommandWatchTimeout)
      .Run(RunWatcherCallback)
      .Start;
end;

procedure Registry(ABuilder: ICommandBuilder);
begin
  ABuilder
    .AddCommand(
      'watch',
      'Monitor current path for changes and execute selected commands.'#13#10 +
      'A project file can be provided, if you don''t want to specify '#13#10 +
      'a file just pass a . as an argument. In this case, pasc looks '#13#10 +
      'for a project in the current folder. If the --test option is '#13#10 +
      'used, pasc will look for a test project based on fpcunit. '#13#10 +
      'The goal is to run a build cycle and tests when changes to the '#13#10 +
      'folder are detected. '#13#10 +
      'Ex: ' + ABuilder.ExeName + ' watch --build --test .'#13#10 +
      'Ex: ' + ABuilder.ExeName + ' watch --build --run',
      @WatchCommand,
      [ccRequiresOneArgument])
      .AddOption(
          'b', 'build', 
          'build the main project', [])
      .AddOption(
          'r', 'run', 
          'run main project'#13#10 + 
          '?: accepts parameters to be passed to the application being executed', ['t'], ocOptionalValue)
      .AddOption(
          't', 'test', 
          'build test project and run it'#13#10 + 
          '?: accepts a test name to run it only', ['r'], ocOptionalValue);
end;

initialization
  RunWatcherCallback := RunUserCommandAsRequested;

end.