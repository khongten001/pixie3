unit Pixie.Canvas.FMX;

// FMX (FireMonkey) implementation of TPixieCanvas for cross-platform Delphi.
// Uses FMX.Graphics for 2D drawing and Pixie.FontMetrics for font metrics
// (FMX has no public ascent/descent API).

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Types, System.UITypes,
  System.UIConsts, System.Generics.Collections, System.Math.Vectors,
  FMX.Graphics, FMX.Types, FMX.TextLayout,
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.Background, Pixie.FontDescription,
  Pixie.Canvas, Pixie.FontMetrics, Pixie.SvgRenderer.FMX;

type
  { TPixieFmxFont — font instance with FMX font + metrics }

  TPixieFmxFont = class
  public
    FmxFont: TFont;
    Metrics: TPixieFontMetrics;
    DecorationLine: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  { TPixieFmxImage — image instance backed by FMX TBitmap }

  TPixieFmxImage = class
  public
    Bitmap: TBitmap;
    ImgWidth: Integer;
    ImgHeight: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TPixieFmxFontList = TObjectList<TPixieFmxFont>;
  TPixieFmxImageList = TObjectList<TPixieFmxImage>;

  { TPixieFmxCanvas }

  TPixieFmxCanvas = class(TPixieCanvas)
  private
    FCanvas: TCanvas;
    FOpacity: Single;
    FOpacityStack: array[0..31] of Single;
    FOpacityTop: Integer;
    FScale: Single;
    FBrush: TBrush;
    FStrokeBrush: TStrokeBrush;
    FPath: TPathData;
    FTextLayout: TTextLayout;
    FStateStack: array[0..63] of TCanvasSaveState;
    FStateTop: Integer;
    FBaseState: TCanvasSaveState;

    function ToAlphaColor(const C: TPixieWebColor): TAlphaColor;
    function HasRadius(const R: TPixieBorderRadiuses): Boolean;
    procedure BuildRoundedRectPath(Path: TPathData; X, Y, W, H: Single;
      const R: TPixieBorderRadiuses);
    procedure SetupGradientStops(const Points: TPixieColorPointList);
    procedure DrawBorderSide(const Border: TPixieBorder;
      X1, Y1, X2, Y2: Single);
  public
    constructor Create;
    destructor Destroy; override;

    // Lifecycle
    procedure BeginPaint(DC: PtrUInt); override;
    procedure EndPaint; override;

    // State
    procedure SaveState; override;
    procedure RestoreState; override;
    procedure PushOpacity(AOpacity: Single); override;
    procedure PopOpacity; override;

    // Clipping
    procedure SetClipRect(const R: TPixiePosition;
      const Radius: TPixieBorderRadiuses); override;

    // Fills
    procedure FillRect(X, Y, W, H: Single;
      Color: TPixieWebColor); override;
    procedure FillRoundedRect(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      Color: TPixieWebColor); override;

    // Gradients
    procedure FillLinearGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieLinearGradientLayer); override;
    procedure FillRadialGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieRadialGradientLayer); override;
    procedure FillConicGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieConicGradientLayer); override;

    // Borders
    procedure DrawBorders(const Borders: TPixieBorders;
      const Pos: TPixiePosition; IsRoot: Boolean); override;

    // Fonts
    function CreateFont(const Descr: TPixieFontDescription;
      out Metrics: TPixieFontMetrics): TPixieFontHandle; override;
    procedure DeleteFont(Handle: TPixieFontHandle); override;

    // Text
    function MeasureText(const Text: string;
      Handle: TPixieFontHandle): TPixiePixel; override;
    procedure DrawText(const Text: string; Handle: TPixieFontHandle;
      Color: TPixieWebColor; X, Y, W, H: Single); override;

    // Units
    function PtToPx(Pt: Single): TPixiePixel; override;

    // Images
    function LoadImage(const Path: string): TPixieImageHandle; override;
    function LoadImageFromPixels(Width, Height: Integer;
      Pixels: Pointer; Pitch: Integer): TPixieImageHandle; override;
    function LoadImageFromStream(Stream: TStream): TPixieImageHandle; override;
    function LoadSvgFromData(Data: Pointer;
      Size: Integer): TPixieImageHandle; override;
    procedure FreeImage(Handle: TPixieImageHandle); override;
    procedure GetImageSize(Handle: TPixieImageHandle;
      out W, H: Single); override;
    procedure DrawImage(Handle: TPixieImageHandle;
      DstX, DstY, DstW, DstH: Single); override;

    // Simple shapes
    procedure FillEllipse(X, Y, W, H: Single;
      Color: TPixieWebColor); override;
    procedure DrawEllipse(X, Y, W, H: Single;
      Color: TPixieWebColor; StrokeWidth: Single); override;
    procedure DrawRect(X, Y, W, H: Single;
      Color: TPixieWebColor; StrokeWidth: Single); override;
    procedure DrawLine(X1, Y1, X2, Y2: Single;
      Color: TPixieWebColor; StrokeWidth: Single); override;
    procedure StrokePolyline(const Points: array of Single;
      Color: TPixieWebColor; StrokeWidth: Single); override;

    // View / scale
    procedure SetScale(Scale: Single); override;
  end;

implementation

const
  // Kappa constant for quarter-circle bezier approximation
  BezierKappa = 0.5522847498;

// ---------------------------------------------------------------------------
// Font check callback for PixieResolveFontFamily
// ---------------------------------------------------------------------------

function FmxCheckFont(const Name: string): Boolean;
var
  Entry: TPixieFontMetricsEntry;
begin
  Result := PixieLookupFontMetrics(Name, Entry);
end;

// ---------------------------------------------------------------------------
// TPixieFmxFont
// ---------------------------------------------------------------------------

constructor TPixieFmxFont.Create;
begin
  inherited Create;
  FmxFont := TFont.Create;
  DecorationLine := 0;
end;

destructor TPixieFmxFont.Destroy;
begin
  FmxFont.Free;
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// TPixieFmxImage
// ---------------------------------------------------------------------------

constructor TPixieFmxImage.Create;
begin
  inherited Create;
  Bitmap := nil;
  ImgWidth := 0;
  ImgHeight := 0;
end;

destructor TPixieFmxImage.Destroy;
begin
  Bitmap.Free;
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// TPixieFmxCanvas — Construction
// ---------------------------------------------------------------------------

constructor TPixieFmxCanvas.Create;
begin
  inherited Create;
  FCanvas := nil;
  FOpacity := 1.0;
  FOpacityTop := 0;
  FScale := 1.0;
  FStateTop := 0;
  FBaseState := nil;
  FBrush := TBrush.Create(TBrushKind.Solid, claBlack);
  FStrokeBrush := TStrokeBrush.Create(TBrushKind.Solid, claBlack);
  FPath := TPathData.Create;
  FTextLayout := TTextLayoutManager.DefaultTextLayout.Create;
end;

destructor TPixieFmxCanvas.Destroy;
begin
  FTextLayout.Free;
  FPath.Free;
  FStrokeBrush.Free;
  FBrush.Free;
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function TPixieFmxCanvas.ToAlphaColor(const C: TPixieWebColor): TAlphaColor;
var
  Rec: TAlphaColorRec;
begin
  Rec.R := C.Red;
  Rec.G := C.Green;
  Rec.B := C.Blue;
  Rec.A := C.Alpha;
  Result := Rec.Color;
end;

function TPixieFmxCanvas.HasRadius(const R: TPixieBorderRadiuses): Boolean;
begin
  Result := (R.TopLeftX > 0) or (R.TopLeftY > 0) or
            (R.TopRightX > 0) or (R.TopRightY > 0) or
            (R.BottomRightX > 0) or (R.BottomRightY > 0) or
            (R.BottomLeftX > 0) or (R.BottomLeftY > 0);
end;

procedure TPixieFmxCanvas.BuildRoundedRectPath(Path: TPathData;
  X, Y, W, H: Single; const R: TPixieBorderRadiuses);
const
  K = BezierKappa;
begin
  Path.Clear;

  // Start at top-left, after the top-left radius
  Path.MoveTo(PointF(X + R.TopLeftX, Y));

  // Top edge
  Path.LineTo(PointF(X + W - R.TopRightX, Y));

  // Top-right corner
  if (R.TopRightX > 0) and (R.TopRightY > 0) then
    Path.CurveTo(
      PointF(X + W - R.TopRightX * (1 - K), Y),
      PointF(X + W, Y + R.TopRightY * (1 - K)),
      PointF(X + W, Y + R.TopRightY))
  else
    Path.LineTo(PointF(X + W, Y));

  // Right edge
  Path.LineTo(PointF(X + W, Y + H - R.BottomRightY));

  // Bottom-right corner
  if (R.BottomRightX > 0) and (R.BottomRightY > 0) then
    Path.CurveTo(
      PointF(X + W, Y + H - R.BottomRightY * (1 - K)),
      PointF(X + W - R.BottomRightX * (1 - K), Y + H),
      PointF(X + W - R.BottomRightX, Y + H))
  else
    Path.LineTo(PointF(X + W, Y + H));

  // Bottom edge
  Path.LineTo(PointF(X + R.BottomLeftX, Y + H));

  // Bottom-left corner
  if (R.BottomLeftX > 0) and (R.BottomLeftY > 0) then
    Path.CurveTo(
      PointF(X + R.BottomLeftX * (1 - K), Y + H),
      PointF(X, Y + H - R.BottomLeftY * (1 - K)),
      PointF(X, Y + H - R.BottomLeftY))
  else
    Path.LineTo(PointF(X, Y + H));

  // Left edge
  Path.LineTo(PointF(X, Y + R.TopLeftY));

  // Top-left corner
  if (R.TopLeftX > 0) and (R.TopLeftY > 0) then
    Path.CurveTo(
      PointF(X, Y + R.TopLeftY * (1 - K)),
      PointF(X + R.TopLeftX * (1 - K), Y),
      PointF(X + R.TopLeftX, Y))
  else
    Path.LineTo(PointF(X, Y));

  Path.ClosePath;
end;

procedure TPixieFmxCanvas.SetupGradientStops(
  const Points: TPixieColorPointList);
var
  I: Integer;
  GradPt: TGradientPoint;
begin
  FBrush.Gradient.Points.Clear;
  for I := 0 to Points.Count - 1 do
  begin
    GradPt := TGradientPoint(FBrush.Gradient.Points.Add);
    GradPt.Offset := Points[I].Offset;
    GradPt.Color := ToAlphaColor(Points[I].Color);
  end;
end;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

procedure TPixieFmxCanvas.BeginPaint(DC: PtrUInt);
var
  M: TMatrix;
begin
  FCanvas := TCanvas(Pointer(DC));
  FOpacity := 1.0;
  FOpacityTop := 0;
  FStateTop := 0;

  if FScale <> 1.0 then
  begin
    FBaseState := FCanvas.SaveState;
    M := TMatrix.CreateScaling(FScale, FScale);
    FCanvas.MultiplyMatrix(M);
  end
  else
    FBaseState := nil;
end;

procedure TPixieFmxCanvas.EndPaint;
begin
  if FBaseState <> nil then
  begin
    FCanvas.RestoreState(FBaseState);
    FBaseState := nil;
  end;
  FCanvas := nil;
end;

// ---------------------------------------------------------------------------
// State save/restore
// ---------------------------------------------------------------------------

procedure TPixieFmxCanvas.SaveState;
begin
  if (FCanvas = nil) or (FStateTop > High(FStateStack)) then Exit;
  FStateStack[FStateTop] := FCanvas.SaveState;
  Inc(FStateTop);
end;

procedure TPixieFmxCanvas.RestoreState;
begin
  if (FCanvas = nil) or (FStateTop <= 0) then Exit;
  Dec(FStateTop);
  FCanvas.RestoreState(FStateStack[FStateTop]);
end;

procedure TPixieFmxCanvas.PushOpacity(AOpacity: Single);
begin
  if FOpacityTop >= Length(FOpacityStack) then Exit;
  FOpacityStack[FOpacityTop] := FOpacity;
  Inc(FOpacityTop);
  FOpacity := FOpacity * AOpacity;
end;

procedure TPixieFmxCanvas.PopOpacity;
begin
  if FOpacityTop <= 0 then Exit;
  Dec(FOpacityTop);
  FOpacity := FOpacityStack[FOpacityTop];
end;

// ---------------------------------------------------------------------------
// Clipping
// ---------------------------------------------------------------------------

procedure TPixieFmxCanvas.SetClipRect(const R: TPixiePosition;
  const Radius: TPixieBorderRadiuses);
begin
  if FCanvas = nil then Exit;
  FCanvas.IntersectClipRect(TRectF.Create(R.X, R.Y, R.X + R.Width,
    R.Y + R.Height));
end;

// ---------------------------------------------------------------------------
// Solid fills
// ---------------------------------------------------------------------------

procedure TPixieFmxCanvas.FillRect(X, Y, W, H: Single;
  Color: TPixieWebColor);
begin
  if (FCanvas = nil) or (Color.Alpha = 0) then Exit;
  FBrush.Kind := TBrushKind.Solid;
  FBrush.Color := ToAlphaColor(Color);
  FCanvas.FillRect(TRectF.Create(X, Y, X + W, Y + H), 0, 0, AllCorners,
    FOpacity, FBrush);
end;

procedure TPixieFmxCanvas.FillRoundedRect(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses; Color: TPixieWebColor);
begin
  if (FCanvas = nil) or (Color.Alpha = 0) then Exit;
  FBrush.Kind := TBrushKind.Solid;
  FBrush.Color := ToAlphaColor(Color);

  if HasRadius(Radius) then
  begin
    BuildRoundedRectPath(FPath, X, Y, W, H, Radius);
    FCanvas.FillPath(FPath, FOpacity, FBrush);
  end
  else
    FCanvas.FillRect(TRectF.Create(X, Y, X + W, Y + H), 0, 0, AllCorners,
      FOpacity, FBrush);
end;

// ---------------------------------------------------------------------------
// Gradients
// ---------------------------------------------------------------------------

procedure TPixieFmxCanvas.FillLinearGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieLinearGradientLayer);
var
  R: TRectF;
  BX1, BY1, BX2, BY2, BW, BH: Single;
begin
  if (FCanvas = nil) or (Gradient = nil) then Exit;
  if Gradient.ColorPoints.Count < 2 then Exit;

  // Bounding rect covering fill area and gradient line
  BX1 := Min(X, Min(Gradient.StartPt.X, Gradient.EndPt.X));
  BY1 := Min(Y, Min(Gradient.StartPt.Y, Gradient.EndPt.Y));
  BX2 := Max(X + W, Max(Gradient.StartPt.X, Gradient.EndPt.X));
  BY2 := Max(Y + H, Max(Gradient.StartPt.Y, Gradient.EndPt.Y));
  BW := BX2 - BX1;
  BH := BY2 - BY1;
  if (BW <= 0) or (BH <= 0) then Exit;

  FBrush.Kind := TBrushKind.Gradient;
  FBrush.Gradient.Style := TGradientStyle.Linear;
  FBrush.Gradient.StartPosition.X := (Gradient.StartPt.X - BX1) / BW;
  FBrush.Gradient.StartPosition.Y := (Gradient.StartPt.Y - BY1) / BH;
  FBrush.Gradient.StopPosition.X := (Gradient.EndPt.X - BX1) / BW;
  FBrush.Gradient.StopPosition.Y := (Gradient.EndPt.Y - BY1) / BH;
  SetupGradientStops(Gradient.ColorPoints);

  SaveState;
  try
    if HasRadius(Radius) then
    begin
      FCanvas.IntersectClipRect(TRectF.Create(X, Y, X + W, Y + H));
      BuildRoundedRectPath(FPath, X, Y, W, H, Radius);
      FCanvas.FillPath(FPath, FOpacity, FBrush);
    end
    else
    begin
      FCanvas.IntersectClipRect(TRectF.Create(X, Y, X + W, Y + H));
      R := TRectF.Create(BX1, BY1, BX2, BY2);
      FCanvas.FillRect(R, 0, 0, AllCorners, FOpacity, FBrush);
    end;
  finally
    RestoreState;
  end;
end;

procedure TPixieFmxCanvas.FillRadialGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieRadialGradientLayer);
var
  R: TRectF;
  GradRect: TRectF;
begin
  if (FCanvas = nil) or (Gradient = nil) then Exit;
  if Gradient.ColorPoints.Count < 2 then Exit;

  FBrush.Kind := TBrushKind.Gradient;
  FBrush.Gradient.Style := TGradientStyle.Radial;
  SetupGradientStops(Gradient.ColorPoints);

  // FMX radial gradient fills an ellipse inscribed in the bounding rect
  GradRect := TRectF.Create(
    Gradient.Position.X - Gradient.Radius.X,
    Gradient.Position.Y - Gradient.Radius.Y,
    Gradient.Position.X + Gradient.Radius.X,
    Gradient.Position.Y + Gradient.Radius.Y);

  SaveState;
  try
    if HasRadius(Radius) then
    begin
      FCanvas.IntersectClipRect(TRectF.Create(X, Y, X + W, Y + H));
      BuildRoundedRectPath(FPath, X, Y, W, H, Radius);
      FCanvas.FillPath(FPath, FOpacity, FBrush);
    end
    else
    begin
      R := TRectF.Create(X, Y, X + W, Y + H);
      FCanvas.IntersectClipRect(R);
      FCanvas.FillRect(GradRect, 0, 0, AllCorners, FOpacity, FBrush);
    end;
  finally
    RestoreState;
  end;
end;

procedure TPixieFmxCanvas.FillConicGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieConicGradientLayer);
var
  Count, I, J, Steps: Integer;
  Cx, Cy, MaxR, Angle, Frac: Single;
  Cp: TPixieColorPoint;
  C: TPixieWebColor;
  StartAngle, SweepAngle, CosA, SinA, CosB, SinB: Single;
begin
  // FMX has no native conic gradient — approximate with pie sectors
  if (FCanvas = nil) or (Gradient = nil) then Exit;
  Count := Gradient.ColorPoints.Count;
  if Count < 2 then Exit;

  Cx := Gradient.Position.X;
  Cy := Gradient.Position.Y;
  MaxR := Max(Max(Abs(X + W - Cx), Abs(X - Cx)),
              Max(Abs(Y + H - Cy), Abs(Y - Cy))) * 1.5;
  if MaxR < 1 then MaxR := 1;

  SaveState;
  try
    FCanvas.IntersectClipRect(TRectF.Create(X, Y, X + W, Y + H));

    Steps := 360;
    SweepAngle := 2 * Pi / Steps;

    for J := 0 to Steps - 1 do
    begin
      Angle := J / Steps;

      // Find the color at this angle
      C := Gradient.ColorPoints[0].Color;
      for I := 0 to Count - 2 do
      begin
        if (Angle >= Gradient.ColorPoints[I].Offset) and
           (Angle <= Gradient.ColorPoints[I + 1].Offset) then
        begin
          Cp := Gradient.ColorPoints[I];
          if (Gradient.ColorPoints[I + 1].Offset - Cp.Offset) > 0.0001 then
          begin
            Frac := (Angle - Cp.Offset) /
              (Gradient.ColorPoints[I + 1].Offset - Cp.Offset);
            C.Red := Round(Cp.Color.Red +
              Frac * (Gradient.ColorPoints[I + 1].Color.Red - Cp.Color.Red));
            C.Green := Round(Cp.Color.Green +
              Frac * (Gradient.ColorPoints[I + 1].Color.Green - Cp.Color.Green));
            C.Blue := Round(Cp.Color.Blue +
              Frac * (Gradient.ColorPoints[I + 1].Color.Blue - Cp.Color.Blue));
            C.Alpha := Round(Cp.Color.Alpha +
              Frac * (Gradient.ColorPoints[I + 1].Color.Alpha - Cp.Color.Alpha));
          end
          else
            C := Cp.Color;
          Break;
        end;
      end;

      FBrush.Kind := TBrushKind.Solid;
      FBrush.Color := ToAlphaColor(C);

      // Build pie sector as a triangle fan segment
      StartAngle := (Gradient.Angle - 90 + J * (360.0 / Steps)) * Pi / 180.0;
      SinCos(StartAngle, SinA, CosA);
      SinCos(StartAngle + SweepAngle, SinB, CosB);

      FPath.Clear;
      FPath.MoveTo(PointF(Cx, Cy));
      FPath.LineTo(PointF(Cx + CosA * MaxR, Cy + SinA * MaxR));
      FPath.LineTo(PointF(Cx + CosB * MaxR, Cy + SinB * MaxR));
      FPath.ClosePath;

      FCanvas.FillPath(FPath, FOpacity, FBrush);
    end;
  finally
    RestoreState;
  end;
end;

// ---------------------------------------------------------------------------
// Borders
// ---------------------------------------------------------------------------

procedure TPixieFmxCanvas.DrawBorderSide(const Border: TPixieBorder;
  X1, Y1, X2, Y2: Single);
var
  LineW, Offset, Dx, Dy, Len, Nx, Ny: Single;
begin
  if (Border.Width <= 0) or (Border.Style = bsNone) or
     (Border.Style = bsHidden) then
    Exit;

  FStrokeBrush.Kind := TBrushKind.Solid;
  FStrokeBrush.Color := ToAlphaColor(Border.Color);
  FStrokeBrush.Thickness := Border.Width;

  // Double border: two solid lines of width/3 separated by width/3 gap
  if Border.Style = bsDouble then
  begin
    LineW := Border.Width / 3;
    if LineW < 1 then LineW := 1;
    Dx := X2 - X1;
    Dy := Y2 - Y1;
    Len := Sqrt(Dx * Dx + Dy * Dy);
    if Len < 0.001 then Exit;
    Nx := -Dy / Len;
    Ny := Dx / Len;
    Offset := Border.Width / 2 - LineW / 2;
    FStrokeBrush.Thickness := LineW;
    FStrokeBrush.Dash := TStrokeDash.Solid;
    FStrokeBrush.Cap := TStrokeCap.Flat;
    // Outer line
    FCanvas.DrawLine(
      PointF(X1 - Nx * Offset, Y1 - Ny * Offset),
      PointF(X2 - Nx * Offset, Y2 - Ny * Offset),
      FOpacity, FStrokeBrush);
    // Inner line
    FCanvas.DrawLine(
      PointF(X1 + Nx * Offset, Y1 + Ny * Offset),
      PointF(X2 + Nx * Offset, Y2 + Ny * Offset),
      FOpacity, FStrokeBrush);
    Exit;
  end;

  case Border.Style of
    bsDotted: FStrokeBrush.Dash := TStrokeDash.Dot;
    bsDashed: FStrokeBrush.Dash := TStrokeDash.Dash;
  else
    FStrokeBrush.Dash := TStrokeDash.Solid;
  end;

  FStrokeBrush.Cap := TStrokeCap.Flat;
  FCanvas.DrawLine(PointF(X1, Y1), PointF(X2, Y2), FOpacity, FStrokeBrush);
end;

procedure TPixieFmxCanvas.DrawBorders(const Borders: TPixieBorders;
  const Pos: TPixiePosition; IsRoot: Boolean);
var
  X, Y, W, H: Single;
begin
  if FCanvas = nil then Exit;
  if not Borders.IsVisible then Exit;

  X := Pos.X;
  Y := Pos.Y;
  W := Pos.Width;
  H := Pos.Height;

  // Rounded borders: draw as single path
  if HasRadius(Borders.Radius) then
  begin
    if (Borders.Top.Width > 0) and (Borders.Top.Style <> bsNone) then
    begin
      FStrokeBrush.Kind := TBrushKind.Solid;
      FStrokeBrush.Color := ToAlphaColor(Borders.Top.Color);
      FStrokeBrush.Thickness := Borders.Top.Width;
      FStrokeBrush.Dash := TStrokeDash.Solid;
      BuildRoundedRectPath(FPath, X, Y, W, H, Borders.Radius);
      FCanvas.DrawPath(FPath, FOpacity, FStrokeBrush);
      Exit;
    end;
  end;

  // Straight borders: draw each side, inset by half adjacent width for clean corners
  DrawBorderSide(Borders.Top,
    X + Borders.Left.Width / 2, Y + Borders.Top.Width / 2,
    X + W - Borders.Right.Width / 2, Y + Borders.Top.Width / 2);

  DrawBorderSide(Borders.Right,
    X + W - Borders.Right.Width / 2, Y + Borders.Top.Width / 2,
    X + W - Borders.Right.Width / 2, Y + H - Borders.Bottom.Width / 2);

  DrawBorderSide(Borders.Bottom,
    X + Borders.Left.Width / 2, Y + H - Borders.Bottom.Width / 2,
    X + W - Borders.Right.Width / 2, Y + H - Borders.Bottom.Width / 2);

  DrawBorderSide(Borders.Left,
    X + Borders.Left.Width / 2, Y + Borders.Top.Width / 2,
    X + Borders.Left.Width / 2, Y + H - Borders.Bottom.Width / 2);
end;

// ---------------------------------------------------------------------------
// Font management
// ---------------------------------------------------------------------------

function TPixieFmxCanvas.CreateFont(
  const Descr: TPixieFontDescription;
  out Metrics: TPixieFontMetrics): TPixieFontHandle;
var
  Info: TPixieFmxFont;
  ResolvedFamily: string;
  Entry: TPixieFontMetricsEntry;
  Scale: Single;
begin
  Info := TPixieFmxFont.Create;
  Info.DecorationLine := Descr.DecorationLine;

  // Resolve font family
  ResolvedFamily := PixieResolveFontFamily(Descr.Family, FmxCheckFont);

  // Configure FMX font
  Info.FmxFont.Family := ResolvedFamily;
  Info.FmxFont.Size := Descr.Size;
  Info.FmxFont.Style := [];
  if Descr.Weight >= 600 then
    Info.FmxFont.Style := Info.FmxFont.Style + [TFontStyle.fsBold];
  if Descr.Style = fstItalic then
    Info.FmxFont.Style := Info.FmxFont.Style + [TFontStyle.fsItalic];

  // Compute metrics from font metrics table
  if PixieLookupFontMetrics(ResolvedFamily, Entry) then
  begin
    Scale := Descr.Size / Entry.UnitsPerEm;
    Metrics.Ascent := Entry.Ascent * Scale;
    Metrics.Descent := Entry.Descent * Scale;
    Metrics.Height := (Entry.Ascent + Entry.Descent + Entry.LineGap) * Scale;
    if Entry.XHeight > 0 then
      Metrics.XHeight := Entry.XHeight * Scale
    else
      Metrics.XHeight := Descr.Size * 0.5;
  end
  else
  begin
    // Fallback: use generic sans-serif metrics
    PixieDefaultFontMetrics(fmcSansSerif, Entry);
    Scale := Descr.Size / Entry.UnitsPerEm;
    Metrics.Ascent := Entry.Ascent * Scale;
    Metrics.Descent := Entry.Descent * Scale;
    Metrics.Height := (Entry.Ascent + Entry.Descent + Entry.LineGap) * Scale;
    Metrics.XHeight := Entry.XHeight * Scale;
  end;

  Metrics.FontSize := Descr.Size;
  Metrics.ChWidth := Descr.Size * 0.6;
  Metrics.DrawSpaces := True;
  Metrics.SubShift := 0;
  Metrics.SuperShift := 0;
  Info.Metrics := Metrics;

  Result := TPixieFontHandle(Info);
end;

procedure TPixieFmxCanvas.DeleteFont(Handle: TPixieFontHandle);
begin
  if Handle = 0 then Exit;
  TPixieFmxFont(Handle).Free;
end;

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

function TPixieFmxCanvas.MeasureText(const Text: string;
  Handle: TPixieFontHandle): TPixiePixel;
var
  Info: TPixieFmxFont;
begin
  Result := 0;
  if Handle = 0 then Exit;
  Info := TPixieFmxFont(Handle);

  FTextLayout.BeginUpdate;
  try
    FTextLayout.Font.Family := Info.FmxFont.Family;
    FTextLayout.Font.Size := Info.FmxFont.Size;
    FTextLayout.Font.Style := Info.FmxFont.Style;
    FTextLayout.Text := Text;
    FTextLayout.MaxSize := TSizeF.Create(100000, 100000);
    FTextLayout.WordWrap := False;
    FTextLayout.Trimming := TTextTrimming.None;
  finally
    FTextLayout.EndUpdate;
  end;
  Result := FTextLayout.TextWidth;
end;

procedure TPixieFmxCanvas.DrawText(const Text: string;
  Handle: TPixieFontHandle; Color: TPixieWebColor;
  X, Y, W, H: Single);
var
  Info: TPixieFmxFont;
  R: TRectF;
  SavedStyle: TFontStyles;
begin
  if (FCanvas = nil) or (Handle = 0) then Exit;
  Info := TPixieFmxFont(Handle);

  // Set fill brush for text color
  FCanvas.Fill.Kind := TBrushKind.Solid;
  FCanvas.Fill.Color := ToAlphaColor(Color);

  // Set font
  SavedStyle := Info.FmxFont.Style;
  FCanvas.Font.Family := Info.FmxFont.Family;
  FCanvas.Font.Size := Info.FmxFont.Size;
  FCanvas.Font.Style := SavedStyle;

  // Text decoration is drawn at the element level (TPixieHtmlTag.DrawBackground)

  R := TRectF.Create(X, Y, X + W, Y + H);
  FCanvas.FillText(R, Text, False, FOpacity, [],
    TTextAlign.Leading, TTextAlign.Leading);
end;

function TPixieFmxCanvas.PtToPx(Pt: Single): TPixiePixel;
begin
  Result := Trunc(Pt * 96.0 / 72.0);
end;

// ---------------------------------------------------------------------------
// Images
// ---------------------------------------------------------------------------

function TPixieFmxCanvas.LoadImage(const Path: string): TPixieImageHandle;
var
  Info: TPixieFmxImage;
  Resolved: string;
begin
  Result := 0;
  Resolved := ExpandFileName(Path);
  if not FileExists(Resolved) then Exit;

  Info := TPixieFmxImage.Create;
  try
    Info.Bitmap := TBitmap.CreateFromFile(Resolved);
    Info.ImgWidth := Info.Bitmap.Width;
    Info.ImgHeight := Info.Bitmap.Height;
  except
    Info.Free;
    Exit;
  end;

  Result := TPixieImageHandle(Info);
end;

function TPixieFmxCanvas.LoadImageFromStream(
  Stream: TStream): TPixieImageHandle;
var
  Info: TPixieFmxImage;
begin
  Result := 0;
  if (Stream = nil) or (Stream.Size = 0) then Exit;

  Info := TPixieFmxImage.Create;
  try
    Info.Bitmap := TBitmap.Create;
    Stream.Position := 0;
    Info.Bitmap.LoadFromStream(Stream);
    Info.ImgWidth := Info.Bitmap.Width;
    Info.ImgHeight := Info.Bitmap.Height;
    if (Info.ImgWidth = 0) or (Info.ImgHeight = 0) then
    begin
      Info.Free;
      Exit;
    end;
  except
    Info.Free;
    Exit;
  end;

  Result := TPixieImageHandle(Info);
end;

function TPixieFmxCanvas.LoadSvgFromData(Data: Pointer;
  Size: Integer): TPixieImageHandle;
var
  Bitmap: TBitmap;
  Info: TPixieFmxImage;
begin
  Result := 0;
  if (Data = nil) or (Size <= 0) then Exit;

  Bitmap := TPixieSvgCanvasRenderer.RenderToBitmap(Data, Size);
  if Bitmap = nil then Exit;

  Info := TPixieFmxImage.Create;
  Info.Bitmap := Bitmap;
  Info.ImgWidth := Bitmap.Width;
  Info.ImgHeight := Bitmap.Height;
  Result := TPixieImageHandle(Info);
end;

function TPixieFmxCanvas.LoadImageFromPixels(Width, Height: Integer;
  Pixels: Pointer; Pitch: Integer): TPixieImageHandle;
var
  Info: TPixieFmxImage;
  MapData: TBitmapData;
  Y, X: Integer;
  Src, Dst: PByte;
  Tmp: Byte;
  NeedSwapRB: Boolean;
begin
  Result := 0;
  if (Width <= 0) or (Height <= 0) or (Pixels = nil) then Exit;

  Info := TPixieFmxImage.Create;
  Info.Bitmap := TBitmap.Create(Width, Height);
  Info.ImgWidth := Width;
  Info.ImgHeight := Height;

  if Info.Bitmap.Map(TMapAccess.Write, MapData) then
  try
    NeedSwapRB := MapData.PixelFormat in [TPixelFormat.RGBA,
      TPixelFormat.RGBA16];
    for Y := 0 to Height - 1 do
    begin
      Src := PByte(Pixels) + Y * Pitch;
      Dst := PByte(MapData.Data) + Y * MapData.Pitch;
      Move(Src^, Dst^, Width * 4);
      if NeedSwapRB then
      begin
        Dst := PByte(MapData.Data) + Y * MapData.Pitch;
        for X := 0 to Width - 1 do
        begin
          Tmp := Dst^; Dst^ := (Dst + 2)^; (Dst + 2)^ := Tmp;
          Inc(Dst, 4);
        end;
      end;
    end;
  finally
    Info.Bitmap.Unmap(MapData);
  end;

  Result := TPixieImageHandle(Info);
end;

procedure TPixieFmxCanvas.FreeImage(Handle: TPixieImageHandle);
begin
  if Handle = 0 then Exit;
  TPixieFmxImage(Handle).Free;
end;

procedure TPixieFmxCanvas.GetImageSize(Handle: TPixieImageHandle;
  out W, H: Single);
var
  Info: TPixieFmxImage;
begin
  W := 0;
  H := 0;
  if Handle = 0 then Exit;
  Info := TPixieFmxImage(Handle);
  W := Info.ImgWidth;
  H := Info.ImgHeight;
end;

procedure TPixieFmxCanvas.DrawImage(Handle: TPixieImageHandle;
  DstX, DstY, DstW, DstH: Single);
var
  Info: TPixieFmxImage;
  SrcRect, DstRect: TRectF;
begin
  if (FCanvas = nil) or (Handle = 0) then Exit;
  Info := TPixieFmxImage(Handle);
  if Info.Bitmap = nil then Exit;

  SrcRect := TRectF.Create(0, 0, Info.ImgWidth, Info.ImgHeight);
  DstRect := TRectF.Create(DstX, DstY, DstX + DstW, DstY + DstH);
  FCanvas.DrawBitmap(Info.Bitmap, SrcRect, DstRect, FOpacity);
end;

// ---------------------------------------------------------------------------
// Simple shapes
// ---------------------------------------------------------------------------

procedure TPixieFmxCanvas.FillEllipse(X, Y, W, H: Single;
  Color: TPixieWebColor);
begin
  if (FCanvas = nil) or (Color.Alpha = 0) then Exit;
  FBrush.Kind := TBrushKind.Solid;
  FBrush.Color := ToAlphaColor(Color);
  FCanvas.FillEllipse(TRectF.Create(X, Y, X + W, Y + H), FOpacity, FBrush);
end;

procedure TPixieFmxCanvas.DrawEllipse(X, Y, W, H: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
begin
  if (FCanvas = nil) or (Color.Alpha = 0) then Exit;
  FStrokeBrush.Kind := TBrushKind.Solid;
  FStrokeBrush.Color := ToAlphaColor(Color);
  FStrokeBrush.Thickness := StrokeWidth;
  FStrokeBrush.Dash := TStrokeDash.Solid;
  FCanvas.DrawEllipse(TRectF.Create(X, Y, X + W, Y + H), FOpacity,
    FStrokeBrush);
end;

procedure TPixieFmxCanvas.DrawRect(X, Y, W, H: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
begin
  if (FCanvas = nil) or (Color.Alpha = 0) then Exit;
  FStrokeBrush.Kind := TBrushKind.Solid;
  FStrokeBrush.Color := ToAlphaColor(Color);
  FStrokeBrush.Thickness := StrokeWidth;
  FStrokeBrush.Dash := TStrokeDash.Solid;
  FCanvas.DrawRect(TRectF.Create(X, Y, X + W, Y + H), 0, 0, AllCorners,
    FOpacity, FStrokeBrush);
end;

procedure TPixieFmxCanvas.DrawLine(X1, Y1, X2, Y2: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
begin
  if (FCanvas = nil) or (Color.Alpha = 0) then Exit;
  FStrokeBrush.Kind := TBrushKind.Solid;
  FStrokeBrush.Color := ToAlphaColor(Color);
  FStrokeBrush.Thickness := StrokeWidth;
  FStrokeBrush.Dash := TStrokeDash.Solid;
  FCanvas.DrawLine(PointF(X1, Y1), PointF(X2, Y2), FOpacity, FStrokeBrush);
end;

procedure TPixieFmxCanvas.StrokePolyline(const Points: array of Single;
  Color: TPixieWebColor; StrokeWidth: Single);
var
  I, Count: Integer;
begin
  if (FCanvas = nil) or (Color.Alpha = 0) then Exit;
  Count := Length(Points) div 2;
  if Count < 2 then Exit;

  FPath.Clear;
  FPath.MoveTo(PointF(Points[0], Points[1]));
  for I := 1 to Count - 1 do
    FPath.LineTo(PointF(Points[I * 2], Points[I * 2 + 1]));

  FStrokeBrush.Kind := TBrushKind.Solid;
  FStrokeBrush.Color := ToAlphaColor(Color);
  FStrokeBrush.Thickness := StrokeWidth;
  FStrokeBrush.Dash := TStrokeDash.Solid;
  FCanvas.DrawPath(FPath, FOpacity, FStrokeBrush);
end;

// ---------------------------------------------------------------------------
// View / scale
// ---------------------------------------------------------------------------

procedure TPixieFmxCanvas.SetScale(Scale: Single);
begin
  FScale := Scale;
end;

end.
