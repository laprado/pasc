/// <summary> Unit which has functions to work with resources embedded into the application 
/// binary file.
/// </summary>
unit Utils.Resources;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LResources;

  /// <summary> Returns a string with the content of the resource file. 
  /// </summary>
  /// <param Name="AName"> Resource name to get the string from </param>
  function GetResource(const AName: string): string;

implementation

function GetResource(const AName: string): string;
var
  LResource: TLResource = nil;
begin
  LResource := LazarusResources.Find(AName);
  if not Assigned(LResource) then
    raise Exception.Create('Resource ' + AName + ' is missing.');
  Result := LResource.Value;
end;

initialization
  {$I pasc.lrs}

end.