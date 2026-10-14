program pasc;

{$MODE DELPHI}{$H+}

uses
  {$IFDEF UNIX}
  cmem,
  cthreads,
  {$ENDIF}
  Command.Interfaces,
  Command.App,
  Command.Add,
  Command.Build,
  Command.Clean,
  Command.Colors,
  Command.Deps,
  Command.Install,
  Command.New,
  Command.Test,
  Command.Usage,
  Command.Version,
  Command.Watch;

var
  PascApp: TCommandApp;

{$R *.res}

/// <summary> pascli has no -h/--help options, so "pasc --help" and "pasc <command> --help"
/// are translated to "pasc help" and "pasc help <command>". Returns false if no help option
/// was provided. </summary>
function HelpArguments(out AArgs: TArray<string>): Boolean;
var
  I: Integer;
  LCommand: string = '';
begin
  Result := False;
  for I := 1 to ParamCount do
    if (ParamStr(I) = '-h') or (ParamStr(I) = '--help') then
      Result := True
    else if (LCommand = '') and (Copy(ParamStr(I), 1, 1) <> '-') then
      LCommand := ParamStr(I);

  AArgs := ['help'];
  if LCommand <> '' then
    AArgs := AArgs + [LCommand];
end;

var
  HelpArgs: TArray<string>;

begin
  PascApp := TCommandApp.Create(nil);
  try
    PascApp.Title := 'Object pascal CLI tool for use with vscode.';
    PascApp.CommandBuilder.UseShortDescriptions := True;
    DarkColorTheme.Title := LightBlue;
    PascApp.CommandBuilder.ColorTheme := DarkColorTheme;

    Command.Add.Registry(PascApp.CommandBuilder);
    Command.Build.Registry(PascApp.CommandBuilder);
    Command.Clean.Registry(PascApp.CommandBuilder);
    Command.Deps.Registry(PascApp.CommandBuilder);
    Command.Usage.Registry(PascApp.CommandBuilder);
    Command.Install.Registry(PascApp.CommandBuilder);
    Command.New.Registry(PascApp.CommandBuilder);
    Command.Test.Registry(PascApp.CommandBuilder);
    Command.Version.Registry(PascApp.CommandBuilder);
    Command.Watch.Registry(PascApp.CommandBuilder);

    PascApp.CommandBuilder.AddArgument('project file name', acOptional);

    if HelpArguments(HelpArgs) then
      PascApp.CommandBuilder.UseArguments(HelpArgs);

    PascApp.Run;
  finally
    PascApp.Free;
  end;
end.
