unit TestCommandBuild;

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

  TTestCommandBuild= class(TTestCase)
  private
    FBuilder: ICommandBuilder;
    FExeName: string;
    FWorkingFolder: string;
    FCurrentDir: string;

  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCommandBuildRegistry;    
    procedure TestCommandBuildBasic;
    procedure TestFindProject;
    procedure TestFindProjectFallbackToLpr;
    procedure TestCommandBuildDoesNotRequireArgument;
  end;

implementation

uses
  Resources,
  StrUtils,
  MockCommandBuilder,
  Command.Build,
  Utils.IO,
  Utils.Shell;

procedure TTestCommandBuild.SetUp;
begin
  FCurrentDir := GetCurrentDir;
  FExeName := ExtractFileName(ParamStr(0));
  FBuilder := TCommandBuilder.Create(FExeName);
  MockSetup(FBuilder);
  Command.Build.Registry(FBuilder);

  FWorkingFolder := ConcatPaths([GetTempDir, '.' + ChangeFileExt(FExeName, '')]);
end;

procedure TTestCommandBuild.TearDown;
begin
  SetCurrentDir(FCurrentDir);
end;

procedure TTestCommandBuild.TestCommandBuildRegistry;
begin
  AssertEquals('build', FBuilder.Commands[0].Name);
end;

procedure TTestCommandBuild.TestCommandBuildBasic;
begin
  // arrange
  FBuilder.UseArguments(['build']);
  FBuilder.Parse;

  // cannot call TestPasc again because it would produce recursive calls indenitely
  // so we need to change ShellCommand and check if it's being called.
  ShellExecute := @MockShell;
  BuildCommand(FBuilder);
    
  // assert
  AssertTrue(
    'Output should contain keyword: "lazbuild" ',
    ContainsText(MockOutputCaptured, 'lazbuild'));
  AssertTrue(
    'Output should contain keyword: "lazbuild" ',
    ContainsText(MockShellCapture, 'lazbuild'));
end;

procedure TTestCommandBuild.TestFindProject;
begin
  AssertEquals(
    ConcatPaths([ExtractFilePath(ParamStr(0)), 'TestPasc.lpi']),
    FindProject(ExtractFilePath(ParamStr(0)), ''));
end;

procedure TTestCommandBuild.TestFindProjectFallbackToLpr;
var
  LFolder: string;
begin
  LFolder := ConcatPaths([FWorkingFolder, 'build_lpr_only']);
  ForceDirectories(LFolder);
  SaveFileContent(ConcatPaths([LFolder, 'sample.lpr']), 'program sample;');

  AssertEquals(
    ConcatPaths([LFolder, 'sample.lpr']),
    FindProject(LFolder, ''));
end;

procedure TTestCommandBuild.TestCommandBuildDoesNotRequireArgument;
begin
  FBuilder.UseArguments(['build']);
  FBuilder.Parse;

  AssertEquals(
    'build without arguments should be valid',
    0, Length(FBuilder.Validate));
end;

initialization
  RegisterTest(TTestCommandBuild);
  
end.