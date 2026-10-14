/// <summary> This unit contains procedures to configure and execute a command to build the
/// specified project or to build the first project found on current dir. 
/// </summary>
unit Command.Build;

{$MODE DELPHI}{$H+}

interface

uses
  Command.Interfaces;

  /// <summary> This command uses the lazbuild tool to build the specified project. If one
  /// was not provided, try to find one on current directory and builds it.
  /// 
  /// The purpose of this command is to automate the build process along with the 
  /// watch command.
  ///
  /// The command accepts two build options --debug or --release. The project file must have both
  /// modes with these respective names. If no option is passed, the lazbuild tool will run 
  // in default mode.
  /// </summary>
  /// <param name="ABuilder"> Command builder that will provide the output callback to print
  /// info about the command execution </param>
  procedure BuildCommand(ABuilder: ICommandBuilder);

  /// <summary> Registry a build command using the command builder from pascli, also sets. 
  /// options and usage help info. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// registry the command. </param>  
  procedure Registry(ABuilder: ICommandBuilder);

  /// <summary> Checks if specified project exists, if a project file is not provided
  /// try to find one on current directory. Returns complete file name if a project
  /// is found. </summary>
  /// <param name="AProjectDir"> Folder to find the lazarus project </param>
  /// <param name="AProjectFile"> Project file specified. </param>
  function FindProject(const AProjectDir, AProjectFile: string): string;

implementation

uses
  Classes,
  SysUtils,
  StrUtils,
  Math,
  Command.Colors,
  Utils.Shell;

function FindFirstFile(const AProjectDir, AExt: string): string;
var
  LSearch: TSearchRec;
begin
  Result := '';
  if FindFirst(ConcatPaths([AProjectDir, '*' + AExt]), faAnyFile, LSearch) = 0 then
    try
      repeat
        if SameText(ExtractFileExt(LSearch.Name), AExt) then
          Exit(ConcatPaths([AProjectDir, LSearch.Name]));
      until FindNext(LSearch) <> 0;
    finally
      FindClose(LSearch);
    end;
end;

function FindProject(const AProjectDir, AProjectFile: string): string;
begin
  Result := '';
  if not DirectoryExists(AProjectDir) then
    exit;

  if (AProjectFile <> '') and FileExists(ConcatPaths([AProjectDir, AProjectFile])) then
    exit(ConcatPaths([AProjectDir, AProjectFile]));

  // lazbuild works with the .lpi file, the .lpr is a fallback
  Result := FindFirstFile(AProjectDir, '.lpi');
  if Result = '' then
    Result := FindFirstFile(AProjectDir, '.lpr');
end;

procedure BuildCommand(ABuilder: ICommandBuilder);
var
  LProjectFile: string = '';
  LOutput: string;
  LArgs: TArray<string>;
  LExitCode: Integer = 0;
begin
  if Length(ABuilder.GetParsedArguments) > 0 then
  begin
    LProjectFile := ABuilder.GetParsedArguments[0].Value;
    if not FileExists(LProjectFile) then
    begin
      ABuilder.OutputColor('Project ' + LProjectFile + ' not found.'#13#10, ABuilder.ColorTheme.Error);
      exit;    
    end;
  end;

  if not FileExists(LProjectFile) then
    LProjectFile := FindProject(GetCurrentDir, LProjectFile);

  if Trim(LProjectFile) = '' then
  begin
    ABuilder.OutputColor(
      'There is no project file on current directory or the specified file ',
      ABuilder.ColorTheme.Other);
    ABuilder.OutputColor(
      'does not exist.'#13#10,
      ABuilder.ColorTheme.Error);
    exit;      
  end;
  
  try
    LOutput := ShellExecute('lazbuild', ['-v'], LExitCode);
    ExitCode := LExitCode;
  except
    on E: Exception do
    begin
      ExitCode := IfThen(LExitCode = 0, 1, LExitCode);
      ABuilder.OutputColor('lazbuild does not exist or its path is not configure to be in PATH environment.',
      ABuilder.ColorTheme.Error);
      exit;      
    end;
  end;
  
  // shell command to build the project
  try
    LArgs := [LProjectFile];
    if ABuilder.CheckOption('d') then
      LArgs := LArgs + ['--build-mode=Debug']
    else if ABuilder.CheckOption('r') then
      LArgs := LArgs + ['--build-mode=Release'];

    LOutput := ShellExecute('lazbuild', LArgs, LExitCode);
    if ContainsText(LOutput, 'Error: ') then
      ABuilder.State := 'Error during build was detected.';
    ABuilder.OutputColor(LOutput + #13#10, ABuilder.ColorTheme.Other);
    ExitCode := LExitCode;
  except
    on E: Exception do
    begin
      ExitCode := IfThen(LExitCode = 0, 1, LExitCode);
      ABuilder.OutputColor('error trying to build the project file.',
      ABuilder.ColorTheme.Error);
      exit;      
    end;
  end;

end;

procedure Registry(ABuilder: ICommandBuilder);
begin
  ABuilder
    .AddCommand(
      'build',
      'build the project in current directory or one provided as an argument.'#13#10 +
      ABuilder.ExeName + ' is not able to compile the project by itself, it is just '#13#10 +
      'calling lazbuild to do it. This command exists only to enable the watch command.'#13#10 +
      'Ex: ' + ABuilder.ExeName + ' build'#13#10 +
      'Ex: ' + ABuilder.ExeName + ' build sample1.lpi',
      @BuildCommand,
      [])
      .AddOption(
          'd', 'debug', 
          'build the project in debug mode, .lpi file must have a debug mode', ['r'])
      .AddOption(
          'r', 'release', 
          'build the project in release mode, .lpi file must have a release mode', ['d'])
end;

end.