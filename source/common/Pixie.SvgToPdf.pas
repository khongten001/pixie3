unit Pixie.SvgToPdf;

// SVG-to-PDF vector conversion.
// Inherits SVG parsing from TPixieSvgRendererBase and overrides abstract
// drawing primitives to emit PDF path operators into a Form XObject.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections,
  Pixie.Types, Pixie.WebColor, Pixie.TrueType, Pixie.PdfWriter,
  Pixie.SvgRenderer;

type
  { TPixieSvgFontInfo - font used in SVG text }

  TPixieSvgFontInfo = record
    TtFont: TPixieTrueTypeFont;
    PdfName: AnsiString;
    Type0ObjId: Integer;
    UsedGlyphs: TPixieGlyphMap;
  end;

  TPixieSvgFontInfoList = TList<TPixieSvgFontInfo>;

  { TPixieSvgRenderer - PDF SVG renderer }

  TPixieSvgRenderer = class(TPixieSvgRendererBase)
  private
    FWriter: TPixiePdfWriter;
    FFontCache: TPixieTrueTypeFontCache;
    FStream: TMemoryStream;
    FResourceExtGState: AnsiString;
    FResourceShading: AnsiString;
    FFonts: TPixieSvgFontInfoList;
    FGsCounter: Integer;
    FFontCounter: Integer;
    FShadingCounter: Integer;

    // Bounding box tracking for gradient fills
    FBBoxMinX, FBBoxMinY, FBBoxMaxX, FBBoxMaxY: Single;
    FBBoxValid: Boolean;

    procedure Emit(const S: AnsiString);
    procedure EmitLn(const S: AnsiString);
    procedure SetPdfColor(const Color: TPixieWebColor; Fill: Boolean);
    procedure UpdateBBox(X, Y: Single);

    // Gradient helpers
    function BuildType2Function(const C0, C1: TPixieWebColor): Integer;
    function BuildColorFunction(const Grad: TPixieSvgGradient): Integer;
    function GradientNeedsAlpha(const Grad: TPixieSvgGradient): Boolean;
    function BuildAlphaType2Function(A0, A1: Byte): Integer;
    function BuildAlphaFunction(const Grad: TPixieSvgGradient): Integer;
    function BuildGradientSMask(const Grad: TPixieSvgGradient;
      IsRadial: Boolean; const CoordsStr: AnsiString;
      ShadingType: Integer): AnsiString;
    procedure FillGradient(const State: TPixieSvgState);

    // Font helpers
    function FindOrCreateSvgFont(const Family: string;
      Weight: Integer): Integer;
    procedure BuildSvgFontObjects;
  protected
    // Override abstract drawing primitives with PDF operators
    procedure DoMoveTo(X, Y: Single); override;
    procedure DoLineTo(X, Y: Single); override;
    procedure DoCurveTo(X1, Y1, X2, Y2, X3, Y3: Single); override;
    procedure DoClosePath; override;
    procedure DoSaveState; override;
    procedure DoRestoreState; override;
    procedure DoSetTransform(const M: TPixieSvgMatrix); override;
    procedure DoFillAndStroke(const State: TPixieSvgState); override;
    procedure DoBeginOpacity(Opacity: Single); override;
    procedure DoEndOpacity; override;
    procedure DoClipPath; override;

    // Override text rendering for PDF font embedding
    procedure RenderText(Node: Pointer;
      const State: TPixieSvgState); override;
  public
    constructor Create(AWriter: TPixiePdfWriter;
      AFontCache: TPixieTrueTypeFontCache);
    destructor Destroy; override;

    function RenderToFormXObject(Data: Pointer; Size: Integer;
      out OutWidth, OutHeight: Single): Integer;
  end;

implementation

uses
  Math, Pixie.SimpleXml, Pixie.Utf8;

{$IFDEF FPC}
function DomToStr(const S: WideString): string; inline;
begin Result := UTF8Encode(S); end;
{$ELSE}
function DomToStr(const S: WideString): string; inline;
begin Result := S; end;
{$ENDIF}

// ===========================================================================
// Construction
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
  FShadingCounter := 0;
  FBBoxValid := False;
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

// ===========================================================================
// Bounding box and gradient helpers
// ===========================================================================

procedure TPixieSvgRenderer.UpdateBBox(X, Y: Single);
begin
  if not FBBoxValid then
  begin
    FBBoxMinX := X; FBBoxMinY := Y;
    FBBoxMaxX := X; FBBoxMaxY := Y;
    FBBoxValid := True;
  end
  else
  begin
    if X < FBBoxMinX then FBBoxMinX := X;
    if Y < FBBoxMinY then FBBoxMinY := Y;
    if X > FBBoxMaxX then FBBoxMaxX := X;
    if Y > FBBoxMaxY then FBBoxMaxY := Y;
  end;
end;

function TPixieSvgRenderer.BuildType2Function(
  const C0, C1: TPixieWebColor): Integer;
var
  Obj: TPixiePdfObject;
begin
  Obj := FWriter.AllocObject;
  Obj.AddEntry('FunctionType', '2');
  Obj.AddEntry('Domain', '[0 1]');
  Obj.AddEntry('C0', '[' + PdfFloat(C0.Red / 255.0) + ' ' +
    PdfFloat(C0.Green / 255.0) + ' ' + PdfFloat(C0.Blue / 255.0) + ']');
  Obj.AddEntry('C1', '[' + PdfFloat(C1.Red / 255.0) + ' ' +
    PdfFloat(C1.Green / 255.0) + ' ' + PdfFloat(C1.Blue / 255.0) + ']');
  Obj.AddEntry('N', '1');
  Result := Obj.Id;
end;

function TPixieSvgRenderer.BuildColorFunction(
  const Grad: TPixieSvgGradient): Integer;
var
  I, N: Integer;
  SubIds: array of Integer;
  FuncsStr, BoundsStr, EncodeStr: AnsiString;
  Obj: TPixiePdfObject;
begin
  N := Grad.Stops.Count;
  if N < 2 then begin Result := 0; Exit; end;

  if N = 2 then
  begin
    Result := BuildType2Function(Grad.Stops[0].Color, Grad.Stops[1].Color);
    Exit;
  end;

  // N >= 3: stitching function (Type 3)
  SetLength(SubIds, N - 1);
  for I := 0 to N - 2 do
    SubIds[I] := BuildType2Function(Grad.Stops[I].Color, Grad.Stops[I + 1].Color);

  FuncsStr := '[';
  for I := 0 to N - 2 do
    FuncsStr := FuncsStr + PdfRef(SubIds[I]) + ' ';
  FuncsStr := FuncsStr + ']';

  BoundsStr := '[';
  for I := 1 to N - 2 do
    BoundsStr := BoundsStr + PdfFloat(Grad.Stops[I].Offset) + ' ';
  BoundsStr := BoundsStr + ']';

  EncodeStr := '[';
  for I := 0 to N - 2 do
    EncodeStr := EncodeStr + '0 1 ';
  EncodeStr := EncodeStr + ']';

  Obj := FWriter.AllocObject;
  Obj.AddEntry('FunctionType', '3');
  Obj.AddEntry('Domain', '[0 1]');
  Obj.AddEntry('Functions', FuncsStr);
  Obj.AddEntry('Bounds', BoundsStr);
  Obj.AddEntry('Encode', EncodeStr);
  Result := Obj.Id;
end;

function TPixieSvgRenderer.GradientNeedsAlpha(
  const Grad: TPixieSvgGradient): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to Grad.Stops.Count - 1 do
    if Grad.Stops[I].Color.Alpha < 255 then
    begin
      Result := True;
      Exit;
    end;
end;

function TPixieSvgRenderer.BuildAlphaType2Function(A0, A1: Byte): Integer;
var
  Obj: TPixiePdfObject;
begin
  Obj := FWriter.AllocObject;
  Obj.AddEntry('FunctionType', '2');
  Obj.AddEntry('Domain', '[0 1]');
  Obj.AddEntry('C0', '[' + PdfFloat(A0 / 255.0) + ']');
  Obj.AddEntry('C1', '[' + PdfFloat(A1 / 255.0) + ']');
  Obj.AddEntry('N', '1');
  Result := Obj.Id;
end;

function TPixieSvgRenderer.BuildAlphaFunction(
  const Grad: TPixieSvgGradient): Integer;
var
  I, N: Integer;
  SubIds: array of Integer;
  FuncsStr, BoundsStr, EncodeStr: AnsiString;
  Obj: TPixiePdfObject;
begin
  N := Grad.Stops.Count;
  if N < 2 then begin Result := 0; Exit; end;

  if N = 2 then
  begin
    Result := BuildAlphaType2Function(
      Grad.Stops[0].Color.Alpha, Grad.Stops[1].Color.Alpha);
    Exit;
  end;

  SetLength(SubIds, N - 1);
  for I := 0 to N - 2 do
    SubIds[I] := BuildAlphaType2Function(
      Grad.Stops[I].Color.Alpha, Grad.Stops[I + 1].Color.Alpha);

  FuncsStr := '[';
  for I := 0 to N - 2 do
    FuncsStr := FuncsStr + PdfRef(SubIds[I]) + ' ';
  FuncsStr := FuncsStr + ']';

  BoundsStr := '[';
  for I := 1 to N - 2 do
    BoundsStr := BoundsStr + PdfFloat(Grad.Stops[I].Offset) + ' ';
  BoundsStr := BoundsStr + ']';

  EncodeStr := '[';
  for I := 0 to N - 2 do
    EncodeStr := EncodeStr + '0 1 ';
  EncodeStr := EncodeStr + ']';

  Obj := FWriter.AllocObject;
  Obj.AddEntry('FunctionType', '3');
  Obj.AddEntry('Domain', '[0 1]');
  Obj.AddEntry('Functions', FuncsStr);
  Obj.AddEntry('Bounds', BoundsStr);
  Obj.AddEntry('Encode', EncodeStr);
  Result := Obj.Id;
end;

function TPixieSvgRenderer.BuildGradientSMask(
  const Grad: TPixieSvgGradient; IsRadial: Boolean;
  const CoordsStr: AnsiString; ShadingType: Integer): AnsiString;
var
  AlphaFuncId: Integer;
  AlphaShObj, FormObj, GsObj: TPixiePdfObject;
  StreamData: AnsiString;
  StreamBytes: TBytes;
  BBoxStr, GsName: AnsiString;
begin
  AlphaFuncId := BuildAlphaFunction(Grad);
  if AlphaFuncId = 0 then begin Result := ''; Exit; end;

  // Grayscale shading for opacity
  AlphaShObj := FWriter.AllocObject;
  AlphaShObj.AddEntry('ShadingType', AnsiString(IntToStr(ShadingType)));
  AlphaShObj.AddEntry('ColorSpace', '/DeviceGray');
  AlphaShObj.AddEntry('Coords', CoordsStr);
  AlphaShObj.AddEntry('Function', PdfRef(AlphaFuncId));
  AlphaShObj.AddEntry('Extend', '[true true]');

  // Form XObject that paints the opacity shading
  BBoxStr := '[' + PdfFloat(FViewBoxX) + ' ' + PdfFloat(FViewBoxY) + ' ' +
    PdfFloat(FViewBoxX + FViewBoxW) + ' ' + PdfFloat(FViewBoxY + FViewBoxH) + ']';

  StreamData := '/AlSh sh' + #10;
  SetLength(StreamBytes, Length(StreamData));
  Move(StreamData[1], StreamBytes[0], Length(StreamData));

  FormObj := FWriter.AllocObject;
  FormObj.AddEntry('Type', '/XObject');
  FormObj.AddEntry('Subtype', '/Form');
  FormObj.AddEntry('BBox', BBoxStr);
  FormObj.AddEntry('Group',
    '<< /Type /Group /S /Transparency /CS /DeviceGray >>');
  FormObj.AddEntry('Resources',
    '<< /Shading << /AlSh ' + PdfRef(AlphaShObj.Id) + ' >> >>');
  FormObj.SetStream(StreamBytes, False);

  // ExtGState with SMask
  GsObj := FWriter.AllocObject;
  GsObj.AddEntry('Type', '/ExtGState');
  GsObj.AddEntry('SMask',
    '<< /Type /Mask /S /Luminosity /G ' + PdfRef(FormObj.Id) + ' >>');

  Inc(FGsCounter);
  GsName := 'SvgGS' + AnsiString(IntToStr(FGsCounter));
  FResourceExtGState := FResourceExtGState + '/' + GsName + ' ' +
    PdfRef(GsObj.Id) + ' ';
  Result := GsName;
end;

procedure TPixieSvgRenderer.FillGradient(const State: TPixieSvgState);
var
  Grad: TPixieSvgGradient;
  FuncId: Integer;
  ShObj: TPixiePdfObject;
  ShName, CoordsStr, GsName: AnsiString;
  ShadingTypeVal: Integer;
  BX, BY, BW, BH: Single;
  GX1, GY1, GX2, GY2: Single;
  GCX, GCY, GR: Single;
  TX, TY: Single;
  M: TPixieSvgMatrix;
  HasTransform: Boolean;
begin
  Grad := ResolveGradientStops(State.FillGradientId);
  if (Grad = nil) or (Grad.Stops.Count < 2) then
  begin
    EmitLn('n');
    Exit;
  end;

  if not FBBoxValid then begin EmitLn('n'); Exit; end;
  BX := FBBoxMinX; BY := FBBoxMinY;
  BW := FBBoxMaxX - FBBoxMinX; BH := FBBoxMaxY - FBBoxMinY;
  if (BW < 0.001) or (BH < 0.001) then begin EmitLn('n'); Exit; end;

  FuncId := BuildColorFunction(Grad);
  if FuncId = 0 then begin EmitLn('n'); Exit; end;

  HasTransform := Grad.GradientTransform <> '';
  if HasTransform then
    M := ParseTransform(Grad.GradientTransform);

  // Build PDF shading object
  ShObj := FWriter.AllocObject;
  ShObj.AddEntry('ColorSpace', '/DeviceRGB');
  ShObj.AddEntry('Function', PdfRef(FuncId));
  ShObj.AddEntry('Extend', '[true true]');

  if not Grad.IsRadial then
  begin
    ShadingTypeVal := 2;
    if Grad.UserSpaceUnits then
    begin
      GX1 := Grad.X1; GY1 := Grad.Y1;
      GX2 := Grad.X2; GY2 := Grad.Y2;
    end
    else
    begin
      GX1 := BX + Grad.X1 * BW; GY1 := BY + Grad.Y1 * BH;
      GX2 := BX + Grad.X2 * BW; GY2 := BY + Grad.Y2 * BH;
    end;
    if HasTransform then
    begin
      TX := M.A * GX1 + M.C * GY1 + M.E;
      TY := M.B * GX1 + M.D * GY1 + M.F;
      GX1 := TX; GY1 := TY;
      TX := M.A * GX2 + M.C * GY2 + M.E;
      TY := M.B * GX2 + M.D * GY2 + M.F;
      GX2 := TX; GY2 := TY;
    end;
    CoordsStr := '[' + PdfFloat(GX1) + ' ' + PdfFloat(GY1) + ' ' +
      PdfFloat(GX2) + ' ' + PdfFloat(GY2) + ']';
  end
  else
  begin
    ShadingTypeVal := 3;
    if Grad.UserSpaceUnits then
    begin
      GCX := Grad.CX; GCY := Grad.CY; GR := Grad.R;
    end
    else
    begin
      GCX := BX + Grad.CX * BW; GCY := BY + Grad.CY * BH;
      GR := Grad.R * Max(BW, BH);
    end;
    if HasTransform then
    begin
      TX := M.A * GCX + M.C * GCY + M.E;
      TY := M.B * GCX + M.D * GCY + M.F;
      GCX := TX; GCY := TY;
      GR := GR * Sqrt(M.A * M.A + M.B * M.B);
    end;
    CoordsStr := '[' + PdfFloat(GCX) + ' ' + PdfFloat(GCY) + ' 0 ' +
      PdfFloat(GCX) + ' ' + PdfFloat(GCY) + ' ' + PdfFloat(GR) + ']';
  end;

  ShObj.AddEntry('ShadingType', AnsiString(IntToStr(ShadingTypeVal)));
  ShObj.AddEntry('Coords', CoordsStr);

  // Register shading resource
  Inc(FShadingCounter);
  ShName := 'SvgSh' + AnsiString(IntToStr(FShadingCounter));
  FResourceShading := FResourceShading + '/' + ShName + ' ' +
    PdfRef(ShObj.Id) + ' ';

  // Apply soft mask for gradient stop-opacity if needed
  if GradientNeedsAlpha(Grad) then
  begin
    GsName := BuildGradientSMask(Grad, Grad.IsRadial, CoordsStr, ShadingTypeVal);
    if GsName <> '' then
      EmitLn('/' + GsName + ' gs');
  end;

  // Clip to path and paint shading
  if State.EvenOddFill then
    EmitLn('W* n')
  else
    EmitLn('W n');
  EmitLn('/' + ShName + ' sh');
end;

// ===========================================================================
// Abstract drawing primitive overrides — PDF operators
// ===========================================================================

procedure TPixieSvgRenderer.DoMoveTo(X, Y: Single);
begin
  UpdateBBox(X, Y);
  EmitLn(PdfFloat(X) + ' ' + PdfFloat(Y) + ' m');
end;

procedure TPixieSvgRenderer.DoLineTo(X, Y: Single);
begin
  UpdateBBox(X, Y);
  EmitLn(PdfFloat(X) + ' ' + PdfFloat(Y) + ' l');
end;

procedure TPixieSvgRenderer.DoCurveTo(X1, Y1, X2, Y2, X3, Y3: Single);
begin
  UpdateBBox(X1, Y1);
  UpdateBBox(X2, Y2);
  UpdateBBox(X3, Y3);
  EmitLn(PdfFloat(X1) + ' ' + PdfFloat(Y1) + ' ' +
         PdfFloat(X2) + ' ' + PdfFloat(Y2) + ' ' +
         PdfFloat(X3) + ' ' + PdfFloat(Y3) + ' c');
end;

procedure TPixieSvgRenderer.DoClosePath;
begin
  EmitLn('h');
end;

procedure TPixieSvgRenderer.DoSaveState;
begin
  EmitLn('q');
end;

procedure TPixieSvgRenderer.DoRestoreState;
begin
  EmitLn('Q');
end;

procedure TPixieSvgRenderer.DoSetTransform(const M: TPixieSvgMatrix);
begin
  EmitLn(PdfFloat(M.A) + ' ' + PdfFloat(M.B) + ' ' +
         PdfFloat(M.C) + ' ' + PdfFloat(M.D) + ' ' +
         PdfFloat(M.E) + ' ' + PdfFloat(M.F) + ' cm');
end;

procedure TPixieSvgRenderer.DoFillAndStroke(const State: TPixieSvgState);
var
  FillAlpha, StrokeAlpha: Single;
  DoFill, DoStroke: Boolean;
  GsObj: TPixiePdfObject;
  GsName: AnsiString;
begin
  FillAlpha := (State.FillColor.Alpha / 255.0) * State.FillOpacity;
  StrokeAlpha := (State.StrokeColor.Alpha / 255.0) * State.StrokeOpacity;
  DoFill := State.HasFill and ((State.FillGradientId <> '') or (FillAlpha > 0.001));
  // Gradient strokes not supported in PDF — skip them
  DoStroke := State.HasStroke and (State.StrokeGradientId = '') and
    (StrokeAlpha > 0.001);

  if State.FillGradientId <> '' then
  begin
    EmitLn('q');
    FillGradient(State);
    EmitLn('Q');
  end
  else if DoFill or DoStroke then
  begin
    // Apply fill/stroke opacity via ExtGState if not fully opaque
    if (DoFill and (FillAlpha < 0.999)) or
       (DoStroke and (StrokeAlpha < 0.999)) then
    begin
      GsObj := FWriter.AllocObject;
      GsObj.AddEntry('Type', '/ExtGState');
      if DoFill then
        GsObj.AddEntry('ca', PdfFloat(FillAlpha));
      if DoStroke then
        GsObj.AddEntry('CA', PdfFloat(StrokeAlpha));
      Inc(FGsCounter);
      GsName := 'SvgGS' + AnsiString(IntToStr(FGsCounter));
      FResourceExtGState := FResourceExtGState + '/' + GsName + ' ' +
        PdfRef(GsObj.Id) + ' ';
      EmitLn('/' + GsName + ' gs');
    end;

    if DoFill and DoStroke then
    begin
      SetPdfColor(State.FillColor, True);
      SetPdfColor(State.StrokeColor, False);
      EmitLn(PdfFloat(State.StrokeWidth) + ' w');
      if State.EvenOddFill then
        EmitLn('B*')
      else
        EmitLn('B');
    end
    else if DoFill then
    begin
      SetPdfColor(State.FillColor, True);
      if State.EvenOddFill then
        EmitLn('f*')
      else
        EmitLn('f');
    end
    else if DoStroke then
    begin
      SetPdfColor(State.StrokeColor, False);
      EmitLn(PdfFloat(State.StrokeWidth) + ' w');
      EmitLn('S');
    end
    else
      EmitLn('n');
  end
  else
    EmitLn('n');

  FBBoxValid := False;
end;

procedure TPixieSvgRenderer.DoBeginOpacity(Opacity: Single);
var
  GsObj: TPixiePdfObject;
  GsName: AnsiString;
begin
  GsObj := FWriter.AllocObject;
  GsObj.AddEntry('Type', '/ExtGState');
  GsObj.AddEntry('ca', PdfFloat(Opacity));
  GsObj.AddEntry('CA', PdfFloat(Opacity));

  Inc(FGsCounter);
  GsName := 'SvgGS' + AnsiString(IntToStr(FGsCounter));
  FResourceExtGState := FResourceExtGState + '/' + GsName + ' ' +
    PdfRef(GsObj.Id) + ' ';

  EmitLn('/' + GsName + ' gs');
end;

procedure TPixieSvgRenderer.DoEndOpacity;
begin
  // No-op for PDF — restore handled by q/Q
end;

procedure TPixieSvgRenderer.DoClipPath;
begin
  // W n — clip to current path (non-zero winding), then clear path
  // W* n — even-odd clip rule
  EmitLn('W n');
end;

// ===========================================================================
// Font helpers
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

// Encode a Unicode codepoint as a hex string in UTF-16BE for ToUnicode CMap.
// BMP codepoints produce 4 hex digits; supplementary plane produces 8 (surrogate pair).
function SvgCodepointToUtf16Hex(Cp: UInt32): AnsiString;
var
  Hi, Lo: UInt16;
begin
  if Cp <= $FFFF then
    Result := AnsiString(IntToHex(Cp, 4))
  else begin
    Hi := UInt16(((Cp - $10000) shr 10) + $D800);
    Lo := UInt16(((Cp - $10000) and $3FF) + $DC00);
    Result := AnsiString(IntToHex(Hi, 4) + IntToHex(Lo, 4));
  end;
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
    CidFont.AddEntry('CIDToGIDMap', '/Identity');

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
              '<' + AnsiString(IntToHex(GlyphId, 4)) + '> ' +
              '<' + SvgCodepointToUtf16Hex(Info.UsedGlyphs[GlyphId]) + '>'#10;
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

// ===========================================================================
// Text rendering (PDF — uses glyph-based font embedding)
// ===========================================================================

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

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyOpacity(State, NeedRestore);

  SetPdfColor(State.FillColor, True);

  // Handle text-anchor
  if GetAttr(Node, 'text-anchor') = 'middle' then
  begin
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
  EmitLn('1 0 0 -1 ' + PdfFloat(X) + ' ' + PdfFloat(Y) + ' Tm');

  if (State.LetterSpacing > 0) then
  begin
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
    FFonts[FontIdx] := Info;
  end
  else
  begin
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
    FFonts[FontIdx] := Info;
  end;

  EmitLn('ET');
  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

// ===========================================================================
// Main entry point
// ===========================================================================

function TPixieSvgRenderer.RenderToFormXObject(Data: Pointer; Size: Integer;
  out OutWidth, OutHeight: Single): Integer;
var
  FormObj: TPixiePdfObject;
  Buf: TBytes;
  MatrixStr, ResourceStr: AnsiString;
  I: Integer;
begin
  Result := 0;
  OutWidth := 0;
  OutHeight := 0;

  if not ParseSvg(Data, Size, OutWidth, OutHeight) then Exit;
  try
    // Clear stream and render
    FStream.Size := 0;
    RenderDocument;

    // Build font objects for any text rendered
    BuildSvgFontObjects;

    // Create Form XObject
    // DrawImage maps unit square [0,0,1,1] to destination rect.
    // Matrix must normalise SVG viewBox coords to [0,0,1,1] and
    // flip Y (SVG is Y-down, PDF DrawImage is Y-up).
    MatrixStr := '[' +
      PdfFloat(1.0 / FViewBoxW) + ' 0 0 ' +
      PdfFloat(-1.0 / FViewBoxH) + ' ' +
      PdfFloat(-FViewBoxX / FViewBoxW) + ' ' +
      PdfFloat((FViewBoxY + FViewBoxH) / FViewBoxH) + ']';

    // Build resource dictionary
    ResourceStr := '<< ';
    if FResourceExtGState <> '' then
      ResourceStr := ResourceStr + '/ExtGState << ' + FResourceExtGState + ' >> ';
    if FResourceShading <> '' then
      ResourceStr := ResourceStr + '/Shading << ' + FResourceShading + ' >> ';
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
    FormObj.AddEntry('BBox', '[0 0 ' + PdfFloat(FViewBoxW) + ' ' +
      PdfFloat(FViewBoxH) + ']');
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
    ClearDocument;
  end;
end;

end.
