unit Pixie.Markdown.Parser;

// Markdown block parser. Walks the input line by line, maintaining a
// stack of open container blocks (document, blockquote, list, list-item)
// and at most one open leaf block (paragraph, code block, HTML block,
// heading), and emits an AST of block nodes.
//
// Block-level only: leaf blocks contain a single mnText child whose
// Literal holds the raw inline source. The inline parser
// (TPixieMdInlineParser.ParseInlinesIntoBlocks) replaces those text
// children with parsed inline trees.
//
// Implements ATX and setext headings, thematic breaks, blockquotes,
// fenced and indented code blocks, ordered and unordered lists with
// nesting, basic HTML blocks, paragraphs, lazy continuation, and YAML
// front-matter stripping. Tables, link reference definitions, and task
// list items are not yet implemented.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Classes, SysUtils, Generics.Collections,
  Pixie.Markdown.Types;

type
  TPixieMdLinkRef = record
    Url: string;
    Title: string;
  end;
  TPixieMdLinkRefMap = TDictionary<string, TPixieMdLinkRef>;

  TPixieMdParser = class
  public
    class function ParseBlocks(const Md: string;
      RefDefs: TPixieMdLinkRefMap = nil;
      Options: TPixieMdOptions = DefaultPixieMdOptions): TPixieMdNode;
  end;

procedure PixieMdSplitLines(const S: string; out Lines: TArray<string>);

implementation

// ---------------------------------------------------------------------------
// Line splitting
// ---------------------------------------------------------------------------

procedure PixieMdSplitLines(const S: string; out Lines: TArray<string>);
var
  Buf: TList<string>;
  I, Start, Len: Integer;
  C: Char;
begin
  Buf := TList<string>.Create;
  try
    Len := Length(S);
    Start := 1;
    I := 1;
    while I <= Len do
    begin
      C := S[I];
      if C = #10 then
      begin
        Buf.Add(Copy(S, Start, I - Start));
        Inc(I);
        Start := I;
      end
      else if C = #13 then
      begin
        Buf.Add(Copy(S, Start, I - Start));
        Inc(I);
        if (I <= Len) and (S[I] = #10) then
          Inc(I);
        Start := I;
      end
      else
        Inc(I);
    end;
    if Start <= Len then
      Buf.Add(Copy(S, Start, Len - Start + 1));
    Lines := Buf.ToArray;
  finally
    Buf.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Whitespace / character helpers
// ---------------------------------------------------------------------------

function IsBlankLine(const S: string): Boolean;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    if (S[I] <> ' ') and (S[I] <> #9) then
      Exit(False);
  Result := True;
end;

// Returns column count consumed and updates Offset (1-based), counting
// tabs as advancing to the next tab stop (4-col).
procedure SkipIndent(const S: string; var Offset: Integer; MaxCols: Integer;
  out Consumed: Integer);
begin
  Consumed := 0;
  while (Offset <= Length(S)) and (Consumed < MaxCols) do
  begin
    if S[Offset] = ' ' then
      Inc(Consumed)
    else if S[Offset] = #9 then
      Consumed := Consumed + (4 - (Consumed mod 4))
    else
      Break;
    Inc(Offset);
  end;
end;

function StripTrailingWhitespace(const S: string): string;
var
  I: Integer;
begin
  I := Length(S);
  while (I >= 1) and ((S[I] = ' ') or (S[I] = #9)) do
    Dec(I);
  Result := Copy(S, 1, I);
end;

function TrimSpaces(const S: string): string;
var
  I, J: Integer;
begin
  I := 1;
  while (I <= Length(S)) and ((S[I] = ' ') or (S[I] = #9)) do
    Inc(I);
  J := Length(S);
  while (J >= I) and ((S[J] = ' ') or (S[J] = #9)) do
    Dec(J);
  Result := Copy(S, I, J - I + 1);
end;

// ---------------------------------------------------------------------------
// Block-start probes
// ---------------------------------------------------------------------------

// ATX heading: 1-6 #s followed by space/tab/EOL. Returns level or 0.
function ProbeAtxHeading(const S: string; Offset: Integer;
  out ContentStart, ContentEnd: Integer): Integer;
var
  HashCount, I, Len: Integer;
  TailStart, TailEnd: Integer;
begin
  Result := 0;
  Len := Length(S);
  HashCount := 0;
  I := Offset;
  while (I <= Len) and (S[I] = '#') and (HashCount < 7) do
  begin
    Inc(HashCount);
    Inc(I);
  end;
  if (HashCount = 0) or (HashCount > 6) then Exit;
  if (I <= Len) and (S[I] <> ' ') and (S[I] <> #9) then Exit;
  while (I <= Len) and ((S[I] = ' ') or (S[I] = #9)) do Inc(I);
  ContentStart := I;
  TailEnd := Len;
  while (TailEnd >= ContentStart) and
        ((S[TailEnd] = ' ') or (S[TailEnd] = #9)) do
    Dec(TailEnd);
  TailStart := TailEnd;
  while (TailStart >= ContentStart) and (S[TailStart] = '#') do
    Dec(TailStart);
  if (TailStart < TailEnd) and (TailStart >= ContentStart) and
     ((S[TailStart] = ' ') or (S[TailStart] = #9)) then
  begin
    while (TailStart >= ContentStart) and
          ((S[TailStart] = ' ') or (S[TailStart] = #9)) do
      Dec(TailStart);
    ContentEnd := TailStart;
  end
  else if (TailStart < ContentStart) and (TailEnd >= ContentStart) then
    ContentEnd := ContentStart - 1
  else
    ContentEnd := TailEnd;
  Result := HashCount;
end;

function ProbeSetextUnderline(const S: string; Offset: Integer): Integer;
var
  I, Len: Integer;
  C: Char;
  HasContent: Boolean;
begin
  Result := 0;
  Len := Length(S);
  I := Offset;
  if I > Len then Exit;
  C := S[I];
  if (C <> '=') and (C <> '-') then Exit;
  HasContent := False;
  while (I <= Len) and (S[I] = C) do
  begin
    HasContent := True;
    Inc(I);
  end;
  if not HasContent then Exit;
  while I <= Len do
  begin
    if (S[I] <> ' ') and (S[I] <> #9) then Exit;
    Inc(I);
  end;
  if C = '=' then Result := 1 else Result := 2;
end;

function ProbeThematicBreak(const S: string; Offset: Integer): Boolean;
var
  I, Len, Count: Integer;
  C, Marker: Char;
begin
  Result := False;
  Len := Length(S);
  I := Offset;
  if I > Len then Exit;
  Marker := S[I];
  if (Marker <> '-') and (Marker <> '_') and (Marker <> '*') then Exit;
  Count := 0;
  while I <= Len do
  begin
    C := S[I];
    if C = Marker then
      Inc(Count)
    else if (C <> ' ') and (C <> #9) then
      Exit;
    Inc(I);
  end;
  Result := Count >= 3;
end;

function ProbeFence(const S: string; Offset: Integer;
  out FenceLen: Integer; out InfoStart, InfoEnd: Integer): Char;
var
  I, Len, J: Integer;
  Marker: Char;
begin
  Result := #0;
  FenceLen := 0;
  Len := Length(S);
  I := Offset;
  if I > Len then Exit;
  Marker := S[I];
  if (Marker <> '`') and (Marker <> '~') then Exit;
  while (I <= Len) and (S[I] = Marker) do
  begin
    Inc(FenceLen);
    Inc(I);
  end;
  if FenceLen < 3 then Exit;
  InfoStart := I;
  InfoEnd := Len;
  if Marker = '`' then
  begin
    J := InfoStart;
    while J <= InfoEnd do
    begin
      if S[J] = '`' then Exit;
      Inc(J);
    end;
  end;
  Result := Marker;
end;

function IsClosingFence(const S: string; Offset: Integer;
  Marker: Char; MinLen: Integer): Boolean;
var
  I, Len, Count: Integer;
begin
  Result := False;
  Len := Length(S);
  I := Offset;
  Count := 0;
  while (I <= Len) and (S[I] = Marker) do
  begin
    Inc(Count);
    Inc(I);
  end;
  if Count < MinLen then Exit;
  while I <= Len do
  begin
    if (S[I] <> ' ') and (S[I] <> #9) then Exit;
    Inc(I);
  end;
  Result := True;
end;

function ProbeListMarker(const S: string; Offset: Integer;
  out IsOrdered: Boolean; out ListChar: Char; out OrderedStart: Integer;
  out AfterMarker: Integer): Integer;
var
  I, Len, Digits: Integer;
  C: Char;
  NumStr: string;
begin
  Result := 0;
  IsOrdered := False;
  ListChar := #0;
  OrderedStart := 1;
  AfterMarker := Offset;
  Len := Length(S);
  I := Offset;
  if I > Len then Exit;
  C := S[I];
  if (C = '-') or (C = '*') or (C = '+') then
  begin
    if (I + 1 > Len) or (S[I + 1] = ' ') or (S[I + 1] = #9) then
    begin
      ListChar := C;
      AfterMarker := I + 1;
      Result := 1;
      Exit;
    end;
  end
  else if (C >= '0') and (C <= '9') then
  begin
    Digits := 0;
    NumStr := '';
    while (I <= Len) and (S[I] >= '0') and (S[I] <= '9') and (Digits < 9) do
    begin
      NumStr := NumStr + S[I];
      Inc(Digits);
      Inc(I);
    end;
    if Digits = 0 then Exit;
    if (I > Len) then Exit;
    if (S[I] <> '.') and (S[I] <> ')') then Exit;
    ListChar := S[I];
    Inc(I);
    if (I <= Len) and (S[I] <> ' ') and (S[I] <> #9) then Exit;
    IsOrdered := True;
    OrderedStart := StrToIntDef(NumStr, 1);
    AfterMarker := I;
    Result := I - Offset;
  end;
end;

function ProbeBlockQuote(const S: string; Offset: Integer): Integer;
var
  I, Spaces: Integer;
begin
  Result := 0;
  I := Offset;
  Spaces := 0;
  while (I <= Length(S)) and (S[I] = ' ') and (Spaces < 3) do
  begin
    Inc(I);
    Inc(Spaces);
  end;
  if (I > Length(S)) or (S[I] <> '>') then Exit;
  Inc(I);
  if (I <= Length(S)) and ((S[I] = ' ') or (S[I] = #9)) then
    Inc(I);
  Result := I;
end;

// HTML block start: returns 1-7 type or 0. Conservative subset that
// covers the common cases (script/pre/style/textarea, comments, CDATA,
// known block-level tags). Type 7 (any complete tag with whitespace)
// not implemented to avoid false positives breaking paragraphs.
function ProbeHtmlBlockStart(const S: string; Offset: Integer): Integer;
const
  Type1: array[0..3] of string = ('script', 'pre', 'style', 'textarea');
  Type6Tags: array[0..61] of string = (
    'address', 'article', 'aside', 'base', 'basefont', 'blockquote',
    'body', 'caption', 'center', 'col', 'colgroup', 'dd', 'details',
    'dialog', 'dir', 'div', 'dl', 'dt', 'fieldset', 'figcaption',
    'figure', 'footer', 'form', 'frame', 'frameset', 'h1', 'h2', 'h3',
    'h4', 'h5', 'h6', 'head', 'header', 'hr', 'html', 'iframe',
    'legend', 'li', 'link', 'main', 'menu', 'menuitem', 'nav',
    'noframes', 'ol', 'optgroup', 'option', 'p', 'param', 'section',
    'source', 'summary', 'table', 'tbody', 'td', 'tfoot', 'th',
    'thead', 'title', 'tr', 'track', 'ul');
var
  Rest: string;
  TagStart, TagEnd, I: Integer;
  Tag: string;
  After: Char;
begin
  Result := 0;
  if (Offset > Length(S)) or (S[Offset] <> '<') then Exit;
  Rest := Copy(S, Offset, Length(S) - Offset + 1);
  if Length(Rest) < 2 then Exit;

  if (Length(Rest) >= 4) and (Copy(Rest, 1, 4) = '<!--') then Exit(2);
  if (Length(Rest) >= 2) and (Copy(Rest, 1, 2) = '<?') then Exit(3);
  if (Length(Rest) >= 3) and (Rest[2] = '!') and
     (Rest[3] >= 'A') and (Rest[3] <= 'Z') then Exit(4);
  if (Length(Rest) >= 9) and (Copy(Rest, 1, 9) = '<![CDATA[') then Exit(5);

  if Rest[2] = '/' then
    TagStart := 3
  else
    TagStart := 2;
  if TagStart > Length(Rest) then Exit;
  if not (((Rest[TagStart] >= 'a') and (Rest[TagStart] <= 'z')) or
          ((Rest[TagStart] >= 'A') and (Rest[TagStart] <= 'Z'))) then Exit;
  TagEnd := TagStart;
  while (TagEnd <= Length(Rest)) and
        (((Rest[TagEnd] >= 'a') and (Rest[TagEnd] <= 'z')) or
         ((Rest[TagEnd] >= 'A') and (Rest[TagEnd] <= 'Z')) or
         ((Rest[TagEnd] >= '0') and (Rest[TagEnd] <= '9')) or
         (Rest[TagEnd] = '-')) do
    Inc(TagEnd);
  Tag := LowerCase(Copy(Rest, TagStart, TagEnd - TagStart));
  if TagEnd > Length(Rest) then
    After := ' '
  else
    After := Rest[TagEnd];
  if (After = ' ') or (After = #9) or (After = '>') or
     ((After = '/') and (TagEnd + 1 <= Length(Rest)) and
      (Rest[TagEnd + 1] = '>')) then
  begin
    for I := 0 to High(Type1) do
      if Tag = Type1[I] then Exit(1);
    for I := 0 to High(Type6Tags) do
      if Tag = Type6Tags[I] then Exit(6);
  end;
end;

function IsHtmlBlockEnd(const S: string; StartType: Integer): Boolean;
var
  Lower: string;
begin
  case StartType of
    1:
      begin
        Lower := LowerCase(S);
        Result := (Pos('</script>', Lower) > 0) or
                  (Pos('</pre>', Lower) > 0) or
                  (Pos('</style>', Lower) > 0) or
                  (Pos('</textarea>', Lower) > 0);
      end;
    2: Result := Pos('-->', S) > 0;
    3: Result := Pos('?>', S) > 0;
    4: Result := Pos('>', S) > 0;
    5: Result := Pos(']]>', S) > 0;
    6, 7: Result := IsBlankLine(S);
  else
    Result := True;
  end;
end;

// ---------------------------------------------------------------------------
// Open-block stack
// ---------------------------------------------------------------------------

type
  TOpenBlockKind = (
    obDocument, obBlockQuote, obList, obListItem,
    obParagraph, obFencedCode, obIndentedCode, obHtmlBlock, obHeading);

  TOpenBlock = class
    Node: TPixieMdNode;
    Kind: TOpenBlockKind;
    ListContentIndent: Integer;
    FenceChar: Char;
    FenceLen: Integer;
    FenceIndent: Integer;
    HtmlStartType: Integer;
    Text: string;
  end;

  TPixieMdParserImpl = class
  private
    FSource: string;
    FLines: TArray<string>;
    FOptions: TPixieMdOptions;
    FOpen: TList<TOpenBlock>;
    FDoc: TPixieMdNode;

    procedure StripFrontMatter;
    function LineWouldStartBlock(const Line: string;
      Offset: Integer): Boolean;
    procedure ProcessLine(const Line: string;
      MatchContainers: Boolean = True);
    function MatchOpenContainers(const Line: string;
      var Offset: Integer): Integer;
    procedure CloseBlocksFrom(Index: Integer);
    procedure CloseBlock(OB: TOpenBlock);
    function DeepestLeaf: TOpenBlock;
    function CurrentContainer: TOpenBlock;
    procedure AddToContainer(Node: TPixieMdNode);
    procedure AddLeaf(OB: TOpenBlock);
    procedure AppendToParagraph(const Text: string);
    function TryStartListItem(const Line: string;
      var Offset: Integer): Boolean;
  public
    constructor Create(const Md: string; Options: TPixieMdOptions);
    destructor Destroy; override;
    function Parse: TPixieMdNode;
  end;

constructor TPixieMdParserImpl.Create(const Md: string;
  Options: TPixieMdOptions);
begin
  inherited Create;
  FSource := Md;
  FOptions := Options;
  FOpen := TList<TOpenBlock>.Create;
end;

destructor TPixieMdParserImpl.Destroy;
var
  I: Integer;
begin
  if FOpen <> nil then
  begin
    for I := 0 to FOpen.Count - 1 do
      FOpen[I].Free;
    FOpen.Free;
  end;
  inherited Destroy;
end;

procedure TPixieMdParserImpl.StripFrontMatter;
var
  I, Last: Integer;
begin
  if Length(FLines) < 2 then Exit;
  if TrimSpaces(FLines[0]) <> '---' then Exit;
  Last := -1;
  for I := 1 to High(FLines) do
    if TrimSpaces(FLines[I]) = '---' then
    begin
      Last := I;
      Break;
    end;
  if Last < 0 then Exit;
  if (Last + 1 <= High(FLines)) and IsBlankLine(FLines[Last + 1]) then
    Inc(Last);
  FLines := Copy(FLines, Last + 1, Length(FLines) - Last - 1);
end;

function TPixieMdParserImpl.CurrentContainer: TOpenBlock;
var
  I: Integer;
begin
  Result := nil;
  for I := FOpen.Count - 1 downto 0 do
    if FOpen[I].Kind in [obDocument, obBlockQuote, obList, obListItem] then
      Exit(FOpen[I]);
end;

function TPixieMdParserImpl.DeepestLeaf: TOpenBlock;
begin
  Result := nil;
  if FOpen.Count = 0 then Exit;
  Result := FOpen[FOpen.Count - 1];
  if Result.Kind in [obDocument, obBlockQuote, obList, obListItem] then
    Result := nil;
end;

procedure TPixieMdParserImpl.AddToContainer(Node: TPixieMdNode);
var
  Container: TOpenBlock;
begin
  Container := CurrentContainer;
  if (Container = nil) or (Container.Node = nil) then
    FDoc.AddChild(Node)
  else
    Container.Node.AddChild(Node);
end;

procedure TPixieMdParserImpl.AddLeaf(OB: TOpenBlock);
begin
  AddToContainer(OB.Node);
  FOpen.Add(OB);
end;

procedure TPixieMdParserImpl.AppendToParagraph(const Text: string);
var
  OB: TOpenBlock;
  Para: TPixieMdNode;
begin
  OB := DeepestLeaf;
  if (OB <> nil) and (OB.Kind = obParagraph) then
  begin
    if OB.Text <> '' then OB.Text := OB.Text + sLineBreak;
    OB.Text := OB.Text + Text;
    Exit;
  end;
  if OB <> nil then
    CloseBlocksFrom(FOpen.IndexOf(OB));
  Para := TPixieMdNode.Create(mnParagraph);
  OB := TOpenBlock.Create;
  OB.Node := Para;
  OB.Kind := obParagraph;
  OB.Text := Text;
  AddLeaf(OB);
end;

procedure TPixieMdParserImpl.CloseBlock(OB: TOpenBlock);
var
  S: string;
  TextChild: TPixieMdNode;
begin
  case OB.Kind of
    obParagraph, obHeading:
      begin
        // Raw inline source becomes a single mnText child here; the
        // inline parser later replaces it with the parsed inline tree.
        S := TrimSpaces(OB.Text);
        if S <> '' then
        begin
          TextChild := TPixieMdNode.Create(mnText);
          TextChild.Literal := S;
          OB.Node.AddChild(TextChild);
        end;
      end;
    obFencedCode, obIndentedCode:
      begin
        S := OB.Text;
        // Strip a single trailing line break (sLineBreak from accumulator).
        if (Length(S) >= Length(sLineBreak)) and
           (Copy(S, Length(S) - Length(sLineBreak) + 1, Length(sLineBreak)) =
            sLineBreak) then
          SetLength(S, Length(S) - Length(sLineBreak));
        OB.Node.Literal := S;
      end;
    obHtmlBlock:
      begin
        S := OB.Text;
        if (Length(S) >= Length(sLineBreak)) and
           (Copy(S, Length(S) - Length(sLineBreak) + 1, Length(sLineBreak)) =
            sLineBreak) then
          SetLength(S, Length(S) - Length(sLineBreak));
        OB.Node.Literal := S;
      end;
  end;
end;

procedure TPixieMdParserImpl.CloseBlocksFrom(Index: Integer);
var
  I: Integer;
begin
  for I := FOpen.Count - 1 downto Index do
  begin
    CloseBlock(FOpen[I]);
    FOpen[I].Free;
    FOpen.Delete(I);
  end;
end;

function TPixieMdParserImpl.LineWouldStartBlock(const Line: string;
  Offset: Integer): Boolean;
var
  TmpOff, Indent, TmpCS, TmpCE, FenceLen, InfoStart, InfoEnd: Integer;
  TmpOrdered: Boolean;
  TmpListChar: Char;
  TmpStart, TmpAfter, TmpLen: Integer;
begin
  TmpOff := Offset;
  SkipIndent(Line, TmpOff, 3, Indent);
  if ProbeAtxHeading(Line, TmpOff, TmpCS, TmpCE) > 0 then Exit(True);
  if ProbeThematicBreak(Line, TmpOff) then Exit(True);
  if ProbeFence(Line, TmpOff, FenceLen, InfoStart, InfoEnd) <> #0 then
    Exit(True);
  if ProbeBlockQuote(Line, TmpOff) > 0 then Exit(True);
  TmpLen := ProbeListMarker(Line, TmpOff, TmpOrdered, TmpListChar,
    TmpStart, TmpAfter);
  if TmpLen > 0 then Exit(True);
  Result := False;
end;

function TPixieMdParserImpl.MatchOpenContainers(const Line: string;
  var Offset: Integer): Integer;
var
  I, NewOffset, Indent, AfterBq: Integer;
  OB: TOpenBlock;
begin
  Result := FOpen.Count;
  for I := 1 to FOpen.Count - 1 do
  begin
    OB := FOpen[I];
    case OB.Kind of
      obBlockQuote:
        begin
          AfterBq := ProbeBlockQuote(Line, Offset);
          if AfterBq = 0 then Exit(I);
          Offset := AfterBq;
        end;
      obListItem:
        begin
          if IsBlankLine(Line) then Continue;
          NewOffset := Offset;
          SkipIndent(Line, NewOffset, OB.ListContentIndent, Indent);
          if Indent < OB.ListContentIndent then Exit(I);
          Offset := NewOffset;
        end;
      obList: ;
      obFencedCode: ;
      obIndentedCode:
        begin
          if IsBlankLine(Line) then Continue;
          NewOffset := Offset;
          SkipIndent(Line, NewOffset, 4, Indent);
          if Indent < 4 then Exit(I);
          Offset := NewOffset;
        end;
      obHtmlBlock: ;
      obParagraph:
        begin
          if IsBlankLine(Line) then Exit(I);
        end;
      obHeading: Exit(I);
    end;
  end;
end;

function TPixieMdParserImpl.TryStartListItem(const Line: string;
  var Offset: Integer): Boolean;
var
  PreSpaces, Tmp, MarkerLen, ContentIndent, OrderedStart, AfterMarker: Integer;
  IsOrdered: Boolean;
  ListChar: Char;
  Container, ListOB, ItemOB: TOpenBlock;
  ListNode, ItemNode: TPixieMdNode;
  I, ListIdx: Integer;
begin
  Result := False;
  PreSpaces := 0;
  Tmp := Offset;
  while (Tmp <= Length(Line)) and (Line[Tmp] = ' ') and (PreSpaces < 4) do
  begin
    Inc(Tmp);
    Inc(PreSpaces);
  end;
  if PreSpaces >= 4 then Exit;
  MarkerLen := ProbeListMarker(Line, Tmp,
    IsOrdered, ListChar, OrderedStart, AfterMarker);
  if MarkerLen = 0 then Exit;

  ContentIndent := PreSpaces + (AfterMarker - Tmp);
  if (AfterMarker <= Length(Line)) and
     ((Line[AfterMarker] = ' ') or (Line[AfterMarker] = #9)) then
  begin
    Inc(ContentIndent);
    Inc(AfterMarker);
  end
  else
    Inc(ContentIndent);

  Container := nil;
  for I := FOpen.Count - 1 downto 0 do
    if FOpen[I].Kind = obList then
    begin
      Container := FOpen[I];
      Break;
    end;

  if (Container <> nil) and
     (Container.Node.ListOrdered = IsOrdered) then
  begin
    ListIdx := FOpen.IndexOf(Container);
    CloseBlocksFrom(ListIdx + 1);
  end
  else
  begin
    ListNode := TPixieMdNode.Create(mnList);
    ListNode.ListOrdered := IsOrdered;
    ListNode.ListStart := OrderedStart;
    ListNode.ListTight := True;
    ListOB := TOpenBlock.Create;
    ListOB.Node := ListNode;
    ListOB.Kind := obList;
    AddToContainer(ListNode);
    FOpen.Add(ListOB);
  end;

  ItemNode := TPixieMdNode.Create(mnListItem);
  ItemOB := TOpenBlock.Create;
  ItemOB.Node := ItemNode;
  ItemOB.Kind := obListItem;
  ItemOB.ListContentIndent := ContentIndent;
  CurrentContainer.Node.AddChild(ItemNode);
  FOpen.Add(ItemOB);

  Offset := AfterMarker;
  Result := True;
end;

procedure TPixieMdParserImpl.ProcessLine(const Line: string;
  MatchContainers: Boolean);
var
  Offset, FailedAt, Indent, Level: Integer;
  ContentStart, ContentEnd: Integer;
  Heading, CodeNode, HtmlNode, Hr, Bq, NewHeading, Parent,
    TextChild: TPixieMdNode;
  HeadingOB, CodeOB, HtmlOB, BqOB, Leaf, OB: TOpenBlock;
  TmpOff, TmpOffset, FenceLen, InfoStart, InfoEnd: Integer;
  FenceChar: Char;
  HtmlType, BqStart, ChildIdx, SI, ListIdx, ParaIdx, SpacePos: Integer;
  IsBlank: Boolean;
  TextRem: string;
begin
  Offset := 1;
  if MatchContainers then
    FailedAt := MatchOpenContainers(Line, Offset)
  else
    FailedAt := FOpen.Count;
  IsBlank := IsBlankLine(Copy(Line, Offset, Length(Line)));
  Leaf := DeepestLeaf;

  // Fenced code block: check for closing fence first.
  if (Leaf <> nil) and (Leaf.Kind = obFencedCode) then
  begin
    TmpOffset := Offset;
    SkipIndent(Line, TmpOffset, Leaf.FenceIndent, Indent);
    if (Indent <= 3) and IsClosingFence(Line, TmpOffset,
      Leaf.FenceChar, Leaf.FenceLen) then
    begin
      CloseBlocksFrom(FOpen.IndexOf(Leaf));
      Exit;
    end;
    SkipIndent(Line, Offset, Leaf.FenceIndent, Indent);
    Leaf.Text := Leaf.Text + Copy(Line, Offset, Length(Line)) + sLineBreak;
    Exit;
  end;

  // HTML block: append until end condition.
  if (Leaf <> nil) and (Leaf.Kind = obHtmlBlock) then
  begin
    Leaf.Text := Leaf.Text + Line + sLineBreak;
    if IsHtmlBlockEnd(Line, Leaf.HtmlStartType) then
      CloseBlocksFrom(FOpen.IndexOf(Leaf));
    Exit;
  end;

  // Lazy paragraph continuation across container boundaries — only when
  // the line doesn't itself start a new block.
  if FailedAt < FOpen.Count then
  begin
    if (not IsBlank) and (Leaf <> nil) and (Leaf.Kind = obParagraph) and
       not LineWouldStartBlock(Line, Offset) then
    begin
      Leaf.Text := Leaf.Text + sLineBreak +
        TrimSpaces(Copy(Line, Offset, Length(Line)));
      Exit;
    end;
    CloseBlocksFrom(FailedAt);
    Leaf := DeepestLeaf;
  end;

  if IsBlank then
  begin
    if Leaf <> nil then
    begin
      if Leaf.Kind = obParagraph then
        CloseBlocksFrom(FOpen.IndexOf(Leaf))
      else if Leaf.Kind = obIndentedCode then
        Leaf.Text := Leaf.Text + sLineBreak;
    end;
    for ListIdx := FOpen.Count - 1 downto 0 do
      if FOpen[ListIdx].Kind = obList then
      begin
        if FOpen[ListIdx].Node.ChildCount > 0 then
          FOpen[ListIdx].Node.ListTight := False;
        Break;
      end;
    Exit;
  end;

  // 1. Indented code (no paragraph open).
  TmpOff := Offset;
  SkipIndent(Line, TmpOff, 4, Indent);
  if (Indent >= 4) and ((Leaf = nil) or (Leaf.Kind <> obParagraph)) then
  begin
    if (Leaf <> nil) and (Leaf.Kind = obIndentedCode) then
    begin
      Leaf.Text := Leaf.Text + Copy(Line, TmpOff, Length(Line)) + sLineBreak;
      Exit;
    end;
    if Leaf <> nil then CloseBlocksFrom(FOpen.IndexOf(Leaf));
    CodeNode := TPixieMdNode.Create(mnCodeBlock);
    CodeOB := TOpenBlock.Create;
    CodeOB.Node := CodeNode;
    CodeOB.Kind := obIndentedCode;
    CodeOB.Text := Copy(Line, TmpOff, Length(Line)) + sLineBreak;
    AddLeaf(CodeOB);
    Exit;
  end;

  // 2. ATX heading.
  TmpOff := Offset;
  SkipIndent(Line, TmpOff, 3, Indent);
  Level := ProbeAtxHeading(Line, TmpOff, ContentStart, ContentEnd);
  if Level > 0 then
  begin
    if Leaf <> nil then CloseBlocksFrom(FOpen.IndexOf(Leaf));
    Heading := TPixieMdNode.Create(mnHeading);
    Heading.HeadingLevel := Level;
    HeadingOB := TOpenBlock.Create;
    HeadingOB.Node := Heading;
    HeadingOB.Kind := obHeading;
    if ContentStart <= ContentEnd then
      HeadingOB.Text := Copy(Line, ContentStart, ContentEnd - ContentStart + 1)
    else
      HeadingOB.Text := '';
    AddLeaf(HeadingOB);
    CloseBlocksFrom(FOpen.IndexOf(HeadingOB));
    Exit;
  end;

  // 3. Fenced code block.
  TmpOff := Offset;
  SkipIndent(Line, TmpOff, 3, Indent);
  FenceChar := ProbeFence(Line, TmpOff, FenceLen, InfoStart, InfoEnd);
  if FenceChar <> #0 then
  begin
    if Leaf <> nil then CloseBlocksFrom(FOpen.IndexOf(Leaf));
    CodeNode := TPixieMdNode.Create(mnCodeBlock);
    CodeNode.CodeLang := TrimSpaces(Copy(Line, InfoStart,
      InfoEnd - InfoStart + 1));
    SpacePos := Pos(' ', CodeNode.CodeLang);
    if SpacePos > 0 then
      CodeNode.CodeLang := Copy(CodeNode.CodeLang, 1, SpacePos - 1);
    CodeOB := TOpenBlock.Create;
    CodeOB.Node := CodeNode;
    CodeOB.Kind := obFencedCode;
    CodeOB.FenceChar := FenceChar;
    CodeOB.FenceLen := FenceLen;
    CodeOB.FenceIndent := Indent;
    CodeOB.Text := '';
    AddLeaf(CodeOB);
    Exit;
  end;

  // 4. Setext heading underline (when paragraph is open). Must come
  // BEFORE thematic break because '---' matches both, and setext wins
  // when a paragraph is open above it.
  if (Leaf <> nil) and (Leaf.Kind = obParagraph) then
  begin
    TmpOff := Offset;
    SkipIndent(Line, TmpOff, 3, Indent);
    Level := ProbeSetextUnderline(Line, TmpOff);
    if Level > 0 then
    begin
      ParaIdx := FOpen.IndexOf(Leaf);
      if ParaIdx > 0 then
        Parent := FOpen[ParaIdx - 1].Node
      else
        Parent := FDoc;
      if Parent = nil then Parent := FDoc;
      NewHeading := TPixieMdNode.Create(mnHeading);
      NewHeading.HeadingLevel := Level;
      TextChild := TPixieMdNode.Create(mnText);
      TextChild.Literal := TrimSpaces(Leaf.Text);
      NewHeading.AddChild(TextChild);
      ChildIdx := Parent.Children.IndexOf(Leaf.Node);
      Parent.Children.Extract(Leaf.Node);
      Leaf.Node.Free;
      Leaf.Node := nil;
      Parent.Children.Insert(ChildIdx, NewHeading);
      Leaf.Free;
      FOpen.Delete(ParaIdx);
      Exit;
    end;
  end;

  // 5. Thematic break.
  TmpOff := Offset;
  SkipIndent(Line, TmpOff, 3, Indent);
  if ProbeThematicBreak(Line, TmpOff) then
  begin
    if Leaf <> nil then CloseBlocksFrom(FOpen.IndexOf(Leaf));
    Hr := TPixieMdNode.Create(mnThematicBreak);
    AddToContainer(Hr);
    Exit;
  end;

  // 6. Blockquote.
  TmpOff := Offset;
  SkipIndent(Line, TmpOff, 3, Indent);
  BqStart := ProbeBlockQuote(Line, TmpOff);
  if BqStart > 0 then
  begin
    if Leaf <> nil then CloseBlocksFrom(FOpen.IndexOf(Leaf));
    Bq := TPixieMdNode.Create(mnBlockQuote);
    BqOB := TOpenBlock.Create;
    BqOB.Node := Bq;
    BqOB.Kind := obBlockQuote;
    AddToContainer(Bq);
    FOpen.Add(BqOB);
    Offset := BqStart;
    ProcessLine(Copy(Line, Offset, Length(Line)), False);
    Exit;
  end;

  // 7. List item.
  if TryStartListItem(Line, Offset) then
  begin
    TextRem := Copy(Line, Offset, Length(Line));
    if not IsBlankLine(TextRem) then
      ProcessLine(TextRem, False);
    Exit;
  end;

  // 8. HTML block.
  TmpOff := Offset;
  SkipIndent(Line, TmpOff, 3, Indent);
  HtmlType := ProbeHtmlBlockStart(Line, TmpOff);
  if (HtmlType > 0) and (moAllowRawHtml in FOptions) then
  begin
    if Leaf <> nil then CloseBlocksFrom(FOpen.IndexOf(Leaf));
    HtmlNode := TPixieMdNode.Create(mnHtmlBlock);
    HtmlOB := TOpenBlock.Create;
    HtmlOB.Node := HtmlNode;
    HtmlOB.Kind := obHtmlBlock;
    HtmlOB.HtmlStartType := HtmlType;
    HtmlOB.Text := Line + sLineBreak;
    AddLeaf(HtmlOB);
    if IsHtmlBlockEnd(Line, HtmlType) then
      CloseBlocksFrom(FOpen.IndexOf(HtmlOB));
    Exit;
  end;

  // 9. Paragraph (default). Preserve trailing whitespace — the inline
  // parser uses two trailing spaces to detect hard breaks.
  TextRem := Copy(Line, Offset, Length(Line));
  SI := 1;
  while (SI <= Length(TextRem)) and (TextRem[SI] = ' ') and (SI <= 3) do
    Inc(SI);
  Delete(TextRem, 1, SI - 1);
  AppendToParagraph(TextRem);
end;

function TPixieMdParserImpl.Parse: TPixieMdNode;
var
  I: Integer;
  RootOB: TOpenBlock;
begin
  PixieMdSplitLines(FSource, FLines);

  if moStripFrontMatter in FOptions then
    StripFrontMatter;

  FDoc := TPixieMdNode.Create(mnDocument);

  RootOB := TOpenBlock.Create;
  RootOB.Node := nil;
  RootOB.Kind := obDocument;
  FOpen.Add(RootOB);

  for I := 0 to High(FLines) do
    ProcessLine(FLines[I], True);

  CloseBlocksFrom(1);

  Result := FDoc;
end;

class function TPixieMdParser.ParseBlocks(const Md: string;
  RefDefs: TPixieMdLinkRefMap;
  Options: TPixieMdOptions): TPixieMdNode;
var
  Impl: TPixieMdParserImpl;
begin
  Impl := TPixieMdParserImpl.Create(Md, Options);
  try
    Result := Impl.Parse;
  finally
    Impl.Free;
  end;
end;

end.
