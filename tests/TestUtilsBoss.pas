unit TestUtilsBoss;

{$MODE DELPHI}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpcunit,
  testregistry;

type

  TTestUtilsBoss= class(TTestCase)
  private
    function SampleOutput: string;
  published
    procedure TestStripAnsi;
    procedure TestFilterBossOutputRemovesDelphiNoise;
    procedure TestFilterBossOutputKeepsOtherLines;
    procedure TestFilterBossOutputWithoutDelphiFilter;
    procedure TestFilterBossOutputWithoutNoise;
  end;

implementation

uses
  StrUtils,
  Utils.Boss;

const
  ESC = #27;

function TTestUtilsBoss.SampleOutput: string;
begin
  // based on the output of boss 3.0.17 "boss init --quiet" on linux
  Result :=
    ESC + '[33m' + ESC + '[33m⚠️ getDelphiVersionFromRegistry not implemented on this platform' + ESC + '[0m'#10 +
    ESC + '[33m' + ESC + '[0m' + ESC + '[0m🔍 Analyzing dependencies...'#10 +
    '✨ Installing 2 dependencies:'#10 +
    ESC + '[1G' + ESC + '[2K' + ESC + '[1A' + ESC + '[2K' + ESC + '[1G' + ESC + '[92m📦' + ESC + '[0m ' +
      ESC + '[1mgithub_com_hashload_bpl-identifier' + ESC + '[0m' + ESC + '[92mInstalled' + ESC + '[0m'#10 +
    ESC + '[1G' + ESC + '[2K' + ESC + '[1A' + ESC + '[2K' + ESC + '[1G' + ESC + '[91m❌' + ESC + '[0m ' +
      ESC + '[1mgithub_com_foo_bar' + ESC + '[0m' + ESC + '[91mFailed' + ESC + '[0m clone error'#10 +
    '♻️ Updating library path...'#10 +
    ESC + '[33m⚠️ ''updateGlobalLibraryPath'' not implemented on this platform' + ESC + '[0m'#10 +
    ESC + '[33mCompiler selection failed: no Delphi installation found. Falling back to default.' + ESC + '[0m'#10 +
    '⚙️ Compiling 1 packages:'#10 +
    ESC + '[91m    ❌ Error on read rsvars.bat' + ESC + '[0m'#10 +
    ESC + '[32m✅ Installation completed successfully!' + ESC + '[0m'#10 +
    ESC + '[91m❌ Cannot install global packages on this platform, only build and install local' + ESC + '[0m'#10 +
    '📄 Adding path ./modules/.bin'#10 +
    '📄 Adding path /home/user/.boss/env/dcp'#10 +
    ESC + '[33m⚠️ Please restart your console after complete.' + ESC + '[0m'#10 +
    ESC + '[33m' + ESC + '[0m' + ESC + '[0m'#10 +
    '{'#10 +
    '  "name": "sample"'#10 +
    '}'#10;
end;

procedure TTestUtilsBoss.TestStripAnsi;
begin
  AssertEquals(
    'colors and cursor control should be removed',
    '📦 github_com_foo_bar Installed',
    StripAnsi(
      ESC + '[1G' + ESC + '[2K' + ESC + '[1A' + ESC + '[1B' + ESC + '[92m📦' + ESC + '[0m ' +
      ESC + '[1mgithub_com_foo_bar ' + ESC + '[0mInstalled'));
end;

procedure TTestUtilsBoss.TestFilterBossOutputRemovesDelphiNoise;
var
  LOutput: string;
  LNoiseFound: Boolean;
begin
  LOutput := FilterBossOutput(SampleOutput, True, LNoiseFound);

  AssertTrue('noise should be detected', LNoiseFound);
  AssertFalse('should not contain escape sequences', ContainsText(LOutput, ESC));
  AssertFalse('should not contain bpl-identifier', ContainsText(LOutput, 'bpl-identifier'));
  AssertFalse('should not contain registry warnings', ContainsText(LOutput, 'not implemented'));
  AssertFalse('should not contain rsvars.bat', ContainsText(LOutput, 'rsvars.bat'));
  AssertFalse('should not contain Delphi detection', ContainsText(LOutput, 'no Delphi installation'));
  AssertFalse('should not contain global packages error', ContainsText(LOutput, 'global packages'));
  AssertFalse('should not contain the paths', ContainsText(LOutput, 'Adding path'));
  AssertFalse('should not ask to restart', ContainsText(LOutput, 'restart your console'));
  AssertFalse('should not contain progress lines', ContainsText(LOutput, 'Installation completed'));
end;

procedure TTestUtilsBoss.TestFilterBossOutputKeepsOtherLines;
var
  LOutput: string;
  LNoiseFound: Boolean;
begin
  LOutput := FilterBossOutput(SampleOutput, True, LNoiseFound);

  AssertTrue(
    'real dependency errors should be kept',
    ContainsText(LOutput, '❌ github_com_foo_barFailed clone error'));
  AssertTrue(
    'boss.json content should be kept',
    ContainsText(LOutput, '"name": "sample"'));
end;

procedure TTestUtilsBoss.TestFilterBossOutputWithoutDelphiFilter;
var
  LOutput: string;
  LNoiseFound: Boolean;
begin
  LOutput := FilterBossOutput(SampleOutput, False, LNoiseFound);

  AssertFalse('noise should not be reported', LNoiseFound);
  AssertFalse('should not contain escape sequences', ContainsText(LOutput, ESC));
  AssertTrue('should keep bpl-identifier', ContainsText(LOutput, 'bpl-identifier'));
  AssertTrue('should keep progress lines', ContainsText(LOutput, 'Installation completed'));
end;

procedure TTestUtilsBoss.TestFilterBossOutputWithoutNoise;
var
  LOutput: string;
  LNoiseFound: Boolean;
begin
  LOutput := FilterBossOutput(
    '🔍 Analyzing dependencies...'#10 + ESC + '[32m✅ Installation completed successfully!' + ESC + '[0m'#10,
    True, LNoiseFound);

  AssertFalse('noise should not be reported', LNoiseFound);
  AssertTrue('should keep progress lines', ContainsText(LOutput, 'Installation completed'));
end;

initialization
  RegisterTest(TTestUtilsBoss);

end.
