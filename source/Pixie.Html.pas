unit Pixie.Html;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Pixie.Types;

const
  PixieWhitespace = ' '#10#13#9#12;

function PixieTrim(const S: string; const CharsToTrim: string = PixieWhitespace): string;
function PixieLowerCase(const S: string): string;
function PixieEqualI(const S1, S2: string): Boolean;
function PixieMatch(const Str: string; Index: Integer; const Substr: string): Boolean;
function PixieValueIndex(const Val, Strings: string; DefValue: Integer = -1; Delim: Char = ';'): Integer;
function PixieIndexValue(Index: Integer; const Strings: string; Delim: Char = ';'): string;
function PixieValueInList(const Val, Strings: string; Delim: Char = ';'): Boolean;
function PixieStrEqualNoCase(const S, LowerVal: string): Boolean;
procedure PixieSplitString(const Str: string; Tokens: TPixieStringVector; const Delims: string = PixieWhitespace; const DelimsPreserve: string = ''; const Quote: string = '"');

function PixieIsWhitespace(C: Integer): Boolean; inline;
function PixieIsAlpha(C: Integer): Boolean; inline;
function PixieIsDigit(C: Integer): Boolean; inline;
function PixieIsHexDigit(C: Integer): Boolean; inline;
function PixieDigitValue(C: Integer): Integer; inline;
function PixieIsSurrogate(C: Integer): Boolean; inline;
function PixieToLower(C: Integer): Integer; inline;

function PixieDecodeHtmlBytes(const Bytes: TBytes): string;

implementation

function PixieTrim(const S: string; const CharsToTrim: string): string;
var
  I, J, Len: Integer;
  Found: Boolean;
  Ch: Char;
begin
  Len := Length(S);
  I := 1;
  while I <= Len do
  begin
    Ch := S[I];
    Found := False;
    for J := 1 to Length(CharsToTrim) do
      if Ch = CharsToTrim[J] then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      Break;
    Inc(I);
  end;

  if I > Len then
  begin
    Result := '';
    Exit;
  end;

  J := Len;
  while J >= I do
  begin
    Ch := S[J];
    Found := False;
    for Len := 1 to Length(CharsToTrim) do
      if Ch = CharsToTrim[Len] then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      Break;
    Dec(J);
  end;

  Result := Copy(S, I, J - I + 1);
end;

function PixieLowerCase(const S: string): string;
var
  I, J, Len: Integer;
begin
  Len := Length(S);
  for I := 1 to Len do
    if (S[I] >= 'A') and (S[I] <= 'Z') then
    begin
      Result := S;
      Result[I] := Chr(Ord(Result[I]) + 32);
      for J := I + 1 to Len do
        if (Result[J] >= 'A') and (Result[J] <= 'Z') then
          Result[J] := Chr(Ord(Result[J]) + 32);
      Exit;
    end;
  Result := S;
end;

function PixieEqualI(const S1, S2: string): Boolean;
var
  I, Len: Integer;
begin
  Len := Length(S1);
  if Len <> Length(S2) then
    Exit(False);
  for I := 1 to Len do
    if PixieToLower(Ord(S1[I])) <> PixieToLower(Ord(S2[I])) then
      Exit(False);
  Result := True;
end;

function PixieMatch(const Str: string; Index: Integer; const Substr: string): Boolean;
var
  I: Integer;
begin
  // Index is 1-based
  if Index < 1 then
    Index := Length(Str) + 1 + Index;
  if (Index < 1) or (Index + Length(Substr) - 1 > Length(Str)) then
    Exit(False);
  for I := 1 to Length(Substr) do
    if Str[Index + I - 1] <> Substr[I] then
      Exit(False);
  Result := True;
end;

function PixieCompareAt(const S: string; Start, Len: Integer; const Val: string): Boolean;
var
  I: Integer;
begin
  if Len <> Length(Val) then
    Exit(False);
  for I := 1 to Len do
    if S[Start + I - 1] <> Val[I] then
      Exit(False);
  Result := True;
end;

function PixieValueIndex(const Val, Strings: string; DefValue: Integer; Delim: Char): Integer;
var
  Idx, Start, ItemEnd, ItemLen, ValLen, StrLen: Integer;
begin
  if (Val = '') or (Strings = '') then
    Exit(DefValue);

  Idx := 0;
  Start := 1;
  ValLen := Length(Val);
  StrLen := Length(Strings);

  while Start <= StrLen do
  begin
    ItemEnd := Start;
    while (ItemEnd <= StrLen) and (Strings[ItemEnd] <> Delim) do
      Inc(ItemEnd);

    ItemLen := ItemEnd - Start;
    if (ItemLen = ValLen) and PixieCompareAt(Strings, Start, ItemLen, Val) then
      Exit(Idx);

    Inc(Idx);
    Start := ItemEnd + 1;
  end;

  Result := DefValue;
end;

function PixieIndexValue(Index: Integer; const Strings: string; Delim: Char): string;
var
  Vals: TPixieStringVector;
  DelimStr: string;
begin
  Vals := TPixieStringVector.Create;
  try
    DelimStr := Delim;
    PixieSplitString(Strings, Vals, DelimStr);
    if (Index >= 0) and (Index < Vals.Count) then
      Result := Vals[Index]
    else
      Result := IntToStr(Index);
  finally
    Vals.Free;
  end;
end;

function PixieValueInList(const Val, Strings: string; Delim: Char): Boolean;
begin
  Result := PixieValueIndex(Val, Strings, -1, Delim) >= 0;
end;

function PixieStrEqualNoCase(const S, LowerVal: string): Boolean;
var
  I, Len: Integer;
  C: Byte;
begin
  Len := Length(S);
  if Len <> Length(LowerVal) then
    Exit(False);
  for I := 1 to Len do
  begin
    C := Ord(S[I]);
    if (C >= Ord('A')) and (C <= Ord('Z')) then
      C := C + 32;
    if C <> Ord(LowerVal[I]) then
      Exit(False);
  end;
  Result := True;
end;

function PixieFindCloseBracket(const S: string; Off: Integer; OpenB: Char; CloseB: Char): Integer;
var
  Cnt, I: Integer;
begin
  Cnt := 0;
  for I := Off to Length(S) do
  begin
    if S[I] = OpenB then
      Inc(Cnt)
    else if S[I] = CloseB then
    begin
      Dec(Cnt);
      if Cnt = 0 then
        Exit(I);
    end;
  end;
  Result := 0;
end;

function CharInStr(Ch: Char; const S: string): Boolean; inline;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    if S[I] = Ch then
      Exit(True);
  Result := False;
end;

procedure PixieSplitString(const Str: string; Tokens: TPixieStringVector; const Delims: string; const DelimsPreserve: string; const Quote: string);
var
  AllDelims: string;
  TokenStart, TokenEnd, StrLen, TokenLen: Integer;
  Token: string;
begin
  if (Str = '') or ((Delims = '') and (DelimsPreserve = '')) then
    Exit;

  AllDelims := Delims + DelimsPreserve + Quote;
  StrLen := Length(Str);
  TokenStart := 1;

  // Find first delimiter
  TokenEnd := 0;
  for TokenLen := TokenStart to StrLen do
    if CharInStr(Str[TokenLen], AllDelims) then
    begin
      TokenEnd := TokenLen;
      Break;
    end;
  if TokenEnd = 0 then
    TokenEnd := StrLen + 1; // past end = no delimiter found

  while True do
  begin
    // Skip over quoted/bracketed content
    while (TokenEnd >= 1) and (TokenEnd <= StrLen) and CharInStr(Str[TokenEnd], Quote) do
    begin
      if Str[TokenEnd] = '(' then
        TokenEnd := PixieFindCloseBracket(Str, TokenEnd, '(', ')')
      else if Str[TokenEnd] = '[' then
        TokenEnd := PixieFindCloseBracket(Str, TokenEnd, '[', ']')
      else if Str[TokenEnd] = '{' then
        TokenEnd := PixieFindCloseBracket(Str, TokenEnd, '{', '}')
      else
      begin
        // Find matching quote char
        TokenLen := TokenEnd + 1;
        while (TokenLen <= StrLen) and (Str[TokenLen] <> Str[TokenEnd]) do
          Inc(TokenLen);
        if TokenLen <= StrLen then
          TokenEnd := TokenLen
        else
          TokenEnd := 0;
      end;

      if (TokenEnd >= 1) and (TokenEnd <= StrLen) then
      begin
        // Find next delimiter after the bracket/quote
        TokenLen := TokenEnd + 1;
        TokenEnd := 0;
        while TokenLen <= StrLen do
        begin
          if CharInStr(Str[TokenLen], AllDelims) then
          begin
            TokenEnd := TokenLen;
            Break;
          end;
          Inc(TokenLen);
        end;
        if TokenEnd = 0 then
          TokenEnd := StrLen + 1;
      end
      else
        TokenEnd := StrLen + 1;
    end;

    // Extract token
    if TokenEnd > StrLen then
      TokenLen := StrLen - TokenStart + 1
    else
      TokenLen := TokenEnd - TokenStart;

    if TokenLen > 0 then
    begin
      Token := Copy(Str, TokenStart, TokenLen);
      if Token <> '' then
        Tokens.Add(Token);
    end;

    // Add preserved delimiter
    if (TokenEnd >= 1) and (TokenEnd <= StrLen) and (DelimsPreserve <> '') and CharInStr(Str[TokenEnd], DelimsPreserve) then
      Tokens.Add(Str[TokenEnd]);

    TokenStart := TokenEnd;
    if (TokenStart < 1) or (TokenStart > StrLen) then
      Break;
    Inc(TokenStart);
    if TokenStart > StrLen then
      Break;

    // Find next delimiter
    TokenEnd := 0;
    for TokenLen := TokenStart to StrLen do
      if CharInStr(Str[TokenLen], AllDelims) then
      begin
        TokenEnd := TokenLen;
        Break;
      end;
    if TokenEnd = 0 then
      TokenEnd := StrLen + 1;
  end;
end;

function PixieIsWhitespace(C: Integer): Boolean;
begin
  Result := (C = Ord(' ')) or (C = 9) or (C = 10) or (C = 13) or (C = 12);
end;

function PixieIsAlpha(C: Integer): Boolean;
begin
  Result := ((C >= Ord('A')) and (C <= Ord('Z'))) or ((C >= Ord('a')) and (C <= Ord('z')));
end;

function PixieIsDigit(C: Integer): Boolean;
begin
  Result := (C >= Ord('0')) and (C <= Ord('9'));
end;

function PixieIsHexDigit(C: Integer): Boolean;
begin
  Result := PixieIsDigit(C) or ((C >= Ord('a')) and (C <= Ord('f'))) or ((C >= Ord('A')) and (C <= Ord('F')));
end;

function PixieDigitValue(C: Integer): Integer;
begin
  if PixieIsDigit(C) then
    Result := C - Ord('0')
  else
    Result := PixieToLower(C) - Ord('a') + 10;
end;

function PixieIsSurrogate(C: Integer): Boolean;
begin
  Result := (C >= $D800) and (C < $E000);
end;

function PixieToLower(C: Integer): Integer;
begin
  if (C >= Ord('A')) and (C <= Ord('Z')) then
    Result := C + 32
  else
    Result := C;
end;

// Detect charset from HTML using the spec prescan algorithm
// (https://html.spec.whatwg.org/multipage/parsing.html#prescan-a-byte-stream-to-determine-its-encoding).
// Scans the first 1024 bytes as Latin1, skips comments and non-meta tags,
// and extracts charset from <meta charset="..."> or
// <meta http-equiv="Content-Type" content="...; charset=...">.

function PrescanLowerAt(const S: string; Pos, Len: Integer;
  const Val: string): Boolean;
var
  I: Integer;
  C: Char;
begin
  if Pos + Length(Val) - 1 > Len then
    Exit(False);
  for I := 1 to Length(Val) do
  begin
    C := S[Pos + I - 1];
    if (C >= 'A') and (C <= 'Z') then
      C := Chr(Ord(C) + 32);
    if C <> Val[I] then
      Exit(False);
  end;
  Result := True;
end;

function PrescanIsWhitespace(C: Char): Boolean; inline;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13) or (C = #12);
end;

// Extract charset value from a content attribute string
// e.g. "text/html; charset=windows-1251" -> "windows-1251"
function PrescanExtractCharset(const Content: string): string;
var
  I, Start, Len: Integer;
  C: Char;
begin
  Result := '';
  Len := Length(Content);
  I := 1;
  while I + 7 <= Len do
  begin
    if not PrescanLowerAt(Content, I, Len, 'charset') then
    begin
      Inc(I);
      Continue;
    end;
    Inc(I, 7);
    // Skip spaces around '='
    while (I <= Len) and (Content[I] = ' ') do
      Inc(I);
    if (I > Len) or (Content[I] <> '=') then
      Continue;
    Inc(I);
    while (I <= Len) and (Content[I] = ' ') do
      Inc(I);
    if I > Len then
      Exit;
    // Quoted or unquoted value
    C := Content[I];
    if (C = '"') or (C = '''') then
    begin
      Inc(I);
      Start := I;
      while (I <= Len) and (Content[I] <> C) do
        Inc(I);
      Result := LowerCase(Copy(Content, Start, I - Start));
    end
    else
    begin
      Start := I;
      while (I <= Len) and (Content[I] <> ' ') and (Content[I] <> ';') do
        Inc(I);
      Result := LowerCase(Copy(Content, Start, I - Start));
    end;
    Exit;
  end;
end;

// Get an attribute name/value pair from the prescan position.
// Returns False when no more attributes are found.
function PrescanGetAttribute(const S: string; var Pos: Integer; Len: Integer;
  out AttrName, AttrValue: string): Boolean;
var
  Start: Integer;
  Quote: Char;
begin
  Result := False;
  AttrName := '';
  AttrValue := '';
  // Skip whitespace and slashes
  while (Pos <= Len) and (PrescanIsWhitespace(S[Pos]) or (S[Pos] = '/')) do
    Inc(Pos);
  if (Pos > Len) or (S[Pos] = '>') then
    Exit;
  // Collect attribute name
  Start := Pos;
  while (Pos <= Len) and (S[Pos] <> '=') and (S[Pos] <> '>')
        and not PrescanIsWhitespace(S[Pos]) do
    Inc(Pos);
  AttrName := LowerCase(Copy(S, Start, Pos - Start));
  if AttrName = '' then
    Exit;
  Result := True;
  // Skip whitespace before '='
  while (Pos <= Len) and PrescanIsWhitespace(S[Pos]) do
    Inc(Pos);
  if (Pos > Len) or (S[Pos] <> '=') then
    Exit; // attribute with no value
  Inc(Pos); // skip '='
  // Skip whitespace after '='
  while (Pos <= Len) and PrescanIsWhitespace(S[Pos]) do
    Inc(Pos);
  if Pos > Len then
    Exit;
  // Collect attribute value
  if (S[Pos] = '"') or (S[Pos] = '''') then
  begin
    Quote := S[Pos];
    Inc(Pos);
    Start := Pos;
    while (Pos <= Len) and (S[Pos] <> Quote) do
      Inc(Pos);
    AttrValue := Copy(S, Start, Pos - Start);
    if Pos <= Len then
      Inc(Pos); // skip closing quote
  end
  else
  begin
    Start := Pos;
    while (Pos <= Len) and not PrescanIsWhitespace(S[Pos]) and (S[Pos] <> '>') do
      Inc(Pos);
    AttrValue := Copy(S, Start, Pos - Start);
  end;
end;

function PixieDetectCharset(const Bytes: TBytes; Len: Integer): string;
var
  ScanLen, I, AttrPos: Integer;
  S: string;
  GotPragma, NeedPragma: Boolean;
  Charset, AttrName, AttrValue: string;
begin
  Result := '';
  ScanLen := Len;
  if ScanLen > 1024 then
    ScanLen := 1024;
  if ScanLen = 0 then
    Exit;

  // Interpret raw bytes as Latin1
  SetLength(S, ScanLen);
  for I := 0 to ScanLen - 1 do
    S[I + 1] := Char(Bytes[I]);

  I := 1;
  while I <= ScanLen do
  begin
    // Skip comment <!-- ... -->
    if (I + 3 <= ScanLen) and (S[I] = '<') and (S[I + 1] = '!')
       and (S[I + 2] = '-') and (S[I + 3] = '-') then
    begin
      Inc(I, 4);
      while I + 2 <= ScanLen do
      begin
        if (S[I] = '-') and (S[I + 1] = '-') and (S[I + 2] = '>') then
        begin
          Inc(I, 3);
          Break;
        end;
        Inc(I);
      end;
      Continue;
    end;

    // Check for <meta followed by whitespace or /
    if (I + 5 <= ScanLen) and (S[I] = '<')
       and PrescanLowerAt(S, I + 1, ScanLen, 'meta')
       and (PrescanIsWhitespace(S[I + 5]) or (S[I + 5] = '/')) then
    begin
      AttrPos := I + 5;
      GotPragma := False;
      NeedPragma := True;
      Charset := '';

      while PrescanGetAttribute(S, AttrPos, ScanLen, AttrName, AttrValue) do
      begin
        if AttrName = 'http-equiv' then
          GotPragma := LowerCase(AttrValue) = 'content-type'
        else if AttrName = 'content' then
        begin
          if Charset = '' then
            Charset := PrescanExtractCharset(AttrValue);
        end
        else if AttrName = 'charset' then
        begin
          Charset := LowerCase(AttrValue);
          NeedPragma := False;
        end;
      end;

      if (Charset <> '') and (not NeedPragma or GotPragma) then
        Exit(Charset);

      I := AttrPos;
      // Skip to '>'
      while (I <= ScanLen) and (S[I] <> '>') do
        Inc(I);
      if I <= ScanLen then
        Inc(I);
      Continue;
    end;

    // Skip other tags: <!, </, <?, or <letter
    if (I < ScanLen) and (S[I] = '<') then
    begin
      if ((S[I + 1] = '!') or (S[I + 1] = '/') or (S[I + 1] = '?'))
         or ((S[I + 1] >= 'A') and (S[I + 1] <= 'Z'))
         or ((S[I + 1] >= 'a') and (S[I + 1] <= 'z')) then
      begin
        Inc(I, 2);
        while (I <= ScanLen) and (S[I] <> '>') do
          Inc(I);
        if I <= ScanLen then
          Inc(I);
        Continue;
      end;
    end;

    Inc(I);
  end;
end;

function PixieCharsetToCodePage(const Charset: string): Integer;
var
  S: string;
begin
  S := LowerCase(Charset);

  // UTF-8 — no conversion needed
  if (S = 'utf-8') or (S = 'utf8') then
    Exit(0);

  // Windows code pages
  if (S = 'windows-1250') or (S = 'cp1250') then Exit(1250);
  if (S = 'windows-1251') or (S = 'cp1251') then Exit(1251);
  if (S = 'windows-1252') or (S = 'cp1252') then Exit(1252);
  if (S = 'windows-1253') or (S = 'cp1253') then Exit(1253);
  if (S = 'windows-1254') or (S = 'cp1254') then Exit(1254);
  if (S = 'windows-1255') or (S = 'cp1255') then Exit(1255);
  if (S = 'windows-1256') or (S = 'cp1256') then Exit(1256);
  if (S = 'windows-1257') or (S = 'cp1257') then Exit(1257);
  if (S = 'windows-1258') or (S = 'cp1258') then Exit(1258);

  // ISO-8859
  if (S = 'iso-8859-1') or (S = 'latin1') then Exit(28591);
  if S = 'iso-8859-2' then Exit(28592);
  if S = 'iso-8859-3' then Exit(28593);
  if S = 'iso-8859-4' then Exit(28594);
  if S = 'iso-8859-5' then Exit(28595);
  if S = 'iso-8859-6' then Exit(28596);
  if S = 'iso-8859-7' then Exit(28597);
  if S = 'iso-8859-8' then Exit(28598);
  if S = 'iso-8859-9' then Exit(28599);
  if S = 'iso-8859-10' then Exit(28600);
  if S = 'iso-8859-13' then Exit(28603);
  if S = 'iso-8859-14' then Exit(28604);
  if S = 'iso-8859-15' then Exit(28605);

  // KOI8
  if S = 'koi8-r' then Exit(20866);
  if S = 'koi8-u' then Exit(21866);

  // Other common
  if (S = 'us-ascii') or (S = 'ascii') then Exit(20127);
  if (S = 'shift_jis') or (S = 'shift-jis') then Exit(932);
  if S = 'euc-jp' then Exit(20932);
  if (S = 'gb2312') or (S = 'gbk') or (S = 'gb18030') then Exit(936);
  if S = 'euc-kr' then Exit(949);
  if S = 'big5' then Exit(950);
  if S = 'tis-620' then Exit(874);

  // Unknown — return 0, treat as UTF-8
  Result := 0;
end;

function PixieDecodeHtmlBytes(const Bytes: TBytes): string;
var
  Charset: string;
  CodePage: Integer;
  Enc: TEncoding;
begin
  // Check for UTF-8 BOM
  if (Length(Bytes) >= 3) and
     (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Exit(TEncoding.UTF8.GetString(Bytes, 3, Length(Bytes) - 3));

  // Check for UTF-16 LE BOM
  if (Length(Bytes) >= 2) and (Bytes[0] = $FF) and (Bytes[1] = $FE) then
    Exit(TEncoding.Unicode.GetString(Bytes, 2, Length(Bytes) - 2));

  // Check for UTF-16 BE BOM
  if (Length(Bytes) >= 2) and (Bytes[0] = $FE) and (Bytes[1] = $FF) then
    Exit(TEncoding.BigEndianUnicode.GetString(Bytes, 2, Length(Bytes) - 2));

  // Detect charset from meta tag
  Charset := PixieDetectCharset(Bytes, Length(Bytes));
  CodePage := PixieCharsetToCodePage(Charset);

  if CodePage = 0 then
    // UTF-8 or unknown — interpret as UTF-8
    Result := TEncoding.UTF8.GetString(Bytes)
  else
  begin
    Enc := TEncoding.GetEncoding(CodePage);
    try
      Result := Enc.GetString(Bytes);
    finally
      Enc.Free;
    end;
  end;
end;

end.
