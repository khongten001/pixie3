unit Pixie.SimpleXml;

// Minimal XML DOM parser providing the same API surface as FPC's fcl-xml
// (DOM, XMLRead units). Supports the subset needed by Pixie.SvgToPdf:
// element/text nodes, attributes, child iteration, and basic entities.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes;

const
  ELEMENT_NODE = 1;
  TEXT_NODE     = 3;

type
  TDOMNode = class;
  TDOMElement = class;
  TDOMNamedNodeMap = class;

  { TDOMNode }

  TDOMNode = class
  private
    FNodeType: Integer;
    FNodeValue: WideString;
    FFirstChild: TDOMNode;
    FLastChild: TDOMNode;
    FNextSibling: TDOMNode;
  public
    destructor Destroy; override;
    procedure AppendChild(Child: TDOMNode);
    property NodeType: Integer read FNodeType;
    property NodeValue: WideString read FNodeValue write FNodeValue;
    property FirstChild: TDOMNode read FFirstChild;
    property NextSibling: TDOMNode read FNextSibling;
  end;

  { TDOMElement }

  TDOMElement = class(TDOMNode)
  private
    FTagName: WideString;
    FAttrNames: TStringList;
    FAttrValues: TStringList;
    FAttrNode: TDOMNode;
    FAttributes: TDOMNamedNodeMap;
  public
    constructor Create;
    destructor Destroy; override;
    function GetAttribute(const Name: WideString): WideString;
    property TagName: WideString read FTagName;
    property Attributes: TDOMNamedNodeMap read FAttributes;
  end;

  { TDOMNamedNodeMap }

  TDOMNamedNodeMap = class
  private
    FOwner: TDOMElement;
  public
    constructor Create(AOwner: TDOMElement);
    function GetNamedItem(const Name: WideString): TDOMNode;
  end;

  { TXMLDocument }

  TXMLDocument = class(TDOMNode)
  private
    FDocumentElement: TDOMElement;
  public
    destructor Destroy; override;
    property DocumentElement: TDOMElement read FDocumentElement;
  end;

procedure ReadXMLFile(out Doc: TXMLDocument; Stream: TStream);

function DomToStr(const S: WideString): string; inline;
function StrToDom(const S: string): WideString; inline;

implementation

{$IFDEF FPC}
function DomToStr(const S: WideString): string; inline;
begin Result := UTF8Encode(S); end;
function StrToDom(const S: string): WideString; inline;
begin Result := UTF8Decode(S); end;
{$ELSE}
function DomToStr(const S: WideString): string; inline;
begin Result := S; end;
function StrToDom(const S: string): WideString; inline;
begin Result := S; end;
{$ENDIF}

// ---------------------------------------------------------------------------
// TDOMNode
// ---------------------------------------------------------------------------

destructor TDOMNode.Destroy;
var
  Child, Next: TDOMNode;
begin
  Child := FFirstChild;
  while Child <> nil do
  begin
    Next := Child.FNextSibling;
    Child.Free;
    Child := Next;
  end;
  inherited;
end;

procedure TDOMNode.AppendChild(Child: TDOMNode);
begin
  if FLastChild = nil then
    FFirstChild := Child
  else
    FLastChild.FNextSibling := Child;
  FLastChild := Child;
end;

// ---------------------------------------------------------------------------
// TDOMElement
// ---------------------------------------------------------------------------

constructor TDOMElement.Create;
begin
  inherited Create;
  FNodeType := ELEMENT_NODE;
  FAttrNames := TStringList.Create;
  FAttrValues := TStringList.Create;
  FAttrNode := TDOMNode.Create;
  FAttributes := TDOMNamedNodeMap.Create(Self);
end;

destructor TDOMElement.Destroy;
begin
  FAttributes.Free;
  FAttrNode.Free;
  FAttrValues.Free;
  FAttrNames.Free;
  inherited;
end;

function TDOMElement.GetAttribute(const Name: WideString): WideString;
var
  Idx: Integer;
begin
  Idx := FAttrNames.IndexOf(string(Name));
  if Idx >= 0 then
    Result := WideString(FAttrValues[Idx])
  else
    Result := '';
end;

// ---------------------------------------------------------------------------
// TDOMNamedNodeMap
// ---------------------------------------------------------------------------

constructor TDOMNamedNodeMap.Create(AOwner: TDOMElement);
begin
  inherited Create;
  FOwner := AOwner;
end;

function TDOMNamedNodeMap.GetNamedItem(const Name: WideString): TDOMNode;
var
  Idx: Integer;
begin
  Idx := FOwner.FAttrNames.IndexOf(string(Name));
  if Idx >= 0 then
  begin
    FOwner.FAttrNode.FNodeValue := WideString(FOwner.FAttrValues[Idx]);
    Result := FOwner.FAttrNode;
  end
  else
    Result := nil;
end;

// ---------------------------------------------------------------------------
// TXMLDocument
// ---------------------------------------------------------------------------

destructor TXMLDocument.Destroy;
begin
  FDocumentElement.Free;
  inherited;
end;

// ---------------------------------------------------------------------------
// XML Parser
// ---------------------------------------------------------------------------

type
  TXmlParser = record
    Data: string;
    Pos: Integer;
    Len: Integer;
  end;

function AtEnd(var P: TXmlParser): Boolean; inline;
begin
  Result := P.Pos > P.Len;
end;

function Peek(var P: TXmlParser): Char; inline;
begin
  if P.Pos <= P.Len then
    Result := P.Data[P.Pos]
  else
    Result := #0;
end;

procedure Skip(var P: TXmlParser; Count: Integer = 1); inline;
begin
  Inc(P.Pos, Count);
end;

function Matches(var P: TXmlParser; const S: string): Boolean;
var
  I, SLen: Integer;
begin
  SLen := Length(S);
  if P.Pos + SLen - 1 > P.Len then Exit(False);
  for I := 1 to SLen do
    if P.Data[P.Pos + I - 1] <> S[I] then Exit(False);
  Result := True;
end;

procedure SkipWhitespace(var P: TXmlParser);
begin
  while (P.Pos <= P.Len) and (P.Data[P.Pos] <= ' ') do
    Inc(P.Pos);
end;

function DecodeEntity(const S: string): WideString;
var
  Code: Integer;
begin
  if S = 'lt' then Result := '<'
  else if S = 'gt' then Result := '>'
  else if S = 'amp' then Result := '&'
  else if S = 'quot' then Result := '"'
  else if S = 'apos' then Result := ''''
  else if (Length(S) >= 2) and (S[1] = '#') then
  begin
    if (Length(S) >= 3) and ((S[2] = 'x') or (S[2] = 'X')) then
      Code := StrToIntDef('$' + Copy(S, 3, Length(S)), 0)
    else
      Code := StrToIntDef(Copy(S, 2, Length(S)), 0);
    if Code > 0 then
      Result := WideChar(Code)
    else
      Result := '&' + WideString(S) + ';';
  end
  else
    Result := '&' + WideString(S) + ';';
end;

function ReadText(var P: TXmlParser; StopChar: Char): WideString;
var
  Start, EntStart: Integer;
  EntName: string;
begin
  Result := '';
  while (P.Pos <= P.Len) and (P.Data[P.Pos] <> StopChar) do
  begin
    if P.Data[P.Pos] = '&' then
    begin
      Inc(P.Pos);
      EntStart := P.Pos;
      while (P.Pos <= P.Len) and (P.Data[P.Pos] <> ';') do
        Inc(P.Pos);
      EntName := Copy(P.Data, EntStart, P.Pos - EntStart);
      if P.Pos <= P.Len then Inc(P.Pos); // skip ';'
      Result := Result + DecodeEntity(EntName);
    end
    else
    begin
      Start := P.Pos;
      while (P.Pos <= P.Len) and (P.Data[P.Pos] <> StopChar) and
            (P.Data[P.Pos] <> '&') do
        Inc(P.Pos);
      Result := Result + WideString(Copy(P.Data, Start, P.Pos - Start));
    end;
  end;
end;

function ReadAttrValue(var P: TXmlParser): WideString;
var
  Quote: Char;
begin
  SkipWhitespace(P);
  if AtEnd(P) then Exit('');
  Quote := P.Data[P.Pos];
  if (Quote <> '"') and (Quote <> '''') then Exit('');
  Inc(P.Pos);
  Result := ReadText(P, Quote);
  if (P.Pos <= P.Len) and (P.Data[P.Pos] = Quote) then
    Inc(P.Pos);
end;

function ReadName(var P: TXmlParser): string;
var
  Start: Integer;
begin
  Start := P.Pos;
  while (P.Pos <= P.Len) and not
    CharInSet(P.Data[P.Pos], [' ', #9, #10, #13, '/', '>', '=']) do
    Inc(P.Pos);
  Result := Copy(P.Data, Start, P.Pos - Start);
end;

procedure SkipComment(var P: TXmlParser);
begin
  // Skip past '-->'
  while P.Pos <= P.Len do
  begin
    if Matches(P, '-->') then
    begin
      Skip(P, 3);
      Exit;
    end;
    Inc(P.Pos);
  end;
end;

procedure SkipPI(var P: TXmlParser);
begin
  // Skip past '?>'
  while P.Pos <= P.Len do
  begin
    if Matches(P, '?>') then
    begin
      Skip(P, 2);
      Exit;
    end;
    Inc(P.Pos);
  end;
end;

procedure SkipDoctype(var P: TXmlParser);
var
  Depth: Integer;
begin
  // Skip past matching '>'
  Depth := 1;
  while (P.Pos <= P.Len) and (Depth > 0) do
  begin
    if P.Data[P.Pos] = '<' then Inc(Depth)
    else if P.Data[P.Pos] = '>' then Dec(Depth);
    Inc(P.Pos);
  end;
end;

function ReadCDATA(var P: TXmlParser): WideString;
var
  Start: Integer;
begin
  Start := P.Pos;
  while P.Pos <= P.Len do
  begin
    if Matches(P, ']]>') then
    begin
      Result := WideString(Copy(P.Data, Start, P.Pos - Start));
      Skip(P, 3);
      Exit;
    end;
    Inc(P.Pos);
  end;
  Result := WideString(Copy(P.Data, Start, P.Pos - Start));
end;

function ParseElement(var P: TXmlParser): TDOMElement; forward;

procedure ParseChildren(var P: TXmlParser; Parent: TDOMNode;
  const ParentTag: string);
var
  TextVal: WideString;
  TextNode: TDOMNode;
  ChildEl: TDOMElement;
  CloseName: string;
begin
  while not AtEnd(P) do
  begin
    if P.Data[P.Pos] = '<' then
    begin
      // Check for closing tag
      if Matches(P, '</') then
      begin
        Skip(P, 2);
        CloseName := ReadName(P);
        // Skip past '>'
        while (P.Pos <= P.Len) and (P.Data[P.Pos] <> '>') do
          Inc(P.Pos);
        if P.Pos <= P.Len then Inc(P.Pos);
        Exit;
      end;

      // Comment
      if Matches(P, '<!--') then
      begin
        Skip(P, 4);
        SkipComment(P);
        Continue;
      end;

      // CDATA
      if Matches(P, '<![CDATA[') then
      begin
        Skip(P, 9);
        TextVal := ReadCDATA(P);
        if TextVal <> '' then
        begin
          TextNode := TDOMNode.Create;
          TextNode.FNodeType := TEXT_NODE;
          TextNode.FNodeValue := TextVal;
          Parent.AppendChild(TextNode);
        end;
        Continue;
      end;

      // Processing instruction
      if Matches(P, '<?') then
      begin
        Skip(P, 2);
        SkipPI(P);
        Continue;
      end;

      // DOCTYPE
      if Matches(P, '<!') then
      begin
        Skip(P, 2);
        SkipDoctype(P);
        Continue;
      end;

      // Child element
      ChildEl := ParseElement(P);
      if ChildEl <> nil then
        Parent.AppendChild(ChildEl);
    end
    else
    begin
      // Text content
      TextVal := ReadText(P, '<');
      if Trim(string(TextVal)) <> '' then
      begin
        TextNode := TDOMNode.Create;
        TextNode.FNodeType := TEXT_NODE;
        TextNode.FNodeValue := TextVal;
        Parent.AppendChild(TextNode);
      end;
    end;
  end;
end;

function ParseElement(var P: TXmlParser): TDOMElement;
var
  El: TDOMElement;
  TagName, AttrName: string;
  AttrValue: WideString;
  SelfClosing: Boolean;
begin
  Result := nil;
  if AtEnd(P) or (P.Data[P.Pos] <> '<') then Exit;
  Inc(P.Pos); // skip '<'

  TagName := ReadName(P);
  if TagName = '' then Exit;

  El := TDOMElement.Create;
  El.FTagName := WideString(TagName);

  // Parse attributes
  while not AtEnd(P) do
  begin
    SkipWhitespace(P);
    if AtEnd(P) then Break;
    if (P.Data[P.Pos] = '/') or (P.Data[P.Pos] = '>') then Break;

    AttrName := ReadName(P);
    if AttrName = '' then
    begin
      Inc(P.Pos); // skip unknown char
      Continue;
    end;

    SkipWhitespace(P);
    if (P.Pos <= P.Len) and (P.Data[P.Pos] = '=') then
    begin
      Inc(P.Pos); // skip '='
      AttrValue := ReadAttrValue(P);
    end
    else
      AttrValue := WideString(AttrName); // boolean attribute

    El.FAttrNames.Add(AttrName);
    El.FAttrValues.Add(string(AttrValue));
  end;

  // Self-closing?
  SelfClosing := False;
  if (P.Pos <= P.Len) and (P.Data[P.Pos] = '/') then
  begin
    Inc(P.Pos);
    SelfClosing := True;
  end;
  if (P.Pos <= P.Len) and (P.Data[P.Pos] = '>') then
    Inc(P.Pos);

  if not SelfClosing then
    ParseChildren(P, El, TagName);

  Result := El;
end;

// ---------------------------------------------------------------------------
// ReadXMLFile
// ---------------------------------------------------------------------------

procedure ReadXMLFile(out Doc: TXMLDocument; Stream: TStream);
var
  Bytes: TBytes;
  Text: string;
  P: TXmlParser;
  El: TDOMElement;
begin
  Doc := nil;
  if (Stream = nil) or (Stream.Size = 0) then Exit;

  SetLength(Bytes, Stream.Size - Stream.Position);
  Stream.Read(Bytes[0], Length(Bytes));

  // Detect and skip UTF-8 BOM
  {$IFDEF FPC}
  // FPC string = UTF-8 AnsiString — use raw bytes directly
  if (Length(Bytes) >= 3) and
     (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    SetString(Text, PAnsiChar(@Bytes[3]), Length(Bytes) - 3)
  else
    SetString(Text, PAnsiChar(@Bytes[0]), Length(Bytes));
  {$ELSE}
  if (Length(Bytes) >= 3) and
     (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Text := TEncoding.UTF8.GetString(Bytes, 3, Length(Bytes) - 3)
  else
    Text := TEncoding.UTF8.GetString(Bytes);
  {$ENDIF}

  P.Data := Text;
  P.Pos := 1;
  P.Len := Length(Text);

  // Skip prolog (<?xml?>, comments, whitespace, DOCTYPE)
  while not AtEnd(P) do
  begin
    SkipWhitespace(P);
    if AtEnd(P) then Break;

    if Matches(P, '<?') then
    begin
      Skip(P, 2);
      SkipPI(P);
    end
    else if Matches(P, '<!--') then
    begin
      Skip(P, 4);
      SkipComment(P);
    end
    else if Matches(P, '<!') then
    begin
      Skip(P, 2);
      SkipDoctype(P);
    end
    else
      Break;
  end;

  // Parse root element
  if AtEnd(P) then Exit;
  El := ParseElement(P);
  if El = nil then Exit;

  Doc := TXMLDocument.Create;
  Doc.FDocumentElement := El;
end;

end.
