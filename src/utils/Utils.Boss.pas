/// <summary> Unit which contains functions to clean up the output of the boss dependency
/// manager before showing it to the user.
///
/// On platforms other than Windows boss tries to install and build bpl-identifier, an internal
/// Delphi-only tool, which always fails and floods the output with errors that have nothing to
/// do with a free pascal project.
/// </summary>
unit Utils.Boss;

{$MODE DELPHI}{$H+}

interface

  /// <summary> Removes ANSI escape sequences (colors and cursor control) from a text. </summary>
  /// <param name="AText"> Text with ANSI escape sequences. </param>
  function StripAnsi(const AText: string): string;

  /// <summary> Returns the boss output without ANSI escape sequences. If AFilterDelphi is true
  /// the lines produced by the Delphi-only internal tools are also removed, and ANoiseFound
  /// returns true if any of them was found. </summary>
  /// <param name="AOutput"> Raw output of a boss command. </param>
  /// <param name="AFilterDelphi"> Removes the Delphi-only noise. </param>
  /// <param name="ANoiseFound"> Returns true if Delphi-only noise was removed. </param>
  function FilterBossOutput(const AOutput: string; const AFilterDelphi: Boolean;
    out ANoiseFound: Boolean): string;

implementation

uses
  Classes,
  SysUtils,
  StrUtils;

const
  DELPHI_NOISE: array[0..6] of string = (
    'bpl-identifier',
    'not implemented on this platform',
    'no Delphi installation found',
    'rsvars.bat',
    'Cannot install global packages on this platform',
    'Adding path ',
    'Please restart your console');

  // boss progress lines, only removed when they belong to the Delphi-only tools
  BOSS_PROGRESS: array[0..4] of string = (
    'Analyzing dependencies',
    'dependencies:',
    'packages:',
    'Updating library path',
    'Installation completed successfully');

function StripAnsi(const AText: string): string;
var
  I, LLength: Integer;
begin
  Result := '';
  I := 1;
  LLength := Length(AText);
  while I <= LLength do
  begin
    if (AText[I] = #27) and (I < LLength) and (AText[I + 1] = '[') then
    begin
      // CSI sequence: ESC [ parameters final byte (@ to ~)
      Inc(I, 2);
      while (I <= LLength) and not (AText[I] in ['@'..'~']) do
        Inc(I);
      Inc(I);
    end
    else
    begin
      Result := Result + AText[I];
      Inc(I);
    end;
  end;
end;

function ContainsAny(const AText: string; const AValues: array of string): Boolean;
var
  LValue: string;
begin
  Result := False;
  for LValue in AValues do
    if ContainsText(AText, LValue) then
      Exit(True);
end;

function FilterBossOutput(const AOutput: string; const AFilterDelphi: Boolean;
  out ANoiseFound: Boolean): string;
var
  LLines, LResult: TStringList;
  LLine: string;
  I: Integer;
begin
  ANoiseFound := False;
  LLines := TStringList.Create;
  LResult := TStringList.Create;
  try
    LLines.Text := StripAnsi(AOutput);
    for LLine in LLines do
    begin
      if AFilterDelphi and ContainsAny(LLine, DELPHI_NOISE) then
      begin
        ANoiseFound := True;
        Continue;
      end;
      LResult.Add(LLine);
    end;

    if ANoiseFound then
      for I := LResult.Count - 1 downto 0 do
        if (Trim(LResult[I]) = '') or ContainsAny(LResult[I], BOSS_PROGRESS) then
          LResult.Delete(I);

    Result := TrimRight(LResult.Text);
  finally
    LLines.Free;
    LResult.Free;
  end;
end;

end.
