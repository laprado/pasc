/// <summary> Unit which has a set of functions for manipulating files and their contents. 
/// It has some functions for content search as well.
/// </summary>
unit Utils.IO;

{$MODE DELPHI}{$H+}

interface

uses
  Classes,
  SysUtils,
  StrUtils;

  /// <summary> Get the contents of AFileName in string. </summary>
  /// <param AName="AFileName"> File name that will have its content returned </param>
  function GetFileContent(const AFileName: string): string;

  /// <summary> Get the contents of a JSON AFileName in string. Remove commented lines to make 
  /// possible do parse its content. Returns JSON content.</summary>
  /// <param AName="AFileName"> File name that will have its content returned </param>
  function GetJsonFileContentWithOutComments(const AFileName: string): string;

  /// <summary> Save AContent string in the provided file name. </summary>
  /// <param name="AFileName">Target file name, the file name will be replaced </param>
  /// <param name="AContent">Content string that will be saved on the file </param>
  procedure SaveFileContent(const AFileName, AContent: string);

  /// <summary> Returns first ocurrence of text in format line:1 (column is always 1).
  /// It is case insensitive search. 
  /// If not text is found the function returns an empty string.</summary>
  /// <param name="ACodeFile"> Should have have the file contents already loaded. </param>
  /// <param name="AText"> The text to be found </param>
  function FindInCodeFile(ACodeFile: TStringList; const AText: string): string;

  /// <summary>Recursively search for the first file from the specified path. 
  /// Returns the filename with the full path if it was found. </summary>
  /// <param name="ACurrentDir">Folder from which to search including subfolders</param>
  /// <param name="AFileName">Name of the file to be searched</param>
  function FindFile(const ACurrentDir, AFileName: string): string;

  /// <summary> From the current directory it tries to locate a lazarus project that contains
  /// a specific text. If AText is empty the first project found will be returned.
  /// Returns the project file name. </summary>
  /// <param name="ABuilder"> Command builder of the main application that will be used to
  /// output user instructions or to iteract with the user. </param>
  function FindProjectFile(const AProjectDir, AText: string): string;

  /// <summary> From the current directory it tries to locate a source file. Any file with 
  /// .pas or .pp extension will be considered as source file. 
  /// Returns the first occurence of a source file. Returns empty if not source file was found.</summary>
  /// <param name="AProjectDir"> Project path from which to search </param>
  function FindSourceFile(const AProjectDir: string): string;
  
implementation

function GetFileContent(const AFileName: string): string;
var
  LFile: TStringList = nil;
begin
  Result := '';
  LFile := TStringList.Create;
  try
    LFile.LoadFromFile(AFileName);
    Result := LFile.Text;
    LFile.Free;
  except
    on E: Exception do
    begin
      LFile.Free;
      raise;
    end;
  end;
end;

function GetJsonFileContentWithOutComments(const AFileName: string): string;
var
  LFile: TStringList = nil;
  I: Integer;
begin
  Result := '';
  LFile := TStringList.Create;
  try
    LFile.LoadFromFile(AFileName);

    for i := 0 to LFile.Count - 1 do
      if not (Pos('//', Trim(LFile[I])) = 1) then
        Result := Result + LFile[I];

    LFile.Free;
  except
    on E: Exception do
    begin
      LFile.Free;
      raise;
    end;
  end;
end;

procedure SaveFileContent(const AFileName, AContent: string);
var
  LFile: TStringList = nil;
begin
  LFile := TStringList.Create;
  try
    LFile.Text := AContent;
    LFile.SaveToFile(AFileName);
    LFile.Free;
  except
    on E: Exception do
    begin
      LFile.Free;
      raise;
    end;
  end;
end;

function FindInCodeFile(ACodeFile: TStringList; const AText: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to ACodeFile.Count - 1 do
    if ContainsText(ACodeFile.Strings[I], AText) then
      Exit(IntToStr(I + 1) + ':1');
end;

function FindFile(const ACurrentDir, AFileName: string): string;
var
  LSearch: TSearchRec;
  LFileFound: string;
begin
  LFileFound := ConcatPaths([ACurrentDir, AFileName]);
  if FileExists(LFileFound) then
    exit(LFileFound);
  LFileFound := '';

  if FindFirst(ConcatPaths([ACurrentDir, AllFilesMask]), faDirectory or faAnyFile, LSearch) = 0 then
    try
      repeat
        if ((LSearch.Attr and faDirectory) <> 0) and 
            (not AnsiMatchText(LSearch.Name, ['.', '..', '.git'])) then
        begin
          LFileFound := FindFile(ConcatPaths([ACurrentDir, LSearch.Name]), AFileName);
          if LFileFound <> '' then
            Exit(LFileFound);
        end;
      until FindNext(LSearch) <> 0;
    finally
      FindClose(LSearch);
    end;
  Result := '';
end;

function FindProjectFile(const AProjectDir, AText: string): string;
var
  LResult: TStringList;
  LSearch: TSearchRec;
  LCodeFile: string;
begin
  Result := '';
  if not DirectoryExists(AProjectDir) then
    Exit;

  LResult := TStringList.Create;
  try
    if FindFirst(ConcatPaths([AProjectDir, '*.lpr']), faAnyFile, LSearch) = 0 then
      repeat
        if ((LSearch.Attr and faAnyFile) <> 0) and (ExtractFileExt(LSearch.Name) = '.lpr') then
        begin
          LCodeFile := ConcatPaths([AProjectDir, LSearch.Name]);
          LResult.LoadFromFile(LCodeFile);
          if (AText = '') or (FindInCodeFile(LResult, AText) <> '') then
          begin
            FindClose(LSearch);
            Exit(LCodeFile);
          end;
          LResult.Clear;
        end;
      until FindNext(LSearch) <> 0;
  finally
    FindClose(LSearch);
    LResult.Free;
  end;  
end;

function FindSourceFile(const AProjectDir: string): string;
var
  LSearch: TSearchRec;
  LFileFound: string;
begin
  if FindFirst(ConcatPaths([AProjectDir, AllFilesMask]), faDirectory or faAnyFile, LSearch) = 0 then
    try
      repeat
        if ((LSearch.Attr and faDirectory) <> 0) and 
            (not AnsiMatchText(LSearch.Name, ['.', '..', '.git'])) then
        begin
          LFileFound := FindSourceFile(ConcatPaths([AProjectDir, LSearch.Name]));
          if LFileFound <> '' then
            Exit(LFileFound);
        end
        else
        begin
          if (ExtractFileExt(LSearch.Name) = '.pas') or (ExtractFileExt(LSearch.Name) = '.pp') then
          begin
            LFileFound := ConcatPaths([AProjectDir, LSearch.Name]);
            if (LFileFound <> '') then
              Exit(LFileFound);
          end;
        end;
      until FindNext(LSearch) <> 0;
    finally
      FindClose(LSearch);
    end;
  Result := '';
end;

end.