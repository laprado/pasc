unit TestUtilsResources;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, 
  SysUtils, 
  fpcunit,
  testregistry;

type

  TTestUtilsResources = class(TTestCase)
  published
    procedure TestGetResource;
  end;

implementation

uses
  StrUtils,
  Resources,
  Utils.Resources;

procedure TTestUtilsResources.TestGetResource;
var
  LActual: string;
begin
  LActual := GetResource('leak_none');
  AssertTrue(
    'Should contain text "0 unfreed memory blocks : 0"',
    ContainsText(LActual, '0 unfreed memory blocks : 0'));
end;

initialization
  RegisterTest(TTestUtilsResources);

end.