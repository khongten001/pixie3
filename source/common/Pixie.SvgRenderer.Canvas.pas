unit Pixie.SvgRenderer.Canvas;

// SVG renderer that draws through TPixieCanvas.
// Inherits SVG parsing from TPixieSvgRendererBase and overrides abstract
// drawing primitives to render via the canvas path API, giving native
// vector rendering on all backends (D2D, Cairo, CG, Qt, FMX).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Math, Generics.Collections,
  Pixie.Types, Pixie.WebColor, Pixie.FontDescription,
  Pixie.GradientLayer, Pixie.Borders,
  Pixie.Canvas, Pixie.SvgRenderer;

type
  { TPixieSvgCanvasRenderer }

  TPixieSvgCanvasRenderer = class(TPixieSvgRendererBase)
  private
    FCanvas: TPixieCanvas;
    FFontHandle: TPixieFontHandle;
    FFontMetrics: TPixieFontMetrics;
    FFontFamily: string;
    FFontSize: Single;
    FFontWeight: Integer;

    // Bounding box of the current path (for gradient coordinate mapping)
    FBBoxMinX, FBBoxMinY, FBBoxMaxX, FBBoxMaxY: Single;
    FBBoxValid: Boolean;

    // Image cache for <image> elements (freed on ClearDocument)
    FImageCache: TDictionary<string, TPixieImageHandle>;

    procedure UpdateBBox(X, Y: Single);
    procedure ResetBBox;
    procedure FillWithGradient(const State: TPixieSvgState;
      FillRule: TPixieFillRule);
    procedure StrokeWithGradient(const State: TPixieSvgState);
    procedure PopulateStops(Layer: TPixieGradientBase;
      const Grad: TPixieSvgGradient; Opacity: Single);
    procedure RebuildAndStroke(const State: TPixieSvgState);
    procedure RebuildAndStrokeGradient(const State: TPixieSvgState);
    function LoadImageFromHref(const Href: string): TPixieImageHandle;
    procedure FreeImageCache;
    function IsPatternFill(const Id: string): Boolean;
    procedure FillWithPattern(const State: TPixieSvgState;
      FillRule: TPixieFillRule);

    // Path recording — only active when gradient fill + stroke needs replay
    type
      TPathOp = (poMoveTo, poLineTo, poCurveTo, poClosePath);
      TPathEntry = record
        Op: TPathOp;
        X, Y, X2, Y2, X3, Y3: Single;
      end;
      TPathEntryList = TList<TPathEntry>;
    var
      FPathRecord: TPathEntryList;
  protected
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
    procedure DoDrawText(const Text: string; X, Y: Single;
      const State: TPixieSvgState); override;
    procedure DoDrawImage(const Href: string;
      X, Y, W, H: Single); override;
    procedure DoClearImages; override;
  public
    constructor Create(ACanvas: TPixieCanvas);
    destructor Destroy; override;

    // Render SVG into a destination rectangle, handling viewBox transform
    procedure RenderToRect(DstX, DstY, DstW, DstH: Single);
  end;

implementation

uses
  Pixie.SimpleXml, Pixie.DataUri
  {$IFDEF FPC}, FPImage, FPReadPNG, FPReadJPEG, FPReadBMP, FPReadGIF,
  Pixie.ImageUtils{$ENDIF};

// ===========================================================================
// Construction
// ===========================================================================

constructor TPixieSvgCanvasRenderer.Create(ACanvas: TPixieCanvas);
begin
  inherited Create;
  FCanvas := ACanvas;
  FFontHandle := 0;
  FFontFamily := '';
  FFontSize := 0;
  FFontWeight := 0;
  FBBoxValid := False;
  FPathRecord := TPathEntryList.Create;
end;

destructor TPixieSvgCanvasRenderer.Destroy;
begin
  FreeImageCache;
  if (FFontHandle <> 0) and (FCanvas <> nil) then
    FCanvas.DeleteFont(FFontHandle);
  FPathRecord.Free;
  inherited;
end;

// ===========================================================================
// Bounding box helpers
// ===========================================================================

procedure TPixieSvgCanvasRenderer.UpdateBBox(X, Y: Single);
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

procedure TPixieSvgCanvasRenderer.ResetBBox;
begin
  FBBoxValid := False;
  FBBoxMinX := 0; FBBoxMinY := 0;
  FBBoxMaxX := 0; FBBoxMaxY := 0;
end;

// ===========================================================================
// Drawing primitives — path construction
// ===========================================================================

procedure TPixieSvgCanvasRenderer.DoMoveTo(X, Y: Single);
var
  Entry: TPathEntry;
begin
  FCanvas.MoveTo(X, Y);
  UpdateBBox(X, Y);
  Entry.Op := poMoveTo;
  Entry.X := X; Entry.Y := Y;
  FPathRecord.Add(Entry);
end;

procedure TPixieSvgCanvasRenderer.DoLineTo(X, Y: Single);
var
  Entry: TPathEntry;
begin
  FCanvas.LineTo(X, Y);
  UpdateBBox(X, Y);
  Entry.Op := poLineTo;
  Entry.X := X; Entry.Y := Y;
  FPathRecord.Add(Entry);
end;

procedure TPixieSvgCanvasRenderer.DoCurveTo(X1, Y1, X2, Y2,
  X3, Y3: Single);
var
  Entry: TPathEntry;
begin
  FCanvas.CurveTo(X1, Y1, X2, Y2, X3, Y3);
  UpdateBBox(X1, Y1);
  UpdateBBox(X2, Y2);
  UpdateBBox(X3, Y3);
  Entry.Op := poCurveTo;
  Entry.X := X1; Entry.Y := Y1;
  Entry.X2 := X2; Entry.Y2 := Y2;
  Entry.X3 := X3; Entry.Y3 := Y3;
  FPathRecord.Add(Entry);
end;

procedure TPixieSvgCanvasRenderer.DoClosePath;
var
  Entry: TPathEntry;
begin
  FCanvas.ClosePath;
  Entry.Op := poClosePath;
  FPathRecord.Add(Entry);
end;

// ===========================================================================
// State management
// ===========================================================================

procedure TPixieSvgCanvasRenderer.DoSaveState;
begin
  FCanvas.SaveState;
end;

procedure TPixieSvgCanvasRenderer.DoRestoreState;
begin
  FCanvas.RestoreState;
end;

procedure TPixieSvgCanvasRenderer.DoSetTransform(
  const M: TPixieSvgMatrix);
begin
  FCanvas.ConcatMatrix(M.A, M.B, M.C, M.D, M.E, M.F);
end;

procedure TPixieSvgCanvasRenderer.PopulateStops(Layer: TPixieGradientBase;
  const Grad: TPixieSvgGradient; Opacity: Single);
var
  I: Integer;
  Stop: TPixieSvgGradientStop;
  CP: TPixieColorPoint;
begin
  for I := 0 to Grad.Stops.Count - 1 do
  begin
    Stop := Grad.Stops[I];
    CP := TPixieColorPoint.Create(Stop.Offset, Stop.Color);
    CP.Color.Alpha := Round(CP.Color.Alpha * Opacity);
    Layer.ColorPoints.Add(CP);
  end;
end;

// ===========================================================================
// Gradient fill via clip-then-fill
// ===========================================================================

procedure TPixieSvgCanvasRenderer.FillWithGradient(
  const State: TPixieSvgState; FillRule: TPixieFillRule);
var
  Grad: TPixieSvgGradient;
  GradLayer: TPixieLinearGradientLayer;
  RadLayer: TPixieRadialGradientLayer;
  BX, BY, BW, BH: Single;
  GX1, GY1, GX2, GY2: Single;
  GCX, GCY, GRX, GRY: Single;
  M: TPixieSvgMatrix;
  HasTransform: Boolean;

  procedure TransformPt(var X, Y: Single);
  var
    TX, TY: Single;
  begin
    TX := M.A * X + M.C * Y + M.E;
    TY := M.B * X + M.D * Y + M.F;
    X := TX; Y := TY;
  end;

begin
  if State.FillGradientId = '' then Exit;
  Grad := ResolveGradientStops(State.FillGradientId);
  if (Grad = nil) or (Grad.Stops.Count < 2) then Exit;

  if not FBBoxValid then Exit;
  BX := FBBoxMinX;
  BY := FBBoxMinY;
  BW := FBBoxMaxX - FBBoxMinX;
  BH := FBBoxMaxY - FBBoxMinY;
  if (BW < 0.001) or (BH < 0.001) then Exit;

  // Parse gradientTransform
  HasTransform := Grad.GradientTransform <> '';
  if HasTransform then
    M := ParseTransform(Grad.GradientTransform);

  if not Grad.IsRadial then
  begin
    // Linear gradient — fill path directly with gradient brush
    GradLayer := TPixieLinearGradientLayer.Create;
    try
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
        TransformPt(GX1, GY1);
        TransformPt(GX2, GY2);
      end;

      GradLayer.StartPt := TPixiePointF.Create(GX1, GY1);
      GradLayer.EndPt := TPixiePointF.Create(GX2, GY2);
      PopulateStops(GradLayer, Grad, State.FillOpacity);
      FCanvas.FillPathLinearGradient(GradLayer, FillRule);
    finally
      GradLayer.Free;
    end;
  end
  else
  begin
    // Radial gradient
    RadLayer := TPixieRadialGradientLayer.Create;
    try
      if Grad.UserSpaceUnits then
      begin
        GCX := Grad.CX; GCY := Grad.CY;
        GRX := Grad.R; GRY := Grad.R;
      end
      else
      begin
        GCX := BX + Grad.CX * BW; GCY := BY + Grad.CY * BH;
        GRX := Grad.R * BW; GRY := Grad.R * BH;
      end;

      // Apply gradientTransform: transform center and compute
      // elliptical radii from the axis vectors
      if HasTransform then
      begin
        TransformPt(GCX, GCY);
        GRX := GRX * Sqrt(M.A * M.A + M.B * M.B);
        GRY := GRY * Sqrt(M.C * M.C + M.D * M.D);
      end;

      RadLayer.Position := TPixiePointF.Create(GCX, GCY);
      RadLayer.Radius := TPixiePointF.Create(GRX, GRY);
      PopulateStops(RadLayer, Grad, State.FillOpacity);
      FCanvas.FillPathRadialGradient(RadLayer, FillRule);
    finally
      RadLayer.Free;
    end;
  end;
end;

procedure TPixieSvgCanvasRenderer.StrokeWithGradient(
  const State: TPixieSvgState);
var
  Grad: TPixieSvgGradient;
  GradLayer: TPixieLinearGradientLayer;
  RadLayer: TPixieRadialGradientLayer;
  BX, BY, BW, BH: Single;
  GX1, GY1, GX2, GY2: Single;
  GCX, GCY, GRX, GRY: Single;
  M: TPixieSvgMatrix;
  HasTransform: Boolean;

  procedure TransformPt(var X, Y: Single);
  var
    TX, TY: Single;
  begin
    TX := M.A * X + M.C * Y + M.E;
    TY := M.B * X + M.D * Y + M.F;
    X := TX; Y := TY;
  end;

begin
  if State.StrokeGradientId = '' then Exit;
  Grad := ResolveGradientStops(State.StrokeGradientId);
  if (Grad = nil) or (Grad.Stops.Count < 2) then Exit;

  if not FBBoxValid then Exit;
  BX := FBBoxMinX;
  BY := FBBoxMinY;
  BW := FBBoxMaxX - FBBoxMinX;
  BH := FBBoxMaxY - FBBoxMinY;
  if (BW < 0.001) or (BH < 0.001) then Exit;

  HasTransform := Grad.GradientTransform <> '';
  if HasTransform then
    M := ParseTransform(Grad.GradientTransform);

  if not Grad.IsRadial then
  begin
    GradLayer := TPixieLinearGradientLayer.Create;
    try
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
        TransformPt(GX1, GY1);
        TransformPt(GX2, GY2);
      end;
      GradLayer.StartPt := TPixiePointF.Create(GX1, GY1);
      GradLayer.EndPt := TPixiePointF.Create(GX2, GY2);
      PopulateStops(GradLayer, Grad, State.StrokeOpacity);
      FCanvas.StrokePathLinearGradient(GradLayer, State.StrokeWidth);
    finally
      GradLayer.Free;
    end;
  end
  else
  begin
    RadLayer := TPixieRadialGradientLayer.Create;
    try
      if Grad.UserSpaceUnits then
      begin
        GCX := Grad.CX; GCY := Grad.CY;
        GRX := Grad.R; GRY := Grad.R;
      end
      else
      begin
        GCX := BX + Grad.CX * BW; GCY := BY + Grad.CY * BH;
        GRX := Grad.R * BW; GRY := Grad.R * BH;
      end;
      if HasTransform then
      begin
        TransformPt(GCX, GCY);
        GRX := GRX * Sqrt(M.A * M.A + M.B * M.B);
        GRY := GRY * Sqrt(M.C * M.C + M.D * M.D);
      end;
      RadLayer.Position := TPixiePointF.Create(GCX, GCY);
      RadLayer.Radius := TPixiePointF.Create(GRX, GRY);
      PopulateStops(RadLayer, Grad, State.StrokeOpacity);
      FCanvas.StrokePathRadialGradient(RadLayer, State.StrokeWidth);
    finally
      RadLayer.Free;
    end;
  end;
end;

procedure TPixieSvgCanvasRenderer.RebuildAndStroke(
  const State: TPixieSvgState);
var
  I: Integer;
  Entry: TPathEntry;
  SC: TPixieWebColor;
begin
  for I := 0 to FPathRecord.Count - 1 do
  begin
    Entry := FPathRecord[I];
    case Entry.Op of
      poMoveTo: FCanvas.MoveTo(Entry.X, Entry.Y);
      poLineTo: FCanvas.LineTo(Entry.X, Entry.Y);
      poCurveTo: FCanvas.CurveTo(Entry.X, Entry.Y,
                   Entry.X2, Entry.Y2, Entry.X3, Entry.Y3);
      poClosePath: FCanvas.ClosePath;
    end;
  end;
  SC := State.StrokeColor;
  SC.Alpha := Round(SC.Alpha * State.StrokeOpacity);
  FCanvas.StrokePath(SC, State.StrokeWidth);
end;

procedure TPixieSvgCanvasRenderer.RebuildAndStrokeGradient(
  const State: TPixieSvgState);
var
  I: Integer;
  Entry: TPathEntry;
begin
  for I := 0 to FPathRecord.Count - 1 do
  begin
    Entry := FPathRecord[I];
    case Entry.Op of
      poMoveTo: FCanvas.MoveTo(Entry.X, Entry.Y);
      poLineTo: FCanvas.LineTo(Entry.X, Entry.Y);
      poCurveTo: FCanvas.CurveTo(Entry.X, Entry.Y,
                   Entry.X2, Entry.Y2, Entry.X3, Entry.Y3);
      poClosePath: FCanvas.ClosePath;
    end;
  end;
  StrokeWithGradient(State);
end;

// ===========================================================================
// Fill and stroke
// ===========================================================================

procedure TPixieSvgCanvasRenderer.DoFillAndStroke(
  const State: TPixieSvgState);
var
  FC, SC: TPixieWebColor;
  HasGradientFill, HasGradientStroke: Boolean;
  FR: TPixieFillRule;
begin
  HasGradientFill := State.FillGradientId <> '';
  HasGradientStroke := State.HasStroke and (State.StrokeGradientId <> '');
  if State.EvenOddFill then
    FR := frEvenOdd
  else
    FR := frNonZero;

  if HasGradientFill and IsPatternFill(State.FillGradientId) then
  begin
    FillWithPattern(State, FR);
    if State.HasStroke then
    begin
      if HasGradientStroke then
        RebuildAndStrokeGradient(State)
      else
        RebuildAndStroke(State);
    end;
  end
  else if HasGradientFill then
  begin
    FillWithGradient(State, FR);
    if State.HasStroke then
    begin
      if HasGradientStroke then
        RebuildAndStrokeGradient(State)
      else
        RebuildAndStroke(State);
    end;
  end
  else if State.HasFill then
  begin
    FC := State.FillColor;
    FC.Alpha := Round(FC.Alpha * State.FillOpacity);
    if State.HasStroke and not HasGradientStroke then
    begin
      SC := State.StrokeColor;
      SC.Alpha := Round(SC.Alpha * State.StrokeOpacity);
      FCanvas.FillAndStrokePath(FC, SC, State.StrokeWidth, FR);
    end
    else
    begin
      FCanvas.FillPath(FC, FR);
      if HasGradientStroke then
        RebuildAndStrokeGradient(State);
    end;
  end
  else if HasGradientStroke then
    StrokeWithGradient(State)
  else if State.HasStroke then
  begin
    SC := State.StrokeColor;
    SC.Alpha := Round(SC.Alpha * State.StrokeOpacity);
    FCanvas.StrokePath(SC, State.StrokeWidth);
  end
  else
    FCanvas.DiscardPath;

  ResetBBox;
  FPathRecord.Clear;
end;

// ===========================================================================
// Opacity
// ===========================================================================

procedure TPixieSvgCanvasRenderer.DoBeginOpacity(Opacity: Single);
begin
  FCanvas.PushOpacity(Opacity);
end;

procedure TPixieSvgCanvasRenderer.DoEndOpacity;
begin
  FCanvas.PopOpacity;
end;

procedure TPixieSvgCanvasRenderer.DoClipPath;
begin
  FCanvas.ClipPath;
end;

// ===========================================================================
// Text
// ===========================================================================

procedure TPixieSvgCanvasRenderer.DoDrawText(const Text: string;
  X, Y: Single; const State: TPixieSvgState);
var
  Desc: TPixieFontDescription;
  TextW: TPixiePixel;
  FC: TPixieWebColor;
begin
  // Create or reuse cached font
  if (FFontHandle = 0) or (FFontFamily <> State.FontFamily) or
     (Abs(FFontSize - State.FontSize) > 0.01) or
     (FFontWeight <> State.FontWeight) then
  begin
    if FFontHandle <> 0 then
      FCanvas.DeleteFont(FFontHandle);
    Desc.Init;
    Desc.Family := State.FontFamily;
    Desc.Size := State.FontSize;
    Desc.Weight := State.FontWeight;
    FFontHandle := FCanvas.CreateFont(Desc, FFontMetrics);
    FFontFamily := State.FontFamily;
    FFontSize := State.FontSize;
    FFontWeight := State.FontWeight;
  end;

  if FFontHandle = 0 then Exit;

  TextW := FCanvas.MeasureText(Text, FFontHandle);

  // Apply text-anchor using real measured width
  if State.TextAnchor = taCenter then
    X := X - TextW * 0.5
  else if State.TextAnchor = taRight then
    X := X - TextW;

  FC := State.FillColor;
  if State.HasFill then
    FC.Alpha := Round(FC.Alpha * State.FillOpacity);

  // SVG text Y is baseline; DrawText expects top-left Y
  FCanvas.DrawText(Text, FFontHandle, FC,
    X, Y - FFontMetrics.Ascent, TextW + 10, FFontMetrics.Height);
end;

// ===========================================================================
// Image support
// ===========================================================================

procedure TPixieSvgCanvasRenderer.FreeImageCache;
var
  Handle: TPixieImageHandle;
begin
  if FImageCache <> nil then
  begin
    if FCanvas <> nil then
      for Handle in FImageCache.Values do
        FCanvas.FreeImage(Handle);
    FreeAndNil(FImageCache);
  end;
end;

function TPixieSvgCanvasRenderer.LoadImageFromHref(
  const Href: string): TPixieImageHandle;
var
  CacheKey: string;
  DataStream: TMemoryStream;
{$IFDEF FPC}
  Img: TFPMemoryImage;
  Pixels: PByte;
  Pitch, W, H: Integer;
{$ENDIF}
begin
  Result := 0;
  if FCanvas = nil then Exit;

  // Use a short key for data: URIs to avoid hashing megabytes of base64
  if (Length(Href) > 256) and (Pos('data:', Href) = 1) then
    CacheKey := 'data:' + IntToStr(Length(Href)) + ':' +
      Copy(Href, Length(Href) - 31, 32)
  else
    CacheKey := Href;

  // Check cache
  if FImageCache <> nil then
    if FImageCache.TryGetValue(CacheKey, Result) then Exit;

  // Decode data: URI
  if Pos('data:', Href) = 1 then
  begin
    if not DecodeDataUri(Href, DataStream) then Exit;
    try
      // Try canvas-native stream loading (D2D/WIC, FMX)
      Result := FCanvas.LoadImageFromStream(DataStream);
    {$IFDEF FPC}
      // FPC backends: FPImage fallback for Cairo/CG/Qt
      if Result = 0 then
      begin
        Img := TFPMemoryImage.Create(0, 0);
        try
          try
            DataStream.Position := 0;
            Img.LoadFromStream(DataStream);
          except
            Exit;
          end;
          ConvertFPImageToBGRA(Img, Pixels, W, H, Pitch);
          if Pixels <> nil then
          try
            Result := FCanvas.LoadImageFromPixels(W, H, Pixels, Pitch);
          finally
            FreeMem(Pixels);
          end;
        finally
          Img.Free;
        end;
      end;
    {$ENDIF}
    finally
      DataStream.Free;
    end;
  end
  else
    // File path
    Result := FCanvas.LoadImage(Href);

  // Cache the loaded handle
  if Result <> 0 then
  begin
    if FImageCache = nil then
      FImageCache := TDictionary<string, TPixieImageHandle>.Create;
    FImageCache.Add(CacheKey, Result);
  end;
end;

procedure TPixieSvgCanvasRenderer.DoDrawImage(const Href: string;
  X, Y, W, H: Single);
var
  Handle: TPixieImageHandle;
begin
  Handle := LoadImageFromHref(Href);
  if Handle = 0 then Exit;
  FCanvas.DrawImage(Handle, X, Y, W, H);
end;

procedure TPixieSvgCanvasRenderer.DoClearImages;
begin
  FreeImageCache;
end;

// ===========================================================================
// Pattern fill
// ===========================================================================

function TPixieSvgCanvasRenderer.IsPatternFill(const Id: string): Boolean;
var
  El: Pointer;
begin
  Result := False;
  if (FIdMap = nil) or (Id = '') then Exit;
  if not FIdMap.TryGetValue(Id, El) then Exit;
  Result := LowerCase(DomToStr(TDOMElement(El).TagName)) = 'pattern';
end;

procedure TPixieSvgCanvasRenderer.FillWithPattern(
  const State: TPixieSvgState; FillRule: TPixieFillRule);
var
  PatternEl, Child, Target: Pointer;
  ChildTag, HrefStr, ImgHref: string;
  Handle: TPixieImageHandle;
  BX, BY, BW, BH: Single;
  Depth: Integer;
begin
  if (FIdMap = nil) or (State.FillGradientId = '') then Exit;
  if not FIdMap.TryGetValue(State.FillGradientId, PatternEl) then Exit;

  // Resolve pattern content to an image href.
  // Walk children: look for <image> directly, or <use> -> <image>.
  ImgHref := '';
  Child := TDOMNode(PatternEl).FirstChild;
  while Child <> nil do
  begin
    if TDOMNode(Child).NodeType = ELEMENT_NODE then
    begin
      ChildTag := LowerCase(DomToStr(TDOMElement(Child).TagName));
      if ChildTag = 'image' then
      begin
        ImgHref := GetAttr(Child, 'xlink:href');
        if ImgHref = '' then
          ImgHref := GetAttr(Child, 'href');
        Break;
      end
      else if ChildTag = 'use' then
      begin
        // Resolve <use> chain to find <image> (depth-limited)
        HrefStr := GetAttr(Child, 'xlink:href');
        if HrefStr = '' then
          HrefStr := GetAttr(Child, 'href');
        Depth := 0;
        while (HrefStr <> '') and (HrefStr[1] = '#') and (Depth < 10) do
        begin
          if not FIdMap.TryGetValue(Copy(HrefStr, 2, MaxInt), Target) then
            Break;
          if LowerCase(DomToStr(TDOMElement(Target).TagName)) = 'image' then
          begin
            ImgHref := GetAttr(Target, 'xlink:href');
            if ImgHref = '' then
              ImgHref := GetAttr(Target, 'href');
            Break;
          end;
          // Follow another <use>
          HrefStr := GetAttr(Target, 'xlink:href');
          if HrefStr = '' then
            HrefStr := GetAttr(Target, 'href');
          Inc(Depth);
        end;
        if ImgHref <> '' then Break;
      end;
    end;
    Child := TDOMNode(Child).NextSibling;
  end;

  if ImgHref = '' then
  begin
    FCanvas.DiscardPath;
    ResetBBox;
    FPathRecord.Clear;
    Exit;
  end;

  Handle := LoadImageFromHref(ImgHref);
  if Handle = 0 then
  begin
    FCanvas.DiscardPath;
    ResetBBox;
    FPathRecord.Clear;
    Exit;
  end;

  // Clip to current path, then draw image stretched to bounding box
  FCanvas.ClipPath(FillRule);

  if FBBoxValid then
  begin
    BX := FBBoxMinX;
    BY := FBBoxMinY;
    BW := FBBoxMaxX - FBBoxMinX;
    BH := FBBoxMaxY - FBBoxMinY;
  end
  else
  begin
    BX := 0; BY := 0; BW := 0; BH := 0;
  end;

  if (BW > 0) and (BH > 0) then
    FCanvas.DrawImage(Handle, BX, BY, BW, BH);

  ResetBBox;
  FPathRecord.Clear;
end;

// ===========================================================================
// Public API
// ===========================================================================

procedure TPixieSvgCanvasRenderer.RenderToRect(
  DstX, DstY, DstW, DstH: Single);
var
  Sx, Sy, Scale, OffX, OffY: Single;
  ClipPos: TPixiePosition;
  ClipRadius: TPixieBorderRadiuses;
begin
  FCanvas.SaveState;
  try
    // Translate to destination position
    FCanvas.ConcatMatrix(1, 0, 0, 1, DstX, DstY);

    // Scale from viewBox to destination size, preserving aspect ratio
    if (FViewBoxW > 0.01) and (FViewBoxH > 0.01) then
    begin
      Sx := DstW / FViewBoxW;
      Sy := DstH / FViewBoxH;
      Scale := Min(Sx, Sy);
      // Centre within the destination rect
      OffX := (DstW - FViewBoxW * Scale) * 0.5;
      OffY := (DstH - FViewBoxH * Scale) * 0.5;
      if (Abs(OffX) > 0.01) or (Abs(OffY) > 0.01) then
        FCanvas.ConcatMatrix(1, 0, 0, 1, OffX, OffY);
      FCanvas.ConcatMatrix(Scale, 0, 0, Scale, 0, 0);

      // Clip to viewBox (SVG default overflow=hidden).
      // Use (0,0) origin because the viewBox offset translation is applied after.
      ClipPos := TPixiePosition.Create(0, 0, FViewBoxW, FViewBoxH);
      ClipRadius.Init;
      FCanvas.SetClipRect(ClipPos, ClipRadius);
    end;

    // Apply viewBox offset
    if (Abs(FViewBoxX) > 0.01) or (Abs(FViewBoxY) > 0.01) then
      FCanvas.ConcatMatrix(1, 0, 0, 1, -FViewBoxX, -FViewBoxY);

    RenderDocument;
  finally
    FCanvas.RestoreState;
  end;
end;

end.
