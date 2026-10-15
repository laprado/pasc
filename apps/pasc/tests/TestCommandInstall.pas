unit TestCommandInstall;

{$MODE DELPHI}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpcunit,
  testregistry,
  Command.Interfaces,
  Command.Builder;

type

  TTestCommandInstall= class(TTestCase)
  private
    FBuilder: ICommandBuilder;
    FExeName: string;
    FHomeDir: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestInstallCommandRegistry;
    procedure TestInstallCommandIsDeprecated;
    procedure TestInstallCommandChangesNothing;
    procedure TestOldInstallCleanupStepsNone;
    procedure TestOldInstallCleanupSteps;
  end;

implementation

uses
  StrUtils,
  MockCommandBuilder,
  Command.Install,
  Utils.IO;

procedure TTestCommandInstall.SetUp;
begin
  FExeName := ExtractFileName(ParamStr(0));
  FBuilder := TCommandBuilder.Create(FExeName);
  MockSetup(FBuilder);
  Command.Install.Registry(FBuilder);

  // a fake home: the old install command changed the real one, these tests must not
  FHomeDir := ConcatPaths([GetTempDir, '.TestCommandInstall', TestName]);
  ForceDirectories(FHomeDir);
  ExitCode := 0;
end;

procedure TTestCommandInstall.TearDown;
begin
  ExitCode := 0;
end;

procedure TTestCommandInstall.TestInstallCommandRegistry;
begin
  AssertEquals('install', FBuilder.Commands[0].Name);
end;

procedure TTestCommandInstall.TestInstallCommandIsDeprecated;
var
  LExitCode: Integer;
begin
  FBuilder.UseArguments(['install']);
  FBuilder.Parse;

  InstallCommand(FBuilder);
  LExitCode := ExitCode;
  ExitCode := 0;

  AssertTrue('should say it is deprecated. Check: ' + MockOutputCaptured, ContainsText(MockOutputCaptured, 'Deprecated'));
  AssertTrue('should point to the install instructions', ContainsText(MockOutputCaptured, 'github.com/laprado/pasc'));
  {$IF NOT (DEFINED(DARWIN) OR DEFINED(CPUAARCH64))}
  AssertTrue('should recommend mise', ContainsText(MockOutputCaptured, 'mise use -g github:laprado/pasc'));
  {$ENDIF}
  AssertEquals('nothing is installed, so the exit code is 1', 1, LExitCode);
end;

procedure TTestCommandInstall.TestInstallCommandChangesNothing;
var
  LFolder: string;
  LExisted: Boolean;
begin
  LFolder := ConcatPaths([GetUserDir, '.' + ChangeFileExt(FExeName, '')]);
  LExisted := DirectoryExists(LFolder);
  FBuilder.UseArguments(['install']);
  FBuilder.Parse;

  InstallCommand(FBuilder);

  // the old command created this folder, named after the running executable
  AssertEquals('no install folder should be created in the home', LExisted, DirectoryExists(LFolder));
end;

procedure TTestCommandInstall.TestOldInstallCleanupStepsNone;
begin
  AssertEquals('a home without an old install has nothing to clean', 0,
    Length(OldInstallCleanupSteps(FHomeDir)));
end;

procedure TTestCommandInstall.TestOldInstallCleanupSteps;
var
  LSteps: string;
begin
  ForceDirectories(ConcatPaths([FHomeDir, '.pasc']));
  SaveFileContent(ConcatPaths([FHomeDir, '.profile']),
    'export EDITOR=vi' + LineEnding + 'export PATH=$PATH:' + ConcatPaths([FHomeDir, '.pasc']) + LineEnding);

  LSteps := string.Join(LineEnding, OldInstallCleanupSteps(FHomeDir));

  AssertTrue('the folder should be listed. Check: ' + LSteps,
    ContainsText(LSteps, 'remove the folder ' + ConcatPaths([FHomeDir, '.pasc'])));
  {$IF NOT DEFINED(WINDOWS)}
  AssertTrue('the profile line should be listed. Check: ' + LSteps,
    ContainsText(LSteps, 'export PATH=$PATH:' + ConcatPaths([FHomeDir, '.pasc'])));
  {$ENDIF}
end;

initialization
  RegisterTest(TTestCommandInstall);

end.
