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
    FFontItalic: Boolean;

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
    function DoMeasureTextRun(const Text: string;
      const State: TPixieSvgState): Single; override;
    procedure DoDrawImage(const Href: string;
      X, Y, W, H: Single); override;
    procedure DoClearImages; override;
  private
    procedure EnsureFont(const State: TPixieSvgState);
  public
    constructor Create(ACanvas: TPixieCanvas);
    destructor Destroy; override;
    procedure ClearDocument; override;

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
  if (FFontHandle <> 0) and (FCanvas <> nil) then
    FCanvas.DeleteFont(FFontHandle);
  // Inherited Destroy runs ClearDocument, which now virtually dispatches
  // to our override and touches FPathRecord — so free the record AFTER.
  inherited;
  FPathRecord.Free;
end;

procedure TPixieSvgCanvasRenderer.ClearDocument;
begin
  inherited;
  // Reset per-shape state in case the renderer is reused to parse a new
  // SVG (as TPixieSvgView does). Any leftover entries would pollute the
  // first shape's stroke rebuild in the new document.
  FPathRecord.Clear;
  ResetBBox;
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
  HasGradientFill, HasGradientStroke, SkipFill, BlendSet: Boolean;
  FR: TPixieFillRule;
begin
  // Set line cap/join and dash style for this stroke operation
  if State.HasStroke then
  begin
    FCanvas.SetPathStrokeStyle(State.LineCap, State.LineJoin);
    if Length(State.DashArray) > 0 then
      FCanvas.SetPathDashStyle(State.DashArray, State.DashOffset);
  end;

  SkipFill := False;
  BlendSet := False;
  if State.BlendMode <> bmNormal then
  begin
    BlendSet := FCanvas.SetBlendMode(State.BlendMode);
    if not BlendSet then
      SkipFill := True;
  end;

  HasGradientFill := (State.FillGradientId <> '') and not SkipFill;
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
  else if State.HasFill and not SkipFill then
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

  if BlendSet then
    FCanvas.ResetBlendMode;

  // Reset stroke style to defaults
  FCanvas.SetPathStrokeStyle(lcButt, ljMiter);
  FCanvas.ClearPathDashStyle;

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
  // The clip path's geometry belonged to the clip, not to the shape that
  // will emit its own path next. Reset so the subsequent stroke rebuild
  // (for pattern/gradient fills) sees only the shape's own geometry.
  FPathRecord.Clear;
  ResetBBox;
end;

// ===========================================================================
// Text
// ===========================================================================

procedure TPixieSvgCanvasRenderer.EnsureFont(const State: TPixieSvgState);
var
  Desc: TPixieFontDescription;
begin
  if (FFontHandle <> 0) and (FFontFamily = State.FontFamily) and
     (Abs(FFontSize - State.FontSize) <= 0.01) and
     (FFontWeight = State.FontWeight) and
     (FFontItalic = State.FontItalic) then Exit;

  if FFontHandle <> 0 then
    FCanvas.DeleteFont(FFontHandle);
  Desc.Init;
  Desc.Family := State.FontFamily;
  Desc.Size := State.FontSize;
  Desc.Weight := State.FontWeight;
  if State.FontItalic then
    Desc.Style := fstItalic;
  FFontHandle := FCanvas.CreateFont(Desc, FFontMetrics);
  FFontFamily := State.FontFamily;
  FFontSize := State.FontSize;
  FFontWeight := State.FontWeight;
  FFontItalic := State.FontItalic;
end;

function TPixieSvgCanvasRenderer.DoMeasureTextRun(const Text: string;
  const State: TPixieSvgState): Single;
begin
  EnsureFont(State);
  if FFontHandle = 0 then
    Result := 0
  else
    Result := FCanvas.MeasureText(Text, FFontHandle);
end;

procedure TPixieSvgCanvasRenderer.DoDrawText(const Text: string;
  X, Y: Single; const State: TPixieSvgState);
var
  TextW: TPixiePixel;
  FC: TPixieWebColor;
begin
  EnsureFont(State);
  if FFontHandle = 0 then Exit;

  TextW := FCanvas.MeasureText(Text, FFontHandle);

  // Note: text-anchor offset is applied once per anchored chunk by the base
  // class (RenderTextChunk), not per text run.

  FC := State.FillColor;
  if State.HasFill then
    FC.Alpha := Round(FC.Alpha * State.FillOpacity);

  // SVG Y is the baseline. DrawTextAtBaseline pins the layout baseline to
  // Ascent, so mixed-font runs on the same line share a baseline (DWrite's
  // default line spacing offsets by lineGap).
  FCanvas.DrawTextAtBaseline(Text, FFontHandle, FFontMetrics, FC, X, Y);

  // Draw text-decoration lines
  if State.TextDecoration <> TextDecorationLineNone then
  begin
    if (State.TextDecoration and TextDecorationLineUnderline) <> 0 then
      FCanvas.DrawLine(X, Y + State.FontSize * SvgDecorationUnderlineOffset,
        X + TextW, Y + State.FontSize * SvgDecorationUnderlineOffset,
        FC, State.FontSize * SvgDecorationThickness);
    if (State.TextDecoration and TextDecorationLineOverline) <> 0 then
      FCanvas.DrawLine(X, Y - FFontMetrics.Ascent, X + TextW,
        Y - FFontMetrics.Ascent, FC, State.FontSize * SvgDecorationThickness);
    if (State.TextDecoration and TextDecorationLineLineThrough) <> 0 then
      FCanvas.DrawLine(X, Y - FFontMetrics.XHeight / 2, X + TextW,
        Y - FFontMetrics.XHeight / 2, FC, State.FontSize * SvgDecorationThickness);
  end;
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

// Preconditions: caller (DoFillAndStroke) owns FPathRecord and FBBox* —
// this routine must not clear them, so the subsequent stroke rebuild still
// sees the path. On any failure we only discard the canvas path.
procedure TPixieSvgCanvasRenderer.FillWithPattern(
  const State: TPixieSvgState; FillRule: TPixieFillRule);
const
  Eps = 0.001;
  MaxTiles = 100000;
var
  Info: TPixieSvgPatternInfo;
  Handle: TPixieImageHandle;
  BX, BY, BW, BH: Single;
  TileX, TileY, TileW, TileH: Single;
  ImgDrawX, ImgDrawY, ImgDrawW, ImgDrawH: Single;
  ScaleX, ScaleY: Single;
  NeedOpacity, ImageFillsTile: Boolean;
  StartCol, EndCol, StartRow, EndRow, Col, Row: Integer;
begin
  if not GetPatternInfo(State.FillGradientId, Info) or not FBBoxValid then
  begin
    FCanvas.DiscardPath;
    Exit;
  end;

  Handle := LoadImageFromHref(Info.ImageHref);
  if Handle = 0 then
  begin
    FCanvas.DiscardPath;
    Exit;
  end;

  BX := FBBoxMinX;
  BY := FBBoxMinY;
  BW := FBBoxMaxX - FBBoxMinX;
  BH := FBBoxMaxY - FBBoxMinY;
  if (BW <= 0) or (BH <= 0) then
  begin
    FCanvas.DiscardPath;
    Exit;
  end;

  // Tile rectangle in user space per patternUnits. GetPatternInfo
  // guarantees Info.Width/Height > 0, and we've verified BW/BH > 0, so
  // TileW/TileH are positive in both branches.
  if Info.PatternUnitsUserSpace then
  begin
    TileX := Info.X;
    TileY := Info.Y;
    TileW := Info.Width;
    TileH := Info.Height;
  end
  else
  begin
    TileX := BX + Info.X * BW;
    TileY := BY + Info.Y * BH;
    TileW := Info.Width * BW;
    TileH := Info.Height * BH;
  end;

  // Image destination rect within a single tile.
  if Info.HasViewBox then
  begin
    ScaleX := TileW / Info.ViewBoxW;
    ScaleY := TileH / Info.ViewBoxH;
    ImgDrawX := (Info.ImgX - Info.ViewBoxX) * ScaleX;
    ImgDrawY := (Info.ImgY - Info.ViewBoxY) * ScaleY;
    ImgDrawW := Info.ImgW * ScaleX;
    ImgDrawH := Info.ImgH * ScaleY;
  end
  else if Info.ContentUnitsObjectBBox then
  begin
    ImgDrawX := Info.ImgX * TileW;
    ImgDrawY := Info.ImgY * TileH;
    ImgDrawW := Info.ImgW * TileW;
    ImgDrawH := Info.ImgH * TileH;
  end
  else
  begin
    ImgDrawX := Info.ImgX;
    ImgDrawY := Info.ImgY;
    ImgDrawW := Info.ImgW;
    ImgDrawH := Info.ImgH;
  end;

  // Zero-sized image child — treat it as filling the whole tile
  if (ImgDrawW <= 0) or (ImgDrawH <= 0) then
  begin
    ImgDrawX := 0;
    ImgDrawY := 0;
    ImgDrawW := TileW;
    ImgDrawH := TileH;
  end;

  NeedOpacity := State.FillOpacity < 1.0;

  // SaveState wraps ClipPath so the mask layer is released before the
  // subsequent stroke rebuild runs outside this routine.
  FCanvas.SaveState;
  try
    FCanvas.ClipPath(FillRule);

    if NeedOpacity then
      FCanvas.PushOpacity(State.FillOpacity);

    // Fast path: image exactly fills the tile — use the canvas's native
    // tiling primitive (D2D bitmap brush, Cairo CAIRO_EXTEND_REPEAT, etc.).
    ImageFillsTile :=
      (Abs(ImgDrawX) < Eps) and (Abs(ImgDrawY) < Eps) and
      (Abs(ImgDrawW - TileW) < Eps) and (Abs(ImgDrawH - TileH) < Eps);

    if ImageFillsTile then
      FCanvas.FillTiledImage(Handle, TileX, TileY, TileW, TileH,
        BX, BY, BW, BH)
    else
    begin
      // Inset image within tile: manual loop so the repeat period stays
      // TileW×TileH while the image draws only its own sub-rect.
      StartCol := Floor((BX - TileX) / TileW);
      EndCol := Ceil((BX + BW - TileX) / TileW) - 1;
      StartRow := Floor((BY - TileY) / TileH);
      EndRow := Ceil((BY + BH - TileY) / TileH) - 1;
      if Int64(EndCol - StartCol + 1) *
         Int64(EndRow - StartRow + 1) <= MaxTiles then
        for Row := StartRow to EndRow do
          for Col := StartCol to EndCol do
            FCanvas.DrawImage(Handle,
              TileX + Col * TileW + ImgDrawX,
              TileY + Row * TileH + ImgDrawY,
              ImgDrawW, ImgDrawH);
    end;

    if NeedOpacity then
      FCanvas.PopOpacity;
  finally
    FCanvas.RestoreState;
  end;
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

      // Clip to viewBox unless overflow is visible (e.g. no explicit size)
      if not FOverflowVisible then
      begin
        ClipPos := TPixiePosition.Create(0, 0, FViewBoxW, FViewBoxH);
        ClipRadius.Init;
        FCanvas.SetClipRect(ClipPos, ClipRadius);
      end;
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
