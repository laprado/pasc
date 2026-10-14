/// <summary> This unit contains procedures to configure and execute a command to clean folders. 
/// </summary>
unit Command.Clean;

{$MODE DELPHI}{$H+}

interface

uses
  Command.Interfaces;

  /// <summary> This command recursively from the current path searches for folders named 
  /// "lib" and "backup" to remove them. However, before removing them, it asks the user 
  /// for confirmation. Confirmation that can be suppressed if the --force option is given.
  /// </summary>
  /// <param name="ABuilder"> Command builder that will provide the output callback to print
  /// info about the command execution </param>
  procedure CleanCommand(ABuilder: ICommandBuilder);

  /// <summary> Registry a clean command using the command builder from pascli, also sets. 
  /// options and usage help info. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// registry the command. </param>
  procedure Registry(ABuilder: ICommandBuilder);

  {$IF DEFINED(TESTAPP)}
  
  /// <summary> asks the user for confirmation to proceed with the operation, as well as 
  /// evaluates whether the option provided is valid or not, repeating the operation until 
  /// obtaining a valid answer.
  /// </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used 
  /// output and caputre input from user. </param>
  procedure CheckAnswer(ABuilder: ICommandBuilder);

  /// <summary> Deletes a folder an its content. Asks user confirmation before delete 
  /// the folder. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used 
  /// output and caputre input from user. </param>
  procedure DeleteFolder(ABuilder: ICommandBuilder; const ACurrentDir, AFolder: string);

  {$ENDIF}

var
  AnsweredAll: boolean;  

implementation

uses
  SysUtils,
  StrUtils,
  FileUtil,
  Utils.Output,
  Command.Colors;

const
  TARGETS: array [0..1] of AnsiString = ('lib', 'backup');
  IGNORE: array [0..3] of AnsiString = ('.', '..', '.git', '.vscode');

//{$IF NOT DEFINED(TESTAPP)}
//var
//  AnsweredAll: boolean;
//{$ENDIF}

procedure CheckAnswer(ABuilder: ICommandBuilder);
var
  LInput: string;
  LKey: char;
  LInvalidKey: Boolean;
begin
  if AnsweredAll then
    Exit;
  
  OutputInfo(ABuilder, 'Confirmation', 'Are you sure? [c]ancel [y]es, [a]ll: ', False);
  LInvalidKey := True;
  while LInvalidKey do
  begin
    LInput := ABuilder.InputLn;

    if Length(LInput) <> 1 then
      LKey := #0
    else
      LKey := LInput[1];

    if (LKey = 'c') then
      //WriteLn; //for linux/macos?
      raise Exception.Create('Cleaning aborted.');

    AnsweredAll := LKey = 'a';
    LInvalidKey := not AnsiMatchText(LKey, ['a', 'y', 'c']);

    if LInvalidKey then 
      OutputInfo(ABuilder, 'Invalid key', 'Are you sure? [c]ancel, [y]es, [a]ll: ', False);
  end;    
end;

procedure DeleteFolder(ABuilder: ICommandBuilder; const ACurrentDir, AFolder: string);
var
  LCurrentDir: string;
begin
  OutputInfo(ABuilder, 'folder', 'will be deleted: ' + IncludeTrailingPathDelimiter(ACurrentDir) + AFolder);
  CheckAnswer(ABuilder);
  LCurrentDir := ConcatPaths([ACurrentDir, AFolder]);
  if DeleteDirectory(LCurrentDir, True) then 
  begin
    RemoveDir(LCurrentDir);
    OutputError(ABuilder, 'folder', 'deleted');
  end;
end;

procedure CleanDirectory(ABuilder: ICommandBuilder; const ACurrentDir: string);
var
  LSearch: TSearchRec;
begin
  if FindFirst(ConcatPaths([ACurrentDir, AllFilesMask]), faDirectory, LSearch) <> 0 then
    exit;

  try
    repeat
      if ((LSearch.Attr and faDirectory) <> 0) and 
         (not AnsiMatchText(LSearch.Name, IGNORE)) then
      begin
        if AnsiMatchText(LSearch.Name, TARGETS) then
          DeleteFolder(ABuilder, ACurrentDir, LSearch.Name)
        else
          CleanDirectory(ABuilder, ConcatPaths([ACurrentDir, LSearch.Name]));
      end;
    until FindNext(LSearch) <> 0;
  finally
    FindClose(LSearch);
  end;
end;

procedure CleanCommand(ABuilder: ICommandBuilder);
begin
  AnsweredAll := ABuilder.CheckOption('f');

  OutputInfo(ABuilder, 'Starting', 'to clean the current path: ' + GetCurrentDir);
  try
    CleanDirectory(ABuilder, GetCurrentDir);
    OutputInfo(ABuilder, 'Cleanning', 'was finished');
  except 
    on E: Exception do
    begin
      if not SameText(E.Message, 'Cleaning aborted.') then
        raise;
      OutputError(ABuilder, 'error', E.MEssage);
    end;
  end;
end;

procedure Registry(ABuilder: ICommandBuilder);
begin
  ABuilder
    .AddCommand(
      'clean',
      'Removes the following folders lib, backup, to make possible a clean build.'#13#10 +
      'Ex: ' + ABuilder.ExeName + ' clean',
      @CleanCommand,
      [ccNoParameters])
      .AddOption('f', 'force', 'do not ask for confirmation before delete.', []);
end;

end.