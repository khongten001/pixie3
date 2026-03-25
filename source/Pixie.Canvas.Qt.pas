unit Pixie.Canvas.Qt;

// QPainter implementation of TPixieCanvas for Qt5 and Qt6 widgetsets.
// Provides 2D drawing via QPainter and text measurement via QFontMetrics.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Math,
  {$IFDEF LCLqt} qt4, {$ENDIF}
  {$IFDEF LCLqt5} qt5, {$ENDIF}
  {$IFDEF LCLqt6} qt6, {$ENDIF}
  qtobjects,
  Graphics, IntfGraphics, FPImage,
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.Background, Pixie.FontDescription,
  Pixie.Canvas;

type
  { TPixieQtFont }

  TPixieQtFont = class
    Handle: QFontH;
    MetricsHandle: QFontMetricsH;
    Metrics: TPixieFontMetrics;
    DecorationLine: Integer;
    destructor Destroy; override;
  end;

  { TPixieQtImage }

  TPixieQtImage = class
    Handle: QImageH;
    PixelData: Pointer;
    ImgWidth: Integer;
    ImgHeight: Integer;
    destructor Destroy; override;
  end;

  TPixieQtSavedState = record
    ClipsPushed: Integer;
  end;

  { TPixieQtCanvas }

  TPixieQtCanvas = class(TPixieCanvas)
  private
    FPainter: QPainterH;
    FScale: Single;
    FViewWidth, FViewHeight: Integer;
    FStateStack: array[0..63] of TPixieQtSavedState;
    FStateTop: Integer;
    FOpacityStack: array[0..15] of Single;
    FOpacityTop: Integer;
    FCurrentOpacity: Single;
    FTempRect: QRectFH;

    function HasRadius(const R: TPixieBorderRadiuses): Boolean;
    procedure MakeColor(const C: TPixieWebColor; out QC: TQColor);
    procedure RoundedRectPath(Path: QPainterPathH; X, Y, W, H: Single;
      const R: TPixieBorderRadiuses);
    procedure DrawBorderSide(const Border: TPixieBorder;
      X1, Y1, X2, Y2: Single);
    function DecodeImageFile(const Path: string): TPixieImageHandle;
  public
    constructor Create;
    destructor Destroy; override;

    procedure BeginPaint(DC: PtrUInt); override;
    procedure EndPaint; override;

    procedure SaveState; override;
    procedure RestoreState; override;
    procedure PushOpacity(AOpacity: Single); override;
    procedure PopOpacity; override;

    procedure SetClipRect(const R: TPixiePosition;
      const Radius: TPixieBorderRadiuses); override;

    procedure FillRect(X, Y, W, H: Single;
      Color: TPixieWebColor); override;
    procedure FillRoundedRect(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      Color: TPixieWebColor); override;
    procedure FillLinearGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieLinearGradientLayer); override;
    procedure FillRadialGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieRadialGradientLayer); override;
    procedure FillConicGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieConicGradientLayer); override;

    procedure DrawBorders(const Borders: TPixieBorders;
      const Pos: TPixiePosition; IsRoot: Boolean); override;

    function CreateFont(const Descr: TPixieFontDescription;
      out Metrics: TPixieFontMetrics): TPixieFontHandle; override;
    procedure DeleteFont(Handle: TPixieFontHandle); override;
    function MeasureText(const Text: string;
      Handle: TPixieFontHandle): TPixiePixel; override;
    procedure DrawText(const Text: string; Handle: TPixieFontHandle;
      Color: TPixieWebColor; X, Y, W, H: Single); override;
    function PtToPx(Pt: Single): TPixiePixel; override;

    function LoadImage(const Path: string): TPixieImageHandle; override;
    function LoadImageFromPixels(Width, Height: Integer;
      Pixels: Pointer; Pitch: Integer): TPixieImageHandle; override;
    procedure FreeImage(Handle: TPixieImageHandle); override;
    procedure GetImageSize(Handle: TPixieImageHandle;
      out W, H: Single); override;
    procedure DrawImage(Handle: TPixieImageHandle;
      DstX, DstY, DstW, DstH: Single); override;

    procedure FillEllipse(X, Y, W, H: Single;
      Color: TPixieWebColor); override;
    procedure DrawEllipse(X, Y, W, H: Single;
      Color: TPixieWebColor; StrokeWidth: Single); override;
    procedure DrawRect(X, Y, W, H: Single;
      Color: TPixieWebColor; StrokeWidth: Single); override;
    procedure DrawLine(X1, Y1, X2, Y2: Single;
      Color: TPixieWebColor; StrokeWidth: Single;
      Style: TPixieTextDecorationStyle = tdsSolid); override;
    procedure StrokePolyline(const Points: array of Single;
      Color: TPixieWebColor; StrokeWidth: Single); override;

    procedure SetViewSize(W, H: Integer; ACanvasScale: Single = 1); override;
    procedure SetScale(Scale: Single); override;
  end;

implementation

// ---------------------------------------------------------------------------
// Font check callback for PixieResolveFontFamily
// ---------------------------------------------------------------------------

function CheckQtFont(const Name: string): Boolean;
begin
  // Qt handles font fallback internally — accept all requested families
  Result := True;
end;

{$IF DEFINED(LCLqt) OR DEFINED(LCLqt5)}
// Qt4/Qt5 use a 0..99 weight scale; Qt6/CSS uses 100..900.
// Map standard CSS breakpoints to Qt5 equivalents.
function CssWeightToQt5(W: Integer): Integer;
const
  CssValues: array[0..8] of Integer = (100, 200, 300, 400, 500, 600, 700, 800, 900);
  Qt5Values: array[0..8] of Integer = (0, 12, 25, 50, 57, 63, 75, 81, 87);
var
  I: Integer;
begin
  for I := High(CssValues) downto 0 do
    if W >= CssValues[I] then
      Exit(Qt5Values[I]);
  Result := 0;
end;
{$ENDIF}

// ---------------------------------------------------------------------------
// TPixieQtFont / TPixieQtImage destructors
// ---------------------------------------------------------------------------

destructor TPixieQtFont.Destroy;
begin
  if MetricsHandle <> nil then
    QFontMetrics_Destroy(MetricsHandle);
  if Handle <> nil then
    QFont_Destroy(Handle);
  inherited;
end;

destructor TPixieQtImage.Destroy;
begin
  if Handle <> nil then
    QImage_Destroy(Handle);
  if PixelData <> nil then
    FreeMem(PixelData);
  inherited;
end;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function TPixieQtCanvas.HasRadius(
  const R: TPixieBorderRadiuses): Boolean;
begin
  Result := (R.TopLeftX > 0) or (R.TopLeftY > 0) or
            (R.TopRightX > 0) or (R.TopRightY > 0) or
            (R.BottomRightX > 0) or (R.BottomRightY > 0) or
            (R.BottomLeftX > 0) or (R.BottomLeftY > 0);
end;

procedure TPixieQtCanvas.MakeColor(
  const C: TPixieWebColor; out QC: TQColor);
begin
  QC.ColorSpec := 1; // QColorRgb
  QC.Alpha := C.Alpha * 257;
  QC.r := C.Red * 257;
  QC.g := C.Green * 257;
  QC.b := C.Blue * 257;
  QC.Pad := 0;
end;

procedure TPixieQtCanvas.RoundedRectPath(Path: QPainterPathH;
  X, Y, W, H: Single; const R: TPixieBorderRadiuses);
begin
  // Trace clockwise on screen using arcTo (negative sweep = CW).
  // arcTo bounding rect is 2*rx by 2*ry for each corner ellipse.
  QPainterPath_moveTo(Path, X, Y + R.TopLeftY);

  // Top-left arc
  if (R.TopLeftX > 0) and (R.TopLeftY > 0) then
    QPainterPath_arcTo(Path, X, Y,
      R.TopLeftX * 2, R.TopLeftY * 2, 180, -90)
  else
    QPainterPath_lineTo(Path, X, Y);

  // Top edge
  QPainterPath_lineTo(Path, X + W - R.TopRightX, Y);

  // Top-right arc
  if (R.TopRightX > 0) and (R.TopRightY > 0) then
    QPainterPath_arcTo(Path, X + W - R.TopRightX * 2, Y,
      R.TopRightX * 2, R.TopRightY * 2, 90, -90)
  else
    QPainterPath_lineTo(Path, X + W, Y);

  // Right edge
  QPainterPath_lineTo(Path, X + W, Y + H - R.BottomRightY);

  // Bottom-right arc
  if (R.BottomRightX > 0) and (R.BottomRightY > 0) then
    QPainterPath_arcTo(Path, X + W - R.BottomRightX * 2,
      Y + H - R.BottomRightY * 2,
      R.BottomRightX * 2, R.BottomRightY * 2, 0, -90)
  else
    QPainterPath_lineTo(Path, X + W, Y + H);

  // Bottom edge
  QPainterPath_lineTo(Path, X + R.BottomLeftX, Y + H);

  // Bottom-left arc
  if (R.BottomLeftX > 0) and (R.BottomLeftY > 0) then
    QPainterPath_arcTo(Path, X, Y + H - R.BottomLeftY * 2,
      R.BottomLeftX * 2, R.BottomLeftY * 2, 270, -90)
  else
    QPainterPath_lineTo(Path, X, Y + H);

  QPainterPath_closeSubpath(Path);
end;

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieQtCanvas.Create;
begin
  inherited Create;
  FPainter := nil;
  FScale := 1.0;
  FViewWidth := 800;
  FViewHeight := 600;
  FStateTop := 0;
  FOpacityTop := 0;
  FCurrentOpacity := 1.0;
  FTempRect := QRectF_Create;
end;

destructor TPixieQtCanvas.Destroy;
begin
  if FTempRect <> nil then
    QRectF_Destroy(FTempRect);
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

procedure TPixieQtCanvas.BeginPaint(DC: PtrUInt);
begin
  FStateTop := 0;
  FOpacityTop := 0;
  FCurrentOpacity := 1.0;

  FPainter := TQtDeviceContext(DC).Widget;
  if FPainter = nil then Exit;

  // Save QPainter state before applying our transform and hints.
  // EndPaint restores this to leave the painter unchanged for the LCL.
  QPainter_save(FPainter);
  QPainter_setRenderHint(FPainter, QPainterAntialiasing, True);
  QPainter_setRenderHint(FPainter, QPainterTextAntialiasing, True);
  QPainter_setRenderHint(FPainter, QPainterSmoothPixmapTransform, True);
  QPainter_setBackgroundMode(FPainter, QtTransparentMode);
  QPainter_scale(FPainter, FScale, FScale);
end;

procedure TPixieQtCanvas.EndPaint;
begin
  if FPainter <> nil then
    QPainter_restore(FPainter);
  FPainter := nil;
end;

// ---------------------------------------------------------------------------
// State save/restore
// ---------------------------------------------------------------------------

procedure TPixieQtCanvas.SaveState;
begin
  if (FPainter = nil) or (FStateTop > High(FStateStack)) then Exit;

  QPainter_save(FPainter);
  FStateStack[FStateTop].ClipsPushed := 0;
  Inc(FStateTop);
end;

procedure TPixieQtCanvas.RestoreState;
var
  I: Integer;
begin
  if (FPainter = nil) or (FStateTop <= 0) then Exit;
  Dec(FStateTop);

  // Each clip pushed its own QPainter_save, undo them
  for I := 0 to FStateStack[FStateTop].ClipsPushed - 1 do
    QPainter_restore(FPainter);

  // Undo the SaveState's QPainter_save
  QPainter_restore(FPainter);
end;

procedure TPixieQtCanvas.PushOpacity(AOpacity: Single);
begin
  if (FPainter = nil) or (FOpacityTop > High(FOpacityStack)) then Exit;
  FOpacityStack[FOpacityTop] := FCurrentOpacity;
  Inc(FOpacityTop);
  FCurrentOpacity := FCurrentOpacity * AOpacity;
  QPainter_setOpacity(FPainter, FCurrentOpacity);
end;

procedure TPixieQtCanvas.PopOpacity;
begin
  if (FPainter = nil) or (FOpacityTop <= 0) then Exit;
  Dec(FOpacityTop);
  FCurrentOpacity := FOpacityStack[FOpacityTop];
  QPainter_setOpacity(FPainter, FCurrentOpacity);
end;

// ---------------------------------------------------------------------------
// Clipping
// ---------------------------------------------------------------------------

procedure TPixieQtCanvas.SetClipRect(const R: TPixiePosition;
  const Radius: TPixieBorderRadiuses);
var
  Path: QPainterPathH;
begin
  if FPainter = nil then Exit;

  // Each clip gets its own QPainter_save so it can be independently undone
  QPainter_save(FPainter);

  if HasRadius(Radius) then
  begin
    Path := QPainterPath_Create;
    try
      RoundedRectPath(Path, R.X, R.Y, R.Width, R.Height, Radius);
      QPainter_setClipPath(FPainter, Path, QtIntersectClip);
    finally
      QPainterPath_Destroy(Path);
    end;
  end
  else
  begin
    QRectF_setRect(FTempRect, R.X, R.Y, R.Width, R.Height);
    QPainter_setClipRect(FPainter, FTempRect, QtIntersectClip);
  end;

  if FStateTop > 0 then
    Inc(FStateStack[FStateTop - 1].ClipsPushed);
end;

// ---------------------------------------------------------------------------
// Solid fills
// ---------------------------------------------------------------------------

procedure TPixieQtCanvas.FillRect(X, Y, W, H: Single;
  Color: TPixieWebColor);
var
  QC: TQColor;
begin
  if (FPainter = nil) or (Color.Alpha = 0) then Exit;
  MakeColor(Color, QC);
  QRectF_setRect(FTempRect, X, Y, W, H);
  QPainter_fillRect(FPainter, FTempRect, @QC);
end;

procedure TPixieQtCanvas.FillRoundedRect(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses; Color: TPixieWebColor);
var
  QC: TQColor;
  Path: QPainterPathH;
  Brush: QBrushH;
begin
  if (FPainter = nil) or (Color.Alpha = 0) then Exit;
  MakeColor(Color, QC);

  if HasRadius(Radius) then
  begin
    Path := QPainterPath_Create;
    Brush := QBrush_Create(@QC);
    try
      RoundedRectPath(Path, X, Y, W, H, Radius);
      QPainter_fillPath(FPainter, Path, Brush);
    finally
      QBrush_Destroy(Brush);
      QPainterPath_Destroy(Path);
    end;
  end
  else
  begin
    QRectF_setRect(FTempRect, X, Y, W, H);
    QPainter_fillRect(FPainter, FTempRect, @QC);
  end;
end;

// ---------------------------------------------------------------------------
// Gradients
// ---------------------------------------------------------------------------

procedure TPixieQtCanvas.FillLinearGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieLinearGradientLayer);
var
  Grad: QLinearGradientH;
  Brush: QBrushH;
  Path: QPainterPathH;
  I: Integer;
  Cp: TPixieColorPoint;
  QC: TQColor;
begin
  if (FPainter = nil) or (Gradient = nil) then Exit;
  if Gradient.ColorPoints.Count < 2 then Exit;

  Grad := QLinearGradient_Create(
    Gradient.StartPt.X, Gradient.StartPt.Y,
    Gradient.EndPt.X, Gradient.EndPt.Y);
  try
    for I := 0 to Gradient.ColorPoints.Count - 1 do
    begin
      Cp := Gradient.ColorPoints[I];
      MakeColor(Cp.Color, QC);
      QGradient_setColorAt(QGradientH(Grad), Cp.Offset, @QC);
    end;

    Brush := QBrush_Create(QGradientH(Grad));
    try
      if HasRadius(Radius) then
      begin
        Path := QPainterPath_Create;
        try
          RoundedRectPath(Path, X, Y, W, H, Radius);
          QPainter_fillPath(FPainter, Path, Brush);
        finally
          QPainterPath_Destroy(Path);
        end;
      end
      else
      begin
        QRectF_setRect(FTempRect, X, Y, W, H);
        QPainter_fillRect(FPainter, FTempRect, Brush);
      end;
    finally
      QBrush_Destroy(Brush);
    end;
  finally
    QLinearGradient_Destroy(Grad);
  end;
end;

procedure TPixieQtCanvas.FillRadialGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieRadialGradientLayer);
var
  Grad: QRadialGradientH;
  Brush: QBrushH;
  Path: QPainterPathH;
  I: Integer;
  Cp: TPixieColorPoint;
  QC: TQColor;
  Cx, Cy, Rx, Ry: Single;
begin
  if (FPainter = nil) or (Gradient = nil) then Exit;
  if Gradient.ColorPoints.Count < 2 then Exit;

  Cx := Gradient.Position.X;
  Cy := Gradient.Position.Y;
  Rx := Gradient.Radius.X;
  Ry := Gradient.Radius.Y;
  if (Rx < 0.001) or (Ry < 0.001) then Exit;

  // Create circular gradient with Rx; for elliptical, scale Y axis
  Grad := QRadialGradient_Create(Cx, Cy, Rx);
  try
    QRadialGradient_setFocalPoint(Grad, Cx, Cy);

    for I := 0 to Gradient.ColorPoints.Count - 1 do
    begin
      Cp := Gradient.ColorPoints[I];
      MakeColor(Cp.Color, QC);
      QGradient_setColorAt(QGradientH(Grad), Cp.Offset, @QC);
    end;

    Brush := QBrush_Create(QGradientH(Grad));
    try
      if Abs(Rx - Ry) < 0.001 then
      begin
        // Circular — draw directly
        if HasRadius(Radius) then
        begin
          Path := QPainterPath_Create;
          try
            RoundedRectPath(Path, X, Y, W, H, Radius);
            QPainter_fillPath(FPainter, Path, Brush);
          finally
            QPainterPath_Destroy(Path);
          end;
        end
        else
        begin
          QRectF_setRect(FTempRect, X, Y, W, H);
          QPainter_fillRect(FPainter, FTempRect, Brush);
        end;
      end
      else
      begin
        // Elliptical — scale Y axis to map circle to ellipse
        QPainter_save(FPainter);
        try
          QPainter_scale(FPainter, 1.0, Ry / Rx);

          if HasRadius(Radius) then
          begin
            Path := QPainterPath_Create;
            try
              RoundedRectPath(Path, X, Y * Rx / Ry, W, H * Rx / Ry, Radius);
              QPainter_fillPath(FPainter, Path, Brush);
            finally
              QPainterPath_Destroy(Path);
            end;
          end
          else
          begin
            QRectF_setRect(FTempRect, X, Y * Rx / Ry, W, H * Rx / Ry);
            QPainter_fillRect(FPainter, FTempRect, Brush);
          end;
        finally
          QPainter_restore(FPainter);
        end;
      end;
    finally
      QBrush_Destroy(Brush);
    end;
  finally
    QRadialGradient_Destroy(Grad);
  end;
end;

procedure TPixieQtCanvas.FillConicGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieConicGradientLayer);
var
  Grad: QConicalGradientH;
  Brush: QBrushH;
  Path: QPainterPathH;
  I: Integer;
  Cp: TPixieColorPoint;
  QC: TQColor;
  Cx, Cy, QtAngle, QtOffset: Single;
begin
  if (FPainter = nil) or (Gradient = nil) then Exit;
  if Gradient.ColorPoints.Count < 2 then Exit;

  Cx := Gradient.Position.X;
  Cy := Gradient.Position.Y;

  // Convert CSS angle (0=top, CW) to Qt angle (0=right, CCW)
  QtAngle := 90 - Gradient.Angle;

  Grad := QConicalGradient_Create(Cx, Cy, QtAngle);
  try
    // Reverse color stop offsets: CSS goes CW, Qt goes CCW
    for I := 0 to Gradient.ColorPoints.Count - 1 do
    begin
      Cp := Gradient.ColorPoints[I];
      MakeColor(Cp.Color, QC);
      QtOffset := 1 - Cp.Offset;
      if QtOffset < 0 then QtOffset := 0;
      if QtOffset > 1 then QtOffset := 1;
      QGradient_setColorAt(QGradientH(Grad), QtOffset, @QC);
    end;

    Brush := QBrush_Create(QGradientH(Grad));
    try
      if HasRadius(Radius) then
      begin
        Path := QPainterPath_Create;
        try
          RoundedRectPath(Path, X, Y, W, H, Radius);
          QPainter_fillPath(FPainter, Path, Brush);
        finally
          QPainterPath_Destroy(Path);
        end;
      end
      else
      begin
        QRectF_setRect(FTempRect, X, Y, W, H);
        QPainter_fillRect(FPainter, FTempRect, Brush);
      end;
    finally
      QBrush_Destroy(Brush);
    end;
  finally
    QConicalGradient_Destroy(Grad);
  end;
end;

// ---------------------------------------------------------------------------
// Borders
// ---------------------------------------------------------------------------

procedure TPixieQtCanvas.DrawBorderSide(const Border: TPixieBorder;
  X1, Y1, X2, Y2: Single);
var
  QC: TQColor;
  Pen: QPenH;
  LineW, Offset, Dx, Dy, Len, Nx, Ny: Single;
  Dashes: TQRealArray;
  P1, P2: TQtPointF;
begin
  if (Border.Width <= 0) or (Border.Style = bsNone) or
     (Border.Style = bsHidden) then
    Exit;

  MakeColor(Border.Color, QC);

  // Double border: two lines of width/3 separated by width/3 gap
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

    Pen := QPen_Create(@QC);
    try
      QPen_setWidthF(Pen, LineW);
      QPainter_setPen(FPainter, Pen);

      // Outer line
      P1.x := X1 - Nx * Offset; P1.y := Y1 - Ny * Offset;
      P2.x := X2 - Nx * Offset; P2.y := Y2 - Ny * Offset;
      QPainter_drawLine(FPainter, PQtPointF(@P1), PQtPointF(@P2));

      // Inner line
      P1.x := X1 + Nx * Offset; P1.y := Y1 + Ny * Offset;
      P2.x := X2 + Nx * Offset; P2.y := Y2 + Ny * Offset;
      QPainter_drawLine(FPainter, PQtPointF(@P1), PQtPointF(@P2));
    finally
      QPen_Destroy(Pen);
    end;
    Exit;
  end;

  Pen := QPen_Create(@QC);
  try
    QPen_setWidthF(Pen, Border.Width);

    case Border.Style of
      bsDotted:
      begin
        // Dash pattern is in pen-width units
        SetLength(Dashes, 2);
        Dashes[0] := 1;
        Dashes[1] := 1;
        QPen_setDashPattern(Pen, @Dashes);
        QPen_setCapStyle(Pen, QtRoundCap);
      end;
      bsDashed:
      begin
        SetLength(Dashes, 2);
        Dashes[0] := 3;
        Dashes[1] := 3;
        QPen_setDashPattern(Pen, @Dashes);
      end;
    end;

    QPainter_setPen(FPainter, Pen);

    P1.x := X1; P1.y := Y1;
    P2.x := X2; P2.y := Y2;
    QPainter_drawLine(FPainter, PQtPointF(@P1), PQtPointF(@P2));
  finally
    QPen_Destroy(Pen);
  end;
end;

procedure TPixieQtCanvas.DrawBorders(const Borders: TPixieBorders;
  const Pos: TPixiePosition; IsRoot: Boolean);
var
  X, Y, W, H: Single;
  QC: TQColor;
  Pen: QPenH;
  Path: QPainterPathH;
begin
  if FPainter = nil then Exit;
  if not Borders.IsVisible then Exit;

  X := Pos.X;
  Y := Pos.Y;
  W := Pos.Width;
  H := Pos.Height;

  if HasRadius(Borders.Radius) then
  begin
    if (Borders.Top.Width > 0) and (Borders.Top.Style <> bsNone) then
    begin
      MakeColor(Borders.Top.Color, QC);
      Pen := QPen_Create(@QC);
      try
        QPen_setWidthF(Pen, Borders.Top.Width);
        QPainter_setPen(FPainter, Pen);
        QPainter_setBrush(FPainter, QtNoBrush);
        Path := QPainterPath_Create;
        try
          RoundedRectPath(Path, X, Y, W, H, Borders.Radius);
          QPainter_drawPath(FPainter, Path);
        finally
          QPainterPath_Destroy(Path);
        end;
      finally
        QPen_Destroy(Pen);
      end;
      Exit;
    end;
  end;

  // Top
  DrawBorderSide(Borders.Top,
    X, Y + Borders.Top.Width / 2,
    X + W, Y + Borders.Top.Width / 2);

  // Right
  DrawBorderSide(Borders.Right,
    X + W - Borders.Right.Width / 2, Y,
    X + W - Borders.Right.Width / 2, Y + H);

  // Bottom
  DrawBorderSide(Borders.Bottom,
    X, Y + H - Borders.Bottom.Width / 2,
    X + W, Y + H - Borders.Bottom.Width / 2);

  // Left
  DrawBorderSide(Borders.Left,
    X + Borders.Left.Width / 2, Y,
    X + Borders.Left.Width / 2, Y + H);
end;

// ---------------------------------------------------------------------------
// Font management
// ---------------------------------------------------------------------------

function TPixieQtCanvas.CreateFont(
  const Descr: TPixieFontDescription;
  out Metrics: TPixieFontMetrics): TPixieFontHandle;
var
  Info: TPixieQtFont;
  FontH: QFontH;
  FM: QFontMetricsH;
  WFamily: WideString;
  ResolvedFamily: string;
begin
  Result := 0;

  Info := TPixieQtFont.Create;
  Info.DecorationLine := Descr.DecorationLine;

  // Resolve CSS font-family list
  ResolvedFamily := PixieResolveFontFamily(Descr.Family, CheckQtFont);
  WFamily := UTF8Decode(ResolvedFamily);

  FontH := QFont_Create(@WFamily);

  // Set pixel size
  QFont_setPixelSize(FontH, Round(Descr.Size));

  // Set weight (Qt5 and Qt6 use different scales)
  {$IF DEFINED(LCLqt) OR DEFINED(LCLqt5)}
  QFont_setWeight(FontH, CssWeightToQt5(Descr.Weight));
  {$ENDIF}
  {$IFDEF LCLqt6}
  QFont_setWeight(FontH, Descr.Weight);
  {$ENDIF}

  // Set style
  QFont_setItalic(FontH, Descr.Style = fstItalic);

  Info.Handle := FontH;

  // Get metrics — QFontMetrics works without an active painter
  FM := QFontMetrics_Create(FontH);
  Info.MetricsHandle := FM;

  Metrics.Ascent := QFontMetrics_ascent(FM);
  Metrics.Descent := QFontMetrics_descent(FM);
  Metrics.Height := QFontMetrics_height(FM);
  Metrics.XHeight := QFontMetrics_xHeight(FM);
  if Metrics.XHeight = 0 then
    Metrics.XHeight := Descr.Size * 0.5;

  Metrics.FontSize := Descr.Size;
  Metrics.ChWidth := QFontMetrics_averageCharWidth(FM);
  if Metrics.ChWidth = 0 then
    Metrics.ChWidth := Descr.Size * 0.6;
  Metrics.DrawSpaces := True;
  Metrics.CalcShifts;
  Info.Metrics := Metrics;

  Result := TPixieFontHandle(Info);
end;

procedure TPixieQtCanvas.DeleteFont(Handle: TPixieFontHandle);
begin
  if Handle <> 0 then
    TPixieQtFont(Handle).Free;
end;

function TPixieQtCanvas.MeasureText(const Text: string;
  Handle: TPixieFontHandle): TPixiePixel;
var
  Info: TPixieQtFont;
  WStr: WideString;
begin
  Result := 0;
  if Handle = 0 then Exit;
  Info := TPixieQtFont(Handle);
  if Info.MetricsHandle = nil then
  begin
    Result := Length(Text) * Info.Metrics.ChWidth;
    Exit;
  end;

  WStr := UTF8Decode(Text);
  Result := QFontMetrics_width(Info.MetricsHandle, @WStr);
end;

procedure TPixieQtCanvas.DrawText(const Text: string;
  Handle: TPixieFontHandle; Color: TPixieWebColor;
  X, Y, W, H: Single);
var
  Info: TPixieQtFont;
  QC: TQColor;
  WStr: WideString;
  Pt: TQtPointF;
begin
  if (Handle = 0) or (FPainter = nil) then Exit;
  Info := TPixieQtFont(Handle);
  if Info.Handle = nil then Exit;

  // Text decoration is drawn at the element level (TPixieHtmlTag.DrawBackground)

  QPainter_setFont(FPainter, Info.Handle);
  MakeColor(Color, QC);
  QPainter_setPen(FPainter, @QC);

  WStr := UTF8Decode(Text);
  // QPainter_drawText uses baseline position; Y is box top, so add ascent
  Pt.x := X;
  Pt.y := Y + Info.Metrics.Ascent;
  QPainter_drawText(FPainter, PQtPointF(@Pt), @WStr);
end;

function TPixieQtCanvas.PtToPx(Pt: Single): TPixiePixel;
begin
  Result := Trunc(Pt * 96.0 / 72.0);
end;

// ---------------------------------------------------------------------------
// Image
// ---------------------------------------------------------------------------

function TPixieQtCanvas.DecodeImageFile(
  const Path: string): TPixieImageHandle;
var
  Pic: TPicture;
  Bmp: TBitmap;
  RawImage: TLazIntfImage;
  PixelBuf: PByte;
  Pitch, ImgX, ImgY, ImgW, ImgH: Integer;
  Colour: TFPColor;
  Dst: PByte;
  A, R, G, B: Byte;
  Info: TPixieQtImage;
begin
  Result := 0;

  Pic := TPicture.Create;
  try
    try
      Pic.LoadFromFile(Path);
    except
      Exit;
    end;

    ImgW := Pic.Width;
    ImgH := Pic.Height;
    if (ImgW <= 0) or (ImgH <= 0) then Exit;

    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(ImgW, ImgH);
      Bmp.Canvas.Draw(0, 0, Pic.Graphic);

      RawImage := Bmp.CreateIntfImage;
      try
        Pitch := ImgW * 4;
        GetMem(PixelBuf, Pitch * ImgH);

        // Copy pixels as premultiplied BGRA (ARGB32_Premultiplied
        // on little-endian is BGRA in memory)
        for ImgY := 0 to ImgH - 1 do
        begin
          Dst := PixelBuf + ImgY * Pitch;
          for ImgX := 0 to ImgW - 1 do
          begin
            Colour := RawImage.Colors[ImgX, ImgY];
            A := Colour.Alpha shr 8;
            if A = 0 then
            begin
              Dst^ := 0; Inc(Dst);
              Dst^ := 0; Inc(Dst);
              Dst^ := 0; Inc(Dst);
              Dst^ := 0; Inc(Dst);
            end
            else if A = 255 then
            begin
              Dst^ := Colour.Blue shr 8; Inc(Dst);
              Dst^ := Colour.Green shr 8; Inc(Dst);
              Dst^ := Colour.Red shr 8; Inc(Dst);
              Dst^ := A; Inc(Dst);
            end
            else
            begin
              R := Colour.Red shr 8;
              G := Colour.Green shr 8;
              B := Colour.Blue shr 8;
              Dst^ := B * A div 255; Inc(Dst);
              Dst^ := G * A div 255; Inc(Dst);
              Dst^ := R * A div 255; Inc(Dst);
              Dst^ := A; Inc(Dst);
            end;
          end;
        end;

        Info := TPixieQtImage.Create;
        Info.Handle := QImage_Create(PByte(PixelBuf), ImgW, ImgH, Pitch,
          QImageFormat_ARGB32_Premultiplied);
        Info.PixelData := PixelBuf;
        Info.ImgWidth := ImgW;
        Info.ImgHeight := ImgH;
        Result := TPixieImageHandle(Info);
      finally
        RawImage.Free;
      end;
    finally
      Bmp.Free;
    end;
  finally
    Pic.Free;
  end;
end;

function TPixieQtCanvas.LoadImage(
  const Path: string): TPixieImageHandle;
var
  Resolved: string;
  WPath: WideString;
  Img: QImageH;
  Info: TPixieQtImage;
begin
  Result := 0;

  Resolved := ExpandFileName(Path);
  if not FileExists(Resolved) then Exit;

  // SVG — skip in phase 1
  if LowerCase(ExtractFileExt(Resolved)) = '.svg' then Exit;

  // Try native Qt image loading (PNG, JPEG, GIF, BMP, etc.)
  WPath := UTF8Decode(Resolved);
  Img := QImage_Create(PWideString(@WPath));
  if (Img <> nil) and (not QImage_isNull(Img)) then
  begin
    Info := TPixieQtImage.Create;
    Info.Handle := Img;
    Info.ImgWidth := QImage_width(Img);
    Info.ImgHeight := QImage_height(Img);
    Result := TPixieImageHandle(Info);
    Exit;
  end;

  if Img <> nil then
    QImage_Destroy(Img);

  // Fallback: decode via LCL
  Result := DecodeImageFile(Resolved);
end;

function TPixieQtCanvas.LoadImageFromPixels(Width, Height: Integer;
  Pixels: Pointer; Pitch: Integer): TPixieImageHandle;
var
  Info: TPixieQtImage;
  BufSize: Integer;
  PixelCopy: Pointer;
begin
  Result := 0;
  if (Width <= 0) or (Height <= 0) or (Pixels = nil) then Exit;

  // QImage references the data pointer directly (no copy),
  // so we make our own copy that outlives the caller's buffer
  BufSize := Pitch * Height;
  GetMem(PixelCopy, BufSize);
  Move(Pixels^, PixelCopy^, BufSize);

  Info := TPixieQtImage.Create;
  Info.Handle := QImage_Create(PByte(PixelCopy), Width, Height, Pitch,
    QImageFormat_ARGB32_Premultiplied);
  Info.PixelData := PixelCopy;
  Info.ImgWidth := Width;
  Info.ImgHeight := Height;
  Result := TPixieImageHandle(Info);
end;

procedure TPixieQtCanvas.FreeImage(Handle: TPixieImageHandle);
begin
  if Handle <> 0 then
    TPixieQtImage(Handle).Free;
end;

procedure TPixieQtCanvas.GetImageSize(Handle: TPixieImageHandle;
  out W, H: Single);
var
  Info: TPixieQtImage;
begin
  W := 0;
  H := 0;
  if Handle = 0 then Exit;
  Info := TPixieQtImage(Handle);
  W := Info.ImgWidth;
  H := Info.ImgHeight;
end;

procedure TPixieQtCanvas.DrawImage(Handle: TPixieImageHandle;
  DstX, DstY, DstW, DstH: Single);
var
  Info: TPixieQtImage;
begin
  if (Handle = 0) or (FPainter = nil) then Exit;
  Info := TPixieQtImage(Handle);
  if (Info.Handle = nil) or (Info.ImgWidth <= 0) or
     (Info.ImgHeight <= 0) then
    Exit;

  QRectF_setRect(FTempRect, DstX, DstY, DstW, DstH);
  QPainter_drawImage(FPainter, FTempRect, Info.Handle);
end;

// ---------------------------------------------------------------------------
// Simple shapes (list markers and form controls)
// ---------------------------------------------------------------------------

procedure TPixieQtCanvas.FillEllipse(X, Y, W, H: Single;
  Color: TPixieWebColor);
var
  QC: TQColor;
  Brush: QBrushH;
begin
  if (FPainter = nil) or (Color.Alpha = 0) then Exit;
  MakeColor(Color, QC);

  Brush := QBrush_Create(@QC);
  try
    QPainter_setPen(FPainter, QtNoPen);
    QPainter_setBrush(FPainter, Brush);
    QRectF_setRect(FTempRect, X, Y, W, H);
    QPainter_drawEllipse(FPainter, FTempRect);
  finally
    QBrush_Destroy(Brush);
  end;
end;

procedure TPixieQtCanvas.DrawEllipse(X, Y, W, H: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
var
  QC: TQColor;
  Pen: QPenH;
begin
  if (FPainter = nil) or (Color.Alpha = 0) then Exit;
  MakeColor(Color, QC);

  Pen := QPen_Create(@QC);
  try
    QPen_setWidthF(Pen, StrokeWidth);
    QPainter_setPen(FPainter, Pen);
    QPainter_setBrush(FPainter, QtNoBrush);
    QRectF_setRect(FTempRect, X, Y, W, H);
    QPainter_drawEllipse(FPainter, FTempRect);
  finally
    QPen_Destroy(Pen);
  end;
end;

procedure TPixieQtCanvas.DrawRect(X, Y, W, H: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
var
  QC: TQColor;
  Pen: QPenH;
begin
  if (FPainter = nil) or (Color.Alpha = 0) then Exit;
  MakeColor(Color, QC);

  Pen := QPen_Create(@QC);
  try
    QPen_setWidthF(Pen, StrokeWidth);
    QPainter_setPen(FPainter, Pen);
    QPainter_setBrush(FPainter, QtNoBrush);
    QRectF_setRect(FTempRect, X, Y, W, H);
    QPainter_drawRect(FPainter, FTempRect);
  finally
    QPen_Destroy(Pen);
  end;
end;

procedure TPixieQtCanvas.DrawLine(X1, Y1, X2, Y2: Single;
  Color: TPixieWebColor; StrokeWidth: Single;
  Style: TPixieTextDecorationStyle);
var
  QC: TQColor;
  Pen: QPenH;
  P1, P2: TQtPointF;
  Dashes: TQRealArray;
begin
  if (FPainter = nil) or (Color.Alpha = 0) then Exit;
  MakeColor(Color, QC);

  Pen := QPen_Create(@QC);
  try
    QPen_setWidthF(Pen, StrokeWidth);
    if Style = tdsDotted then
    begin
      SetLength(Dashes, 2);
      Dashes[0] := 1;
      Dashes[1] := 2;
      QPen_setDashPattern(Pen, @Dashes);
      QPen_setCapStyle(Pen, QtRoundCap);
    end
    else if Style = tdsDashed then
    begin
      SetLength(Dashes, 2);
      Dashes[0] := 3;
      Dashes[1] := 2;
      QPen_setDashPattern(Pen, @Dashes);
    end;
    QPainter_setPen(FPainter, Pen);
    P1.x := X1; P1.y := Y1;
    P2.x := X2; P2.y := Y2;
    QPainter_drawLine(FPainter, PQtPointF(@P1), PQtPointF(@P2));
  finally
    QPen_Destroy(Pen);
  end;
end;

procedure TPixieQtCanvas.StrokePolyline(const Points: array of Single;
  Color: TPixieWebColor; StrokeWidth: Single);
var
  Count, I: Integer;
  QC: TQColor;
  QtPts: array of TQtPointF;
  Pen: QPenH;
begin
  Count := Length(Points) div 2;
  if (FPainter = nil) or (Color.Alpha = 0) or (Count < 2) then Exit;

  SetLength(QtPts, Count);
  for I := 0 to Count - 1 do
  begin
    QtPts[I].x := Points[I * 2];
    QtPts[I].y := Points[I * 2 + 1];
  end;

  MakeColor(Color, QC);
  Pen := QPen_Create(@QC);
  try
    QPen_setWidthF(Pen, StrokeWidth);
    QPen_setCapStyle(Pen, QtRoundCap);
    QPen_setJoinStyle(Pen, QtRoundJoin);
    QPainter_setPen(FPainter, Pen);
    QPainter_drawPolyline(FPainter, PQtPointF(@QtPts[0]), Count);
  finally
    QPen_Destroy(Pen);
  end;
end;

// ---------------------------------------------------------------------------
// Scale / View size
// ---------------------------------------------------------------------------

procedure TPixieQtCanvas.SetViewSize(W, H: Integer; ACanvasScale: Single);
begin
  FViewWidth := W;
  FViewHeight := H;
end;

procedure TPixieQtCanvas.SetScale(Scale: Single);
begin
  FScale := Scale;
end;

end.
