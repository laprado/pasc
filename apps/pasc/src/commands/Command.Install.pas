/// <summary> This unit contains procedures to configure and execute a command to install 
/// pasc app in the following path $HOME/.pasc. 
/// </summary>
unit Command.Install;

interface

uses
  Command.Interfaces;

  /// <summary> Copy the pasc application to the "home" folder and create the folder 
  /// if it doesn't exist. Updates the OS-equivalent path environment variable with 
  /// the new folder so that pasc is visible on the command line. </summary>
  /// <param name="ABuilder"> Instance o the builder that will be use to output
  /// instructions to user about the installation status </param>
  procedure InstallCommand(ABuilder: ICommandBuilder);

  /// <summary> Registry a install command using the command builder from pascli, also sets. 
  /// options and usage help info. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// registry the command. </param>
  procedure Registry(ABuilder: ICommandBuilder);

  {$IF DEFINED(TESTAPP)}

  /// <summary> Creates a subfolder in the user's home folder with the application name. 
  /// Set the home folder to the new current path. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output info about folder creation. </param>
  /// <param name="AFolder"> Output parameter with the folder name created. </param>
  procedure CreateFolder(ABuilder: ICommandBuilder; var AFolder: string);

  /// <summary> Copy the application itself to the given path. Overwrite the file if it exists.
  /// </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output info about app copy. </param>
  /// <param name="AFolder"> Target full path to copy the application </param>
  procedure CopyApp(ABuilder: ICommandBuilder; const AFolder: string);

  /// <summary> Adds the given path to the .profile user file. It also displays state 
  /// information to the user about the success or failure of this action. The user can be 
  /// guided to perform administration elevation procedures.
  /// </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output info about path variable change. </param>
  /// <param name="AFolder"> Full path that will be added to path environment variable. </param>
  procedure UpdateEnvironmentPathLinux(ABuilder: ICommandBuilder; const AFolder: string);

  /// <summary> Adds the given path to the /etc/paths user file. It also displays state 
  /// information to the user about the success or failure of this action. The user can be 
  /// guided to perform administration elevation procedures.
  /// </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output info about path variable change. </param>
  /// <param name="AFolder"> Full path that will be added to path environment variable. </param>
  procedure UpdateEnvironmentPathMacos(ABuilder: ICommandBuilder; const AFolder: string);

  /// <summary> Adds the given path to the path environment variable. It also displays state 
  /// information to the user about the success or failure of this action. The user can be 
  /// guided to perform administration elevation procedures.
  /// </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output info about path variable change. </param>
  /// <param name="AFolder"> Full path that will be added to path environment variable. </param>
  procedure UpdateEnvironmentPathWindows(ABuilder: ICommandBuilder; const AFolder: string);

  {$ENDIF}

implementation

uses
  Classes,
  StrUtils,
  SysUtils,
  FileUtil,
  Utils.Resources,
  Utils.Shell,
  Utils.IO,
  Utils.Output;

procedure CreateFolder(ABuilder: ICommandBuilder; var AFolder: string);
var
  LSubFolder: string;
begin
  LSubFolder := '.' + ChangeFileExt(ABuilder.ExeName, '');
  AFolder := ConcatPaths([GetUserDir, LSubFolder]);

  OutputInfo(ABuilder, 'creating', 'destination folder ' + AFolder);

  if not DirectoryExists(AFolder) then
  begin
    SetCurrentDir(GetUserDir);
    CreateDir(LSubFolder);
  end;
end;

procedure CopyApp(ABuilder: ICommandBuilder; const AFolder: string);
begin
  OutputInfo(ABuilder, 'copying', ApplicationName + ' to destination folder');
  if not SameText(ParamStr(0), ConcatPaths([AFolder, ExtractFileName(ParamStr(0))])) then
    CopyFile(ParamStr(0), ConcatPaths([AFolder, ExtractFileName(ParamStr(0))]), [cffOverwriteFile]);  
end;

procedure UpdateEnvironmentPathLinux(ABuilder: ICommandBuilder; const AFolder: string);
var
  LProfile, LContent, LExport: string;
  LExitCode: Integer = 0;
begin
  OutputInfo(ABuilder, 'updating', 'path environment variable, this may require administration privileges');
  
  LProfile := ConcatPaths([GetUserDir, '.profile']);
  LContent := GetFileContent(LProfile);

  OutputInfo(ABuilder, 'changing', 'file: ~/.profile ');

  // adequar para a pasta passada como parâmetro
  LExport := 'export PATH=$PATH:' + AFolder;
  if not ContainsText(LContent, LExport) then 
  begin
    LContent := LContent + #13#10 + LExport;
    SaveFileContent(LProfile, LContent);
  end;

  OutputInfo(ABuilder, 'running', 'source ~/.profile to make path changes to take effect');
    
  LContent := GetResource('update-path-sh'); 
  SaveFileContent(ConcatPaths([AFolder, 'update-path.sh']), LContent);

  LContent := ShellCommand(
    'bash', 
    [
      ConcatPaths([AFolder, 'update-path.sh']), 
      ConcatPaths([AFolder, ABuilder.ExeName])
    ],
    LExitCode);
  ExitCode := LExitCode;
  if LExitCode <> 0 then
    OutputError(ABuilder, 'error', 'failed to update path environment variable: exit code ' + IntToStr(LExitCode));

  if LContent <> '' then
    ABuilder.OutputColor(LContent + #13#10, ABuilder.ColorTheme.Other);
end;

procedure UpdateEnvironmentPathMacos(ABuilder: ICommandBuilder; const AFolder: string);
var
  LFile: TStringList = nil;
  LProfile, LContent: string;
  I: Integer;
  LExitCode: Integer = 0;
  LFound: Boolean = false;
begin
  OutputInfo(ABuilder, 'updating', 'path environment variable, this may require administration privileges');

  LFile := TStringList.Create;
  try
    LProfile := ConcatPaths(['/', 'etc', 'paths']);
    LFile.LoadFromFile(LProfile);
    
    OutputInfo(ABuilder, 'changing', 'file: /etc/paths to add pasc path ');
    
    for I := 0 to LFile.Count -1 do 
      if ContainsText(LFile.Strings[I], AFolder) then 
      begin
        LFound := True;
        break;
      end;

    if not LFound then
    begin
      LFile.Add(AFolder);
      LFile.SaveToFile(LProfile);
    end;
  
    OutputInfo(ABuilder, 'running', 'shell script to make allow pasc to ben run on new path');
    
    LFile.Clear;
    LFile.AddText(GetResource('update-path-sh'));
    LFile.SaveToFile(ConcatPaths([AFolder, 'update-path.sh']));

    LContent := ShellCommand(
      'bash', 
      [
        ConcatPaths([AFolder, 'update-path.sh']), 
        ConcatPaths([AFolder, ABuilder.ExeName])
      ],
      LExitCode);
    if LExitCode <> 0 then
      OutputError(ABuilder, 'error', 'failed to update path environment variable: exit code ' + IntToStr(LExitCode));

    WriteLn(LContent);

  finally
    LFile.Free;
  end; 
end;

procedure UpdateEnvironmentPathWindows(ABuilder: ICommandBuilder; const AFolder: string);
var
  LName: string = 'update-path.ps1';
  LExitCode: Integer = 0;
begin
  OutputInfo(ABuilder, 'updating', 'environment path, this may require administration privileges ');
  SaveFileContent(ConcatPaths([AFolder, LName]), GetResource('update-path-ps1'));

  OutputInfo(ABuilder, 'script', 'running shell script file: ' + LName);
  ShellCommand('powershell', [ConcatPaths([AFolder, LName]), AFolder], LExitCode);
  if LExitCode <> 0 then
  begin
    OutputError(ABuilder, 'error', 'failed to update path environment variable: exit code ' + IntToStr(LExitCode));
    OutputError(ABuilder, '', 'this could be caused by the lack of administration privileges while running the script');
    OutputError(ABuilder, '', 'or the lack of execution policy to run powershell scripts. To fix this, run the following command:');
    OutputError(ABuilder, '', 'Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser');
    OutputError(ABuilder, '', 'execute the command to install pasc again after that');
  end;

  OutputInfo(ABuilder, 'info', 'please restart your terminal app to path variable take effect');
end;

procedure InstallCommand(ABuilder: ICommandBuilder);
var
  LAppFolder: string = '';
begin
  try
    OutputInfo(ABuilder, 'Starting', 'to install pasc on user''s home folder');
    CreateFolder(ABuilder, LAppFolder);
    CopyApp(ABuilder, LAppFolder);
    SetCurrentDir(LAppFolder);
    {$IF DEFINED(WINDOWS)}
    UpdateEnvironmentPathWindows(ABuilder, LAppFolder);
    {$ENDIF}
    {$IF DEFINED(LINUX)}
    UpdateEnvironmentPathLinux(ABuilder, LAppFolder);
    {$ENDIF}
    {$IF DEFINED(Darwin)}
    UpdateEnvironmentPathMacos(ABuilder, LAppFolder);
    {$ENDIF}
    OutputInfo(ABuilder, 'install', 'complete');
  except
    on E: Exception do
    begin
      OutputError(ABuilder, 'error', E.Message);
      raise;
    end;
  end;
end;

procedure Registry(ABuilder: ICommandBuilder);
begin
  ABuilder
    .AddCommand(
      'install',
      'Install pasc on user home folder and add it to path.'#13#10 +
      'A folder called .pasc will be created on user''s home folder and will be added to '#13#10 +
      'the path environment variable. You may need to restart the terminal to this '#13#10 +
      'change takes effect. '#13#10 +
      'Administration privileges may be required to execute this command.'#13#10 +
      'Ex: ./' + ABuilder.ExeName + ' install',
      @InstallCommand,
      [ccNoParameters]);  
end;

end.