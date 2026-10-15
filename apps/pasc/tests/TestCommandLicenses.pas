unit TestCommandLicenses;

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

  TTestCommandLicenses = class(TTestCase)
  private
    FBuilder: ICommandBuilder;
    function RepositoryFile(const AName: string): string;
  protected
    procedure SetUp; override;
  published
    procedure TestLicensesCommandRegistry;
    procedure TestLicensesCommandOutput;
    procedure TestEmbeddedLicenseIsCurrent;
    procedure TestEmbeddedNoticesAreCurrent;
  end;

implementation

uses
  StrUtils,
  MockCommandBuilder,
  Command.Licenses,
  Utils.IO,
  Utils.Resources;

function NormalizeLineBreaks(const AText: string): string;
begin
  Result := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
end;

function TTestCommandLicenses.RepositoryFile(const AName: string): string;
begin
  // the test executable is in apps/pasc/tests
  Result := ExpandFileName(ConcatPaths([ExtractFilePath(ParamStr(0)), '..', '..', '..', AName]));
end;

procedure TTestCommandLicenses.SetUp;
begin
  FBuilder := TCommandBuilder.Create(ExtractFileName(ParamStr(0)));
  MockSetup(FBuilder);
  Command.Licenses.Registry(FBuilder);
end;

procedure TTestCommandLicenses.TestLicensesCommandRegistry;
begin
  AssertEquals('licenses', FBuilder.Commands[0].Name);
end;

procedure TTestCommandLicenses.TestLicensesCommandOutput;
begin
  FBuilder.UseArguments(['licenses']);
  FBuilder.Parse;

  LicensesCommand(FBuilder);

  AssertTrue('should show the pasc license. Check: ' + MockOutputCaptured,
    ContainsText(MockOutputCaptured, 'MIT License'));
  AssertTrue('should show the pascli notice', ContainsText(MockOutputCaptured, 'pascli'));
  AssertTrue('should list the tools that are not distributed', ContainsText(MockOutputCaptured, 'boss'));
end;

procedure TTestCommandLicenses.TestEmbeddedLicenseIsCurrent;
begin
  AssertEquals('pasc.lrs is outdated, run resources/compile.sh',
    NormalizeLineBreaks(GetFileContent(RepositoryFile('LICENSE'))),
    NormalizeLineBreaks(GetResource('LICENSE')));
end;

procedure TTestCommandLicenses.TestEmbeddedNoticesAreCurrent;
begin
  AssertEquals('pasc.lrs is outdated, run resources/compile.sh',
    NormalizeLineBreaks(GetFileContent(RepositoryFile('THIRD-PARTY-NOTICES.md'))),
    NormalizeLineBreaks(GetResource('THIRD-PARTY-NOTICES')));
end;

initialization
  RegisterTest(TTestCommandLicenses);

end.
