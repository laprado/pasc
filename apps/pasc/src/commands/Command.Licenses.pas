/// <summary> This unit contains the licenses command, which shows the license of pasc and the
/// notices of the third-party software included in the executable, so they go with it even
/// when it is copied without the release zip. The texts are the LICENSE and
/// THIRD-PARTY-NOTICES.md files of the repository, embedded by resources/compile.sh.
/// </summary>
unit Command.Licenses;

{$MODE DELPHI}{$H+}

interface

uses
  Command.Interfaces;

  /// <summary> Shows the pasc license followed by the third-party notices. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output the texts. </param>
  procedure LicensesCommand(ABuilder: ICommandBuilder);

  /// <summary> Registry the licenses command using the command builder from pascli, also sets
  /// usage help info. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// registry the command. </param>
  procedure Registry(ABuilder: ICommandBuilder);

implementation

uses
  Utils.Resources;

procedure LicensesCommand(ABuilder: ICommandBuilder);
begin
  ABuilder.Output(GetResource('LICENSE') + #13#10);
  ABuilder.Output(GetResource('THIRD-PARTY-NOTICES') + #13#10);
end;

procedure Registry(ABuilder: ICommandBuilder);
begin
  ABuilder
    .AddCommand(
      'licenses',
      'shows the pasc license and the notices of the third-party software.'#13#10 +
      'The notices list the software included in the executable, the resources '#13#10 +
      'embedded in it and the tools pasc runs but does not distribute, like '#13#10 +
      'Free Pascal, Lazarus, boss, git, PasDoc and kcov.'#13#10 +
      'Ex: ' + ABuilder.ExeName + ' licenses',
      @LicensesCommand,
      [ccNoParameters]);
end;

end.
