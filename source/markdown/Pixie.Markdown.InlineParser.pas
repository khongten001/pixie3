unit Pixie.Markdown.InlineParser;

// Markdown inline parser. Takes a string of inline source (typically
// the contents of a paragraph or heading) and emits a list of inline
// AST nodes (mnText, mnEmph, mnStrong, mnCodeSpan, mnLink, mnImage,
// mnLineBreak, mnSoftBreak, mnRawHtml, mnStrikethrough).
//
// Pragmatic implementation rather than a full CommonMark conformance:
// emphasis matching is greedy and avoids the intricate left/right
// flanking delimiter-run rules of the spec — works correctly for
// common cases like **bold**, *em*, ***both***, **bold *em* bold**,
// but won't reproduce every spec edge case.
//
// Also exposes ParseInlinesIntoBlocks which walks an AST and replaces
// the raw mnText children left by the block parser with parsed
// inline trees.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Classes, SysUtils, Generics.Collections,
  Pixie.Markdown.Types;

type
  TPixieMdInlineParser = class
  public
    // Parses inline source and returns a list of inline nodes. Caller
    // owns the returned nodes; pass them to a parent's AddChild.
    class function Parse(const Source: string;
      Options: TPixieMdOptions = DefaultPixieMdOptions): TPixieMdNodeList;

    // Walks Doc, replacing the single mnText child the block parser
    // left in paragraphs / headings / list items / table cells with
    // parsed inline trees.
    class procedure ParseInlinesIntoBlocks(Doc: TPixieMdNode;
      Options: TPixieMdOptions = DefaultPixieMdOptions);
  end;

implementation

uses
  Pixie.HtmlEntities;

// Forward declarations
procedure InsertAt(List: TPixieMdNodeList; Index: Integer;
  Node: TPixieMdNode); forward;

function CodepointToUtf8(CP: UInt32): string;
begin
  if CP < $80 then
    Result := Chr(CP)
  else if CP < $800 then
  begin
    SetLength(Result, 2);
    Result[1] := Chr($C0 or (CP shr 6));
    Result[2] := Chr($80 or (CP and $3F));
  end
  else if CP < $10000 then
  begin
    SetLength(Result, 3);
    Result[1] := Chr($E0 or (CP shr 12));
    Result[2] := Chr($80 or ((CP shr 6) and $3F));
    Result[3] := Chr($80 or (CP and $3F));
  end
  else
  begin
    SetLength(Result, 4);
    Result[1] := Chr($F0 or (CP shr 18));
    Result[2] := Chr($80 or ((CP shr 12) and $3F));
    Result[3] := Chr($80 or ((CP shr 6) and $3F));
    Result[4] := Chr($80 or (CP and $3F));
  end;
end;

function ResolveNamedEntity(const Name: string): string;
var
  Data: TPixieEntityData;
begin
  Result := '';
  if PixieLookupEntity(Name, Data) then
  begin
    Result := CodepointToUtf8(Data.Codepoint1);
    if Data.Codepoint2 <> 0 then
      Result := Result + CodepointToUtf8(Data.Codepoint2);
  end;
end;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function IsAsciiAlpha(C: Char): Boolean;
begin
  Result := ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z'));
end;

function IsAsciiAlnum(C: Char): Boolean;
begin
  Result := IsAsciiAlpha(C) or ((C >= '0') and (C <= '9'));
end;

function IsPunctOrSpace(C: Char): Boolean;
begin
  // Loose definition for emphasis flanking: whitespace or ASCII punctuation.
  case C of
    #0..' ',
    '!', '"', '#', '$', '%', '&', '''', '(', ')', '*', '+', ',', '-',
    '.', '/', ':', ';', '<', '=', '>', '?', '@', '[', '\', ']', '^',
    '_', '`', '{', '|', '}', '~':
      Result := True;
  else
    Result := False;
  end;
end;

function IsValidScheme(const S: string): Boolean;
var
  I: Integer;
begin
  // RFC 3986 scheme: ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
  if Length(S) < 2 then Exit(False);
  if not IsAsciiAlpha(S[1]) then Exit(False);
  for I := 2 to Length(S) do
    if not (IsAsciiAlnum(S[I]) or (S[I] = '+') or (S[I] = '-') or
            (S[I] = '.')) then
      Exit(False);
  Result := True;
end;

function NewText(const S: string): TPixieMdNode;
begin
  Result := TPixieMdNode.Create(mnText);
  Result.Literal := S;
end;

procedure FlushText(var Pending: string; List: TPixieMdNodeList);
begin
  if Pending = '' then Exit;
  List.Add(NewText(Pending));
  Pending := '';
end;

// ---------------------------------------------------------------------------
// Inline scanners
// ---------------------------------------------------------------------------

// Backtick code span: opening run of N backticks must match a closing
// run of exactly N backticks. Returns position after closing backticks
// and sets Content (with internal whitespace stripped per CommonMark).
function ScanCodeSpan(const S: string; Start: Integer;
  out Content: string): Integer;
var
  N, I, Len, EndStart, EndCount, K: Integer;
  HasNonSpace: Boolean;
begin
  Result := 0;
  Len := Length(S);
  N := 0;
  I := Start;
  while (I <= Len) and (S[I] = '`') do
  begin
    Inc(N);
    Inc(I);
  end;
  if N = 0 then Exit;
  // Search for closing run of exactly N backticks.
  while I <= Len do
  begin
    if S[I] = '`' then
    begin
      EndStart := I;
      EndCount := 0;
      while (I <= Len) and (S[I] = '`') do
      begin
        Inc(EndCount);
        Inc(I);
      end;
      if EndCount = N then
      begin
        Content := Copy(S, Start + N, EndStart - (Start + N));
        if (Length(Content) >= 2) and (Content[1] = ' ') and
           (Content[Length(Content)] = ' ') then
        begin
          HasNonSpace := False;
          for K := 1 to Length(Content) do
            if Content[K] <> ' ' then
            begin
              HasNonSpace := True;
              Break;
            end;
          if HasNonSpace then
          begin
            Delete(Content, 1, 1);
            Delete(Content, Length(Content), 1);
          end;
        end;
        Result := I;
        Exit;
      end;
    end
    else
      Inc(I);
  end;
end;

// Autolink: <scheme:...> or <email@...>. Returns position after closing
// '>' and fills Url, or 0.
function ScanAutoLink(const S: string; Start: Integer;
  out Url: string; out IsEmail: Boolean): Integer;
var
  I, Len: Integer;
  Inner: string;
  ColonPos, AtPos: Integer;
  Scheme: string;
begin
  Result := 0;
  IsEmail := False;
  Len := Length(S);
  if (Start > Len) or (S[Start] <> '<') then Exit;
  I := Start + 1;
  Inner := '';
  while (I <= Len) and (S[I] <> '>') do
  begin
    if (S[I] = ' ') or (S[I] = #9) or (S[I] = '<') then Exit;
    Inner := Inner + S[I];
    Inc(I);
  end;
  if (I > Len) or (S[I] <> '>') then Exit;
  // URL form: contains a colon with valid scheme before it.
  ColonPos := Pos(':', Inner);
  if ColonPos > 0 then
  begin
    Scheme := Copy(Inner, 1, ColonPos - 1);
    if IsValidScheme(Scheme) then
    begin
      Url := Inner;
      Result := I + 1;
      Exit;
    end;
  end;
  // Email form: contains @ with at least one char before and dot after.
  AtPos := Pos('@', Inner);
  if (AtPos > 1) and (AtPos < Length(Inner)) and
     (Pos('.', Copy(Inner, AtPos + 1, Length(Inner))) > 0) then
  begin
    Url := Inner;
    IsEmail := True;
    Result := I + 1;
  end;
end;

// Raw inline HTML tag: <tag ...>, </tag>, <!-- ... -->, etc. Returns
// position after the tag's closing '>' or 0.
function ScanRawHtml(const S: string; Start: Integer): Integer;
var
  I, Len: Integer;
begin
  Result := 0;
  Len := Length(S);
  if (Start > Len) or (S[Start] <> '<') then Exit;
  if Start + 1 > Len then Exit;
  // <!-- ... -->
  if (Start + 3 <= Len) and (Copy(S, Start, 4) = '<!--') then
  begin
    I := Start + 4;
    while I + 2 <= Len + 1 do
    begin
      if (I + 2 <= Len) and (S[I] = '-') and (S[I + 1] = '-') and
         (S[I + 2] = '>') then
        Exit(I + 3);
      Inc(I);
    end;
    Exit;
  end;
  // <? ... ?>
  if (Start + 1 <= Len) and (S[Start + 1] = '?') then
  begin
    I := Start + 2;
    while I + 1 <= Len do
    begin
      if (S[I] = '?') and (S[I + 1] = '>') then
        Exit(I + 2);
      Inc(I);
    end;
    Exit;
  end;
  // <![CDATA[ ... ]]>
  if (Start + 8 <= Len) and (Copy(S, Start, 9) = '<![CDATA[') then
  begin
    I := Start + 9;
    while I + 2 <= Len do
    begin
      if (S[I] = ']') and (S[I + 1] = ']') and (S[I + 2] = '>') then
        Exit(I + 3);
      Inc(I);
    end;
    Exit;
  end;
  // Open or close tag: <tag ...>, </tag ...>
  I := Start + 1;
  if (I <= Len) and (S[I] = '/') then Inc(I);
  if (I > Len) or not IsAsciiAlpha(S[I]) then Exit;
  while (I <= Len) and (IsAsciiAlnum(S[I]) or (S[I] = '-')) do Inc(I);
  // Skip attributes / whitespace until '>'
  while I <= Len do
  begin
    if S[I] = '>' then Exit(I + 1);
    if S[I] = '<' then Exit; // unterminated
    Inc(I);
  end;
end;

// HTML entity: &name; or &#NNN; or &#xHH;. Returns position after ';'
// and the decoded text, or 0.
function ScanEntity(const S: string; Start: Integer;
  out Decoded: string): Integer;
var
  I, Len, NumStart, CodePoint: Integer;
  IsHex: Boolean;
  Name: string;
  C: Char;
  Resolved: string;
begin
  Result := 0;
  Len := Length(S);
  if (Start > Len) or (S[Start] <> '&') then Exit;
  if Start + 1 > Len then Exit;

  // Numeric: &# or &#x
  if S[Start + 1] = '#' then
  begin
    I := Start + 2;
    IsHex := False;
    if (I <= Len) and ((S[I] = 'x') or (S[I] = 'X')) then
    begin
      IsHex := True;
      Inc(I);
    end;
    NumStart := I;
    while (I <= Len) and (((not IsHex) and (S[I] >= '0') and (S[I] <= '9')) or
          (IsHex and (((S[I] >= '0') and (S[I] <= '9')) or
                      ((S[I] >= 'a') and (S[I] <= 'f')) or
                      ((S[I] >= 'A') and (S[I] <= 'F'))))) do
      Inc(I);
    if (I = NumStart) or (I > Len) or (S[I] <> ';') then Exit;
    if IsHex then
      CodePoint := StrToIntDef('$' + Copy(S, NumStart, I - NumStart), 0)
    else
      CodePoint := StrToIntDef(Copy(S, NumStart, I - NumStart), 0);
    if (CodePoint <= 0) or (CodePoint > $10FFFF) then
      CodePoint := $FFFD;
    Decoded := CodepointToUtf8(CodePoint);
    Result := I + 1;
    Exit;
  end;

  // Named entity
  I := Start + 1;
  while (I <= Len) and (IsAsciiAlnum(S[I])) do Inc(I);
  if (I > Len) or (S[I] <> ';') or (I = Start + 1) then Exit;
  Name := Copy(S, Start + 1, I - Start - 1);
  Resolved := ResolveNamedEntity(Name);
  if Resolved = '' then Exit;
  Decoded := Resolved;
  Result := I + 1;
  // Suppress unused-variable warning
  C := S[Start];
end;

// Link or image: [text](url "title") or ![alt](url "title").
// Returns position after closing paren, or 0.
function ScanLink(const S: string; Start: Integer; var IsImage: Boolean;
  out LabelText, Url, Title: string; out LabelEnd: Integer): Integer;
var
  I, Len, BracketDepth, ParenDepth: Integer;
  TitleStart: Integer;
  Quote: Char;
begin
  Result := 0;
  IsImage := False;
  Len := Length(S);
  I := Start;
  if (I <= Len) and (S[I] = '!') then
  begin
    IsImage := True;
    Inc(I);
  end;
  if (I > Len) or (S[I] <> '[') then Exit;
  Inc(I);
  // Find matching ']'
  BracketDepth := 1;
  LabelEnd := I;
  while I <= Len do
  begin
    if S[I] = '\' then
    begin
      Inc(I, 2);
      Continue;
    end;
    if S[I] = '[' then Inc(BracketDepth)
    else if S[I] = ']' then
    begin
      Dec(BracketDepth);
      if BracketDepth = 0 then
      begin
        LabelEnd := I - 1;
        Break;
      end;
    end;
    Inc(I);
  end;
  if (I > Len) or (S[I] <> ']') then Exit;
  if IsImage then
    LabelText := Copy(S, Start + 2, LabelEnd - Start - 1)
  else
    LabelText := Copy(S, Start + 1, LabelEnd - Start);
  Inc(I);
  // Inline form: ( url "title" )
  if (I > Len) or (S[I] <> '(') then Exit;
  Inc(I);
  // Skip whitespace
  while (I <= Len) and ((S[I] = ' ') or (S[I] = #9)) do Inc(I);
  // URL: <...> or non-whitespace, balanced parens
  if (I <= Len) and (S[I] = '<') then
  begin
    Inc(I);
    Url := '';
    while (I <= Len) and (S[I] <> '>') and (S[I] <> #10) do
    begin
      Url := Url + S[I];
      Inc(I);
    end;
    if (I > Len) or (S[I] <> '>') then Exit;
    Inc(I);
  end
  else
  begin
    Url := '';
    ParenDepth := 0;
    while I <= Len do
    begin
      if S[I] = '\' then
      begin
        if I + 1 <= Len then
          Url := Url + S[I + 1];
        Inc(I, 2);
        Continue;
      end;
      if (S[I] = ' ') or (S[I] = #9) or (S[I] = #10) then Break;
      if S[I] = '(' then Inc(ParenDepth)
      else if S[I] = ')' then
      begin
        if ParenDepth = 0 then Break;
        Dec(ParenDepth);
      end;
      Url := Url + S[I];
      Inc(I);
    end;
  end;
  // Optional title
  Title := '';
  while (I <= Len) and ((S[I] = ' ') or (S[I] = #9)) do Inc(I);
  if (I <= Len) and ((S[I] = '"') or (S[I] = '''') or (S[I] = '(')) then
  begin
    if S[I] = '(' then Quote := ')' else Quote := S[I];
    Inc(I);
    TitleStart := I;
    while (I <= Len) and (S[I] <> Quote) do
    begin
      if S[I] = '\' then Inc(I);
      Inc(I);
    end;
    if (I <= Len) and (S[I] = Quote) then
    begin
      Title := Copy(S, TitleStart, I - TitleStart);
      Inc(I);
    end
    else
      Exit;
  end;
  while (I <= Len) and ((S[I] = ' ') or (S[I] = #9)) do Inc(I);
  if (I > Len) or (S[I] <> ')') then Exit;
  Result := I + 1;
end;

// ---------------------------------------------------------------------------
// Emphasis processor
// ---------------------------------------------------------------------------
//
// Greedy approach: scan looking for delimiter runs. When we see a run
// of *s or _s, we emit a marker node. After the whole pass, we walk the
// node list and pair up matching markers into emph/strong nodes.

type
  TDelimMarker = class(TPixieMdNode)
  public
    DelimChar: Char;
    DelimLen: Integer;
    Active: Boolean;
    constructor CreateMarker(C: Char; Len: Integer);
  end;

constructor TDelimMarker.CreateMarker(C: Char; Len: Integer);
begin
  inherited Create(mnText);
  Literal := StringOfChar(C, Len);
  DelimChar := C;
  DelimLen := Len;
  Active := True;
end;

procedure ResolveDelimiters(List: TPixieMdNodeList);
var
  Stack: TList<TDelimMarker>;
  I, J, K, OpenIdx, OpenPos, ClosePos, Take, ContentCount: Integer;
  M, Open, Close: TDelimMarker;
  Wrapper: TPixieMdNode;
begin
  Stack := TList<TDelimMarker>.Create;
  try
    I := 0;
    while I < List.Count do
    begin
      if not (List[I] is TDelimMarker) then
      begin
        Inc(I);
        Continue;
      end;
      M := TDelimMarker(List[I]);

      // Try to pair as closer with most recent matching opener.
      OpenIdx := -1;
      for K := Stack.Count - 1 downto 0 do
        if Stack[K].DelimChar = M.DelimChar then
        begin
          OpenIdx := K;
          Break;
        end;

      if OpenIdx < 0 then
      begin
        // No opener; treat as potential opener.
        Stack.Add(M);
        Inc(I);
        Continue;
      end;

      Open := Stack[OpenIdx];
      Close := M;
      if (Open.DelimLen >= 2) and (Close.DelimLen >= 2) then
        Take := 2
      else
        Take := 1;

      if Take = 2 then
        Wrapper := TPixieMdNode.Create(mnStrong)
      else
        Wrapper := TPixieMdNode.Create(mnEmph);

      // Move nodes between Open and Close into the wrapper.
      OpenPos := List.IndexOf(Open);
      ClosePos := List.IndexOf(Close);
      ContentCount := ClosePos - OpenPos - 1;
      for J := 0 to ContentCount - 1 do
        Wrapper.AddChild(List.Extract(List[OpenPos + 1]));

      // Open marker handling.
      Open.DelimLen := Open.DelimLen - Take;
      Close.DelimLen := Close.DelimLen - Take;

      if Open.DelimLen = 0 then
      begin
        // Replace Open with Wrapper in-place.
        OpenPos := List.IndexOf(Open);
        InsertAt(List, OpenPos, Wrapper);
        List.Extract(Open);
        Open.Free;
        Stack.Delete(OpenIdx);
      end
      else
      begin
        Open.Literal := StringOfChar(Open.DelimChar, Open.DelimLen);
        OpenPos := List.IndexOf(Open);
        InsertAt(List, OpenPos + 1, Wrapper);
      end;

      // Close marker handling.
      if Close.DelimLen = 0 then
      begin
        I := List.IndexOf(Close);
        List.Extract(Close);
        Close.Free;
      end
      else
      begin
        Close.Literal := StringOfChar(Close.DelimChar, Close.DelimLen);
        I := List.IndexOf(Close);
      end;

      // Drop any markers above OpenIdx that are now stale (their
      // contents got absorbed into the wrapper).
      while Stack.Count > OpenIdx do
      begin
        if Stack[Stack.Count - 1] = Open then Break;
        Stack.Delete(Stack.Count - 1);
      end;
    end;
  finally
    Stack.Free;
  end;
end;

// Inserts a node at position Index in List. Trivial wrapper but kept
// as a separate symbol for forward-declaration with the resolver.
procedure InsertAt(List: TPixieMdNodeList; Index: Integer; Node: TPixieMdNode);
begin
  List.Insert(Index, Node);
end;

// ---------------------------------------------------------------------------
// Main inline parse
// ---------------------------------------------------------------------------

function ParseImpl(const Source: string;
  Options: TPixieMdOptions): TPixieMdNodeList;
var
  I, Len, Start, RunLen: Integer;
  C: Char;
  Pending: string;
  CodeContent, Url, Decoded, LabelText, Title: string;
  AfterCode, AfterAuto, AfterEntity, AfterLink, AfterHtml, LabelEnd: Integer;
  IsEmail, IsImage: Boolean;
  Node: TPixieMdNode;
  Marker: TDelimMarker;
  StrikeStart, StrikeEnd: Integer;
  InlineList: TPixieMdNodeList;
begin
  Result := TPixieMdNodeList.Create(True);
  Pending := '';
  Len := Length(Source);
  I := 1;
  while I <= Len do
  begin
    C := Source[I];
    case C of
      '\':
        begin
          // Backslash escape: \X for ASCII punctuation or \n -> hard break.
          if I + 1 <= Len then
          begin
            if Source[I + 1] = #10 then
            begin
              FlushText(Pending, Result);
              Result.Add(TPixieMdNode.Create(mnLineBreak));
              Inc(I, 2);
              Continue;
            end;
            if IsPunctOrSpace(Source[I + 1]) and (Source[I + 1] <> ' ') and
               (Source[I + 1] <> #9) then
            begin
              Pending := Pending + Source[I + 1];
              Inc(I, 2);
              Continue;
            end;
          end;
          Pending := Pending + C;
          Inc(I);
        end;
      '`':
        begin
          AfterCode := ScanCodeSpan(Source, I, CodeContent);
          if AfterCode > 0 then
          begin
            FlushText(Pending, Result);
            Node := TPixieMdNode.Create(mnCodeSpan);
            Node.Literal := CodeContent;
            Result.Add(Node);
            I := AfterCode;
          end
          else
          begin
            Pending := Pending + C;
            Inc(I);
          end;
        end;
      '<':
        begin
          AfterAuto := ScanAutoLink(Source, I, Url, IsEmail);
          if AfterAuto > 0 then
          begin
            FlushText(Pending, Result);
            Node := TPixieMdNode.Create(mnLink);
            if IsEmail then
              Node.LinkUrl := 'mailto:' + Url
            else
              Node.LinkUrl := Url;
            Node.AddChild(NewText(Url));
            Result.Add(Node);
            I := AfterAuto;
            Continue;
          end;
          AfterHtml := ScanRawHtml(Source, I);
          if (AfterHtml > 0) and (moAllowRawHtml in Options) then
          begin
            FlushText(Pending, Result);
            Node := TPixieMdNode.Create(mnRawHtml);
            Node.Literal := Copy(Source, I, AfterHtml - I);
            Result.Add(Node);
            I := AfterHtml;
            Continue;
          end;
          Pending := Pending + C;
          Inc(I);
        end;
      '&':
        begin
          AfterEntity := ScanEntity(Source, I, Decoded);
          if AfterEntity > 0 then
          begin
            Pending := Pending + Decoded;
            I := AfterEntity;
          end
          else
          begin
            Pending := Pending + C;
            Inc(I);
          end;
        end;
      '!':
        begin
          if (I < Len) and (Source[I + 1] = '[') then
          begin
            IsImage := True;
            AfterLink := ScanLink(Source, I, IsImage,
              LabelText, Url, Title, LabelEnd);
            if AfterLink > 0 then
            begin
              FlushText(Pending, Result);
              Node := TPixieMdNode.Create(mnImage);
              Node.LinkUrl := Url;
              Node.LinkTitle := Title;
              Node.ImageAlt := LabelText;
              Result.Add(Node);
              I := AfterLink;
              Continue;
            end;
          end;
          Pending := Pending + C;
          Inc(I);
        end;
      '[':
        begin
          IsImage := False;
          AfterLink := ScanLink(Source, I, IsImage,
            LabelText, Url, Title, LabelEnd);
          if AfterLink > 0 then
          begin
            FlushText(Pending, Result);
            Node := TPixieMdNode.Create(mnLink);
            Node.LinkUrl := Url;
            Node.LinkTitle := Title;
            // Recursively parse label text into the link's children.
            InlineList := ParseImpl(LabelText, Options);
            try
              while InlineList.Count > 0 do
                Node.AddChild(InlineList.Extract(InlineList[0]));
            finally
              InlineList.Free;
            end;
            Result.Add(Node);
            I := AfterLink;
            Continue;
          end;
          Pending := Pending + C;
          Inc(I);
        end;
      '*', '_':
        begin
          // Run of delimiter chars.
          Start := I;
          RunLen := 0;
          while (I <= Len) and (Source[I] = C) do
          begin
            Inc(RunLen);
            Inc(I);
          end;
          FlushText(Pending, Result);
          Marker := TDelimMarker.CreateMarker(C, RunLen);
          Result.Add(Marker);
        end;
      '~':
        begin
          if (moGfmStrikethrough in Options) and
             (I + 1 <= Len) and (Source[I + 1] = '~') then
          begin
            // Search for closing ~~
            StrikeStart := I + 2;
            StrikeEnd := StrikeStart;
            while StrikeEnd < Len do
            begin
              if (Source[StrikeEnd] = '~') and
                 (StrikeEnd + 1 <= Len) and (Source[StrikeEnd + 1] = '~') then
                Break;
              Inc(StrikeEnd);
            end;
            if (StrikeEnd < Len) and (Source[StrikeEnd] = '~') and
               (StrikeEnd > StrikeStart) then
            begin
              FlushText(Pending, Result);
              Node := TPixieMdNode.Create(mnStrikethrough);
              InlineList := ParseImpl(
                Copy(Source, StrikeStart, StrikeEnd - StrikeStart), Options);
              try
                while InlineList.Count > 0 do
                  Node.AddChild(InlineList.Extract(InlineList[0]));
              finally
                InlineList.Free;
              end;
              Result.Add(Node);
              I := StrikeEnd + 2;
              Continue;
            end;
          end;
          Pending := Pending + C;
          Inc(I);
        end;
      #10:
        begin
          // Soft break: trailing two spaces or backslash at end -> hard break.
          if (Length(Pending) >= 2) and
             (Pending[Length(Pending)] = ' ') and
             (Pending[Length(Pending) - 1] = ' ') then
          begin
            // Strip trailing spaces, emit hard break.
            while (Length(Pending) > 0) and
                  (Pending[Length(Pending)] = ' ') do
              SetLength(Pending, Length(Pending) - 1);
            FlushText(Pending, Result);
            Result.Add(TPixieMdNode.Create(mnLineBreak));
          end
          else
          begin
            // Soft break: trim trailing whitespace, emit soft break.
            while (Length(Pending) > 0) and
                  ((Pending[Length(Pending)] = ' ') or
                   (Pending[Length(Pending)] = #9)) do
              SetLength(Pending, Length(Pending) - 1);
            FlushText(Pending, Result);
            Result.Add(TPixieMdNode.Create(mnSoftBreak));
          end;
          Inc(I);
          // Skip leading whitespace on next line.
          while (I <= Len) and ((Source[I] = ' ') or (Source[I] = #9)) do
            Inc(I);
        end;
      #13:
        Inc(I); // ignore CR
    else
      Pending := Pending + C;
      Inc(I);
    end;
  end;
  FlushText(Pending, Result);

  // Resolve emphasis/strong delimiter pairs.
  ResolveDelimiters(Result);
end;

class function TPixieMdInlineParser.Parse(const Source: string;
  Options: TPixieMdOptions): TPixieMdNodeList;
begin
  Result := ParseImpl(Source, Options);
end;

// ---------------------------------------------------------------------------
// Tree walk: replace block-parser's raw mnText with parsed inlines
// ---------------------------------------------------------------------------

procedure ProcessBlock(Node: TPixieMdNode; Options: TPixieMdOptions); forward;

procedure ProcessLeaf(Node: TPixieMdNode; Options: TPixieMdOptions);
var
  Source: string;
  InlineList: TPixieMdNodeList;
  Child: TPixieMdNode;
begin
  // Pull current text out (single mnText child the block parser left).
  if (Node.ChildCount = 1) and (Node.Children[0].Kind = mnText) then
  begin
    Source := Node.Children[0].Literal;
    // Free the text child by clearing Children, then re-add parsed
    // inlines.
    Node.Children.Clear;
    InlineList := TPixieMdInlineParser.Parse(Source, Options);
    try
      while InlineList.Count > 0 do
      begin
        Child := InlineList.Extract(InlineList[0]);
        Node.AddChild(Child);
      end;
    finally
      InlineList.Free;
    end;
  end;
end;

procedure ProcessBlock(Node: TPixieMdNode; Options: TPixieMdOptions);
var
  I: Integer;
begin
  case Node.Kind of
    mnDocument, mnBlockQuote, mnList, mnListItem, mnTable, mnTableRow:
      if Node.HasChildren then
        for I := 0 to Node.ChildCount - 1 do
          ProcessBlock(Node.Children[I], Options);
    mnHeading, mnParagraph, mnTableCell:
      ProcessLeaf(Node, Options);
    // mnCodeBlock, mnHtmlBlock, mnThematicBreak: nothing to do
  end;
end;

class procedure TPixieMdInlineParser.ParseInlinesIntoBlocks(Doc: TPixieMdNode;
  Options: TPixieMdOptions);
begin
  if Doc <> nil then
    ProcessBlock(Doc, Options);
end;

end.
