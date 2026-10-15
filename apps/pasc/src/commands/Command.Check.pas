/// <summary> This unit contains procedures to configure and execute a command to check the
/// projects and packages for folders and units that lazbuild would not find.
/// </summary>
unit Command.Check;

{$MODE DELPHI}{$H+}

interface

uses
  Command.Interfaces;

  /// <summary> This command checks every member of the workspace, or the project in the current
  /// folder, and its test project: folders with units that are not in the search paths of every
  /// build mode, search paths that do not exist, and for a package the units that are not in
  /// its files and the files that no longer exist. In a workspace it also checks the modules
  /// folder: out of place, missing, or without the modules of boss-lock.json. Each problem is a warning with the line to add or remove, and the exit code
  /// is 1 when there is any. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output the warnings. </param>
  procedure CheckCommand(ABuilder: ICommandBuilder);

  /// <summary> Checks the modules folder of the workspace, then every member and its test
  /// project, and outputs one warning per problem. Returns the number of warnings. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output the warnings. </param>
  /// <param name="AWorkspaceDir"> Workspace root folder. </param>
  function CheckWorkspace(ABuilder: ICommandBuilder; const AWorkspaceDir: string): Integer;

  /// <summary> Prepares the members of the workspace to be built: adds the src folders of each
  /// app to its search paths, then outputs the warnings of CheckWorkspace. Used by pasc build and
  /// pasc test before calling lazbuild, so a problem shows up before the first member is built.
  /// </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output the updated files and the warnings. </param>
  /// <param name="AWorkspaceDir"> Workspace root folder. </param>
  procedure PrepareWorkspace(ABuilder: ICommandBuilder; const AWorkspaceDir: string);

  /// <summary> Registry a check command using the command builder from pascli. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// registry the command. </param>
  procedure Registry(ABuilder: ICommandBuilder);

implementation

uses
  SysUtils,
  StrUtils,
  Command.Build,
  Command.Deps,
  Utils.Check,
  Utils.Output,
  Utils.Workspace;

function OutputWarnings(ABuilder: ICommandBuilder; const AProjectFile, ABaseDir: string): Integer;
var
  LWarning: string;
  LWarnings: TArray<string>;
begin
  Result := 0;
  if (AProjectFile = '') or not FileExists(AProjectFile) then
    Exit;
  try
    LWarnings := CheckProject(AProjectFile, ABaseDir);
  except
    on E: Exception do
      LWarnings := [ExtractFileName(AProjectFile) + ' could not be checked: ' + E.Message];
  end;
  for LWarning in LWarnings do
    OutputError(ABuilder, 'Warning', LWarning);
  Result := Length(LWarnings);
end;

function CheckWorkspace(ABuilder: ICommandBuilder; const AWorkspaceDir: string): Integer;
var
  LMember: TWorkspaceMember;
  LMembers: TWorkspaceMembers;
  LMemberDirs, LWarnings: TArray<string>;
  LWarning: string;
begin
  // the modules first: a missing or moved modules folder explains the missing search paths
  LMembers := GetWorkspaceMembers(AWorkspaceDir);
  LMemberDirs := [];
  for LMember in LMembers do
    LMemberDirs := LMemberDirs + [LMember.Dir];
  try
    LWarnings := CheckWorkspaceModules(AWorkspaceDir, LMemberDirs);
  except
    on E: Exception do
      LWarnings := ['the modules of the workspace could not be checked: ' + E.Message];
  end;
  for LWarning in LWarnings do
    OutputError(ABuilder, 'Warning', LWarning);
  Result := Length(LWarnings);

  for LMember in LMembers do
  begin
    Inc(Result, OutputWarnings(ABuilder, LMember.ProjectFile, AWorkspaceDir));
    Inc(Result, OutputWarnings(ABuilder, GetMemberTestProject(LMember.Dir), AWorkspaceDir));
  end;
end;

procedure PrepareWorkspace(ABuilder: ICommandBuilder; const AWorkspaceDir: string);
var
  LMember: TWorkspaceMember;
begin
  for LMember in GetWorkspaceMembers(AWorkspaceDir) do
    SyncMemberSources(ABuilder, AWorkspaceDir, LMember);
  CheckWorkspace(ABuilder, AWorkspaceDir);
end;

procedure CheckCommand(ABuilder: ICommandBuilder);
var
  LWorkspaceDir, LProjectFile: string;
  LCount: Integer;
begin
  LWorkspaceDir := FindWorkspaceRoot(GetCurrentDir);
  if LWorkspaceDir <> '' then
    LCount := CheckWorkspace(ABuilder, LWorkspaceDir)
  else
  begin
    LProjectFile := FindProject(GetCurrentDir, '');
    if SameText(ExtractFileExt(LProjectFile), '.lpr') then
      LProjectFile := ChangeFileExt(LProjectFile, '.lpi');
    if not FileExists(LProjectFile) then
    begin
      OutputError(ABuilder, 'Error', 'No project or workspace found in the current folder.');
      ExitCode := 1;
      Exit;
    end;
    LCount := OutputWarnings(ABuilder, LProjectFile, GetCurrentDir);
    Inc(LCount, OutputWarnings(ABuilder, GetMemberTestProject(GetCurrentDir), GetCurrentDir));
  end;

  if LCount = 0 then
  begin
    OutputInfo(ABuilder, 'Check', 'no problems found');
    Exit;
  end;
  OutputInfo(ABuilder, 'Check', IntToStr(LCount) + IfThen(LCount = 1, ' problem', ' problems') + ' found');
  ExitCode := 1;
end;

procedure Registry(ABuilder: ICommandBuilder);
begin
  ABuilder
    .AddCommand(
      'check',
      'checks the projects and packages for units that lazbuild would not find.'#13#10 +
      'For every member of the workspace, or the project in the current folder,'#13#10 +
      'and its test project: folders with units missing from the search paths'#13#10 +
      'of a build mode, search paths that do not exist, and for a package the'#13#10 +
      'units missing from its files and the files that no longer exist.'#13#10 +
      'In a workspace it also checks the modules folder: out of place, missing,'#13#10 +
      'or without the modules recorded in boss-lock.json.'#13#10 +
      'Exits with 1 when there is any problem.'#13#10 +
      'In a workspace, pasc build and pasc test show the same warnings first.'#13#10 +
      'Ex: ' + ABuilder.ExeName + ' check',
      @CheckCommand,
      [ccNoParameters]);
end;

end.
