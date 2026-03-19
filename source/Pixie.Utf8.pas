unit Pixie.Utf8;

{$mode delphi}

interface

function ReadUtf8Char(const Str: string; var Index: Integer): UInt32;
procedure PrevUtf8Char(const Str: string; var Index: Integer);
procedure AppendUtf8Char(var Str: string; Ch: UInt32);

implementation

function ReadUtf8Char(const Str: string; var Index: Integer): UInt32;
var
  B1, B2, B3, B4: Byte;
  Len: Integer;
begin
  Len := Length(Str);
  if Index > Len then
    Exit(0);

  B1 := Ord(Str[Index]);
  Inc(Index);

  // 1-byte sequence: 0xxxxxxx
  if (B1 and $80) = 0 then
    Exit(B1);

  // 2-byte sequence: 110yyyyy 10xxxxxx
  if (B1 and $E0) = $C0 then
  begin
    Result := (B1 and $1F) shl 6;
    if Index <= Len then
    begin
      Result := Result or (Ord(Str[Index]) and $3F);
      Inc(Index);
    end;
    Exit;
  end;

  // 3-byte sequence: 1110zzzz 10yyyyyy 10xxxxxx
  if (B1 and $F0) = $E0 then
  begin
    Result := (B1 and $0F) shl 12;
    if Index <= Len then
    begin
      B2 := Ord(Str[Index]);
      Inc(Index);
      Result := Result or ((B2 and $3F) shl 6);
    end;
    if Index <= Len then
    begin
      Result := Result or (Ord(Str[Index]) and $3F);
      Inc(Index);
    end;
    Exit;
  end;

  // 4-byte sequence: 11110uuu 10zzzzzz 10yyyyyy 10xxxxxx
  if (B1 and $F8) = $F0 then
  begin
    B2 := 0;
    B3 := 0;
    B4 := 0;
    if Index <= Len then
    begin
      B2 := Ord(Str[Index]) and $3F;
      Inc(Index);
    end;
    if Index <= Len then
    begin
      B3 := Ord(Str[Index]) and $3F;
      Inc(Index);
    end;
    if Index <= Len then
    begin
      B4 := Ord(Str[Index]) and $3F;
      Inc(Index);
    end;
    Result := ((B1 and $07) shl 18) or (B2 shl 12) or (B3 shl 6) or B4;
    Exit;
  end;

  // Invalid byte
  Result := $FFFD;
end;

procedure PrevUtf8Char(const Str: string; var Index: Integer);
begin
  // Skip continuation bytes (10xxxxxx)
  while (Index > 1) do
  begin
    Dec(Index);
    if (Ord(Str[Index]) shr 6) <> 2 then
      Break;
  end;
end;

procedure AppendUtf8Char(var Str: string; Ch: UInt32);
begin
  if Ch <= $7F then
    Str := Str + Char(Ch)
  else if Ch <= $7FF then
  begin
    Str := Str + Char((Ch shr 6) + 192);
    Str := Str + Char((Ch and 63) + 128);
  end
  else if (Ch >= $D800) and (Ch <= $DFFF) then
  begin
    // Surrogate: skip (error)
  end
  else if Ch <= $FFFF then
  begin
    Str := Str + Char((Ch shr 12) + 224);
    Str := Str + Char(((Ch shr 6) and 63) + 128);
    Str := Str + Char((Ch and 63) + 128);
  end
  else if Ch <= $10FFFF then
  begin
    Str := Str + Char((Ch shr 18) + 240);
    Str := Str + Char(((Ch shr 12) and 63) + 128);
    Str := Str + Char(((Ch shr 6) and 63) + 128);
    Str := Str + Char((Ch and 63) + 128);
  end;
end;

end.
