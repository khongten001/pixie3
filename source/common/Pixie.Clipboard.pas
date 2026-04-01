unit Pixie.Clipboard;

// Platform clipboard abstraction for text copy/paste.
//
// - FPC/Lazarus: uses the Clipbrd unit directly
// - Delphi VCL: uses Vcl.Clipbrd
// - Delphi FMX: uses IFMXClipboardService
//
// For FMX, the initialization section auto-registers the FMX clipboard
// service. No manual setup is needed.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

function PixieClipboardGetText: string;
procedure PixieClipboardSetText(const Text: string);

implementation

uses
{$IFDEF FPC}
  Clipbrd;
{$ELSE}
  {$IFDEF FRAMEWORK_VCL}Vcl.Clipbrd{$ENDIF}
  {$IFDEF FRAMEWORK_FMX}System.Rtti, FMX.Platform{$ENDIF}
  {$IF NOT DEFINED(FRAMEWORK_VCL) AND NOT DEFINED(FRAMEWORK_FMX)}SysUtils{$ENDIF}
  ;
{$ENDIF}

function PixieClipboardGetText: string;
{$IFDEF FRAMEWORK_FMX}
var
  Svc: IFMXClipboardService;
  V: TValue;
{$ENDIF}
begin
{$IFDEF FPC}
  Result := Clipboard.AsText;
{$ELSE}
  Result := '';
  {$IFDEF FRAMEWORK_VCL}
  Result := Clipboard.AsText;
  {$ENDIF}
  {$IFDEF FRAMEWORK_FMX}
  if TPlatformServices.Current.SupportsPlatformService(
    IFMXClipboardService, Svc) then
  begin
    V := Svc.GetClipboard;
    if not V.IsEmpty and V.IsType<string> then
      Result := V.AsString;
  end;
  {$ENDIF}
{$ENDIF}
end;

procedure PixieClipboardSetText(const Text: string);
{$IFDEF FRAMEWORK_FMX}
var
  Svc: IFMXClipboardService;
{$ENDIF}
begin
{$IFDEF FPC}
  Clipboard.AsText := Text;
{$ELSE}
  {$IFDEF FRAMEWORK_VCL}
  Clipboard.AsText := Text;
  {$ENDIF}
  {$IFDEF FRAMEWORK_FMX}
  if TPlatformServices.Current.SupportsPlatformService(
    IFMXClipboardService, Svc) then
    Svc.SetClipboard(TValue.From<string>(Text));
  {$ENDIF}
{$ENDIF}
end;

end.
