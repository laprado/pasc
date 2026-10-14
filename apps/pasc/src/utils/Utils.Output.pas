/// <summary> Unit which contains functions to display colored output.
/// </summary>
unit Utils.Output;

{$MODE DELPHI}{$H+}

interface

uses
  Command.Interfaces;

  /// <summary> Outputs a text in console with color from CommandBuilder theme color.
  /// </summary>
  /// <param name="ATitle">Title highlighted using the theme's Title color property</param>
  /// <param name="AText">information description without accent color, uses the theme's Other 
  /// color property </param>
  procedure OutputInfo(ABuilder: ICommandBuilder; const ATitle, AText: string; const ABreakLine: Boolean = True);
  
  /// <summary> Outputs a error message in console with color from CommandBuilder theme color.
  /// </summary>
  /// <param name="ATitle">Title highlighted using the theme's Title color property</param>
  /// <param name="AText">information description with accent color, uses the theme's Error 
  /// color property </param>
  procedure OutputError(ABuilder: ICommandBuilder; const ATitle, AError: string);
  
implementation

uses
  StrUtils;

procedure OutputInfo(ABuilder: ICommandBuilder; const ATitle, AText: string; const ABreakLine: Boolean = True);
begin
  ABuilder.OutputColor(PadLeft(ATitle + ' ', 13), ABuilder.ColorTheme.Title);
  ABuilder.OutputColor(AText + IfThen(ABreakLine, #13#10, ''), ABuilder.ColorTheme.Other);
end;

procedure OutputError(ABuilder: ICommandBuilder; const ATitle, AError: string);
begin
  ABuilder.OutputColor(PadLeft(ATitle + ' ', 13), ABuilder.ColorTheme.Title);
  ABuilder.OutputColor(AError + #13#10, ABuilder.ColorTheme.Error);
end;

end.