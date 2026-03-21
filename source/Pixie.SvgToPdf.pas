unit Pixie.SvgToPdf;

// SVG-to-PDF vector conversion.
// Parses SVG XML, walks the element tree, and emits PDF path operators
// into a Form XObject for embedding in PDF output.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections,
  Pixie.Types, Pixie.WebColor, Pixie.TrueType, Pixie.PdfWriter;

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
    FontFamily: string;
    FontSize: Single;
    FontWeight: Integer;
    LetterSpacing: Single;
  end;

  { TPixieSvgPathCmd - tokenised path command }

  TPixieSvgPathCmd = record
    Cmd: AnsiChar;
    Args: array of Single;
  end;

  TPixieSvgPathCmdList = TList<TPixieSvgPathCmd>;

  { TPixieSvgFontInfo - font used in SVG text }

  TPixieSvgFontInfo = record
    TtFont: TPixieTrueTypeFont;
    PdfName: AnsiString;
    Type0ObjId: Integer;
    UsedGlyphs: TPixieGlyphMap;
  end;

  TPixieSvgFontInfoList = TList<TPixieSvgFontInfo>;

  { TPixieSvgRenderer }

  TPixieSvgRenderer = class
  private
    FWriter: TPixiePdfWriter;
    FFontCache: TPixieTrueTypeFontCache;
    FStream: TMemoryStream;
    FResourceExtGState: AnsiString;
    FFonts: TPixieSvgFontInfoList;
    FGsCounter: Integer;
    FFontCounter: Integer;

    procedure Emit(const S: AnsiString);
    procedure EmitLn(const S: AnsiString);

    // Attribute parsing
    function GetAttr(Node: Pointer; const Name: string;
      const Default: string = ''): string;
    function ParseSvgFloat(const S: string): Single;
    function ParseSvgColor(const S: string; out Color: TPixieWebColor): Boolean;
    function ParseStyleAttribute(const StyleStr, PropName: string): string;
    function InheritState(Node: Pointer; const ParentState: TPixieSvgState): TPixieSvgState;
    function ParseTransform(const S: string): TPixieSvgMatrix;

    // Shape rendering
    procedure RenderGroup(Node: Pointer; const State: TPixieSvgState);
    procedure RenderRect(Node: Pointer; const State: TPixieSvgState);
    procedure RenderCircle(Node: Pointer; const State: TPixieSvgState);
    procedure RenderEllipse(Node: Pointer; const State: TPixieSvgState);
    procedure RenderLine(Node: Pointer; const State: TPixieSvgState);
    procedure RenderPolyline(Node: Pointer; const State: TPixieSvgState;
      ClosePath: Boolean);
    procedure RenderPath(Node: Pointer; const State: TPixieSvgState);
    procedure RenderText(Node: Pointer; const State: TPixieSvgState);

    // Path helpers
    procedure EmitBezierEllipse(CX, CY, RX, RY: Single);
    procedure EmitFillAndStroke(const State: TPixieSvgState);
    procedure SetPdfColor(const Color: TPixieWebColor; Fill: Boolean);
    procedure EmitTransform(Node: Pointer);
    procedure EmitOpacity(const State: TPixieSvgState;
      out NeedRestore: Boolean);

    // Path data parsing
    function ParsePathData(const D: string): TPixieSvgPathCmdList;
    procedure EmitPathCommands(Cmds: TPixieSvgPathCmdList);
    procedure ArcToBezier(X1, Y1, RX, RY, XRotation: Single;
      LargeArc, Sweep: Boolean; X2, Y2: Single);

    // Font helpers
    function FindOrCreateSvgFont(const Family: string;
      Weight: Integer): Integer;
    procedure BuildSvgFontObjects;
  public
    constructor Create(AWriter: TPixiePdfWriter;
      AFontCache: TPixieTrueTypeFontCache);
    destructor Destroy; override;

    function RenderToFormXObject(Data: Pointer; Size: Integer;
      out OutWidth, OutHeight: Single): Integer;
  end;

implementation

uses
  Math, {$IFDEF FPC}DOM, XMLRead,{$ELSE}Pixie.SimpleXml,{$ENDIF} Pixie.Utf8;

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
  Result.A := A * M.A + B * M.C;
  Result.B := A * M.B + B * M.D;
  Result.C := C * M.A + D * M.C;
  Result.D := C * M.B + D * M.D;
  Result.E := E * M.A + F * M.C + M.E;
  Result.F := E * M.B + F * M.D + M.F;
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
// TPixieSvgRenderer - construction
// ===========================================================================

constructor TPixieSvgRenderer.Create(AWriter: TPixiePdfWriter;
  AFontCache: TPixieTrueTypeFontCache);
begin
  inherited Create;
  FWriter := AWriter;
  FFontCache := AFontCache;
  FStream := TMemoryStream.Create;
  FFonts := TPixieSvgFontInfoList.Create;
  FGsCounter := 0;
  FFontCounter := 0;
end;

destructor TPixieSvgRenderer.Destroy;
var
  I: Integer;
begin
  for I := 0 to FFonts.Count - 1 do
    FFonts[I].UsedGlyphs.Free;
  FFonts.Free;
  FStream.Free;
  inherited;
end;

// ===========================================================================
// Content stream writing
// ===========================================================================

procedure TPixieSvgRenderer.Emit(const S: AnsiString);
begin
  if Length(S) > 0 then
    FStream.Write(S[1], Length(S));
end;

procedure TPixieSvgRenderer.EmitLn(const S: AnsiString);
begin
  Emit(S + #10);
end;

// ===========================================================================
// Attribute parsing
// ===========================================================================

function TPixieSvgRenderer.GetAttr(Node: Pointer; const Name: string;
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

function TPixieSvgRenderer.ParseSvgFloat(const S: string): Single;
var
  Trimmed: string;
  Code: Integer;
begin
  Result := 0;
  Trimmed := Trim(S);
  if Trimmed = '' then Exit;

  // Strip common suffixes
  if (Length(Trimmed) > 2) and
     ((Copy(Trimmed, Length(Trimmed) - 1, 2) = 'px') or
      (Copy(Trimmed, Length(Trimmed) - 1, 2) = 'pt') or
      (Copy(Trimmed, Length(Trimmed) - 1, 2) = 'em')) then
    Trimmed := Copy(Trimmed, 1, Length(Trimmed) - 2);

  Val(Trimmed, Result, Code);
end;

function TPixieSvgRenderer.ParseSvgColor(const S: string;
  out Color: TPixieWebColor): Boolean;
var
  Trimmed: string;
begin
  Trimmed := Trim(S);
  if (Trimmed = '') or (Trimmed = 'none') then
  begin
    Result := False;
    Exit;
  end;
  Result := PixieParseColorString(Trimmed, Color);
end;

function TPixieSvgRenderer.ParseStyleAttribute(
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

function TPixieSvgRenderer.InheritState(Node: Pointer;
  const ParentState: TPixieSvgState): TPixieSvgState;
var
  FillStr, StrokeStr, StrokeWStr, OpacStr: string;
  FillOpStr, StrokeOpStr: string;
  StyleStr: string;
  FontFamilyStr, FontSizeStr, FontWeightStr: string;
  LetterSpacingStr: string;
  Color: TPixieWebColor;
begin
  Result := ParentState;

  StyleStr := GetAttr(Node, 'style');

  // Fill
  FillStr := GetAttr(Node, 'fill');
  if FillStr = '' then
    FillStr := ParseStyleAttribute(StyleStr, 'fill');
  if FillStr <> '' then
  begin
    if FillStr = 'none' then
      Result.HasFill := False
    else if (FillStr <> 'inherit') and ParseSvgColor(FillStr, Color) then
    begin
      Result.FillColor := Color;
      Result.HasFill := True;
    end;
  end;

  // Stroke
  StrokeStr := GetAttr(Node, 'stroke');
  if StrokeStr = '' then
    StrokeStr := ParseStyleAttribute(StyleStr, 'stroke');
  if StrokeStr <> '' then
  begin
    if StrokeStr = 'none' then
      Result.HasStroke := False
    else if (StrokeStr <> 'inherit') and ParseSvgColor(StrokeStr, Color) then
    begin
      Result.StrokeColor := Color;
      Result.HasStroke := True;
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
end;

// ===========================================================================
// Transform parsing
// ===========================================================================

function TPixieSvgRenderer.ParseTransform(const S: string): TPixieSvgMatrix;
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
        Args[ArgCount] := StrToFloatDef(NumStr, 0);
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
// Color and state helpers
// ===========================================================================

procedure TPixieSvgRenderer.SetPdfColor(const Color: TPixieWebColor;
  Fill: Boolean);
var
  R, G, B: Single;
begin
  R := Color.Red / 255.0;
  G := Color.Green / 255.0;
  B := Color.Blue / 255.0;
  if Fill then
    EmitLn(PdfFloat(R) + ' ' + PdfFloat(G) + ' ' + PdfFloat(B) + ' rg')
  else
    EmitLn(PdfFloat(R) + ' ' + PdfFloat(G) + ' ' + PdfFloat(B) + ' RG');
end;

procedure TPixieSvgRenderer.EmitTransform(Node: Pointer);
var
  TransStr: string;
  M: TPixieSvgMatrix;
begin
  TransStr := GetAttr(Node, 'transform');
  if TransStr = '' then Exit;

  M := ParseTransform(TransStr);
  // Only emit if not identity
  if (Abs(M.A - 1) > 0.0001) or (Abs(M.B) > 0.0001) or
     (Abs(M.C) > 0.0001) or (Abs(M.D - 1) > 0.0001) or
     (Abs(M.E) > 0.0001) or (Abs(M.F) > 0.0001) then
    EmitLn(PdfFloat(M.A) + ' ' + PdfFloat(M.B) + ' ' +
           PdfFloat(M.C) + ' ' + PdfFloat(M.D) + ' ' +
           PdfFloat(M.E) + ' ' + PdfFloat(M.F) + ' cm');
end;

procedure TPixieSvgRenderer.EmitOpacity(const State: TPixieSvgState;
  out NeedRestore: Boolean);
var
  Eff: Single;
  GsObj: TPixiePdfObject;
  GsName: AnsiString;
begin
  NeedRestore := False;
  Eff := State.Opacity;
  if Eff >= 1.0 then Exit;

  GsObj := FWriter.AllocObject;
  GsObj.AddEntry('Type', '/ExtGState');
  GsObj.AddEntry('ca', PdfFloat(Eff));
  GsObj.AddEntry('CA', PdfFloat(Eff));

  Inc(FGsCounter);
  GsName := 'SvgGS' + AnsiString(IntToStr(FGsCounter));
  FResourceExtGState := FResourceExtGState + '/' + GsName + ' ' +
    PdfRef(GsObj.Id) + ' ';

  EmitLn('/' + GsName + ' gs');
  NeedRestore := True;
end;

procedure TPixieSvgRenderer.EmitFillAndStroke(const State: TPixieSvgState);
begin
  if State.HasFill and State.HasStroke then
  begin
    SetPdfColor(State.FillColor, True);
    SetPdfColor(State.StrokeColor, False);
    EmitLn(PdfFloat(State.StrokeWidth) + ' w');
    EmitLn('B');
  end
  else if State.HasFill then
  begin
    SetPdfColor(State.FillColor, True);
    EmitLn('f');
  end
  else if State.HasStroke then
  begin
    SetPdfColor(State.StrokeColor, False);
    EmitLn(PdfFloat(State.StrokeWidth) + ' w');
    EmitLn('S');
  end
  else
    EmitLn('n');
end;

// ===========================================================================
// Bezier ellipse
// ===========================================================================

procedure TPixieSvgRenderer.EmitBezierEllipse(CX, CY, RX, RY: Single);
var
  KX, KY: Single;
begin
  KX := RX * Kappa;
  KY := RY * Kappa;

  EmitLn(PdfFloat(CX) + ' ' + PdfFloat(CY - RY) + ' m');
  // Top -> right
  EmitLn(PdfFloat(CX + KX) + ' ' + PdfFloat(CY - RY) + ' ' +
         PdfFloat(CX + RX) + ' ' + PdfFloat(CY - KY) + ' ' +
         PdfFloat(CX + RX) + ' ' + PdfFloat(CY) + ' c');
  // Right -> bottom
  EmitLn(PdfFloat(CX + RX) + ' ' + PdfFloat(CY + KY) + ' ' +
         PdfFloat(CX + KX) + ' ' + PdfFloat(CY + RY) + ' ' +
         PdfFloat(CX) + ' ' + PdfFloat(CY + RY) + ' c');
  // Bottom -> left
  EmitLn(PdfFloat(CX - KX) + ' ' + PdfFloat(CY + RY) + ' ' +
         PdfFloat(CX - RX) + ' ' + PdfFloat(CY + KY) + ' ' +
         PdfFloat(CX - RX) + ' ' + PdfFloat(CY) + ' c');
  // Left -> top
  EmitLn(PdfFloat(CX - RX) + ' ' + PdfFloat(CY - KY) + ' ' +
         PdfFloat(CX - KX) + ' ' + PdfFloat(CY - RY) + ' ' +
         PdfFloat(CX) + ' ' + PdfFloat(CY - RY) + ' c');
end;

// ===========================================================================
// Shape renderers
// ===========================================================================

procedure TPixieSvgRenderer.RenderRect(Node: Pointer;
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

  EmitLn('q');
  EmitTransform(Node);
  EmitOpacity(State, NeedRestore);

  if (RX > 0) or (RY > 0) then
  begin
    // Rounded rect via bezier corners
    if RX > W / 2 then RX := W / 2;
    if RY > H / 2 then RY := H / 2;

    EmitLn(PdfFloat(X + RX) + ' ' + PdfFloat(Y) + ' m');
    // Top edge -> top-right
    EmitLn(PdfFloat(X + W - RX) + ' ' + PdfFloat(Y) + ' l');
    EmitLn(PdfFloat(X + W - RX + RX * Kappa) + ' ' + PdfFloat(Y) + ' ' +
           PdfFloat(X + W) + ' ' + PdfFloat(Y + RY - RY * Kappa) + ' ' +
           PdfFloat(X + W) + ' ' + PdfFloat(Y + RY) + ' c');
    // Right edge -> bottom-right
    EmitLn(PdfFloat(X + W) + ' ' + PdfFloat(Y + H - RY) + ' l');
    EmitLn(PdfFloat(X + W) + ' ' + PdfFloat(Y + H - RY + RY * Kappa) + ' ' +
           PdfFloat(X + W - RX + RX * Kappa) + ' ' + PdfFloat(Y + H) + ' ' +
           PdfFloat(X + W - RX) + ' ' + PdfFloat(Y + H) + ' c');
    // Bottom edge -> bottom-left
    EmitLn(PdfFloat(X + RX) + ' ' + PdfFloat(Y + H) + ' l');
    EmitLn(PdfFloat(X + RX - RX * Kappa) + ' ' + PdfFloat(Y + H) + ' ' +
           PdfFloat(X) + ' ' + PdfFloat(Y + H - RY + RY * Kappa) + ' ' +
           PdfFloat(X) + ' ' + PdfFloat(Y + H - RY) + ' c');
    // Left edge -> top-left
    EmitLn(PdfFloat(X) + ' ' + PdfFloat(Y + RY) + ' l');
    EmitLn(PdfFloat(X) + ' ' + PdfFloat(Y + RY - RY * Kappa) + ' ' +
           PdfFloat(X + RX - RX * Kappa) + ' ' + PdfFloat(Y) + ' ' +
           PdfFloat(X + RX) + ' ' + PdfFloat(Y) + ' c');
    EmitLn('h');
  end
  else
    EmitLn(PdfFloat(X) + ' ' + PdfFloat(Y) + ' ' +
           PdfFloat(W) + ' ' + PdfFloat(H) + ' re');

  EmitFillAndStroke(State);
  EmitLn('Q');
end;

procedure TPixieSvgRenderer.RenderCircle(Node: Pointer;
  const State: TPixieSvgState);
var
  CX, CY, R: Single;
  NeedRestore: Boolean;
begin
  CX := ParseSvgFloat(GetAttr(Node, 'cx', '0'));
  CY := ParseSvgFloat(GetAttr(Node, 'cy', '0'));
  R := ParseSvgFloat(GetAttr(Node, 'r', '0'));

  if R <= 0 then Exit;

  EmitLn('q');
  EmitTransform(Node);
  EmitOpacity(State, NeedRestore);

  EmitBezierEllipse(CX, CY, R, R);
  EmitFillAndStroke(State);
  EmitLn('Q');
end;

procedure TPixieSvgRenderer.RenderEllipse(Node: Pointer;
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

  EmitLn('q');
  EmitTransform(Node);
  EmitOpacity(State, NeedRestore);

  EmitBezierEllipse(CX, CY, RX, RY);
  EmitFillAndStroke(State);
  EmitLn('Q');
end;

procedure TPixieSvgRenderer.RenderLine(Node: Pointer;
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

  EmitLn('q');
  EmitTransform(Node);
  EmitOpacity(State, NeedRestore);

  SetPdfColor(State.StrokeColor, False);
  EmitLn(PdfFloat(State.StrokeWidth) + ' w');
  EmitLn(PdfFloat(X1) + ' ' + PdfFloat(Y1) + ' m ' +
         PdfFloat(X2) + ' ' + PdfFloat(Y2) + ' l S');
  EmitLn('Q');
end;

procedure TPixieSvgRenderer.RenderPolyline(Node: Pointer;
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
      Nums[NumCount] := StrToFloatDef(NumStr, 0);
      Inc(NumCount);
    end;
  end;

  if NumCount < 4 then Exit; // need at least 2 points

  EmitLn('q');
  EmitTransform(Node);
  EmitOpacity(State, NeedRestore);

  EmitLn(PdfFloat(Nums[0]) + ' ' + PdfFloat(Nums[1]) + ' m');
  I := 2;
  while I + 1 < NumCount do
  begin
    EmitLn(PdfFloat(Nums[I]) + ' ' + PdfFloat(Nums[I + 1]) + ' l');
    Inc(I, 2);
  end;

  if ClosePath then
    EmitLn('h');

  EmitFillAndStroke(State);
  EmitLn('Q');
end;

// ===========================================================================
// SVG path mini-language
// ===========================================================================

function TPixieSvgRenderer.ParsePathData(
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
          NumStr := NumStr + D[P];
          Inc(P);
        end;

        if NumStr <> '' then
        begin
          if ArgCount >= Length(ArgList) then
            SetLength(ArgList, Length(ArgList) * 2);
          ArgList[ArgCount] := StrToFloatDef(NumStr, 0);
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

procedure TPixieSvgRenderer.EmitPathCommands(Cmds: TPixieSvgPathCmdList);
var
  I, J, ArgIdx, ArgLen: Integer;
  Cmd: TPixieSvgPathCmd;
  CurX, CurY, StartX, StartY: Single;
  X, Y, X1, Y1, X2, Y2: Single;
  PrevCpX, PrevCpY: Single;   // previous control point for S/T
  PrevQpX, PrevQpY: Single;   // previous quadratic control point for T
  PrevCmd: AnsiChar;
  RX, RY, XRot: Single;
  LargeArc, Sweep: Boolean;
  // Quadratic to cubic conversion
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
        // First pair is moveto, rest are implicit lineto
        J := 0;
        while ArgIdx + 1 < ArgLen do
        begin
          X := Cmd.Args[ArgIdx]; Y := Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          if J = 0 then
          begin
            EmitLn(PdfFloat(X) + ' ' + PdfFloat(Y) + ' m');
            StartX := X; StartY := Y;
          end
          else
            EmitLn(PdfFloat(X) + ' ' + PdfFloat(Y) + ' l');
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
            EmitLn(PdfFloat(X) + ' ' + PdfFloat(Y) + ' m');
            StartX := X; StartY := Y;
          end
          else
            EmitLn(PdfFloat(X) + ' ' + PdfFloat(Y) + ' l');
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
          EmitLn(PdfFloat(X) + ' ' + PdfFloat(Y) + ' l');
          CurX := X; CurY := Y;
        end;
      end;

      'l':
      begin
        while ArgIdx + 1 < ArgLen do
        begin
          X := CurX + Cmd.Args[ArgIdx]; Y := CurY + Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          EmitLn(PdfFloat(X) + ' ' + PdfFloat(Y) + ' l');
          CurX := X; CurY := Y;
        end;
      end;

      'H':
      begin
        while ArgIdx < ArgLen do
        begin
          X := Cmd.Args[ArgIdx]; Inc(ArgIdx);
          EmitLn(PdfFloat(X) + ' ' + PdfFloat(CurY) + ' l');
          CurX := X;
        end;
      end;

      'h':
      begin
        while ArgIdx < ArgLen do
        begin
          X := CurX + Cmd.Args[ArgIdx]; Inc(ArgIdx);
          EmitLn(PdfFloat(X) + ' ' + PdfFloat(CurY) + ' l');
          CurX := X;
        end;
      end;

      'V':
      begin
        while ArgIdx < ArgLen do
        begin
          Y := Cmd.Args[ArgIdx]; Inc(ArgIdx);
          EmitLn(PdfFloat(CurX) + ' ' + PdfFloat(Y) + ' l');
          CurY := Y;
        end;
      end;

      'v':
      begin
        while ArgIdx < ArgLen do
        begin
          Y := CurY + Cmd.Args[ArgIdx]; Inc(ArgIdx);
          EmitLn(PdfFloat(CurX) + ' ' + PdfFloat(Y) + ' l');
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
          EmitLn(PdfFloat(X1) + ' ' + PdfFloat(Y1) + ' ' +
                 PdfFloat(X2) + ' ' + PdfFloat(Y2) + ' ' +
                 PdfFloat(X) + ' ' + PdfFloat(Y) + ' c');
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
          EmitLn(PdfFloat(X1) + ' ' + PdfFloat(Y1) + ' ' +
                 PdfFloat(X2) + ' ' + PdfFloat(Y2) + ' ' +
                 PdfFloat(X) + ' ' + PdfFloat(Y) + ' c');
          PrevCpX := X2; PrevCpY := Y2;
          CurX := X; CurY := Y;
        end;
      end;

      'S':
      begin
        while ArgIdx + 3 < ArgLen do
        begin
          // Reflect previous control point
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
          EmitLn(PdfFloat(X1) + ' ' + PdfFloat(Y1) + ' ' +
                 PdfFloat(X2) + ' ' + PdfFloat(Y2) + ' ' +
                 PdfFloat(X) + ' ' + PdfFloat(Y) + ' c');
          PrevCpX := X2; PrevCpY := Y2;
          CurX := X; CurY := Y;
          PrevCmd := 'S';
        end;
        Continue; // PrevCmd already set
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
          EmitLn(PdfFloat(X1) + ' ' + PdfFloat(Y1) + ' ' +
                 PdfFloat(X2) + ' ' + PdfFloat(Y2) + ' ' +
                 PdfFloat(X) + ' ' + PdfFloat(Y) + ' c');
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
          EmitLn(PdfFloat(Cp1X) + ' ' + PdfFloat(Cp1Y) + ' ' +
                 PdfFloat(Cp2X) + ' ' + PdfFloat(Cp2Y) + ' ' +
                 PdfFloat(X) + ' ' + PdfFloat(Y) + ' c');
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
          EmitLn(PdfFloat(Cp1X) + ' ' + PdfFloat(Cp1Y) + ' ' +
                 PdfFloat(Cp2X) + ' ' + PdfFloat(Cp2Y) + ' ' +
                 PdfFloat(X) + ' ' + PdfFloat(Y) + ' c');
          PrevQpX := X1; PrevQpY := Y1;
          CurX := X; CurY := Y;
        end;
      end;

      'T':
      begin
        while ArgIdx + 1 < ArgLen do
        begin
          // Reflect previous quadratic control point
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
          EmitLn(PdfFloat(Cp1X) + ' ' + PdfFloat(Cp1Y) + ' ' +
                 PdfFloat(Cp2X) + ' ' + PdfFloat(Cp2Y) + ' ' +
                 PdfFloat(X) + ' ' + PdfFloat(Y) + ' c');
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
          EmitLn(PdfFloat(Cp1X) + ' ' + PdfFloat(Cp1Y) + ' ' +
                 PdfFloat(Cp2X) + ' ' + PdfFloat(Cp2Y) + ' ' +
                 PdfFloat(X) + ' ' + PdfFloat(Y) + ' c');
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
        EmitLn('h');
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

procedure TPixieSvgRenderer.ArcToBezier(X1, Y1, RX, RY, XRotation: Single;
  LargeArc, Sweep: Boolean; X2, Y2: Single);
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
    EmitLn(PdfFloat(X2) + ' ' + PdfFloat(Y2) + ' l');
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

    // Endpoint 1 on unit circle
    EP1X := Cos1;
    EP1Y := Sin1;
    // Endpoint 2 on unit circle
    EP2X := Cos2;
    EP2Y := Sin2;

    // Control points on unit circle
    // CP1 = EP1 + alpha * tangent at EP1
    // CP2 = EP2 - alpha * tangent at EP2
    Cp1X := EP1X - Alpha * Sin1;
    Cp1Y := EP1Y + Alpha * Cos1;
    Cp2X := EP2X + Alpha * Sin2;
    Cp2Y := EP2Y - Alpha * Cos2;

    // Transform from unit circle to ellipse coordinates
    // Scale by radii, rotate by phi, translate to center
    E1X := CosPhi * RX * Cp1X - SinPhi * RY * Cp1Y + CX;
    E1Y := SinPhi * RX * Cp1X + CosPhi * RY * Cp1Y + CY;
    E2X := CosPhi * RX * Cp2X - SinPhi * RY * Cp2Y + CX;
    E2Y := SinPhi * RX * Cp2X + CosPhi * RY * Cp2Y + CY;

    // End point
    EP2X := CosPhi * RX * Cos2 - SinPhi * RY * Sin2 + CX;
    EP2Y := SinPhi * RX * Cos2 + CosPhi * RY * Sin2 + CY;

    EmitLn(PdfFloat(E1X) + ' ' + PdfFloat(E1Y) + ' ' +
           PdfFloat(E2X) + ' ' + PdfFloat(E2Y) + ' ' +
           PdfFloat(EP2X) + ' ' + PdfFloat(EP2Y) + ' c');

    T := T + SegAngle;
  end;
end;

// ===========================================================================
// Path rendering
// ===========================================================================

procedure TPixieSvgRenderer.RenderPath(Node: Pointer;
  const State: TPixieSvgState);
var
  D: string;
  Cmds: TPixieSvgPathCmdList;
  NeedRestore: Boolean;
begin
  D := GetAttr(Node, 'd');
  if D = '' then Exit;

  EmitLn('q');
  EmitTransform(Node);
  EmitOpacity(State, NeedRestore);

  Cmds := ParsePathData(D);
  try
    EmitPathCommands(Cmds);
  finally
    Cmds.Free;
  end;

  EmitFillAndStroke(State);
  EmitLn('Q');
end;

// ===========================================================================
// Text rendering
// ===========================================================================

function TPixieSvgRenderer.FindOrCreateSvgFont(const Family: string;
  Weight: Integer): Integer;
var
  I: Integer;
  FilePath: string;
  TtFont: TPixieTrueTypeFont;
  Key: string;
  Info: TPixieSvgFontInfo;
begin
  // Check existing
  for I := 0 to FFonts.Count - 1 do
  begin
    if (FFonts[I].TtFont <> nil) and
       (LowerCase(FFonts[I].TtFont.FamilyName) = LowerCase(Family)) then
    begin
      Result := I;
      Exit;
    end;
  end;

  // Find font file
  Key := LowerCase(Family) + ':' + IntToStr(Weight) + ':0';
  if not FFontCache.TryGetValue(Key, TtFont) then
  begin
    FilePath := PixieFindFontFile(Family, Weight, False);
    if FilePath = '' then
    begin
      // Try fallbacks
      {$IFDEF MSWINDOWS}
      FilePath := PixieFindFontFile('Segoe UI', Weight, False);
      if FilePath = '' then
        FilePath := PixieFindFontFile('Arial', Weight, False);
      {$ENDIF}
      {$IFDEF LINUX}
      FilePath := PixieFindFontFile('DejaVu Sans', Weight, False);
      {$ENDIF}
      {$IFDEF DARWIN}
      FilePath := PixieFindFontFile('Helvetica', Weight, False);
      {$ENDIF}
    end;

    TtFont := TPixieTrueTypeFont.Create;
    if (FilePath <> '') and TtFont.LoadFromFile(FilePath) then
      FFontCache.Add(Key, TtFont)
    else
    begin
      TtFont.Free;
      Result := -1;
      Exit;
    end;
  end;

  Inc(FFontCounter);
  Info.TtFont := TtFont;
  Info.PdfName := 'SvgF' + AnsiString(IntToStr(FFontCounter));
  Info.Type0ObjId := 0;
  Info.UsedGlyphs := TPixieGlyphMap.Create;
  FFonts.Add(Info);
  Result := FFonts.Count - 1;
end;

procedure TPixieSvgRenderer.BuildSvgFontObjects;
var
  I, J, K, ChunkSize: Integer;
  Info: TPixieSvgFontInfo;
  Scale: Single;
  FontFile, Descriptor, CidFont, Type0, ToUnicode: TPixiePdfObject;
  FontData: TBytes;
  WArray, CmapStr: AnsiString;
  SortedGlyphs: TList<UInt16>;
  Pair: TPair<UInt16, UInt32>;
  GlyphId, AdvWidth: UInt16;
  Flags: Integer;
  Asc, Desc: Single;
begin
  for I := 0 to FFonts.Count - 1 do
  begin
    Info := FFonts[I];
    if (Info.TtFont = nil) or (Info.UsedGlyphs.Count = 0) then Continue;

    Scale := 1000.0 / Info.TtFont.UnitsPerEm;

    // FontFile2
    FontFile := FWriter.AllocObject;
    FontData := Info.TtFont.BuildSubsetFont(Info.UsedGlyphs);
    FontFile.AddEntry('Length1', AnsiString(IntToStr(Length(FontData))));
    FontFile.SetStream(FontData, True);

    // FontDescriptor
    Descriptor := FWriter.AllocObject;
    Flags := 32;
    if Info.TtFont.ItalicAngle <> 0 then
      Flags := Flags or 64;
    if Info.TtFont.WeightClass >= 700 then
      Flags := Flags or (1 shl 18);

    Asc := Info.TtFont.Ascent * Scale;
    Desc := Info.TtFont.Descent * Scale;

    Descriptor.AddEntry('Type', '/FontDescriptor');
    Descriptor.AddEntry('FontName', '/' + Info.PdfName + 'TT');
    Descriptor.AddEntry('Flags', AnsiString(IntToStr(Flags)));
    Descriptor.AddEntry('FontBBox', PdfRect(
      Info.TtFont.BBoxXMin * Scale, Info.TtFont.BBoxYMin * Scale,
      Info.TtFont.BBoxXMax * Scale, Info.TtFont.BBoxYMax * Scale));
    Descriptor.AddEntry('ItalicAngle', PdfFloat(Info.TtFont.ItalicAngle));
    Descriptor.AddEntry('Ascent', PdfFloat(Asc));
    Descriptor.AddEntry('Descent', PdfFloat(Desc));
    Descriptor.AddEntry('CapHeight', PdfFloat(Info.TtFont.CapHeight * Scale));
    Descriptor.AddEntry('StemV', '80');
    Descriptor.AddEntry('FontFile2', PdfRef(FontFile.Id));

    // W array
    SortedGlyphs := TList<UInt16>.Create;
    try
      for Pair in Info.UsedGlyphs do
        SortedGlyphs.Add(Pair.Key);
      SortedGlyphs.Sort;

      WArray := '[';
      for J := 0 to SortedGlyphs.Count - 1 do
      begin
        GlyphId := SortedGlyphs[J];
        AdvWidth := Info.TtFont.GetGlyphWidth(GlyphId);
        WArray := WArray + AnsiString(IntToStr(GlyphId)) + ' [' +
          PdfFloat(AdvWidth * Scale) + '] ';
      end;
      WArray := WArray + ']';
    finally
      SortedGlyphs.Free;
    end;

    // CIDFontType2
    CidFont := FWriter.AllocObject;
    CidFont.AddEntry('Type', '/Font');
    CidFont.AddEntry('Subtype', '/CIDFontType2');
    CidFont.AddEntry('BaseFont', '/' + Info.PdfName + 'TT');
    CidFont.AddEntry('CIDSystemInfo',
      '<< /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>');
    CidFont.AddEntry('FontDescriptor', PdfRef(Descriptor.Id));
    CidFont.AddEntry('W', WArray);
    CidFont.AddEntry('DW', '1000');

    // ToUnicode CMap
    ToUnicode := FWriter.AllocObject;
    CmapStr :=
      '/CIDInit /ProcSet findresource begin'#10 +
      '12 dict begin'#10 +
      'begincmap'#10 +
      '/CIDSystemInfo'#10 +
      '<< /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def'#10 +
      '/CMapName /Adobe-Identity-UCS def'#10 +
      '/CMapType 2 def'#10 +
      '1 begincodespacerange'#10 +
      '<0000> <FFFF>'#10 +
      'endcodespacerange'#10;

    SortedGlyphs := TList<UInt16>.Create;
    try
      for Pair in Info.UsedGlyphs do
        SortedGlyphs.Add(Pair.Key);
      SortedGlyphs.Sort;

      if SortedGlyphs.Count > 0 then
      begin
        J := 0;
        while J < SortedGlyphs.Count do
        begin
          ChunkSize := SortedGlyphs.Count - J;
          if ChunkSize > 100 then ChunkSize := 100;
          CmapStr := CmapStr +
            AnsiString(IntToStr(ChunkSize)) + ' beginbfchar'#10;
          for K := J to J + ChunkSize - 1 do
          begin
            GlyphId := SortedGlyphs[K];
            CmapStr := CmapStr +
              '<' + AnsiString(LowerCase(IntToHex(GlyphId, 4))) + '> ' +
              '<' + AnsiString(LowerCase(IntToHex(
                Info.UsedGlyphs[GlyphId], 4))) + '>'#10;
          end;
          CmapStr := CmapStr + 'endbfchar'#10;
          Inc(J, ChunkSize);
        end;
      end;
    finally
      SortedGlyphs.Free;
    end;

    CmapStr := CmapStr +
      'endcmap'#10 +
      'CMapName currentdict /CMap defineresource pop'#10 +
      'end'#10 +
      'end'#10;
    ToUnicode.SetStream(TEncoding.ASCII.GetBytes(string(CmapStr)), True);

    // Type0
    Type0 := FWriter.AllocObject;
    Type0.AddEntry('Type', '/Font');
    Type0.AddEntry('Subtype', '/Type0');
    Type0.AddEntry('BaseFont', '/' + Info.PdfName + 'TT');
    Type0.AddEntry('Encoding', '/Identity-H');
    Type0.AddEntry('DescendantFonts', '[' + PdfRef(CidFont.Id) + ']');
    Type0.AddEntry('ToUnicode', PdfRef(ToUnicode.Id));

    // Update info with object ID
    Info.Type0ObjId := Type0.Id;
    FFonts[I] := Info;
  end;
end;

procedure TPixieSvgRenderer.RenderText(Node: Pointer;
  const State: TPixieSvgState);
var
  X, Y: Single;
  TextContent: string;
  FontIdx: Integer;
  Info: TPixieSvgFontInfo;
  PtSize, Scale: Single;
  I, Len: Integer;
  Codepoint: UInt32;
  GlyphId: UInt16;
  HexStr: AnsiString;
  NeedRestore: Boolean;
  Child: TDOMNode;
  TotalWidth, GlyphW: Single;
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

  FontIdx := FindOrCreateSvgFont(State.FontFamily, State.FontWeight);
  if FontIdx < 0 then Exit;

  Info := FFonts[FontIdx];
  if Info.TtFont = nil then Exit;

  PtSize := State.FontSize;
  Scale := PtSize / Info.TtFont.UnitsPerEm;

  EmitLn('q');
  EmitTransform(Node);
  EmitOpacity(State, NeedRestore);

  SetPdfColor(State.FillColor, True);

  // Handle text-anchor
  if GetAttr(Node, 'text-anchor') = 'middle' then
  begin
    // Measure text width and shift left by half
    TotalWidth := 0;
    I := 1;
    Len := Length(TextContent);
    while I <= Len do
    begin
      Codepoint := ReadUtf8Char(TextContent, I);
      if Codepoint = 0 then Break;
      GlyphId := Info.TtFont.CharToGlyph(Codepoint);
      TotalWidth := TotalWidth + Info.TtFont.GetGlyphWidth(GlyphId) * Scale;
      if State.LetterSpacing > 0 then
        TotalWidth := TotalWidth + State.LetterSpacing;
    end;
    X := X - TotalWidth / 2;
  end;

  EmitLn('BT');
  EmitLn('/' + Info.PdfName + ' ' + PdfFloat(PtSize) + ' Tf');
  // Use Tm with -1 Y scale to counteract the Form XObject's Y-flip,
  // so text renders right-side up
  EmitLn('1 0 0 -1 ' + PdfFloat(X) + ' ' + PdfFloat(Y) + ' Tm');

  if (State.LetterSpacing > 0) then
  begin
    // Render character by character with spacing
    I := 1;
    Len := Length(TextContent);
    while I <= Len do
    begin
      Codepoint := ReadUtf8Char(TextContent, I);
      if Codepoint = 0 then Break;
      GlyphId := Info.TtFont.CharToGlyph(Codepoint);
      if not Info.UsedGlyphs.ContainsKey(GlyphId) then
        Info.UsedGlyphs.Add(GlyphId, Codepoint);

      HexStr := '<' + AnsiString(LowerCase(IntToHex(GlyphId, 4))) + '>';
      GlyphW := Info.TtFont.GetGlyphWidth(GlyphId) * Scale + State.LetterSpacing;
      EmitLn(HexStr + ' Tj');
      EmitLn(PdfFloat(GlyphW) + ' 0 Td');
    end;
    // Update info
    FFonts[FontIdx] := Info;
  end
  else
  begin
    // Normal text rendering
    HexStr := '<';
    I := 1;
    Len := Length(TextContent);
    while I <= Len do
    begin
      Codepoint := ReadUtf8Char(TextContent, I);
      if Codepoint = 0 then Break;
      GlyphId := Info.TtFont.CharToGlyph(Codepoint);
      if not Info.UsedGlyphs.ContainsKey(GlyphId) then
        Info.UsedGlyphs.Add(GlyphId, Codepoint);
      HexStr := HexStr + AnsiString(LowerCase(IntToHex(GlyphId, 4)));
    end;
    HexStr := HexStr + '>';
    EmitLn(HexStr + ' Tj');
    // Update info
    FFonts[FontIdx] := Info;
  end;

  EmitLn('ET');
  EmitLn('Q');
end;

// ===========================================================================
// Group rendering (recursive tree walk)
// ===========================================================================

procedure TPixieSvgRenderer.RenderGroup(Node: Pointer;
  const State: TPixieSvgState);
var
  Child: TDOMNode;
  El: TDOMElement;
  TagName: string;
  ChildState: TPixieSvgState;
  IsGroup: Boolean;
begin
  Child := TDOMNode(Node).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = ELEMENT_NODE then
    begin
      El := TDOMElement(Child);
      TagName := LowerCase(DomToStr(El.TagName));
      ChildState := InheritState(Child, State);

      IsGroup := (TagName = 'g') or (TagName = 'svg');

      if IsGroup then
      begin
        EmitLn('q');
        EmitTransform(Child);
        RenderGroup(Child, ChildState);
        EmitLn('Q');
      end
      else if TagName = 'rect' then
        RenderRect(Child, ChildState)
      else if TagName = 'circle' then
        RenderCircle(Child, ChildState)
      else if TagName = 'ellipse' then
        RenderEllipse(Child, ChildState)
      else if TagName = 'line' then
        RenderLine(Child, ChildState)
      else if TagName = 'polyline' then
        RenderPolyline(Child, ChildState, False)
      else if TagName = 'polygon' then
        RenderPolyline(Child, ChildState, True)
      else if TagName = 'path' then
        RenderPath(Child, ChildState)
      else if TagName = 'text' then
        RenderText(Child, ChildState);
    end;

    Child := Child.NextSibling;
  end;
end;

// ===========================================================================
// Main entry point
// ===========================================================================

function TPixieSvgRenderer.RenderToFormXObject(Data: Pointer; Size: Integer;
  out OutWidth, OutHeight: Single): Integer;
var
  Doc: TXMLDocument;
  SvgRoot: TDOMElement;
  MemStream: TMemoryStream;
  VbStr, WidthStr, HeightStr: string;
  VbX, VbY, VbW, VbH: Single;
  Parts: array[0..3] of string;
  P, Idx: Integer;
  InitState: TPixieSvgState;
  FormObj: TPixiePdfObject;
  Buf: TBytes;
  MatrixStr, ResourceStr: AnsiString;
  I: Integer;
begin
  Result := 0;
  OutWidth := 0;
  OutHeight := 0;

  if (Data = nil) or (Size <= 0) then Exit;

  MemStream := TMemoryStream.Create;
  Doc := nil;
  try
    MemStream.Write(Data^, Size);
    MemStream.Position := 0;

    try
      ReadXMLFile(Doc, MemStream);
    except
      Exit;
    end;

    if Doc = nil then Exit;
    SvgRoot := Doc.DocumentElement;
    if SvgRoot = nil then Exit;

    // Parse viewBox
    VbStr := DomToStr(SvgRoot.GetAttribute('viewBox'));
    VbX := 0; VbY := 0; VbW := 0; VbH := 0;

    if VbStr <> '' then
    begin
      // Split by whitespace or comma
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

      VbX := StrToFloatDef(Parts[0], 0);
      VbY := StrToFloatDef(Parts[1], 0);
      VbW := StrToFloatDef(Parts[2], 0);
      VbH := StrToFloatDef(Parts[3], 0);
    end;

    // Parse width/height, fall back to viewBox
    WidthStr := DomToStr(SvgRoot.GetAttribute('width'));
    HeightStr := DomToStr(SvgRoot.GetAttribute('height'));

    if WidthStr <> '' then
      OutWidth := ParseSvgFloat(WidthStr)
    else
      OutWidth := VbW;
    if HeightStr <> '' then
      OutHeight := ParseSvgFloat(HeightStr)
    else
      OutHeight := VbH;

    if (OutWidth <= 0) or (OutHeight <= 0) then Exit;

    if VbW <= 0 then VbW := OutWidth;
    if VbH <= 0 then VbH := OutHeight;

    // Initialise default state
    InitState.FillColor := TPixieWebColor.Black;
    InitState.StrokeColor := TPixieWebColor.Black;
    InitState.StrokeWidth := 1;
    InitState.Opacity := 1.0;
    InitState.FillOpacity := 1.0;
    InitState.StrokeOpacity := 1.0;
    InitState.HasFill := True;
    InitState.HasStroke := False;
    InitState.FontFamily := 'sans-serif';
    InitState.FontSize := 16;
    InitState.FontWeight := 400;
    InitState.LetterSpacing := 0;

    // Inherit state from the root SVG element
    InitState := InheritState(SvgRoot, InitState);

    // Clear stream and render
    FStream.Size := 0;
    RenderGroup(SvgRoot, InitState);

    // Build font objects for any text rendered
    BuildSvgFontObjects;

    // Create Form XObject
    // DrawImage maps unit square [0,0,1,1] to destination rect.
    // Matrix must normalise SVG viewBox coords to [0,0,1,1] and
    // flip Y (SVG is Y-down, PDF DrawImage is Y-up).
    // Maps SVG (VbX,VbY) -> (0,1) and (VbX+VbW,VbY+VbH) -> (1,0).
    MatrixStr := '[' +
      PdfFloat(1.0 / VbW) + ' 0 0 ' +
      PdfFloat(-1.0 / VbH) + ' ' +
      PdfFloat(-VbX / VbW) + ' ' +
      PdfFloat((VbY + VbH) / VbH) + ']';

    // Build resource dictionary
    ResourceStr := '<< ';
    if FResourceExtGState <> '' then
      ResourceStr := ResourceStr + '/ExtGState << ' + FResourceExtGState + ' >> ';
    if FFonts.Count > 0 then
    begin
      ResourceStr := ResourceStr + '/Font << ';
      for I := 0 to FFonts.Count - 1 do
        if FFonts[I].Type0ObjId <> 0 then
          ResourceStr := ResourceStr + '/' + FFonts[I].PdfName + ' ' +
            PdfRef(FFonts[I].Type0ObjId) + ' ';
      ResourceStr := ResourceStr + '>> ';
    end;
    ResourceStr := ResourceStr + '>>';

    // Create the Form XObject
    FormObj := FWriter.AllocObject;
    FormObj.AddEntry('Type', '/XObject');
    FormObj.AddEntry('Subtype', '/Form');
    FormObj.AddEntry('BBox', '[0 0 ' + PdfFloat(VbW) + ' ' + PdfFloat(VbH) + ']');
    FormObj.AddEntry('Matrix', MatrixStr);
    FormObj.AddEntry('Resources', ResourceStr);

    SetLength(Buf, FStream.Size);
    if FStream.Size > 0 then
    begin
      FStream.Position := 0;
      FStream.Read(Buf[0], Length(Buf));
    end;
    FormObj.SetStream(Buf, True);

    Result := FormObj.Id;
  finally
    Doc.Free;
    MemStream.Free;
  end;
end;

end.
