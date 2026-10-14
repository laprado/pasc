/// <summary>This unit contains a standard implmentation for IPathWatcher.
/// </summary>
unit Utils.Watcher;

{$MODE DELPHI}{$H+}

interface

uses
  Classes,
  SysUtils,
  Generics.Collections,
  Utils.Interfaces;

type
  TDictFile = TDictionary<string, string>;

  TPathWatcher = class(TInterfacedObject, IPathWatcher)
  private
    FPath: String;

    FIgnoreStartText: TArray<string>;
    FIgnoreFolders: TArray<string>;
    FIgnoreFiles: TArray<string>;
    FIgnoreExt: TArray<string>;

    FTimeout: LongInt;

    FWatcherRun: TWatcherRunCallback;

    FCurrentFile: TDictFile;
    
    /// <summary>Add all items from AData array to AArray without duplicates. </summary>
    procedure AppendDataToArray(var AArray: TArray<string>; AData: TArray<string>);

    /// <summary>Create a dictionary where the filename is the key and the value is the last 
    /// modified date and time. The added files will be those found in the informed folder, 
    /// including subfolders as well. Ignore settings will be applied as well.
    /// 
    /// Validations will be made during the assembly of the list, as long as an old list is 
    /// passed as a parameter. Among the validations we have:
    /// 1. If it is a new file in relation to the old list. Ends the process and returns the
    /// name of the new file in the FChangeMessage parameter.
    /// 2. If the last modification date of the file is different. Ends the process and 
    /// returns the name of the new file in the FChangeMessage parameter.
    /// 3. If the file count is different between the old and new list. Returns a message 
    /// stating that there was a deletion.
    ///
    /// At the end of the process the FCurrentFile will be overwritten if no change was detected.
    /// <param name="ANew">If a new list is passed, changes will be added to it instead of
    /// creating a new empty list. Should not be informed. </param>
    /// <param name="AChangeMessage">It is an output parameter, will contain a change 
    /// description. If no change was detected it will be empty</param>
    procedure BuildFileList(const APath: string; ANew: TDictFile; const AJustBuild: Boolean;
      out AChangeMessage: string);

    /// <summary>Returns true if item should be ignored because its name starts with text
    /// present on a list of texts to be ignored. </summary>
    /// <param name="ASearchRec">Current search result record thar reprents a file or 
    /// a folder.</param>
    function CheckIgnoreStartText(ASearchRec: TSearchRec): Boolean;

    /// <summary>Returns true if item should be ignored because its name is equal to anyone
    /// on the list of folders to be ignored. </summary>
    /// <param name="ASearchRec">Current search result record thar reprents a file or 
    /// a folder.</param>
    function CheckIgnoreFolders(ASearchRec: TSearchRec): Boolean;

    /// <summary>Returns true if item should be ignored because its name is equal to anyone
    /// on the list of files to be ignored. </summary>
    /// <param name="ASearchRec">Current search result record thar reprents a file or 
    /// a folder.</param>
    function CheckIgnoreFiles(ASearchRec: TSearchRec): Boolean;

    /// <summary>Returns true if item should be ignored because its name is equal to anyone
    /// on the list of extensions to be ignored. </summary>
    /// <param name="ASearchRec">Current search result record thar reprents a file or 
    /// a folder.</param>
    function CheckIgnoreExt(ASearchRec: TSearchRec): Boolean;

  public

    /// <summary>Default class constructor. Initialize interanal arrays and dictionaries. 
    /// Use new method for as default class factory.
    /// instantiation. </summary>
    constructor Create;

    /// <summary>Default class destructor. Release resources. </summary>
    destructor Destroy; override;

    /// <summary>Factory method for TPathWatcher, this is the recommended method to create a new
    /// instance of the class. </summary>
    class function New: IPathWatcher;

    /// <summary>Sets the path to watch for changes. Returns self to allow chained watcher calls.
    /// </summary>
    /// <param name="APath">Path that will be monitored</param>
    function Path(const APath: string): IPathWatcher;

    /// <summary>Defines a set of values to be ignored according to the type provided as a parameter.
    /// Ex: to ignore all items, folders or files that start with "." just call the function as follows:
    /// Watcher.Ignore(ikStartsText, ['.']);
    /// Ex: to ignore all folders with specific names, call the function as follows:
    /// Watcher.Ignore(ikFolder, ['bin', 'lib', 'modules']);
    ///    
    /// Returns self to allow chained watcher calls.
    /// </summary>
    /// <param name="AIgnoreKind">Kind of item to be ignored by the watcher</param>
    /// <param name="AItems">An array containing strings to be ignored according to AIgnoreKind
    /// </param>
    function Ignore(const AIgnoreKind: TIgnoreKind; AItems: TArray<string>): IPathWatcher;

    /// <summary>Sets maximum timeout in milliseconds to call the watcher run callback. Every time run 
    /// is called this timer is reset. If the maximum timeout is reached TPathWatcher is terminated.
    /// Default value is 3600 seconds or 3,600,000 milliseconds.
    /// </summary>
    /// <param name="ATime">Number of milliseconds to set the maximum timeout.</param>
    function Timeout(const ATime: Longint): IPathWatcher;

    /// <summary>Defines the callback procedure that should be executed when a change is detected.
    /// </summary>
    /// <param name="AProc">A procedure that will be called after a change</param>
    /// </param>
    function Run(const AWatcherRun: TWatcherRunCallback): IPathWatcher;

    /// <summary>Start watching the path considering the ignore parameters that have been configured. 
    /// As soon as a change is detected the callback routine will be called.
    /// </summary>
    function Start: IPathWatcher;

  end;

implementation

uses
  Utils.Shell,
  StrUtils;

constructor TPathWatcher.Create;
begin
  FPath := '';
  FTimeout := 3600000;
  SetLength(FIgnoreStartText, 0);
  SetLength(FIgnoreFolders, 0);
  SetLength(FIgnoreFiles, 0);
  SetLength(FIgnoreExt, 0);  
  FWatcherRun := nil;
  FCurrentFile := TDictFile.Create;
end;

class function TPathWatcher.New: IPathWatcher;
begin
  Result := Self.Create;
end;

destructor TPathWatcher.Destroy;
begin
  FCurrentFile.Free;
end;

function TPathWatcher.Path(const APath: string): IPathWatcher;
begin
  if not DirectoryExists(APath) then
    raise Exception.Create('Path "' + APath + '" doest not exist');

  FPath := APath;  

  Result := Self;
end;

procedure TPathWatcher.AppendDataToArray(var AArray: TArray<string>; AData: TArray<string>);
var
  LNewItem, LOldItem: string;
  LFound: Boolean;
begin
  for LNewItem in AData do
  begin
    LFound := False;
    for LOldItem in AArray do
      if SameText(LNewItem, LOldItem) then
      begin
        LFound := True;
        break;
      end;

    if not LFound then
    begin
      SetLength(AArray, Length(AArray) + 1);
      AArray[Length(AArray) - 1] := LNewItem;
    end;
  end;
end;

procedure TPathWatcher.BuildFileList(const APath: string; ANew: TDictFile; const AJustBuild: Boolean;
  out AChangeMessage: string);
var
  LSearch: TSearchRec;
  LFirst: Boolean = false;
  LKey, LValue: string;
begin
  if not Assigned(ANew) then
  begin
    ANew := TDictFile.Create;
    LFirst := True;
  end;
  
  if FindFirst(ConcatPaths([APath, AllFilesMask]), faDirectory or faAnyFile, LSearch) = 0 then
    try
      repeat
        if CheckIgnoreStartText(LSearch) or 
           CheckIgnoreFolders(LSearch) or
           CheckIgnoreFiles(LSearch) or 
           CheckIgnoreExt(LSearch) then
          continue;

        if (LSearch.Attr and faAnyFile) <> 0 then
        begin
          LKey := ConcatPaths([APath, LSearch.Name]);

          if not ANew.ContainsKey(LKey) then
          begin
            LValue := IntToStr(FileAge(LKey)) + '_' + IntToStr(LSearch.Size);
            ANew.Add(LKey, LValue);
          end;
                    
          if (not AJustBuild) then
          begin
            if (not FCurrentFile.ContainsKey(LKey)) then
            begin
              if (not ((LSearch.Attr and faDirectory) <> 0)) then
              begin
                AChangeMessage := 'new: ' + LKey;
                FCurrentFile.Add(LKey, ANew[LKey]);
                break;
              end;
            end
            else 
            if (FCurrentFile[LKey] <> ANew[LKey]) then
            begin
              AChangeMessage := 'modified: ' + LKey;
              FCurrentFile[LKey] := ANew[LKey];
              break;
            end;
          end;
        end;

        // search inside sub folder
        if ((LSearch.Attr and faDirectory) <> 0) and (not AnsiMatchText(LSearch.Name, ['.', '..'])) then
        begin
          BuildFileList(
            ConcatPaths([APath, LSearch.Name]), 
            ANew,
            AJustBuild,
            AChangeMessage);
          if AChangeMessage <> '' then
            break;
        end;
      until FindNext(LSearch) <> 0;
    except
      on E: Exception do
      begin
        FindClose(LSearch);
        FreeAndNil(ANew);
        AChangeMessage := 'error: ' + E.Message;
      end;
    end;

    FindClose(LSearch);
  
    if (LFirst) and (AChangeMessage = '') and (Assigned(FCurrentFile)) and (not AJustBuild) then
      if ANew.Count < FCurrentFile.Count then 
        AChangeMessage := 'delete';

    if (LFirst) then
    begin
      if (FCurrentFile.Count = 0) or (AChangeMessage = 'delete') then
      begin
        FreeAndNil(FCurrentFile);
        FCurrentFile := ANew;
        ANew := nil;
      end
      else
        FreeAndNil(ANew);
    end;
end;

function TPathWatcher.Ignore(const AIgnoreKind: TIgnoreKind; AItems: TArray<string>): IPathWatcher;
begin
  if Length(AItems) = 0 then
    exit(Self);

  case AIgnoreKind of 
  ikStartsText:
    AppendDataToArray(FIgnoreStartText, AItems);
  ikFolder:
    AppendDataToArray(FIgnoreFolders, AItems);
  ikFile:
    AppendDataToArray(FIgnoreFiles, AItems);
  ikExtension:
    AppendDataToArray(FIgnoreExt, AItems);
  end;
  Result := Self;
end;

function TPathWatcher.Timeout(const ATime: Longint): IPathWatcher;
begin
  FTimeout := ATime;
  Result := Self;
end;

function TPathWatcher.Run(const AWatcherRun: TWatcherRunCallback): IPathWatcher;
begin
  FWatcherRun := AWatcherRun;
  Result := Self;
end;

function TPathWatcher.Start: IPathWatcher;
var
  LChangeMessage: string;
  LStart: QWord;
begin
  if (not DirectoryExists(FPath)) or (FPath = '') then
    raise Exception.Create('Path "' + FPath + '" doest not exist');

  if not Assigned(FWatcherRun) then
    raise Exception.Create('Watcher callback not assigned, call Run method to assign one.');

  // build initial file list
  BuildFileList(FPath, nil, True, LChangeMessage);

  if FWatcherRun('first run', weFirstRun) then
    exit(Self);
  
  LStart := GetTickCount64;
  while True do
  begin
    BuildFileList(FPath, nil, False, LChangeMessage);

    if LChangeMessage <> '' then
      if FWatcherRun(LChangeMessage, weFileChanged) then
        break;
    
    if (GetTickCount64 - LStart) >= FTimeout then
    begin
      FWatcherRun('timeout exceeded', weTimeout);
      break;
    end;

    FWatcherRun('', weNoChange);

    Sleep(75);
    CheckIfUserPressedCtrlC('TPathWatcher.Start');
  end;
  
  Result := Self;
end;

function TPathWatcher.CheckIgnoreStartText(ASearchRec: TSearchRec): Boolean;
var
  LItem: string;
begin
  Result := False;
  for LItem in FIgnoreStartText do
    if StartsText(LItem, ASearchRec.Name) then
      exit(True);
end;

function TPathWatcher.CheckIgnoreFolders(ASearchRec: TSearchRec): Boolean;
begin
  Result := False;
  if (ASearchRec.Attr and faDirectory) <> 0 then
    Result := AnsiMatchText(ASearchRec.Name, FIgnoreFolders);
end;

function TPathWatcher.CheckIgnoreFiles(ASearchRec: TSearchRec): Boolean;
begin
  Result := False;
  if (ASearchRec.Attr and faAnyFile) <> 0 then
    Result := AnsiMatchText(ASearchRec.Name, FIgnoreFiles);
end;

function TPathWatcher.CheckIgnoreExt(ASearchRec: TSearchRec): Boolean;
begin
  Result := False;
  if ((ASearchRec.Attr and faAnyFile) <> 0) and ((ASearchRec.Attr and faDirectory) = 0) then
    Result := AnsiMatchText(ExtractFileExt(ASearchRec.Name), FIgnoreExt);
end;

end.