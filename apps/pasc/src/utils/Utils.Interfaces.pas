/// <summary>This unit contains the declaration of the interfaces used in the application.
/// </summary>
unit Utils.Interfaces;

{$MODE DELPHI}{$H+}

interface

uses
  Classes,
  Command.Interfaces
  ;

type

  TWatcherEvent = (
    weFirstRun,     /// The first run of the application
    weFileChanged,  /// The file has changed
    weTimeout,      /// The file has been deleted
    weNoChange      /// No changes were detected
  );

  /// <summary>A procedure that will be called after a change. The file name that triggered 
  /// this action will be passed as a parameter. If function returns true, watcher stops
  /// running. </summary>
  /// <param name="AFile">The file that triggered the event. It will be empty for first 
  /// run and no change.</param>
  /// <param name="AEvent">The event that triggered this procedure.</param>
  TWatcherRunCallback = function (const AFile: string; const AEvent: TWatcherEvent): boolean;

  /// <summary>Enum type to identify the type of item to be ignored by the Watcher. </summary>
  TIgnoreKind = (
    ikStartsText, /// itens of any kind that starts with the text specified
    ikFolder,     /// ignore folders with the specified name
    ikFile,       /// ignore files with the specified name
    ikExtension   /// ignore files with the specified extension
    );

  /// <summary>Interface that represents an object to monitor a path, with methods to configure
  /// parameters and callback in addition to initializing the watch itself. </summary>
  IPathWatcher = interface
    ['{E995078A-19C1-4785-AE53-8A3113574A72}']

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

  /// <summary> Interface that represents a single point in code with the possible memory leak.
  /// </summary>
  ILeakItem = interface
    ['{B1F82A18-688A-41E8-8317-3448D1C077B5}']

    function GetStatus: string;
    procedure SetStatus(const AValue: string);
    /// <summary> Item status. Currently it can only be Leak.</summary>
    property Status: string read GetStatus write SetStatus;
    
    function GetSize: string;
    procedure SetSize(const AValue: string);
    /// <summary> Memory leak size in bytes </summary>
    property Size: string read GetSize write SetSize;
    
    function GetSource: string;
    procedure SetSource(const AValue: string);
    /// <summary> Data about the source code where the leak originated, 
    /// as well as the method and code line number within the file. </summary>
    property Source: string read GetSource write SetSource;
    
  end;

  /// <sumary> This class aims to interpret the memory leak trace file and produce 
  /// a simpler report summarizing enough information to locate the problem at its source.
  /// </summary>
  ILeakReport = interface
    ['{A6E7FB5F-E747-4D5C-B98E-DEFE441E95A4}']

    /// <summary> Set the command builder used to produce the report </summary>
    procedure SetCommandBuilder(ABuilder: ICommandBuilder);
   
    /// <summary> Adds a new memory leak item to the report.</summary>
    function AddItem(AItem: ILeakItem): ILeakItem;

    /// <summary> Scans the contents of the AContent variable to summarize the details 
    /// of a memory leak reported in the trace file. If a memory leak is found then it
    /// added to the report calling AddItem method. </summary>
    procedure CreateLeakItem(AContent: TStringList; AStart: Integer);

    /// <summary> Considering the content of AText, it searches for the string AField, 
    /// if successful, returns the value immediately to the right of that string. 
    /// The returned value will be limited until it finds the next space or the end 
    /// of the string. </summary>
    function GetNextStringOf(const AText, AField: string): string;

    /// <summary> Given a filename, try to locate it recursively in the projects folder, 
    /// then in the current directory. If the file is found, the relative path will be 
    /// added to the file name. </summary>
    function AddRelativePath(const AFile: string): string;

    /// <summary> Prints a report using ICommandBuilder's Output Callback. This report will have 
    /// data regarding possible memory leaks like size, source method and source code 
    /// file with line number. If no leak was found, it will display a message indicating 
    /// the same. </summary>
    procedure Output;

    /// <summary> Parses the contents of the trace file generated by the HeapTrace unit. 
    /// Groups the information into a TLeakItem list. </summary> 
    /// <param name="AContent"> Accepts the contents of the memory leak trace file. 
    /// If an empty string is passed, the method will try to locate the heap.trc file 
    /// in the test project's executable directory. </param>
    function ParseHeapTrace(const AContent: string): ILeakReport;    

    function GetExecutable: string;
    procedure SetExecutable(const AValue: string);
    /// <summary> Test project excutable name. </summary> 
    property Executable: string read GetExecutable write SetExecutable;
    
    function GetProjectSource: string;
    procedure SetProjectSource(const AValue: string);
    /// <summary> Path to test project source files </summary> 
    property ProjectSource: string read GetProjectSource write SetProjectSource;

    function GetLeakData: TArray<ILeakItem>;    
    /// <summary> Array of TLeakItem that is generated after calling ParseHeapTrace method.
    /// </summary> 
    property LeakData: TArray<ILeakItem> read GetLeakData;

  end;

implementation

end.