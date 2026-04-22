unit Pixie.DataUri;

// Decode data: URIs with base64 content into a TMemoryStream.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes;

function DecodeDataUri(const Src: string;
  out Stream: TMemoryStream): Boolean;

implementation

uses
  {$IFDEF FPC}Base64{$ELSE}System.NetEncoding{$ENDIF};

{$IFDEF FPC}
type
  TReadOnlyStream = class(TCustomMemoryStream)
  public
    constructor Create(P: Pointer; ASize: Integer);
  end;

constructor TReadOnlyStream.Create(P: Pointer; ASize: Integer);
begin
  inherited Create;
  SetPointer(P, ASize);
end;
{$ENDIF}

function DecodeDataUri(const Src: string;
  out Stream: TMemoryStream): Boolean;
var
  Marker, DataLen: Integer;
{$IFDEF FPC}
  Input: TReadOnlyStream;
  Decoder: TBase64DecodingStream;
  Buf: array[0..4095] of Byte;
  Count: Integer;
{$ELSE}
  Bytes: TBytes;
{$ENDIF}
begin
  Result := False;
  Stream := nil;

  // Find ;base64, marker
  Marker := Pos(';base64,', Src);
  if Marker = 0 then Exit;

  DataLen := Length(Src) - Marker - 7;
  if DataLen <= 0 then Exit;

  Stream := TMemoryStream.Create;
  try
  {$IFDEF FPC}
    // Point directly into Src buffer — no copy (safe: Src is const)
    Input := TReadOnlyStream.Create(@Src[Marker + 8], DataLen);
    try
      Decoder := TBase64DecodingStream.Create(Input);
      try
        repeat
          Count := Decoder.Read(Buf, SizeOf(Buf));
          if Count > 0 then
            Stream.Write(Buf, Count);
        until Count = 0;
      finally
        Decoder.Free;
      end;
    finally
      Input.Free;
    end;
  {$ELSE}
    Bytes := TNetEncoding.Base64.DecodeStringToBytes(
      Copy(Src, Marker + 8, MaxInt));
    if Length(Bytes) > 0 then
      Stream.Write(Bytes[0], Length(Bytes));
  {$ENDIF}
    Result := Stream.Size > 0;
    if Result then
      Stream.Position := 0
    else
      FreeAndNil(Stream);
  except
    FreeAndNil(Stream);
    Result := False;
  end;
end;

end.
