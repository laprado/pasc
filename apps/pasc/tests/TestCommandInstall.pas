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
    FAppFolder: string;
    FAppFile: string;
    FCurrentDir: string;

    function GetPathVariable: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestInstallCommandRegistry;
    procedure TestCreateFolder;
    procedure TestCopyApp;
    procedure TestUpdateEnvironmentPathLinux;
    procedure TestUpdateEnvironmentPathMacos;
    procedure TestUpdateEnvironmentPathWindows;
    procedure TestInstallCommandMain;
  end;

implementation

uses
  Resources,
  StrUtils,
  MockCommandBuilder,
  Command.Install,
  Utils.IO,
  Utils.Shell;

procedure TTestCommandInstall.SetUp;
begin
  FCurrentDir := GetCurrentDir;
  FExeName := ExtractFileName(ParamStr(0));
  FBuilder := TCommandBuilder.Create(FExeName);
  MockSetup(FBuilder);
  Command.Install.Registry(FBuilder);

  FAppFolder := ConcatPaths([GetUserDir, '.' + ChangeFileExt(FExeName, '')]);
  FAppFile := ConcatPaths([FAppFolder, FExeName]);

  if FileExists(FAppFile) then
    DeleteFile(FAppFile);
  if DirectoryExists(FAppFolder) then
    RemoveDir(FAppFolder);
end;

procedure TTestCommandInstall.TearDown;
begin
  SetCurrentDir(FCurrentDir);
end;

function TTestCommandInstall.GetPathVariable: string;
var
  LExitCode: Integer = 0;
begin
  {$IFDEF WINDOWS}
  SaveFileContent(ConcatPaths([GetTempDir, 'get-path.ps1']), GetTestResource('get-path-ps1'));
  Result := ShellCommand('powershell', [ConcatPaths([GetTempDir, 'get-path.ps1'])], LExitCode);
  {$ENDIF}
  {$IFDEF LINUX}
  Result := GetFileContent(ConcatPaths([GetUserDir, '.profile']));
  {$ENDIF}
  {$IFDEF Darwin}
  Result := GetFileContent(ConcatPaths(['/etc', 'paths']));
  {$ENDIF}
end;

procedure TTestCommandInstall.TestInstallCommandRegistry;
begin
  AssertEquals('install', FBuilder.Commands[0].Name);
end;

procedure TTestCommandInstall.TestCreateFolder;
var
  LCreatedFolder: string = '';
begin
  CreateFolder(FBuilder, LCreatedFolder);
  AssertTrue('Folder ' + LCreatedFolder + ' should exist', DirectoryExists(LCreatedFolder));
end;

procedure TTestCommandInstall.TestCopyApp;
var
  LCreatedFolder: string = '';
  LTargetFile: string;
begin
  CreateFolder(FBuilder, LCreatedFolder);
  CopyApp(FBuilder, LCreatedFolder);
  LTargetFile := ConcatPaths([LCreatedFolder, FExeName]);
  AssertTrue('App should exist on app folder', FileExists(LTargetFile));
end;

procedure TTestCommandInstall.TestUpdateEnvironmentPathLinux;
{$IFDEF LINUX}
var
  LOutput: string;
  LCreatedFolder: string = '';
{$ENDIF}
begin
  {$IFDEF LINUX}
  CreateFolder(FBuilder, LCreatedFolder);
  UpdateEnvironmentPathLinux(FBuilder, FAppFolder);
  LOutput := GetPathVariable;
  AssertTrue('should contain app folder: ' + FAppFolder + ' in path env variable: ' + LOutput, ContainsText(LOutput, FAppFolder));
  {$ENDIF}
end;

procedure TTestCommandInstall.TestUpdateEnvironmentPathMacos;
{$IF DEFINED(Darwin)}
var
  LOutput: string;
  LCreatedFolder: string = '';
{$ENDIF}
begin
  {$IF DEFINED(Darwin)}
  CreateFolder(FBuilder, LCreatedFolder);
  UpdateEnvironmentPathMacos(FBuilder, FAppFolder);
  LOutput := GetPathVariable;
  AssertTrue('should contain app folder in path', ContainsText(LOutput, FAppFolder));
  {$ENDIF}
end;

procedure TTestCommandInstall.TestUpdateEnvironmentPathWindows;
var
  LOutput: string;
  LCreatedFolder: string = '';
begin
  {$IFDEF WINDOWS}
  CreateFolder(FBuilder, LCreatedFolder);
  UpdateEnvironmentPathWindows(FBuilder, FAppFolder);
  LOutput := GetPathVariable;
  AssertTrue('should contain app folder in path', ContainsText(LOutput, FAppFolder));
  {$ENDIF}
end;

procedure TTestCommandInstall.TestInstallCommandMain;
begin
  InstallCommand(FBuilder);
  
  // assert
  AssertTrue('AppFolder should exist: ' + FAppFolder, DirectoryExists(FAppFolder));
  AssertTrue('AppFile should exist: ' + FAppFolder, FileExists(FAppFile));
  AssertTrue(
    'Path environment variable should contain FAppFolder', 
    ContainsText(GetPathVariable, FAppFolder));
end;

initialization
  RegisterTest(TTestCommandInstall);
  
end.

