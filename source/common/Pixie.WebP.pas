unit Pixie.WebP;

// Minimal WebP decoding via dynamically loaded libwebp.
// Decode-only: no encoding, no incremental, no animation.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

function PixieWebPAvailable: Boolean;

// Decode WebP data to premultiplied BGRA pixels.
// Caller must free the returned Pixels with PixieWebPFreePixels.
function PixieWebPDecode(Data: Pointer; DataSize: Integer;
  out Width, Height: Integer; out Pixels: Pointer): Boolean;

procedure PixieWebPFreePixels(Pixels: Pointer);

implementation

uses
  {$IFDEF FPC}DynLibs,{$ELSE}Winapi.Windows,{$ENDIF}
  SysUtils;

type
  TWebPGetInfo = function(Data: Pointer; DataSize: NativeUInt;
    Width, Height: PInteger): Integer; cdecl;
  TWebPDecodeBGRA = function(Data: Pointer; DataSize: NativeUInt;
    Width, Height: PInteger): Pointer; cdecl;
  TWebPFree = procedure(Ptr: Pointer); cdecl;

var
  Loaded: Boolean = False;
  Tried: Boolean = False;
  LibHandle: {$IFDEF FPC}TLibHandle{$ELSE}THandle{$ENDIF};
  ProcGetInfo: TWebPGetInfo = nil;
  ProcDecodeBGRA: TWebPDecodeBGRA = nil;
  ProcFree: TWebPFree = nil;

procedure TryLoad;

  function TryLib(const Name: string): Boolean;
  begin
    LibHandle := {$IFDEF FPC}DynLibs.SafeLoadLibrary(Name)
      {$ELSE}LoadLibrary(PChar(Name)){$ENDIF};
    Result := LibHandle <> {$IFDEF FPC}DynLibs.NilHandle{$ELSE}0{$ENDIF};
  end;

  function GetProc(const Name: string): Pointer;
  begin
    Result := {$IFDEF FPC}DynLibs.GetProcedureAddress(LibHandle, PChar(Name))
      {$ELSE}GetProcAddress(LibHandle, PChar(Name)){$ENDIF};
  end;

var
  ExeDir: string;
begin
  Tried := True;
  ExeDir := ExtractFilePath(ParamStr(0));

  // Try next to executable first, then system paths
  {$IFDEF CPUX86}
  if not TryLib(ExeDir + 'libwebp32.dll') then
  {$ENDIF}
  {$IFDEF CPUX86_64}
  if not TryLib(ExeDir + 'libwebp64.dll') then
  {$ENDIF}
  if not TryLib(ExeDir + 'libwebp.dll') then
  {$IFDEF UNIX}
  if not TryLib('libwebp.so.7') then
  if not TryLib('libwebp.so.6') then
  if not TryLib('libwebp.so') then
  {$ENDIF}
  {$IFDEF DARWIN}
  if not TryLib('libwebp.7.dylib') then
  if not TryLib('libwebp.6.dylib') then
  if not TryLib('libwebp.dylib') then
  {$ENDIF}
    Exit;

  ProcGetInfo := TWebPGetInfo(GetProc('WebPGetInfo'));
  ProcDecodeBGRA := TWebPDecodeBGRA(GetProc('WebPDecodeBGRA'));
  ProcFree := TWebPFree(GetProc('WebPFree'));

  Loaded := Assigned(ProcGetInfo) and Assigned(ProcDecodeBGRA) and
            Assigned(ProcFree);
end;

function PixieWebPAvailable: Boolean;
begin
  if not Tried then
    TryLoad;
  Result := Loaded;
end;

function PixieWebPDecode(Data: Pointer; DataSize: Integer;
  out Width, Height: Integer; out Pixels: Pointer): Boolean;
var
  Raw: Pointer;
  I, Count: Integer;
  P: PByte;
  A, R, B: Byte;
begin
  Result := False;
  Pixels := nil;
  Width := 0;
  Height := 0;

  if not PixieWebPAvailable then Exit;
  if ProcGetInfo(Data, DataSize, @Width, @Height) = 0 then Exit;

  // Decode to BGRA (straight alpha)
  Raw := ProcDecodeBGRA(Data, DataSize, @Width, @Height);
  if Raw = nil then Exit;

  // Premultiply alpha in-place
  Count := Width * Height;
  P := PByte(Raw);
  for I := 0 to Count - 1 do
  begin
    A := P[3];
    if A = 0 then
    begin
      P[0] := 0;
      P[1] := 0;
      P[2] := 0;
    end
    else if A < 255 then
    begin
      P[0] := (P[0] * A + 127) div 255;
      P[1] := (P[1] * A + 127) div 255;
      P[2] := (P[2] * A + 127) div 255;
    end;
    Inc(P, 4);
  end;

  Pixels := Raw;
  Result := True;
end;

procedure PixieWebPFreePixels(Pixels: Pointer);
begin
  if Loaded and (Pixels <> nil) then
    ProcFree(Pixels);
end;

end.
