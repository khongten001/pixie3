unit Pixie.SvgRenderer;

// Shared SVG rendering base class.
// Provides SVG parsing (DOM walking, attribute/color/transform/path-data parsing,
// arc-to-bezier conversion, state inheritance) and shape renderers that call
// abstract drawing primitives. Subclasses override the primitives to emit
// backend-specific commands (PDF operators, FMX canvas calls, etc.).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections,
  Pixie.Types, Pixie.WebColor;

type
  { TPixieSvgMatrix - 2D affine transform [a b c d e f] }

  TPixieSvgMatrix = record
    A, B, C, D, E, F: Single;
    class function Identity: TPixieSvgMatrix; static;
    function Multiply(const M: TPixieSvgMatrix): TPixieSvgMatrix;
    class function CreateTranslate(TX, TY: Single): TPixieSvgMatrix; static;
    class function CreateScale(SX, SY: Single): TPixieSvgMatrix; static;
    class function CreateRotate(Angle: Single): TPixieSvgMatrix; static;
    class function CreateRotateAt(Angle, CX, CY: Single): TPixieSvgMatrix; static;
  end;

  { TPixieSvgState - inherited graphics state }

  TPixieSvgState = record
    FillColor: TPixieWebColor;
    StrokeColor: TPixieWebColor;
    StrokeWidth: Single;
    Opacity: Single;
    FillOpacity: Single;
    StrokeOpacity: Single;
    HasFill: Boolean;
    HasStroke: Boolean;
    EvenOddFill: Boolean;
    FontFamily: string;
    FontSize: Single;
    FontWeight: Integer;
    LetterSpacing: Single;
    TextAnchor: TPixieTextAlign;
    FillGradientId: string;
    StrokeGradientId: string;
  end;

  { TPixieSvgGradientStop }

  TPixieSvgGradientStop = record
    Offset: Single;
    Color: TPixieWebColor;
  end;

  TPixieSvgGradientStopList = TList<TPixieSvgGradientStop>;

  { TPixieSvgGradient }

  TPixieSvgGradient = class
  public
    Id: string;
    IsRadial: Boolean;
    X1, Y1, X2, Y2: Single;
    CX, CY, R, FX, FY: Single;
    Stops: TPixieSvgGradientStopList;
    UserSpaceUnits: Boolean;
    HrefId: string;
    GradientTransform: string;
    constructor Create;
    destructor Destroy; override;
  end;

  TPixieSvgGradientMap = TObjectDictionary<string, TPixieSvgGradient>;

  { TPixieSvgPathCmd - tokenised path command }

  TPixieSvgPathCmd = record
    Cmd: AnsiChar;
    Args: array of Single;
  end;

  TPixieSvgPathCmdList = TList<TPixieSvgPathCmd>;

  { TPixieSvgRendererBase - abstract SVG renderer }

  TPixieSvgIdMap = TDictionary<string, Pointer>;
  TPixieSvgStyleMap = TDictionary<string, string>;

  TPixieSvgRendererBase = class
  protected
    FDoc: TObject;
    FSvgRoot: Pointer;
    FInitState: TPixieSvgState;
    FViewBoxX, FViewBoxY, FViewBoxW, FViewBoxH: Single;
    FGradients: TPixieSvgGradientMap;
    FIdMap: TPixieSvgIdMap;
    FStyleMap: TPixieSvgStyleMap;
    FUseDepth: Integer;
  protected
    // Abstract drawing primitives — subclasses override these
    procedure DoMoveTo(X, Y: Single); virtual; abstract;
    procedure DoLineTo(X, Y: Single); virtual; abstract;
    procedure DoCurveTo(X1, Y1, X2, Y2, X3, Y3: Single); virtual; abstract;
    procedure DoClosePath; virtual; abstract;
    procedure DoSaveState; virtual; abstract;
    procedure DoRestoreState; virtual; abstract;
    procedure DoSetTransform(const M: TPixieSvgMatrix); virtual; abstract;
    procedure DoFillAndStroke(const State: TPixieSvgState); virtual; abstract;
    procedure DoBeginOpacity(Opacity: Single); virtual; abstract;
    procedure DoEndOpacity; virtual; abstract;
    procedure DoClipPath; virtual; abstract;
    procedure DoDrawText(const Text: string; X, Y: Single;
      const State: TPixieSvgState); virtual;

    // Attribute parsing
    function GetAttr(Node: Pointer; const Name: string;
      const Default: string = ''): string;
    function ParseSvgFloat(const S: string): Single;
    function ParseSvgColor(const S: string;
      out Color: TPixieWebColor): Boolean;
    function ParseStyleAttribute(
      const StyleStr, PropName: string): string;
    function InheritState(Node: Pointer;
      const ParentState: TPixieSvgState): TPixieSvgState;
    function ParseTransform(const S: string): TPixieSvgMatrix;

    // Path data parsing
    function ParsePathData(const D: string): TPixieSvgPathCmdList;
    procedure EmitPathCommands(Cmds: TPixieSvgPathCmdList);
    procedure ArcToBezier(X1, Y1, RX, RY, XRotation: Single;
      LargeArc, Sweep: Boolean; X2, Y2: Single);

    // Shape helpers
    procedure EmitBezierEllipse(CX, CY, RX, RY: Single);
    procedure ApplyNodeTransform(Node: Pointer);
    procedure ApplyOpacity(const State: TPixieSvgState;
      out NeedRestore: Boolean);
    procedure EmitShapeGeometry(Node: Pointer);
    procedure ApplyClipPath(Node: Pointer);

    // CSS <style> support
    procedure ParseStyleElement(const CSS: string);

    // Gradient support
    procedure CollectDefs(Node: Pointer);
    procedure CollectAllGradients(Node: Pointer);
    procedure ParseGradient(Node: Pointer; IsRadial: Boolean);
    function ResolveGradientStops(const Id: string): TPixieSvgGradient;
    class function ExtractUrlId(const S: string): string; static;

    // ID map for <use> element lookup
    procedure BuildIdMap(Node: Pointer);

    // Shape renderers (call abstract drawing primitives)
    procedure RenderElement(Node: Pointer; const State: TPixieSvgState);
    procedure RenderGroup(Node: Pointer; const State: TPixieSvgState);
    procedure RenderUse(Node: Pointer; const State: TPixieSvgState);
    procedure RenderRect(Node: Pointer; const State: TPixieSvgState);
    procedure RenderCircle(Node: Pointer; const State: TPixieSvgState);
    procedure RenderEllipse(Node: Pointer; const State: TPixieSvgState);
    procedure RenderLine(Node: Pointer; const State: TPixieSvgState);
    procedure RenderPolyline(Node: Pointer; const State: TPixieSvgState;
      ClosePath: Boolean);
    procedure RenderPath(Node: Pointer; const State: TPixieSvgState);
    procedure RenderText(Node: Pointer;
      const State: TPixieSvgState); virtual;
  public
    destructor Destroy; override;

    // Parse SVG XML, extract dimensions. Call RenderDocument after setup.
    function ParseSvg(Data: Pointer; Size: Integer;
      out W, H: Single): Boolean;
    // Override viewport dimensions (call after ParseSvg, before rendering)
    procedure SetViewport(AWidth, AHeight: Single);
    // Render the parsed document by walking the SVG tree.
    procedure RenderDocument;
    // Free the parsed document.
    procedure ClearDocument;
  end;

implementation

uses
  Math, Pixie.SimpleXml, Pixie.Utf8;

const
  Kappa: Single = 0.5522847498;

// FPC DOM uses WideString; Delphi SimpleXml uses WideString too but
// string = UnicodeString, so the UTF8Encode/Decode round-trip is not needed.
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

// Locale-independent float parse (Val uses '.' regardless of locale)
function SvgStrToFloat(const S: string): Single;
var
  Code: Integer;
begin
  Val(S, Result, Code);
  if Code <> 0 then
    Result := 0;
end;

// ===========================================================================
// DOCTYPE entity expansion
// ===========================================================================

procedure ExpandDoctypeEntities(var S: string; DtdStart, DtdEnd: Integer);
var
  Subset, EntName, EntValue: string;
  BracketStart, BracketEnd: Integer;
  P, Q, ValStart, ValEnd: Integer;
  QuoteCh: Char;
begin
  // Find internal subset between [ and ]
  BracketStart := Pos('[', S, DtdStart);
  if (BracketStart = 0) or (BracketStart > DtdEnd) then Exit;
  BracketEnd := Pos(']', S, BracketStart);
  if (BracketEnd = 0) or (BracketEnd > DtdEnd) then Exit;

  Subset := Copy(S, BracketStart + 1, BracketEnd - BracketStart - 1);

  // Parse <!ENTITY Name "Value"> declarations and expand &Name; in body
  P := 1;
  while P < Length(Subset) do
  begin
    P := Pos('<!ENTITY', Subset, P);
    if P = 0 then Break;
    Inc(P, 8);

    // Skip whitespace
    while (P <= Length(Subset)) and (Subset[P] <= ' ') do Inc(P);

    // Read entity name
    Q := P;
    while (Q <= Length(Subset)) and (Subset[Q] > ' ') and
          (Subset[Q] <> '"') and (Subset[Q] <> '''') do Inc(Q);
    EntName := Copy(Subset, P, Q - P);
    P := Q;

    // Skip whitespace
    while (P <= Length(Subset)) and (Subset[P] <= ' ') do Inc(P);
    if P > Length(Subset) then Break;

    // Read quoted value
    QuoteCh := Subset[P];
    if (QuoteCh <> '"') and (QuoteCh <> '''') then
    begin
      Inc(P);
      Continue;
    end;
    Inc(P);
    ValStart := P;
    while (P <= Length(Subset)) and (Subset[P] <> QuoteCh) do Inc(P);
    ValEnd := P;
    EntValue := Copy(Subset, ValStart, ValEnd - ValStart);
    Inc(P);

    // Expand &Name; references in the document body (after DOCTYPE)
    if EntName <> '' then
      S := StringReplace(S, '&' + EntName + ';', EntValue, [rfReplaceAll]);
  end;
end;

// ===========================================================================
// TPixieSvgMatrix
// ===========================================================================

class function TPixieSvgMatrix.Identity: TPixieSvgMatrix;
begin
  Result.A := 1; Result.B := 0;
  Result.C := 0; Result.D := 1;
  Result.E := 0; Result.F := 0;
end;

function TPixieSvgMatrix.Multiply(const M: TPixieSvgMatrix): TPixieSvgMatrix;
begin
  // Column-vector convention matching SVG spec and ConcatMatrix
  Result.A := A * M.A + C * M.B;
  Result.B := B * M.A + D * M.B;
  Result.C := A * M.C + C * M.D;
  Result.D := B * M.C + D * M.D;
  Result.E := A * M.E + C * M.F + E;
  Result.F := B * M.E + D * M.F + F;
end;

class function TPixieSvgMatrix.CreateTranslate(TX, TY: Single): TPixieSvgMatrix;
begin
  Result := Identity;
  Result.E := TX;
  Result.F := TY;
end;

class function TPixieSvgMatrix.CreateScale(SX, SY: Single): TPixieSvgMatrix;
begin
  Result := Identity;
  Result.A := SX;
  Result.D := SY;
end;

class function TPixieSvgMatrix.CreateRotate(Angle: Single): TPixieSvgMatrix;
var
  Rad, S, C: Single;
begin
  Rad := Angle * Pi / 180.0;
  S := Sin(Rad);
  C := Cos(Rad);
  Result.A := C;  Result.B := S;
  Result.C := -S; Result.D := C;
  Result.E := 0;  Result.F := 0;
end;

class function TPixieSvgMatrix.CreateRotateAt(Angle, CX, CY: Single): TPixieSvgMatrix;
begin
  Result := CreateTranslate(CX, CY).Multiply(
    CreateRotate(Angle)).Multiply(
    CreateTranslate(-CX, -CY));
end;

// ===========================================================================
// TPixieSvgGradient
// ===========================================================================

constructor TPixieSvgGradient.Create;
begin
  inherited Create;
  Stops := TPixieSvgGradientStopList.Create;
  // Linear defaults (left to right in objectBoundingBox)
  X1 := 0; Y1 := 0; X2 := 1; Y2 := 0;
  // Radial defaults
  CX := 0.5; CY := 0.5; R := 0.5; FX := -1; FY := -1;
  UserSpaceUnits := False;
end;

destructor TPixieSvgGradient.Destroy;
begin
  Stops.Free;
  inherited;
end;

// ===========================================================================
// TPixieSvgRendererBase — lifecycle
// ===========================================================================

destructor TPixieSvgRendererBase.Destroy;
begin
  ClearDocument;
  inherited;
end;

procedure TPixieSvgRendererBase.ClearDocument;
begin
  FreeAndNil(FGradients);
  FreeAndNil(FIdMap);
  FreeAndNil(FStyleMap);
  if FDoc <> nil then
  begin
    FDoc.Free;
    FDoc := nil;
  end;
  FSvgRoot := nil;
end;

// ===========================================================================
// Default DoDrawText — no-op, override in subclasses
// ===========================================================================

procedure TPixieSvgRendererBase.DoDrawText(const Text: string;
  X, Y: Single; const State: TPixieSvgState);
begin
  // no-op — override in subclass for text rendering
end;

// ===========================================================================
// Attribute parsing
// ===========================================================================

function TPixieSvgRendererBase.GetAttr(Node: Pointer; const Name: string;
  const Default: string): string;
var
  El: TDOMElement;
  Attr: TDOMNode;
begin
  Result := Default;
  if Node = nil then Exit;
  El := TDOMElement(Node);
  Attr := El.Attributes.GetNamedItem(StrToDom(Name));
  if Attr <> nil then
    Result := DomToStr(Attr.NodeValue);
end;

function TPixieSvgRendererBase.ParseSvgFloat(const S: string): Single;
var
  Trimmed, Suffix: string;
  Code, Len: Integer;
  Scale: Single;
begin
  Result := 0;
  Trimmed := Trim(S);
  if Trimmed = '' then Exit;

  // Handle percentage suffix (e.g. "50%" → 0.5)
  Len := Length(Trimmed);
  if (Len > 1) and (Trimmed[Len] = '%') then
  begin
    Trimmed := Copy(Trimmed, 1, Len - 1);
    Val(Trimmed, Result, Code);
    if Code = 0 then
      Result := Result / 100.0;
    Exit;
  end;

  // Detect and strip unit suffix, apply conversion factor
  // SVG default is px (user units); 1in=96px, 1cm=96/2.54, 1mm=96/25.4, 1pt=96/72
  Scale := 1.0;
  if Len > 2 then
  begin
    Suffix := Copy(Trimmed, Len - 1, 2);
    if Suffix = 'px' then
      Trimmed := Copy(Trimmed, 1, Len - 2)
    else if Suffix = 'cm' then
    begin
      Trimmed := Copy(Trimmed, 1, Len - 2);
      Scale := 96.0 / 2.54;
    end
    else if Suffix = 'mm' then
    begin
      Trimmed := Copy(Trimmed, 1, Len - 2);
      Scale := 96.0 / 25.4;
    end
    else if Suffix = 'in' then
    begin
      Trimmed := Copy(Trimmed, 1, Len - 2);
      Scale := 96.0;
    end
    else if Suffix = 'pt' then
    begin
      Trimmed := Copy(Trimmed, 1, Len - 2);
      Scale := 96.0 / 72.0;
    end
    else if Suffix = 'pc' then
    begin
      Trimmed := Copy(Trimmed, 1, Len - 2);
      Scale := 96.0 / 6.0;
    end
    else if Suffix = 'em' then
      Trimmed := Copy(Trimmed, 1, Len - 2);
  end;

  Val(Trimmed, Result, Code);
  if Code = 0 then
    Result := Result * Scale;
end;

function TPixieSvgRendererBase.ParseSvgColor(const S: string;
  out Color: TPixieWebColor): Boolean;
var
  Trimmed, Lower: string;
  P, ParenStart, Depth: Integer;
  Vals: array[0..3] of Single;
  ValCount: Integer;
  NumStr: string;
  AlphaIsPercent: Boolean;
  Fallback: string;
begin
  Trimmed := Trim(S);
  if (Trimmed = '') or (Trimmed = 'none') then
  begin
    Result := False;
    Exit;
  end;

  // Resolve var() — extract fallback value (handles nesting)
  Lower := LowerCase(Trimmed);
  while Pos('var(', Lower) = 1 do
  begin
    // Find the comma separating property name from fallback
    P := 5; // after 'var('
    Depth := 1;
    while (P <= Length(Trimmed)) and (Depth > 0) do
    begin
      if Trimmed[P] = '(' then Inc(Depth)
      else if Trimmed[P] = ')' then Dec(Depth)
      else if (Trimmed[P] = ',') and (Depth = 1) then Break;
      Inc(P);
    end;
    if (P > Length(Trimmed)) or (Trimmed[P] <> ',') then
    begin
      // No fallback — cannot resolve
      Exit(False);
    end;
    // Extract fallback, strip outer closing paren
    Fallback := Trim(Copy(Trimmed, P + 1, Length(Trimmed) - P));
    if (Length(Fallback) > 0) and (Fallback[Length(Fallback)] = ')') then
      Fallback := Trim(Copy(Fallback, 1, Length(Fallback) - 1));
    Trimmed := Fallback;
    Lower := LowerCase(Trimmed);
  end;

  if (Trimmed = '') or (Trimmed = 'none') then
    Exit(False);

  // Try rgb()/rgba() first
  if (Pos('rgb(', Lower) = 1) or (Pos('rgba(', Lower) = 1) then
  begin
    ParenStart := Pos('(', Trimmed);
    if ParenStart = 0 then Exit(False);
    P := ParenStart + 1;
    ValCount := 0;
    AlphaIsPercent := False;
    while (P <= Length(Trimmed)) and (ValCount < 4) do
    begin
      while (P <= Length(Trimmed)) and
            CharInSet(Trimmed[P], [' ', ',', '/', #9]) do Inc(P);
      if (P > Length(Trimmed)) or (Trimmed[P] = ')') then Break;

      NumStr := '';
      while (P <= Length(Trimmed)) and
            CharInSet(Trimmed[P], ['0'..'9', '.', '-']) do
      begin
        NumStr := NumStr + Trimmed[P];
        Inc(P);
      end;
      if NumStr = '' then Break;

      Vals[ValCount] := SvgStrToFloat(NumStr);
      if (P <= Length(Trimmed)) and (Trimmed[P] = '%') then
      begin
        if ValCount < 3 then
          Vals[ValCount] := Vals[ValCount] * 255 / 100
        else
          AlphaIsPercent := True;
        Inc(P);
      end;
      Inc(ValCount);
    end;

    if ValCount >= 3 then
    begin
      Color := TPixieWebColor.Create(
        EnsureRange(Round(Vals[0]), 0, 255),
        EnsureRange(Round(Vals[1]), 0, 255),
        EnsureRange(Round(Vals[2]), 0, 255));
      if ValCount >= 4 then
      begin
        if AlphaIsPercent then
          Color.Alpha := EnsureRange(Round(Vals[3] * 255 / 100), 0, 255)
        else
          Color.Alpha := EnsureRange(Round(Vals[3] * 255), 0, 255);
      end;
      Exit(True);
    end;
    Exit(False);
  end;

  Result := PixieParseColorString(Trimmed, Color);
end;

procedure TPixieSvgRendererBase.ParseStyleElement(const CSS: string);
var
  P, Len, BraceStart, BraceEnd: Integer;
  Selector, Declarations: string;
begin
  if FStyleMap = nil then
    FStyleMap := TPixieSvgStyleMap.Create;

  P := 1;
  Len := Length(CSS);
  while P <= Len do
  begin
    // Skip whitespace and comments
    while (P <= Len) and (CSS[P] <= ' ') do Inc(P);
    if (P < Len) and (CSS[P] = '/') and (CSS[P + 1] = '*') then
    begin
      Inc(P, 2);
      while (P < Len) and not ((CSS[P] = '*') and (CSS[P + 1] = '/')) do Inc(P);
      Inc(P, 2);
      Continue;
    end;
    if P > Len then Break;

    // Read selector(s) up to '{'
    BraceStart := P;
    while (BraceStart <= Len) and (CSS[BraceStart] <> '{') do Inc(BraceStart);
    if BraceStart > Len then Break;
    Selector := Trim(Copy(CSS, P, BraceStart - P));

    // Read declarations up to '}'
    BraceEnd := BraceStart + 1;
    while (BraceEnd <= Len) and (CSS[BraceEnd] <> '}') do Inc(BraceEnd);
    if BraceEnd > Len then Break;
    Declarations := Trim(Copy(CSS, BraceStart + 1, BraceEnd - BraceStart - 1));
    P := BraceEnd + 1;

    // Handle simple class selectors: .className
    if (Length(Selector) > 1) and (Selector[1] = '.') and
       (Pos(' ', Selector) = 0) and (Pos(',', Selector) = 0) then
      FStyleMap.AddOrSetValue(Copy(Selector, 2, MaxInt), Declarations);
  end;
end;

function TPixieSvgRendererBase.ParseStyleAttribute(
  const StyleStr, PropName: string): string;
var
  Props: string;
  P, SemiPos, ColonPos: Integer;
  Key, Value: string;
begin
  Result := '';
  Props := StyleStr;
  P := 1;
  while P <= Length(Props) do
  begin
    SemiPos := Pos(';', Props, P);
    if SemiPos = 0 then
      SemiPos := Length(Props) + 1;

    Key := Trim(Copy(Props, P, SemiPos - P));
    ColonPos := Pos(':', Key);
    if ColonPos > 0 then
    begin
      Value := Trim(Copy(Key, ColonPos + 1, MaxInt));
      Key := Trim(Copy(Key, 1, ColonPos - 1));
      if LowerCase(Key) = LowerCase(PropName) then
      begin
        Result := Value;
        Exit;
      end;
    end;
    P := SemiPos + 1;
  end;
end;

function TPixieSvgRendererBase.InheritState(Node: Pointer;
  const ParentState: TPixieSvgState): TPixieSvgState;
var
  FillStr, StrokeStr, StrokeWStr, OpacStr: string;
  FillOpStr, StrokeOpStr: string;
  StyleStr, ClassStr, ClassDecl, InlineStyleStr: string;
  FontFamilyStr, FontSizeStr, FontWeightStr: string;
  LetterSpacingStr: string;
  AnchorStr: string;
  Color: TPixieWebColor;
  SpacePos: Integer;
  ClassName: string;
begin
  Result := ParentState;

  // Resolve class-based styles from <style> element
  StyleStr := '';
  if FStyleMap <> nil then
  begin
    ClassStr := GetAttr(Node, 'class');
    if ClassStr <> '' then
    begin
      // Support space-separated class lists: class="st0 st1 st2"
      while ClassStr <> '' do
      begin
        SpacePos := Pos(' ', ClassStr);
        if SpacePos > 0 then
        begin
          ClassName := Copy(ClassStr, 1, SpacePos - 1);
          ClassStr := TrimLeft(Copy(ClassStr, SpacePos + 1, MaxInt));
        end
        else
        begin
          ClassName := ClassStr;
          ClassStr := '';
        end;
        if (ClassName <> '') and FStyleMap.TryGetValue(ClassName, ClassDecl) then
        begin
          if StyleStr <> '' then
            StyleStr := StyleStr + ';' + ClassDecl
          else
            StyleStr := ClassDecl;
        end;
      end;
    end;
  end;

  // Inline style attribute overrides class styles
  InlineStyleStr := GetAttr(Node, 'style');
  if InlineStyleStr <> '' then
  begin
    if StyleStr <> '' then
      StyleStr := StyleStr + ';' + InlineStyleStr
    else
      StyleStr := InlineStyleStr;
  end;

  // Fill
  FillStr := GetAttr(Node, 'fill');
  if FillStr = '' then
    FillStr := ParseStyleAttribute(StyleStr, 'fill');
  if FillStr <> '' then
  begin
    if FillStr = 'none' then
    begin
      Result.HasFill := False;
      Result.FillGradientId := '';
    end
    else if Pos('url(', LowerCase(FillStr)) > 0 then
    begin
      Result.FillGradientId := ExtractUrlId(FillStr);
      Result.HasFill := True;
    end
    else if (FillStr <> 'inherit') and ParseSvgColor(FillStr, Color) then
    begin
      Result.FillColor := Color;
      Result.HasFill := True;
      Result.FillGradientId := '';
    end;
  end;

  // Stroke
  StrokeStr := GetAttr(Node, 'stroke');
  if StrokeStr = '' then
    StrokeStr := ParseStyleAttribute(StyleStr, 'stroke');
  if StrokeStr <> '' then
  begin
    if StrokeStr = 'none' then
    begin
      Result.HasStroke := False;
      Result.StrokeGradientId := '';
    end
    else if Pos('url(', LowerCase(StrokeStr)) > 0 then
    begin
      Result.StrokeGradientId := ExtractUrlId(StrokeStr);
      Result.HasStroke := True;
    end
    else if (StrokeStr <> 'inherit') and ParseSvgColor(StrokeStr, Color) then
    begin
      Result.StrokeColor := Color;
      Result.HasStroke := True;
      Result.StrokeGradientId := '';
    end;
  end;

  // Stroke width
  StrokeWStr := GetAttr(Node, 'stroke-width');
  if StrokeWStr = '' then
    StrokeWStr := ParseStyleAttribute(StyleStr, 'stroke-width');
  if StrokeWStr <> '' then
    Result.StrokeWidth := ParseSvgFloat(StrokeWStr);

  // Opacity
  OpacStr := GetAttr(Node, 'opacity');
  if OpacStr = '' then
    OpacStr := ParseStyleAttribute(StyleStr, 'opacity');
  if OpacStr <> '' then
    Result.Opacity := ParseSvgFloat(OpacStr);

  // Fill opacity
  FillOpStr := GetAttr(Node, 'fill-opacity');
  if FillOpStr = '' then
    FillOpStr := ParseStyleAttribute(StyleStr, 'fill-opacity');
  if FillOpStr <> '' then
    Result.FillOpacity := ParseSvgFloat(FillOpStr);

  // Stroke opacity
  StrokeOpStr := GetAttr(Node, 'stroke-opacity');
  if StrokeOpStr = '' then
    StrokeOpStr := ParseStyleAttribute(StyleStr, 'stroke-opacity');
  if StrokeOpStr <> '' then
    Result.StrokeOpacity := ParseSvgFloat(StrokeOpStr);

  // Font family
  FontFamilyStr := GetAttr(Node, 'font-family');
  if FontFamilyStr = '' then
    FontFamilyStr := ParseStyleAttribute(StyleStr, 'font-family');
  if FontFamilyStr <> '' then
  begin
    // Strip quotes and use first family
    FontFamilyStr := StringReplace(FontFamilyStr, '''', '', [rfReplaceAll]);
    FontFamilyStr := StringReplace(FontFamilyStr, '"', '', [rfReplaceAll]);
    if Pos(',', FontFamilyStr) > 0 then
      FontFamilyStr := Trim(Copy(FontFamilyStr, 1, Pos(',', FontFamilyStr) - 1));
    Result.FontFamily := FontFamilyStr;
  end;

  // Font size
  FontSizeStr := GetAttr(Node, 'font-size');
  if FontSizeStr = '' then
    FontSizeStr := ParseStyleAttribute(StyleStr, 'font-size');
  if FontSizeStr <> '' then
    Result.FontSize := ParseSvgFloat(FontSizeStr);

  // Font weight
  FontWeightStr := GetAttr(Node, 'font-weight');
  if FontWeightStr = '' then
    FontWeightStr := ParseStyleAttribute(StyleStr, 'font-weight');
  if FontWeightStr <> '' then
  begin
    if FontWeightStr = 'bold' then
      Result.FontWeight := 700
    else if FontWeightStr = 'normal' then
      Result.FontWeight := 400
    else
      Result.FontWeight := Round(ParseSvgFloat(FontWeightStr));
  end;

  // Letter spacing
  LetterSpacingStr := GetAttr(Node, 'letter-spacing');
  if LetterSpacingStr = '' then
    LetterSpacingStr := ParseStyleAttribute(StyleStr, 'letter-spacing');
  if LetterSpacingStr <> '' then
  begin
    if LetterSpacingStr = 'normal' then
      Result.LetterSpacing := 0
    else
      Result.LetterSpacing := ParseSvgFloat(LetterSpacingStr);
  end;

  // Text anchor
  AnchorStr := GetAttr(Node, 'text-anchor');
  if AnchorStr = '' then
    AnchorStr := ParseStyleAttribute(StyleStr, 'text-anchor');
  if AnchorStr = 'middle' then
    Result.TextAnchor := taCenter
  else if AnchorStr = 'end' then
    Result.TextAnchor := taRight
  else if AnchorStr = 'start' then
    Result.TextAnchor := taLeft;

  // Fill rule
  AnchorStr := GetAttr(Node, 'fill-rule');
  if AnchorStr = '' then
    AnchorStr := ParseStyleAttribute(StyleStr, 'fill-rule');
  if AnchorStr = 'evenodd' then
    Result.EvenOddFill := True
  else if AnchorStr = 'nonzero' then
    Result.EvenOddFill := False;
end;

// ===========================================================================
// Transform parsing
// ===========================================================================

function TPixieSvgRendererBase.ParseTransform(const S: string): TPixieSvgMatrix;
var
  P, Len: Integer;
  FuncName: string;
  Args: array[0..5] of Single;
  ArgCount: Integer;
  NumStr: string;
  M: TPixieSvgMatrix;

  procedure ParseArgs;
  begin
    ArgCount := 0;
    // Skip '('
    while (P <= Len) and (S[P] <> '(') do Inc(P);
    Inc(P); // skip '('

    while (P <= Len) and (S[P] <> ')') do
    begin
      // Skip separators
      while (P <= Len) and CharInSet(S[P], [' ', ',', #9, #10, #13]) do Inc(P);
      if (P > Len) or (S[P] = ')') then Break;

      // Read number
      NumStr := '';
      if (P <= Len) and CharInSet(S[P], ['-', '+']) then
      begin
        NumStr := NumStr + S[P];
        Inc(P);
      end;
      while (P <= Len) and CharInSet(S[P], ['0'..'9', '.', 'e', 'E']) do
      begin
        NumStr := NumStr + S[P];
        Inc(P);
      end;

      if (NumStr <> '') and (ArgCount <= High(Args)) then
      begin
        Args[ArgCount] := SvgStrToFloat(NumStr);
        Inc(ArgCount);
      end;
    end;

    if (P <= Len) and (S[P] = ')') then Inc(P);
  end;

begin
  Result := TPixieSvgMatrix.Identity;
  P := 1;
  Len := Length(S);

  while P <= Len do
  begin
    // Skip whitespace
    while (P <= Len) and CharInSet(S[P], [' ', ',', #9, #10, #13]) do Inc(P);
    if P > Len then Break;

    // Read function name
    FuncName := '';
    while (P <= Len) and CharInSet(S[P], ['a'..'z', 'A'..'Z']) do
    begin
      FuncName := FuncName + S[P];
      Inc(P);
    end;

    if FuncName = '' then
    begin
      Inc(P);
      Continue;
    end;

    FuncName := LowerCase(FuncName);
    FillChar(Args, SizeOf(Args), 0);
    ParseArgs;

    if FuncName = 'translate' then
    begin
      M := TPixieSvgMatrix.CreateTranslate(Args[0],
        IfThen(ArgCount >= 2, Args[1], 0));
      Result := Result.Multiply(M);
    end
    else if FuncName = 'scale' then
    begin
      if ArgCount >= 2 then
        M := TPixieSvgMatrix.CreateScale(Args[0], Args[1])
      else
        M := TPixieSvgMatrix.CreateScale(Args[0], Args[0]);
      Result := Result.Multiply(M);
    end
    else if FuncName = 'rotate' then
    begin
      if ArgCount >= 3 then
        M := TPixieSvgMatrix.CreateRotateAt(Args[0], Args[1], Args[2])
      else
        M := TPixieSvgMatrix.CreateRotate(Args[0]);
      Result := Result.Multiply(M);
    end
    else if FuncName = 'matrix' then
    begin
      if ArgCount >= 6 then
      begin
        M.A := Args[0]; M.B := Args[1];
        M.C := Args[2]; M.D := Args[3];
        M.E := Args[4]; M.F := Args[5];
        Result := Result.Multiply(M);
      end;
    end;
  end;
end;

// ===========================================================================
// Shape helpers
// ===========================================================================

procedure TPixieSvgRendererBase.ApplyNodeTransform(Node: Pointer);
var
  TransStr: string;
  M: TPixieSvgMatrix;
begin
  TransStr := GetAttr(Node, 'transform');
  if TransStr = '' then Exit;

  M := ParseTransform(TransStr);
  // Only apply if not identity
  if (Abs(M.A - 1) > 0.0001) or (Abs(M.B) > 0.0001) or
     (Abs(M.C) > 0.0001) or (Abs(M.D - 1) > 0.0001) or
     (Abs(M.E) > 0.0001) or (Abs(M.F) > 0.0001) then
    DoSetTransform(M);
end;

procedure TPixieSvgRendererBase.ApplyOpacity(const State: TPixieSvgState;
  out NeedRestore: Boolean);
begin
  NeedRestore := False;
  if State.Opacity >= 1.0 then Exit;
  DoBeginOpacity(State.Opacity);
  NeedRestore := True;
end;

procedure TPixieSvgRendererBase.EmitShapeGeometry(Node: Pointer);
var
  TagName: string;
  X, Y, W, H, CX, CY, R, RX, RY: Single;
  D: string;
  Cmds: TPixieSvgPathCmdList;
begin
  TagName := LowerCase(DomToStr(TDOMElement(Node).TagName));

  if TagName = 'path' then
  begin
    D := GetAttr(Node, 'd');
    if D <> '' then
    begin
      Cmds := ParsePathData(D);
      try
        EmitPathCommands(Cmds);
      finally
        Cmds.Free;
      end;
    end;
  end
  else if TagName = 'rect' then
  begin
    X := ParseSvgFloat(GetAttr(Node, 'x', '0'));
    Y := ParseSvgFloat(GetAttr(Node, 'y', '0'));
    W := ParseSvgFloat(GetAttr(Node, 'width', '0'));
    H := ParseSvgFloat(GetAttr(Node, 'height', '0'));
    if (W > 0) and (H > 0) then
    begin
      DoMoveTo(X, Y);
      DoLineTo(X + W, Y);
      DoLineTo(X + W, Y + H);
      DoLineTo(X, Y + H);
      DoClosePath;
    end;
  end
  else if TagName = 'circle' then
  begin
    CX := ParseSvgFloat(GetAttr(Node, 'cx', '0'));
    CY := ParseSvgFloat(GetAttr(Node, 'cy', '0'));
    R := ParseSvgFloat(GetAttr(Node, 'r', '0'));
    if R > 0 then
      EmitBezierEllipse(CX, CY, R, R);
  end
  else if TagName = 'ellipse' then
  begin
    CX := ParseSvgFloat(GetAttr(Node, 'cx', '0'));
    CY := ParseSvgFloat(GetAttr(Node, 'cy', '0'));
    RX := ParseSvgFloat(GetAttr(Node, 'rx', '0'));
    RY := ParseSvgFloat(GetAttr(Node, 'ry', '0'));
    if (RX > 0) and (RY > 0) then
      EmitBezierEllipse(CX, CY, RX, RY);
  end
  else if TagName = 'polygon' then
  begin
    // Reuse polyline parsing — emit points and close
    D := GetAttr(Node, 'points');
    if D <> '' then
    begin
      // Parse points as path M...L...Z
      D := 'M' + D + 'Z';
      Cmds := ParsePathData(D);
      try
        EmitPathCommands(Cmds);
      finally
        Cmds.Free;
      end;
    end;
  end;
end;

procedure TPixieSvgRendererBase.ApplyClipPath(Node: Pointer);
var
  ClipStr, ClipId: string;
  ClipEl: Pointer;
  Child: TDOMNode;
begin
  if FIdMap = nil then Exit;

  ClipStr := GetAttr(Node, 'clip-path');
  if ClipStr = '' then Exit;

  ClipId := ExtractUrlId(ClipStr);
  if ClipId = '' then Exit;

  if not FIdMap.TryGetValue(ClipId, ClipEl) then Exit;

  // Emit geometry of all children in the <clipPath> element
  Child := TDOMNode(ClipEl).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = ELEMENT_NODE then
      EmitShapeGeometry(Child);
    Child := Child.NextSibling;
  end;

  DoClipPath;
end;

procedure TPixieSvgRendererBase.EmitBezierEllipse(CX, CY, RX, RY: Single);
var
  KX, KY: Single;
begin
  KX := RX * Kappa;
  KY := RY * Kappa;

  DoMoveTo(CX, CY - RY);
  // Top -> right
  DoCurveTo(CX + KX, CY - RY, CX + RX, CY - KY, CX + RX, CY);
  // Right -> bottom
  DoCurveTo(CX + RX, CY + KY, CX + KX, CY + RY, CX, CY + RY);
  // Bottom -> left
  DoCurveTo(CX - KX, CY + RY, CX - RX, CY + KY, CX - RX, CY);
  // Left -> top
  DoCurveTo(CX - RX, CY - KY, CX - KX, CY - RY, CX, CY - RY);
end;

// ===========================================================================
// Gradient support
// ===========================================================================

class function TPixieSvgRendererBase.ExtractUrlId(const S: string): string;
var
  P1, P2: Integer;
begin
  Result := '';
  P1 := Pos('#', S);
  if P1 = 0 then Exit;
  Inc(P1);
  P2 := Pos(')', S, P1);
  if P2 = 0 then P2 := Length(S) + 1;
  Result := Trim(Copy(S, P1, P2 - P1));
  // Strip optional quotes
  if (Length(Result) >= 2) and (Result[1] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

procedure TPixieSvgRendererBase.CollectDefs(Node: Pointer);
var
  Child: TDOMNode;
  El: TDOMElement;
  TagName: string;
begin
  if FGradients = nil then
    FGradients := TPixieSvgGradientMap.Create([doOwnsValues]);

  Child := TDOMNode(Node).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = ELEMENT_NODE then
    begin
      El := TDOMElement(Child);
      TagName := LowerCase(DomToStr(El.TagName));
      if TagName = 'lineargradient' then
        ParseGradient(Child, False)
      else if TagName = 'radialgradient' then
        ParseGradient(Child, True);
    end;
    Child := Child.NextSibling;
  end;
end;

procedure TPixieSvgRendererBase.CollectAllGradients(Node: Pointer);
begin
  // Merged into BuildIdMap — single tree walk collects both IDs and gradients
  BuildIdMap(Node);
end;

procedure TPixieSvgRendererBase.BuildIdMap(Node: Pointer);
var
  Child, TextChild: TDOMNode;
  El: TDOMElement;
  IdStr, TagName, CSS: string;
begin
  if FIdMap = nil then
    FIdMap := TPixieSvgIdMap.Create;

  if TDOMNode(Node).NodeType = ELEMENT_NODE then
  begin
    El := TDOMElement(Node);
    IdStr := DomToStr(El.GetAttribute('id'));
    if IdStr <> '' then
      FIdMap.AddOrSetValue(IdStr, Node);
  end;

  Child := TDOMNode(Node).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = ELEMENT_NODE then
    begin
      TagName := LowerCase(DomToStr(TDOMElement(Child).TagName));
      if TagName = 'defs' then
        CollectDefs(Child)
      else if TagName = 'lineargradient' then
        ParseGradient(Child, False)
      else if TagName = 'radialgradient' then
        ParseGradient(Child, True)
      else if TagName = 'style' then
      begin
        CSS := '';
        TextChild := Child.FirstChild;
        while TextChild <> nil do
        begin
          if TextChild.NodeType = TEXT_NODE then
            CSS := CSS + DomToStr(TextChild.NodeValue);
          TextChild := TextChild.NextSibling;
        end;
        if CSS <> '' then
          ParseStyleElement(CSS);
      end;
      BuildIdMap(Child);
    end;
    Child := Child.NextSibling;
  end;
end;

procedure TPixieSvgRendererBase.ParseGradient(Node: Pointer;
  IsRadial: Boolean);
var
  El: TDOMElement;
  Grad: TPixieSvgGradient;
  GradId, Units, HrefStr: string;
  Child: TDOMNode;
  ChildEl: TDOMElement;
  ChildTag: string;
  Stop: TPixieSvgGradientStop;
  OffsetStr, StopColorStr, StopOpacStr, StyleStr: string;
  StopColor: TPixieWebColor;
  StopOpacity: Single;
begin
  if FGradients = nil then
    FGradients := TPixieSvgGradientMap.Create([doOwnsValues]);

  El := TDOMElement(Node);
  GradId := DomToStr(El.GetAttribute('id'));
  if GradId = '' then Exit;
  if (FGradients <> nil) and FGradients.ContainsKey(GradId) then Exit;

  Grad := TPixieSvgGradient.Create;
  Grad.Id := GradId;
  Grad.IsRadial := IsRadial;

  // gradientUnits
  Units := DomToStr(El.GetAttribute('gradientUnits'));
  Grad.UserSpaceUnits := (LowerCase(Units) = 'userspaceonuse');

  // xlink:href / href
  HrefStr := DomToStr(El.GetAttribute('xlink:href'));
  if HrefStr = '' then
    HrefStr := DomToStr(El.GetAttribute('href'));
  if (HrefStr <> '') and (HrefStr[1] = '#') then
    Grad.HrefId := Copy(HrefStr, 2, MaxInt);

  // gradientTransform
  Grad.GradientTransform := DomToStr(El.GetAttribute('gradientTransform'));

  if IsRadial then
  begin
    Grad.CX := ParseSvgFloat(GetAttr(Node, 'cx', '0.5'));
    Grad.CY := ParseSvgFloat(GetAttr(Node, 'cy', '0.5'));
    Grad.R := ParseSvgFloat(GetAttr(Node, 'r', '0.5'));
    Grad.FX := ParseSvgFloat(GetAttr(Node, 'fx', '-1'));
    Grad.FY := ParseSvgFloat(GetAttr(Node, 'fy', '-1'));
  end
  else
  begin
    Grad.X1 := ParseSvgFloat(GetAttr(Node, 'x1', '0'));
    Grad.Y1 := ParseSvgFloat(GetAttr(Node, 'y1', '0'));
    Grad.X2 := ParseSvgFloat(GetAttr(Node, 'x2', '1'));
    Grad.Y2 := ParseSvgFloat(GetAttr(Node, 'y2', '0'));
  end;

  // Parse <stop> children
  Child := TDOMNode(Node).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = ELEMENT_NODE then
    begin
      ChildEl := TDOMElement(Child);
      ChildTag := LowerCase(DomToStr(ChildEl.TagName));
      if ChildTag = 'stop' then
      begin
        OffsetStr := DomToStr(ChildEl.GetAttribute('offset'));
        Stop.Offset := ParseSvgFloat(OffsetStr);
        Stop.Offset := EnsureRange(Stop.Offset, 0, 1);

        // Parse stop-color from attribute or style
        StyleStr := DomToStr(ChildEl.GetAttribute('style'));
        StopColorStr := DomToStr(ChildEl.GetAttribute('stop-color'));
        if StopColorStr = '' then
          StopColorStr := ParseStyleAttribute(StyleStr, 'stop-color');
        if StopColorStr = '' then
          StopColorStr := 'black';

        if not ParseSvgColor(StopColorStr, StopColor) then
          StopColor := TPixieWebColor.Black;

        // Parse stop-opacity
        StopOpacStr := DomToStr(ChildEl.GetAttribute('stop-opacity'));
        if StopOpacStr = '' then
          StopOpacStr := ParseStyleAttribute(StyleStr, 'stop-opacity');
        if StopOpacStr <> '' then
          StopOpacity := EnsureRange(ParseSvgFloat(StopOpacStr), 0, 1)
        else
          StopOpacity := 1.0;

        StopColor.Alpha := Round(StopColor.Alpha * StopOpacity);
        Stop.Color := StopColor;
        Grad.Stops.Add(Stop);
      end;
    end;
    Child := Child.NextSibling;
  end;

  // Add or replace in dictionary
  if FGradients.ContainsKey(GradId) then
    FGradients.Remove(GradId);
  FGradients.Add(GradId, Grad);
end;

function TPixieSvgRendererBase.ResolveGradientStops(
  const Id: string): TPixieSvgGradient;
var
  Grad, RefGrad: TPixieSvgGradient;
  Visited: Integer;
begin
  Result := nil;
  if (FGradients = nil) or not FGradients.TryGetValue(Id, Grad) then
    Exit;

  // If this gradient has stops, use it directly
  if Grad.Stops.Count > 0 then
  begin
    Result := Grad;
    Exit;
  end;

  // Follow xlink:href chain to find stops
  Visited := 0;
  while (Grad.Stops.Count = 0) and (Grad.HrefId <> '') and (Visited < 10) do
  begin
    if not FGradients.TryGetValue(Grad.HrefId, RefGrad) then
      Break;
    if RefGrad.Stops.Count > 0 then
    begin
      Result := Grad;
      // Copy stops from referenced gradient
      Grad.Stops.Clear;
      Grad.Stops.AddRange(RefGrad.Stops.ToArray);
      Exit;
    end;
    Grad := RefGrad;
    Inc(Visited);
  end;

  if Grad.Stops.Count > 0 then
    Result := Grad;
end;

// ===========================================================================
// Shape renderers
// ===========================================================================

procedure TPixieSvgRendererBase.RenderRect(Node: Pointer;
  const State: TPixieSvgState);
var
  X, Y, W, H, RX, RY: Single;
  NeedRestore: Boolean;
begin
  X := ParseSvgFloat(GetAttr(Node, 'x', '0'));
  Y := ParseSvgFloat(GetAttr(Node, 'y', '0'));
  W := ParseSvgFloat(GetAttr(Node, 'width', '0'));
  H := ParseSvgFloat(GetAttr(Node, 'height', '0'));
  RX := ParseSvgFloat(GetAttr(Node, 'rx', '0'));
  RY := ParseSvgFloat(GetAttr(Node, 'ry', '0'));

  if (W <= 0) or (H <= 0) then Exit;

  // If only one radius specified, use it for both
  if (RX > 0) and (RY = 0) then RY := RX;
  if (RY > 0) and (RX = 0) then RX := RY;

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyOpacity(State, NeedRestore);

  if (RX > 0) or (RY > 0) then
  begin
    // Rounded rect via bezier corners
    if RX > W / 2 then RX := W / 2;
    if RY > H / 2 then RY := H / 2;

    DoMoveTo(X + RX, Y);
    // Top edge -> top-right corner
    DoLineTo(X + W - RX, Y);
    DoCurveTo(X + W - RX + RX * Kappa, Y,
              X + W, Y + RY - RY * Kappa,
              X + W, Y + RY);
    // Right edge -> bottom-right corner
    DoLineTo(X + W, Y + H - RY);
    DoCurveTo(X + W, Y + H - RY + RY * Kappa,
              X + W - RX + RX * Kappa, Y + H,
              X + W - RX, Y + H);
    // Bottom edge -> bottom-left corner
    DoLineTo(X + RX, Y + H);
    DoCurveTo(X + RX - RX * Kappa, Y + H,
              X, Y + H - RY + RY * Kappa,
              X, Y + H - RY);
    // Left edge -> top-left corner
    DoLineTo(X, Y + RY);
    DoCurveTo(X, Y + RY - RY * Kappa,
              X + RX - RX * Kappa, Y,
              X + RX, Y);
    DoClosePath;
  end
  else
  begin
    DoMoveTo(X, Y);
    DoLineTo(X + W, Y);
    DoLineTo(X + W, Y + H);
    DoLineTo(X, Y + H);
    DoClosePath;
  end;

  DoFillAndStroke(State);
  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

procedure TPixieSvgRendererBase.RenderCircle(Node: Pointer;
  const State: TPixieSvgState);
var
  CX, CY, R: Single;
  NeedRestore: Boolean;
begin
  CX := ParseSvgFloat(GetAttr(Node, 'cx', '0'));
  CY := ParseSvgFloat(GetAttr(Node, 'cy', '0'));
  R := ParseSvgFloat(GetAttr(Node, 'r', '0'));

  if R <= 0 then Exit;

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyOpacity(State, NeedRestore);

  EmitBezierEllipse(CX, CY, R, R);
  DoFillAndStroke(State);
  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

procedure TPixieSvgRendererBase.RenderEllipse(Node: Pointer;
  const State: TPixieSvgState);
var
  CX, CY, RX, RY: Single;
  NeedRestore: Boolean;
begin
  CX := ParseSvgFloat(GetAttr(Node, 'cx', '0'));
  CY := ParseSvgFloat(GetAttr(Node, 'cy', '0'));
  RX := ParseSvgFloat(GetAttr(Node, 'rx', '0'));
  RY := ParseSvgFloat(GetAttr(Node, 'ry', '0'));

  if (RX <= 0) or (RY <= 0) then Exit;

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyOpacity(State, NeedRestore);

  EmitBezierEllipse(CX, CY, RX, RY);
  DoFillAndStroke(State);
  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

procedure TPixieSvgRendererBase.RenderLine(Node: Pointer;
  const State: TPixieSvgState);
var
  X1, Y1, X2, Y2: Single;
  NeedRestore: Boolean;
begin
  X1 := ParseSvgFloat(GetAttr(Node, 'x1', '0'));
  Y1 := ParseSvgFloat(GetAttr(Node, 'y1', '0'));
  X2 := ParseSvgFloat(GetAttr(Node, 'x2', '0'));
  Y2 := ParseSvgFloat(GetAttr(Node, 'y2', '0'));

  if not State.HasStroke then Exit;

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyOpacity(State, NeedRestore);

  DoMoveTo(X1, Y1);
  DoLineTo(X2, Y2);
  DoFillAndStroke(State);
  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

procedure TPixieSvgRendererBase.RenderPolyline(Node: Pointer;
  const State: TPixieSvgState; ClosePath: Boolean);
var
  PointsStr: string;
  Nums: array of Single;
  NumCount: Integer;
  P, Len: Integer;
  NumStr: string;
  I: Integer;
  NeedRestore: Boolean;
begin
  PointsStr := GetAttr(Node, 'points');
  if PointsStr = '' then Exit;

  // Parse numbers from points attribute
  SetLength(Nums, 64);
  NumCount := 0;
  P := 1;
  Len := Length(PointsStr);

  while P <= Len do
  begin
    // Skip separators
    while (P <= Len) and CharInSet(PointsStr[P], [' ', ',', #9, #10, #13]) do Inc(P);
    if P > Len then Break;

    NumStr := '';
    if (P <= Len) and CharInSet(PointsStr[P], ['-', '+']) then
    begin
      NumStr := NumStr + PointsStr[P];
      Inc(P);
    end;
    while (P <= Len) and CharInSet(PointsStr[P], ['0'..'9', '.']) do
    begin
      NumStr := NumStr + PointsStr[P];
      Inc(P);
    end;

    if NumStr <> '' then
    begin
      if NumCount >= Length(Nums) then
        SetLength(Nums, Length(Nums) * 2);
      Nums[NumCount] := SvgStrToFloat(NumStr);
      Inc(NumCount);
    end;
  end;

  if NumCount < 4 then Exit; // need at least 2 points

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyOpacity(State, NeedRestore);

  DoMoveTo(Nums[0], Nums[1]);
  I := 2;
  while I + 1 < NumCount do
  begin
    DoLineTo(Nums[I], Nums[I + 1]);
    Inc(I, 2);
  end;

  if ClosePath then
    DoClosePath;

  DoFillAndStroke(State);
  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

// ===========================================================================
// SVG path mini-language
// ===========================================================================

function TPixieSvgRendererBase.ParsePathData(
  const D: string): TPixieSvgPathCmdList;
var
  P, Len: Integer;
  Cmd: TPixieSvgPathCmd;
  NumStr: string;
  ArgList: array of Single;
  ArgCount: Integer;
  Ch: Char;
  HasDot: Boolean;
begin
  Result := TPixieSvgPathCmdList.Create;
  P := 1;
  Len := Length(D);
  SetLength(ArgList, 32);

  while P <= Len do
  begin
    // Skip whitespace and commas
    while (P <= Len) and CharInSet(D[P], [' ', ',', #9, #10, #13]) do Inc(P);
    if P > Len then Break;

    Ch := D[P];
    if CharInSet(Ch, ['M','m','L','l','H','h','V','v','C','c','S','s',
              'Q','q','T','t','A','a','Z','z']) then
    begin
      Cmd.Cmd := AnsiChar(Ch);
      Inc(P);

      // Collect numeric arguments
      ArgCount := 0;
      while P <= Len do
      begin
        // Skip whitespace and commas
        while (P <= Len) and CharInSet(D[P], [' ', ',', #9, #10, #13]) do Inc(P);
        if P > Len then Break;

        // Check if next char starts a number or is a new command
        if CharInSet(D[P], ['M','m','L','l','H','h','V','v','C','c','S','s',
                     'Q','q','T','t','A','a','Z','z']) then
          Break;

        // Read number
        NumStr := '';
        if (P <= Len) and CharInSet(D[P], ['-', '+']) then
        begin
          NumStr := NumStr + D[P];
          Inc(P);
        end;
        HasDot := False;
        while (P <= Len) and CharInSet(D[P], ['0'..'9', '.', 'e', 'E']) do
        begin
          // Handle implicit separator on second decimal point
          if (D[P] = '.') then
          begin
            if HasDot then Break;
            HasDot := True;
          end;
          // Handle exponent sign: e.g. 2.81e-07
          if CharInSet(D[P], ['e', 'E']) then
          begin
            NumStr := NumStr + D[P];
            Inc(P);
            if (P <= Len) and CharInSet(D[P], ['-', '+']) then
            begin
              NumStr := NumStr + D[P];
              Inc(P);
            end;
            Continue;
          end;
          NumStr := NumStr + D[P];
          Inc(P);
        end;

        if NumStr <> '' then
        begin
          if ArgCount >= Length(ArgList) then
            SetLength(ArgList, Length(ArgList) * 2);
          ArgList[ArgCount] := SvgStrToFloat(NumStr);
          Inc(ArgCount);
        end
        else
          Break;
      end;

      SetLength(Cmd.Args, ArgCount);
      if ArgCount > 0 then
        Move(ArgList[0], Cmd.Args[0], ArgCount * SizeOf(Single));
      Result.Add(Cmd);
    end
    else
      Inc(P); // skip unexpected character
  end;
end;

procedure TPixieSvgRendererBase.EmitPathCommands(
  Cmds: TPixieSvgPathCmdList);
var
  I, J, ArgIdx, ArgLen: Integer;
  Cmd: TPixieSvgPathCmd;
  CurX, CurY, StartX, StartY: Single;
  X, Y, X1, Y1, X2, Y2: Single;
  PrevCpX, PrevCpY: Single;
  PrevQpX, PrevQpY: Single;
  PrevCmd: AnsiChar;
  RX, RY, XRot: Single;
  LargeArc, Sweep: Boolean;
  Cp1X, Cp1Y, Cp2X, Cp2Y: Single;
begin
  CurX := 0; CurY := 0;
  StartX := 0; StartY := 0;
  PrevCpX := 0; PrevCpY := 0;
  PrevQpX := 0; PrevQpY := 0;
  PrevCmd := #0;

  for I := 0 to Cmds.Count - 1 do
  begin
    Cmd := Cmds[I];
    ArgIdx := 0;
    ArgLen := Length(Cmd.Args);

    case Cmd.Cmd of
      'M':
      begin
        J := 0;
        while ArgIdx + 1 < ArgLen do
        begin
          X := Cmd.Args[ArgIdx]; Y := Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          if J = 0 then
          begin
            DoMoveTo(X, Y);
            StartX := X; StartY := Y;
          end
          else
            DoLineTo(X, Y);
          CurX := X; CurY := Y;
          Inc(J);
        end;
      end;

      'm':
      begin
        J := 0;
        while ArgIdx + 1 < ArgLen do
        begin
          X := CurX + Cmd.Args[ArgIdx]; Y := CurY + Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          if J = 0 then
          begin
            DoMoveTo(X, Y);
            StartX := X; StartY := Y;
          end
          else
            DoLineTo(X, Y);
          CurX := X; CurY := Y;
          Inc(J);
        end;
      end;

      'L':
      begin
        while ArgIdx + 1 < ArgLen do
        begin
          X := Cmd.Args[ArgIdx]; Y := Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          DoLineTo(X, Y);
          CurX := X; CurY := Y;
        end;
      end;

      'l':
      begin
        while ArgIdx + 1 < ArgLen do
        begin
          X := CurX + Cmd.Args[ArgIdx]; Y := CurY + Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          DoLineTo(X, Y);
          CurX := X; CurY := Y;
        end;
      end;

      'H':
      begin
        while ArgIdx < ArgLen do
        begin
          X := Cmd.Args[ArgIdx]; Inc(ArgIdx);
          DoLineTo(X, CurY);
          CurX := X;
        end;
      end;

      'h':
      begin
        while ArgIdx < ArgLen do
        begin
          X := CurX + Cmd.Args[ArgIdx]; Inc(ArgIdx);
          DoLineTo(X, CurY);
          CurX := X;
        end;
      end;

      'V':
      begin
        while ArgIdx < ArgLen do
        begin
          Y := Cmd.Args[ArgIdx]; Inc(ArgIdx);
          DoLineTo(CurX, Y);
          CurY := Y;
        end;
      end;

      'v':
      begin
        while ArgIdx < ArgLen do
        begin
          Y := CurY + Cmd.Args[ArgIdx]; Inc(ArgIdx);
          DoLineTo(CurX, Y);
          CurY := Y;
        end;
      end;

      'C':
      begin
        while ArgIdx + 5 < ArgLen do
        begin
          X1 := Cmd.Args[ArgIdx]; Y1 := Cmd.Args[ArgIdx + 1];
          X2 := Cmd.Args[ArgIdx + 2]; Y2 := Cmd.Args[ArgIdx + 3];
          X := Cmd.Args[ArgIdx + 4]; Y := Cmd.Args[ArgIdx + 5];
          Inc(ArgIdx, 6);
          DoCurveTo(X1, Y1, X2, Y2, X, Y);
          PrevCpX := X2; PrevCpY := Y2;
          CurX := X; CurY := Y;
        end;
      end;

      'c':
      begin
        while ArgIdx + 5 < ArgLen do
        begin
          X1 := CurX + Cmd.Args[ArgIdx]; Y1 := CurY + Cmd.Args[ArgIdx + 1];
          X2 := CurX + Cmd.Args[ArgIdx + 2]; Y2 := CurY + Cmd.Args[ArgIdx + 3];
          X := CurX + Cmd.Args[ArgIdx + 4]; Y := CurY + Cmd.Args[ArgIdx + 5];
          Inc(ArgIdx, 6);
          DoCurveTo(X1, Y1, X2, Y2, X, Y);
          PrevCpX := X2; PrevCpY := Y2;
          CurX := X; CurY := Y;
        end;
      end;

      'S':
      begin
        while ArgIdx + 3 < ArgLen do
        begin
          if PrevCmd in ['C', 'c', 'S', 's'] then
          begin
            X1 := 2 * CurX - PrevCpX;
            Y1 := 2 * CurY - PrevCpY;
          end
          else
          begin
            X1 := CurX; Y1 := CurY;
          end;
          X2 := Cmd.Args[ArgIdx]; Y2 := Cmd.Args[ArgIdx + 1];
          X := Cmd.Args[ArgIdx + 2]; Y := Cmd.Args[ArgIdx + 3];
          Inc(ArgIdx, 4);
          DoCurveTo(X1, Y1, X2, Y2, X, Y);
          PrevCpX := X2; PrevCpY := Y2;
          CurX := X; CurY := Y;
          PrevCmd := 'S';
        end;
        Continue;
      end;

      's':
      begin
        while ArgIdx + 3 < ArgLen do
        begin
          if PrevCmd in ['C', 'c', 'S', 's'] then
          begin
            X1 := 2 * CurX - PrevCpX;
            Y1 := 2 * CurY - PrevCpY;
          end
          else
          begin
            X1 := CurX; Y1 := CurY;
          end;
          X2 := CurX + Cmd.Args[ArgIdx]; Y2 := CurY + Cmd.Args[ArgIdx + 1];
          X := CurX + Cmd.Args[ArgIdx + 2]; Y := CurY + Cmd.Args[ArgIdx + 3];
          Inc(ArgIdx, 4);
          DoCurveTo(X1, Y1, X2, Y2, X, Y);
          PrevCpX := X2; PrevCpY := Y2;
          CurX := X; CurY := Y;
          PrevCmd := 's';
        end;
        Continue;
      end;

      'Q':
      begin
        while ArgIdx + 3 < ArgLen do
        begin
          X1 := Cmd.Args[ArgIdx]; Y1 := Cmd.Args[ArgIdx + 1];
          X := Cmd.Args[ArgIdx + 2]; Y := Cmd.Args[ArgIdx + 3];
          Inc(ArgIdx, 4);
          // Convert quadratic to cubic
          Cp1X := CurX + (2.0 / 3.0) * (X1 - CurX);
          Cp1Y := CurY + (2.0 / 3.0) * (Y1 - CurY);
          Cp2X := X + (2.0 / 3.0) * (X1 - X);
          Cp2Y := Y + (2.0 / 3.0) * (Y1 - Y);
          DoCurveTo(Cp1X, Cp1Y, Cp2X, Cp2Y, X, Y);
          PrevQpX := X1; PrevQpY := Y1;
          CurX := X; CurY := Y;
        end;
      end;

      'q':
      begin
        while ArgIdx + 3 < ArgLen do
        begin
          X1 := CurX + Cmd.Args[ArgIdx]; Y1 := CurY + Cmd.Args[ArgIdx + 1];
          X := CurX + Cmd.Args[ArgIdx + 2]; Y := CurY + Cmd.Args[ArgIdx + 3];
          Inc(ArgIdx, 4);
          Cp1X := CurX + (2.0 / 3.0) * (X1 - CurX);
          Cp1Y := CurY + (2.0 / 3.0) * (Y1 - CurY);
          Cp2X := X + (2.0 / 3.0) * (X1 - X);
          Cp2Y := Y + (2.0 / 3.0) * (Y1 - Y);
          DoCurveTo(Cp1X, Cp1Y, Cp2X, Cp2Y, X, Y);
          PrevQpX := X1; PrevQpY := Y1;
          CurX := X; CurY := Y;
        end;
      end;

      'T':
      begin
        while ArgIdx + 1 < ArgLen do
        begin
          if PrevCmd in ['Q', 'q', 'T', 't'] then
          begin
            X1 := 2 * CurX - PrevQpX;
            Y1 := 2 * CurY - PrevQpY;
          end
          else
          begin
            X1 := CurX; Y1 := CurY;
          end;
          X := Cmd.Args[ArgIdx]; Y := Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          Cp1X := CurX + (2.0 / 3.0) * (X1 - CurX);
          Cp1Y := CurY + (2.0 / 3.0) * (Y1 - CurY);
          Cp2X := X + (2.0 / 3.0) * (X1 - X);
          Cp2Y := Y + (2.0 / 3.0) * (Y1 - Y);
          DoCurveTo(Cp1X, Cp1Y, Cp2X, Cp2Y, X, Y);
          PrevQpX := X1; PrevQpY := Y1;
          CurX := X; CurY := Y;
          PrevCmd := 'T';
        end;
        Continue;
      end;

      't':
      begin
        while ArgIdx + 1 < ArgLen do
        begin
          if PrevCmd in ['Q', 'q', 'T', 't'] then
          begin
            X1 := 2 * CurX - PrevQpX;
            Y1 := 2 * CurY - PrevQpY;
          end
          else
          begin
            X1 := CurX; Y1 := CurY;
          end;
          X := CurX + Cmd.Args[ArgIdx]; Y := CurY + Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          Cp1X := CurX + (2.0 / 3.0) * (X1 - CurX);
          Cp1Y := CurY + (2.0 / 3.0) * (Y1 - CurY);
          Cp2X := X + (2.0 / 3.0) * (X1 - X);
          Cp2Y := Y + (2.0 / 3.0) * (Y1 - Y);
          DoCurveTo(Cp1X, Cp1Y, Cp2X, Cp2Y, X, Y);
          PrevQpX := X1; PrevQpY := Y1;
          CurX := X; CurY := Y;
          PrevCmd := 't';
        end;
        Continue;
      end;

      'A':
      begin
        while ArgIdx + 6 < ArgLen do
        begin
          RX := Cmd.Args[ArgIdx];
          RY := Cmd.Args[ArgIdx + 1];
          XRot := Cmd.Args[ArgIdx + 2];
          LargeArc := Cmd.Args[ArgIdx + 3] <> 0;
          Sweep := Cmd.Args[ArgIdx + 4] <> 0;
          X := Cmd.Args[ArgIdx + 5];
          Y := Cmd.Args[ArgIdx + 6];
          Inc(ArgIdx, 7);
          ArcToBezier(CurX, CurY, RX, RY, XRot, LargeArc, Sweep, X, Y);
          CurX := X; CurY := Y;
        end;
      end;

      'a':
      begin
        while ArgIdx + 6 < ArgLen do
        begin
          RX := Cmd.Args[ArgIdx];
          RY := Cmd.Args[ArgIdx + 1];
          XRot := Cmd.Args[ArgIdx + 2];
          LargeArc := Cmd.Args[ArgIdx + 3] <> 0;
          Sweep := Cmd.Args[ArgIdx + 4] <> 0;
          X := CurX + Cmd.Args[ArgIdx + 5];
          Y := CurY + Cmd.Args[ArgIdx + 6];
          Inc(ArgIdx, 7);
          ArcToBezier(CurX, CurY, RX, RY, XRot, LargeArc, Sweep, X, Y);
          CurX := X; CurY := Y;
        end;
      end;

      'Z', 'z':
      begin
        DoClosePath;
        CurX := StartX;
        CurY := StartY;
      end;
    end;

    PrevCmd := Cmd.Cmd;
  end;
end;

// ===========================================================================
// Arc-to-Bezier conversion (SVG spec Appendix F)
// ===========================================================================

procedure TPixieSvgRendererBase.ArcToBezier(X1, Y1, RX, RY,
  XRotation: Single; LargeArc, Sweep: Boolean; X2, Y2: Single);
var
  Phi, CosPhi, SinPhi: Single;
  X1p, Y1p, CxP, CyP, CX, CY: Single;
  Sq, Coeff: Single;
  Theta1, DTheta: Single;
  Segments, Seg: Integer;
  SegAngle: Single;
  T, Alpha: Single;
  Cos1, Sin1, Cos2, Sin2: Single;
  EP1X, EP1Y, EP2X, EP2Y: Single;
  E1X, E1Y, E2X, E2Y: Single;
  Cp1X, Cp1Y, Cp2X, Cp2Y: Single;
  Rx2, Ry2, X1p2, Y1p2, Lambda: Single;
  Dx, Dy: Single;
  N, NX, NY, DX2, DY2: Single;
begin
  // Degenerate cases
  Dx := X2 - X1;
  Dy := Y2 - Y1;
  if (Abs(Dx) < 0.001) and (Abs(Dy) < 0.001) then Exit;

  RX := Abs(RX);
  RY := Abs(RY);
  if (RX < 0.001) or (RY < 0.001) then
  begin
    DoLineTo(X2, Y2);
    Exit;
  end;

  Phi := XRotation * Pi / 180.0;
  CosPhi := Cos(Phi);
  SinPhi := Sin(Phi);

  // Step 1: compute (x1', y1')
  X1p := CosPhi * (X1 - X2) / 2.0 + SinPhi * (Y1 - Y2) / 2.0;
  Y1p := -SinPhi * (X1 - X2) / 2.0 + CosPhi * (Y1 - Y2) / 2.0;

  // Ensure radii are large enough (F.6.6)
  X1p2 := X1p * X1p;
  Y1p2 := Y1p * Y1p;
  Rx2 := RX * RX;
  Ry2 := RY * RY;
  Lambda := X1p2 / Rx2 + Y1p2 / Ry2;
  if Lambda > 1.0 then
  begin
    RX := RX * Sqrt(Lambda);
    RY := RY * Sqrt(Lambda);
    Rx2 := RX * RX;
    Ry2 := RY * RY;
  end;

  // Step 2: compute (cx', cy')
  Sq := (Rx2 * Ry2 - Rx2 * Y1p2 - Ry2 * X1p2) /
        (Rx2 * Y1p2 + Ry2 * X1p2);
  if Sq < 0 then Sq := 0;
  Coeff := Sqrt(Sq);
  if LargeArc = Sweep then
    Coeff := -Coeff;

  CxP := Coeff * (RX * Y1p / RY);
  CyP := Coeff * (-(RY * X1p / RX));

  // Step 3: compute (cx, cy)
  CX := CosPhi * CxP - SinPhi * CyP + (X1 + X2) / 2.0;
  CY := SinPhi * CxP + CosPhi * CyP + (Y1 + Y2) / 2.0;

  // Step 4: compute theta1 and dtheta
  NX := (X1p - CxP) / RX;
  NY := (Y1p - CyP) / RY;
  DX2 := (-X1p - CxP) / RX;
  DY2 := (-Y1p - CyP) / RY;

  N := Sqrt(NX * NX + NY * NY);
  if N < 0.0001 then N := 0.0001;
  Theta1 := ArcCos(EnsureRange(NX / N, -1, 1));
  if NY < 0 then
    Theta1 := -Theta1;

  N := Sqrt((NX * NX + NY * NY) * (DX2 * DX2 + DY2 * DY2));
  if N < 0.0001 then N := 0.0001;
  DTheta := ArcCos(EnsureRange((NX * DX2 + NY * DY2) / N, -1, 1));
  if (NX * DY2 - NY * DX2) < 0 then
    DTheta := -DTheta;

  if Sweep and (DTheta < 0) then
    DTheta := DTheta + 2 * Pi
  else if (not Sweep) and (DTheta > 0) then
    DTheta := DTheta - 2 * Pi;

  // Split into segments of at most 90 degrees
  Segments := Ceil(Abs(DTheta) / (Pi / 2));
  if Segments < 1 then Segments := 1;
  SegAngle := DTheta / Segments;
  Alpha := 4.0 / 3.0 * Tan(SegAngle / 4.0);

  T := Theta1;
  for Seg := 0 to Segments - 1 do
  begin
    Cos1 := Cos(T);
    Sin1 := Sin(T);
    Cos2 := Cos(T + SegAngle);
    Sin2 := Sin(T + SegAngle);

    EP1X := Cos1;
    EP1Y := Sin1;
    EP2X := Cos2;
    EP2Y := Sin2;

    Cp1X := EP1X - Alpha * Sin1;
    Cp1Y := EP1Y + Alpha * Cos1;
    Cp2X := EP2X + Alpha * Sin2;
    Cp2Y := EP2Y - Alpha * Cos2;

    E1X := CosPhi * RX * Cp1X - SinPhi * RY * Cp1Y + CX;
    E1Y := SinPhi * RX * Cp1X + CosPhi * RY * Cp1Y + CY;
    E2X := CosPhi * RX * Cp2X - SinPhi * RY * Cp2Y + CX;
    E2Y := SinPhi * RX * Cp2X + CosPhi * RY * Cp2Y + CY;

    EP2X := CosPhi * RX * Cos2 - SinPhi * RY * Sin2 + CX;
    EP2Y := SinPhi * RX * Cos2 + CosPhi * RY * Sin2 + CY;

    DoCurveTo(E1X, E1Y, E2X, E2Y, EP2X, EP2Y);

    T := T + SegAngle;
  end;
end;

// ===========================================================================
// Path rendering
// ===========================================================================

procedure TPixieSvgRendererBase.RenderPath(Node: Pointer;
  const State: TPixieSvgState);
var
  D: string;
  Cmds: TPixieSvgPathCmdList;
  NeedRestore: Boolean;
begin
  D := GetAttr(Node, 'd');
  if D = '' then Exit;

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyOpacity(State, NeedRestore);

  Cmds := ParsePathData(D);
  try
    EmitPathCommands(Cmds);
  finally
    Cmds.Free;
  end;

  DoFillAndStroke(State);
  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

// ===========================================================================
// Text rendering (default implementation — calls DoDrawText)
// ===========================================================================

procedure TPixieSvgRendererBase.RenderText(Node: Pointer;
  const State: TPixieSvgState);
var
  X, Y: Single;
  TextContent: string;
  NeedRestore: Boolean;
  Child: TDOMNode;
begin
  X := ParseSvgFloat(GetAttr(Node, 'x', '0'));
  Y := ParseSvgFloat(GetAttr(Node, 'y', '0'));

  // Collect text from child text nodes
  TextContent := '';
  Child := TDOMNode(Node).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = TEXT_NODE then
      TextContent := TextContent + DomToStr(Child.NodeValue);
    Child := Child.NextSibling;
  end;

  TextContent := Trim(TextContent);
  if TextContent = '' then Exit;

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyOpacity(State, NeedRestore);

  DoDrawText(TextContent, X, Y, State);
  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

// ===========================================================================
// Element rendering (single-node dispatch)
// ===========================================================================

procedure TPixieSvgRendererBase.RenderElement(Node: Pointer;
  const State: TPixieSvgState);
var
  TagName: string;
  IsGroup: Boolean;
begin
  TagName := LowerCase(DomToStr(TDOMElement(Node).TagName));

  IsGroup := (TagName = 'g') or (TagName = 'svg') or (TagName = 'symbol');

  if IsGroup then
  begin
    DoSaveState;
    ApplyNodeTransform(Node);
    ApplyClipPath(Node);
    RenderGroup(Node, State);
    DoRestoreState;
  end
  else if TagName = 'rect' then
    RenderRect(Node, State)
  else if TagName = 'circle' then
    RenderCircle(Node, State)
  else if TagName = 'ellipse' then
    RenderEllipse(Node, State)
  else if TagName = 'line' then
    RenderLine(Node, State)
  else if TagName = 'polyline' then
    RenderPolyline(Node, State, False)
  else if TagName = 'polygon' then
    RenderPolyline(Node, State, True)
  else if TagName = 'path' then
    RenderPath(Node, State)
  else if TagName = 'text' then
    RenderText(Node, State)
  else if TagName = 'use' then
    RenderUse(Node, State)
  else if TagName = 'defs' then
    CollectDefs(Node)
  else if TagName = 'lineargradient' then
    ParseGradient(Node, False)
  else if TagName = 'radialgradient' then
    ParseGradient(Node, True);
end;

// ===========================================================================
// <use> element rendering
// ===========================================================================

procedure TPixieSvgRendererBase.RenderUse(Node: Pointer;
  const State: TPixieSvgState);
var
  HrefStr, TargetId: string;
  Target: Pointer;
  X, Y: Single;
  M: TPixieSvgMatrix;
  TargetState: TPixieSvgState;
begin
  if FIdMap = nil then Exit;

  // Recursion guard
  if FUseDepth >= 10 then Exit;

  // Resolve href
  HrefStr := GetAttr(Node, 'xlink:href');
  if HrefStr = '' then
    HrefStr := GetAttr(Node, 'href');
  if (HrefStr = '') or (HrefStr[1] <> '#') then Exit;

  TargetId := Copy(HrefStr, 2, MaxInt);
  if not FIdMap.TryGetValue(TargetId, Target) then Exit;

  // Get x/y offset
  X := ParseSvgFloat(GetAttr(Node, 'x', '0'));
  Y := ParseSvgFloat(GetAttr(Node, 'y', '0'));

  DoSaveState;

  // Apply <use> element's own transform, then x/y translation
  ApplyNodeTransform(Node);
  if (Abs(X) > 0.0001) or (Abs(Y) > 0.0001) then
  begin
    M := TPixieSvgMatrix.CreateTranslate(X, Y);
    DoSetTransform(M);
  end;

  // Merge target's own style attributes on top of the <use> state
  TargetState := InheritState(Target, State);
  Inc(FUseDepth);
  try
    RenderElement(Target, TargetState);
  finally
    Dec(FUseDepth);
  end;

  DoRestoreState;
end;

// ===========================================================================
// Group rendering (recursive tree walk)
// ===========================================================================

procedure TPixieSvgRendererBase.RenderGroup(Node: Pointer;
  const State: TPixieSvgState);
var
  Child: TDOMNode;
  ChildState: TPixieSvgState;
begin
  Child := TDOMNode(Node).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = ELEMENT_NODE then
    begin
      ChildState := InheritState(Child, State);
      RenderElement(Child, ChildState);
    end;

    Child := Child.NextSibling;
  end;
end;

// ===========================================================================
// Public API
// ===========================================================================

function TPixieSvgRendererBase.ParseSvg(Data: Pointer; Size: Integer;
  out W, H: Single): Boolean;
var
  Doc: TXMLDocument;
  SvgRoot: TDOMElement;
  MemStream: TMemoryStream;
  VbStr, WidthStr, HeightStr: string;
  Parts: array[0..3] of string;
  P, Idx: Integer;
  SvgStr: string;
  DtdStart, DtdEnd: Integer;
  Utf8: UTF8String;
begin
  Result := False;
  W := 0;
  H := 0;

  if (Data = nil) or (Size <= 0) then Exit;

  // Free any previous document
  ClearDocument;

  // Strip <!DOCTYPE...> declaration — FPC XML parser fails on external DTDs.
  // Before stripping, extract <!ENTITY> definitions from any internal subset
  // and expand entity references in the document body.
  SetString(SvgStr, PAnsiChar(Data), Size);
  DtdStart := Pos('<!DOCTYPE', SvgStr);
  if DtdStart > 0 then
  begin
    // Find closing '>' — handle nested brackets for internal subsets
    DtdEnd := DtdStart + 9;
    while (DtdEnd <= Length(SvgStr)) and (SvgStr[DtdEnd] <> '>') do
    begin
      if SvgStr[DtdEnd] = '[' then
        while (DtdEnd <= Length(SvgStr)) and (SvgStr[DtdEnd] <> ']') do
          Inc(DtdEnd);
      Inc(DtdEnd);
    end;

    // Extract and expand internal entities before removing DOCTYPE
    ExpandDoctypeEntities(SvgStr, DtdStart, DtdEnd);
    Delete(SvgStr, DtdStart, DtdEnd - DtdStart + 1);
  end;

  Utf8 := UTF8String(SvgStr);
  MemStream := TMemoryStream.Create;
  try
    MemStream.Write(Utf8[1], Length(Utf8));
    MemStream.Position := 0;

    Doc := nil;
    try
      ReadXMLFile(Doc, MemStream);
    except
      Exit;
    end;

    if Doc = nil then Exit;
    SvgRoot := Doc.DocumentElement;
    if SvgRoot = nil then
    begin
      Doc.Free;
      Exit;
    end;

    // Parse viewBox
    VbStr := DomToStr(SvgRoot.GetAttribute('viewBox'));
    FViewBoxX := 0; FViewBoxY := 0; FViewBoxW := 0; FViewBoxH := 0;

    if VbStr <> '' then
    begin
      Idx := 0;
      P := 1;
      Parts[0] := ''; Parts[1] := ''; Parts[2] := ''; Parts[3] := '';
      while (P <= Length(VbStr)) and (Idx <= 3) do
      begin
        while (P <= Length(VbStr)) and CharInSet(VbStr[P], [' ', ',', #9]) do Inc(P);
        Parts[Idx] := '';
        while (P <= Length(VbStr)) and not CharInSet(VbStr[P], [' ', ',', #9]) do
        begin
          Parts[Idx] := Parts[Idx] + VbStr[P];
          Inc(P);
        end;
        Inc(Idx);
      end;

      FViewBoxX := SvgStrToFloat(Parts[0]);
      FViewBoxY := SvgStrToFloat(Parts[1]);
      FViewBoxW := SvgStrToFloat(Parts[2]);
      FViewBoxH := SvgStrToFloat(Parts[3]);
    end;

    // Parse width/height, fall back to viewBox
    WidthStr := DomToStr(SvgRoot.GetAttribute('width'));
    HeightStr := DomToStr(SvgRoot.GetAttribute('height'));

    if WidthStr <> '' then
      W := ParseSvgFloat(WidthStr)
    else
      W := FViewBoxW;
    if HeightStr <> '' then
      H := ParseSvgFloat(HeightStr)
    else
      H := FViewBoxH;

    // If only one dimension given, derive the other from viewBox aspect ratio
    if (W <= 0) and (H > 0) and (FViewBoxW > 0) and (FViewBoxH > 0) then
      W := H * FViewBoxW / FViewBoxH;
    if (H <= 0) and (W > 0) and (FViewBoxW > 0) and (FViewBoxH > 0) then
      H := W * FViewBoxH / FViewBoxW;

    // If still missing one dimension and no viewBox, match the other
    if (W <= 0) and (H > 0) then W := H;
    if (H <= 0) and (W > 0) then H := W;

    // Last resort: default to 300x150 (SVG spec default)
    if W <= 0 then W := 300;
    if H <= 0 then H := 150;

    if FViewBoxW <= 0 then FViewBoxW := W;
    if FViewBoxH <= 0 then FViewBoxH := H;

    // Initialise default state
    FInitState.FillColor := TPixieWebColor.Black;
    FInitState.StrokeColor := TPixieWebColor.Black;
    FInitState.StrokeWidth := 1;
    FInitState.Opacity := 1.0;
    FInitState.FillOpacity := 1.0;
    FInitState.StrokeOpacity := 1.0;
    FInitState.HasFill := True;
    FInitState.HasStroke := False;
    FInitState.EvenOddFill := False;
    FInitState.FontFamily := 'sans-serif';
    FInitState.FontSize := 16;
    FInitState.FontWeight := 400;
    FInitState.LetterSpacing := 0;
    FInitState.TextAnchor := taLeft;
    FInitState.FillGradientId := '';
    FInitState.StrokeGradientId := '';

    // Inherit state from the root SVG element
    FInitState := InheritState(SvgRoot, FInitState);

    // Store document for RenderDocument
    FDoc := Doc;
    FSvgRoot := SvgRoot;

    // Build ID map and pre-collect gradients (single tree walk)
    BuildIdMap(SvgRoot);

    Result := True;
  finally
    MemStream.Free;
  end;
end;

procedure TPixieSvgRendererBase.SetViewport(AWidth, AHeight: Single);
begin
  FViewBoxW := AWidth;
  FViewBoxH := AHeight;
end;

procedure TPixieSvgRendererBase.RenderDocument;
begin
  if FSvgRoot = nil then Exit;
  RenderGroup(FSvgRoot, FInitState);
end;

end.
