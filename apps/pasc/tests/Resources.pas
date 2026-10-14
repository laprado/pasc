unit Resources;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LResources;

  function GetTestResource(const AName: string): string;

implementation

function GetTestResource(const AName: string): string;
var
  LResource: TLResource = nil;
begin
  LResource := LazarusResources.Find(AName);
  if not Assigned(LResource) then
    raise Exception.Create('Resource ' + AName + ' is missing.');
  Result := LResource.Value;
end;

initialization
  {$I testdata.lrs}

end.