/// <summary> This unit contains the deprecated install command. pasc used to copy itself to
/// $HOME/.pasc and change the PATH (~/.profile on Linux, /etc/paths on macOS, the user PATH on
/// Windows), which was unreliable. The command now only shows how to install pasc with a
/// package manager, manually or from source, and how to remove an old install. It does not
/// change anything.
/// </summary>
unit Command.Install;

{$MODE DELPHI}{$H+}

interface

uses
  Command.Interfaces;

  /// <summary> Shows the recommended way to install pasc on the current platform, and the
  /// steps to remove an install made by the previous versions of this command. Nothing is
  /// changed, and the exit code is 1, since pasc is not installed by it. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output the instructions. </param>
  procedure InstallCommand(ABuilder: ICommandBuilder);

  /// <summary> Registry a install command using the command builder from pascli, also sets.
  /// options and usage help info. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// registry the command. </param>
  procedure Registry(ABuilder: ICommandBuilder);

  {$IF DEFINED(TESTAPP)}

  /// <summary> Returns the steps to remove an install made by the previous versions of the
  /// install command, found from the given home folder. Returns empty if there is none.
  /// </summary>
  /// <param name="AHomeDir"> User home folder. </param>
  function OldInstallCleanupSteps(const AHomeDir: string): TArray<string>;

  {$ENDIF}

implementation

uses
  Classes,
  SysUtils,
  StrUtils,
  Utils.IO,
  Utils.Output;

const
  RELEASES_URL = 'https://github.com/laprado/pasc/releases/latest';
  README_URL = 'https://github.com/laprado/pasc#install';

function OldInstallCleanupSteps(const AHomeDir: string): TArray<string>;
var
  LFolder, LProfile: string;
  {$IF DEFINED(WINDOWS)}
  LPath: string;
  {$ENDIF}
begin
  Result := [];
  LFolder := ConcatPaths([AHomeDir, '.pasc']);
  if DirectoryExists(LFolder) then
    Result := Result + ['remove the folder ' + LFolder];

  {$IF DEFINED(WINDOWS)}
  LPath := GetEnvironmentVariable('PATH');
  if ContainsText(LPath, LFolder) then
    Result := Result + [
      'remove ' + LFolder + ' from the user PATH: Settings > System > About > ' +
      'Advanced system settings > Environment Variables'];
  {$ELSE}
  LProfile := ConcatPaths([AHomeDir, '.profile']);
  if FileExists(LProfile) and ContainsText(GetFileContent(LProfile), 'export PATH=$PATH:' + LFolder) then
    Result := Result + ['remove the line "export PATH=$PATH:' + LFolder + '" from ' + LProfile];
  {$ENDIF}

  {$IF DEFINED(DARWIN)}
  if FileExists('/etc/paths') and ContainsText(GetFileContent('/etc/paths'), LFolder) then
    Result := Result + ['remove the line ' + LFolder + ' from /etc/paths (needs sudo)'];
  {$ENDIF}
end;

procedure OutputRecommendedInstall(ABuilder: ICommandBuilder);
begin
  {$IF DEFINED(DARWIN) OR DEFINED(CPUAARCH64)}
  // there is no release binary for this platform
  OutputInfo(ABuilder, 'Install', 'there is no pasc release binary for this platform yet, build it from source:');
  OutputInfo(ABuilder, '', README_URL);
  {$ELSE}
  OutputInfo(ABuilder, 'Install', 'with mise (https://mise.jdx.dev), which also upgrades and uninstalls it:');
  OutputInfo(ABuilder, '', 'mise use -g github:laprado/pasc');
  OutputInfo(ABuilder, 'Manual', 'download pasc-' + {$IF DEFINED(WINDOWS)}'windows'{$ELSE}'linux'{$ENDIF} +
    '-amd64.zip from ' + RELEASES_URL + ',');
  OutputInfo(ABuilder, '', 'check it against the checksums file of the release and extract it to a folder in the PATH');
  OutputInfo(ABuilder, 'Details', README_URL);
  {$ENDIF}
end;

procedure InstallCommand(ABuilder: ICommandBuilder);
var
  LStep: string;
  LSteps: TArray<string>;
begin
  OutputError(ABuilder, 'Deprecated',
    'pasc install no longer installs pasc or changes the PATH, use a package manager instead.');
  OutputRecommendedInstall(ABuilder);

  LSteps := OldInstallCleanupSteps(GetUserDir);
  if Length(LSteps) > 0 then
  begin
    OutputInfo(ABuilder, 'Cleanup', 'an install made by a previous pasc install was found, to remove it:');
    for LStep in LSteps do
      OutputInfo(ABuilder, '', '- ' + LStep);
  end;

  // nothing was installed, so scripts relying on this command notice it
  ExitCode := 1;
end;

procedure Registry(ABuilder: ICommandBuilder);
begin
  ABuilder
    .AddCommand(
      'install',
      'deprecated: shows how to install pasc and how to remove an old install.'#13#10 +
      'It no longer copies pasc or changes the PATH, which was unreliable. Use a package '#13#10 +
      'manager instead, like mise: mise use -g github:laprado/pasc'#13#10 +
      'Ex: ' + ABuilder.ExeName + ' install',
      @InstallCommand,
      [ccNoParameters]);
end;

end.
