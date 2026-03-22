unit Pixie.Canvas.CG;

// CoreGraphics + CoreText implementation of TPixieCanvas for macOS/Cocoa.
// Provides 2D drawing via Quartz 2D and text measurement/rendering via CoreText.
// SVG rendering uses Apple's private CoreSVG framework (macOS 10.15+).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Math,
  MacOSAll,
  CocoaGDIObjects,
  dl,
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.Background, Pixie.FontDescription,
  Pixie.Canvas;

type
  { TPixieCGFont }

  TPixieCGFont = class
    Font: CTFontRef;
    Metrics: TPixieFontMetrics;
    DecorationLine: Integer;
    destructor Destroy; override;
  end;

  { TPixieCGImage }

  TPixieCGImage = class
    Image: CGImageRef;
    SvgDocument: Pointer;
    ImgWidth: Integer;
    ImgHeight: Integer;
    destructor Destroy; override;
  end;

  TPixieCGSavedState = record
    ClipsPushed: Integer;
  end;

  { TPixieCGCanvas }

  TPixieCGCanvas = class(TPixieCanvas)
  private
    FCG: CGContextRef;
    FColorSpace: CGColorSpaceRef;
    FScale: Single;
    FCanvasScale: Single;
    FViewWidth, FViewHeight: Integer;
    FStateStack: array[0..63] of TPixieCGSavedState;
    FStateTop: Integer;

    function HasRadius(const R: TPixieBorderRadiuses): Boolean;
    procedure RoundedRectPath(X, Y, W, H: Single;
      const R: TPixieBorderRadiuses);
    procedure SetFillColor(const C: TPixieWebColor);
    procedure SetStrokeColor(const C: TPixieWebColor);
    procedure DrawBorderSide(const Border: TPixieBorder;
      X1, Y1, X2, Y2: Single);
    function LoadSvgFile(const Path: string): TPixieImageHandle;
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
      Color: TPixieWebColor; StrokeWidth: Single); override;
    procedure StrokePolyline(const Points: array of Single;
      Color: TPixieWebColor; StrokeWidth: Single); override;

    function LoadSvgFromData(Data: Pointer;
      Size: Integer): TPixieImageHandle; override;

    procedure SetViewSize(W, H: Integer; ACanvasScale: Single = 1); override;
    procedure SetScale(Scale: Single); override;
  end;

implementation

function CheckCGFont(const Name: string): Boolean;
var
  CFName: CFStringRef;
  Font: CTFontRef;
begin
  CFName := CFStringCreateWithCString(nil,
    PAnsiChar(Name), kCFStringEncodingUTF8);
  Font := CTFontCreateWithName(CFName, 12, nil);
  CFRelease(CFName);
  Result := Font <> nil;
  if Result then
    CFRelease(Font);
end;

// ---------------------------------------------------------------------------
// CoreSVG dynamic loading (private framework, available since macOS 10.15)
// ---------------------------------------------------------------------------

var
  CoreSVGLoaded: Boolean = False;

  CGSVGDocumentCreateFromData: function(Data: CFDataRef;
    Options: CFDictionaryRef): Pointer; cdecl = nil;
  CGSVGDocumentGetCanvasSize: function(
    Document: Pointer): CGSize; cdecl = nil;
  pCGContextDrawSVGDocument: procedure(Context: CGContextRef;
    Document: Pointer); cdecl = nil;
  CGSVGDocumentRelease: procedure(
    Document: Pointer); cdecl = nil;

procedure EnsureCoreSVG;
begin
  if CoreSVGLoaded then Exit;
  CoreSVGLoaded := True;
  @CGSVGDocumentCreateFromData :=
    dlsym(RTLD_DEFAULT, 'CGSVGDocumentCreateFromData');
  @CGSVGDocumentGetCanvasSize :=
    dlsym(RTLD_DEFAULT, 'CGSVGDocumentGetCanvasSize');
  @pCGContextDrawSVGDocument :=
    dlsym(RTLD_DEFAULT, 'CGContextDrawSVGDocument');
  @CGSVGDocumentRelease :=
    dlsym(RTLD_DEFAULT, 'CGSVGDocumentRelease');
end;

// ---------------------------------------------------------------------------
// TPixieCGFont / TPixieCGImage destructors
// ---------------------------------------------------------------------------

destructor TPixieCGFont.Destroy;
begin
  if Font <> nil then
    CFRelease(Font);
  inherited;
end;

destructor TPixieCGImage.Destroy;
begin
  if Image <> nil then
    CGImageRelease(Image);
  if (SvgDocument <> nil) and Assigned(CGSVGDocumentRelease) then
    CGSVGDocumentRelease(SvgDocument);
  inherited;
end;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function TPixieCGCanvas.HasRadius(
  const R: TPixieBorderRadiuses): Boolean;
begin
  Result := (R.TopLeftX > 0) or (R.TopLeftY > 0) or
            (R.TopRightX > 0) or (R.TopRightY > 0) or
            (R.BottomRightX > 0) or (R.BottomRightY > 0) or
            (R.BottomLeftX > 0) or (R.BottomLeftY > 0);
end;

procedure TPixieCGCanvas.SetFillColor(const C: TPixieWebColor);
begin
  CGContextSetRGBFillColor(FCG,
    C.Red / 255.0, C.Green / 255.0,
    C.Blue / 255.0, C.Alpha / 255.0);
end;

procedure TPixieCGCanvas.SetStrokeColor(const C: TPixieWebColor);
begin
  CGContextSetRGBStrokeColor(FCG,
    C.Red / 255.0, C.Green / 255.0,
    C.Blue / 255.0, C.Alpha / 255.0);
end;

procedure TPixieCGCanvas.RoundedRectPath(X, Y, W, H: Single;
  const R: TPixieBorderRadiuses);
begin
  // Build a rounded-rect path using arc segments for elliptical corners.
  // Uses CGContext path ops with save/scale for elliptical radii,
  // same approach as the Cairo backend.
  CGContextBeginPath(FCG);
  CGContextMoveToPoint(FCG, X, Y + R.TopLeftY);

  // Top-left arc
  if (R.TopLeftX > 0) and (R.TopLeftY > 0) then
  begin
    CGContextSaveGState(FCG);
    CGContextTranslateCTM(FCG, X + R.TopLeftX, Y + R.TopLeftY);
    CGContextScaleCTM(FCG, R.TopLeftX, R.TopLeftY);
    CGContextAddArc(FCG, 0, 0, 1, Pi, 3 * Pi / 2, 0);
    CGContextRestoreGState(FCG);
  end
  else
    CGContextAddLineToPoint(FCG, X, Y);

  // Top edge
  CGContextAddLineToPoint(FCG, X + W - R.TopRightX, Y);

  // Top-right arc
  if (R.TopRightX > 0) and (R.TopRightY > 0) then
  begin
    CGContextSaveGState(FCG);
    CGContextTranslateCTM(FCG, X + W - R.TopRightX, Y + R.TopRightY);
    CGContextScaleCTM(FCG, R.TopRightX, R.TopRightY);
    CGContextAddArc(FCG, 0, 0, 1, 3 * Pi / 2, 2 * Pi, 0);
    CGContextRestoreGState(FCG);
  end
  else
    CGContextAddLineToPoint(FCG, X + W, Y);

  // Right edge
  CGContextAddLineToPoint(FCG, X + W, Y + H - R.BottomRightY);

  // Bottom-right arc
  if (R.BottomRightX > 0) and (R.BottomRightY > 0) then
  begin
    CGContextSaveGState(FCG);
    CGContextTranslateCTM(FCG, X + W - R.BottomRightX,
      Y + H - R.BottomRightY);
    CGContextScaleCTM(FCG, R.BottomRightX, R.BottomRightY);
    CGContextAddArc(FCG, 0, 0, 1, 0, Pi / 2, 0);
    CGContextRestoreGState(FCG);
  end
  else
    CGContextAddLineToPoint(FCG, X + W, Y + H);

  // Bottom edge
  CGContextAddLineToPoint(FCG, X + R.BottomLeftX, Y + H);

  // Bottom-left arc
  if (R.BottomLeftX > 0) and (R.BottomLeftY > 0) then
  begin
    CGContextSaveGState(FCG);
    CGContextTranslateCTM(FCG, X + R.BottomLeftX,
      Y + H - R.BottomLeftY);
    CGContextScaleCTM(FCG, R.BottomLeftX, R.BottomLeftY);
    CGContextAddArc(FCG, 0, 0, 1, Pi / 2, Pi, 0);
    CGContextRestoreGState(FCG);
  end
  else
    CGContextAddLineToPoint(FCG, X, Y + H);

  CGContextClosePath(FCG);
end;

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieCGCanvas.Create;
begin
  inherited Create;
  FCG := nil;
  FColorSpace := CGColorSpaceCreateDeviceRGB;
  FScale := 1.0;
  FCanvasScale := 1.0;
  FViewWidth := 800;
  FViewHeight := 600;
  FStateTop := 0;
end;

destructor TPixieCGCanvas.Destroy;
begin
  if FColorSpace <> nil then
    CGColorSpaceRelease(FColorSpace);
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.BeginPaint(DC: PtrUInt);
var
  CocoaCtx: TCocoaContext;
begin
  FStateTop := 0;
  CocoaCtx := TCocoaContext(DC);
  FCG := CocoaCtx.CGContext;
  if FCG = nil then Exit;
  CGContextSaveGState(FCG);
  CGContextScaleCTM(FCG, FScale, FScale);
end;

procedure TPixieCGCanvas.EndPaint;
begin
  if FCG <> nil then
  begin
    CGContextRestoreGState(FCG);
    FCG := nil;
  end;
end;

// ---------------------------------------------------------------------------
// State save/restore
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.SaveState;
begin
  if (FCG = nil) or (FStateTop > High(FStateStack)) then Exit;

  CGContextSaveGState(FCG);
  FStateStack[FStateTop].ClipsPushed := 0;
  Inc(FStateTop);
end;

procedure TPixieCGCanvas.RestoreState;
var
  I: Integer;
begin
  if (FCG = nil) or (FStateTop <= 0) then Exit;
  Dec(FStateTop);

  for I := 0 to FStateStack[FStateTop].ClipsPushed - 1 do
    CGContextRestoreGState(FCG);

  CGContextRestoreGState(FCG);
end;

procedure TPixieCGCanvas.PushOpacity(AOpacity: Single);
begin
  if FCG = nil then Exit;
  CGContextSaveGState(FCG);
  CGContextSetAlpha(FCG, AOpacity);
  CGContextBeginTransparencyLayer(FCG, nil);
end;

procedure TPixieCGCanvas.PopOpacity;
begin
  if FCG = nil then Exit;
  CGContextEndTransparencyLayer(FCG);
  CGContextRestoreGState(FCG);
end;

// ---------------------------------------------------------------------------
// Clipping
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.SetClipRect(const R: TPixiePosition;
  const Radius: TPixieBorderRadiuses);
begin
  if FCG = nil then Exit;

  CGContextSaveGState(FCG);

  if HasRadius(Radius) then
  begin
    RoundedRectPath(R.X, R.Y, R.Width, R.Height, Radius);
    CGContextClip(FCG);
  end
  else
    CGContextClipToRect(FCG, CGRectMake(R.X, R.Y, R.Width, R.Height));

  if FStateTop > 0 then
    Inc(FStateStack[FStateTop - 1].ClipsPushed);
end;

// ---------------------------------------------------------------------------
// Solid fills
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.FillRect(X, Y, W, H: Single;
  Color: TPixieWebColor);
begin
  if (FCG = nil) or (Color.Alpha = 0) then Exit;
  SetFillColor(Color);
  CGContextFillRect(FCG, CGRectMake(X, Y, W, H));
end;

procedure TPixieCGCanvas.FillRoundedRect(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses; Color: TPixieWebColor);
begin
  if (FCG = nil) or (Color.Alpha = 0) then Exit;
  SetFillColor(Color);

  if HasRadius(Radius) then
  begin
    RoundedRectPath(X, Y, W, H, Radius);
    CGContextFillPath(FCG);
  end
  else
    CGContextFillRect(FCG, CGRectMake(X, Y, W, H));
end;

// ---------------------------------------------------------------------------
// Gradients
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.FillLinearGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieLinearGradientLayer);
var
  Components: array of CGFloat;
  Locations: array of CGFloat;
  I, Count: Integer;
  Cp: TPixieColorPoint;
  Grad: CGGradientRef;
begin
  if (FCG = nil) or (Gradient = nil) then Exit;
  Count := Gradient.ColorPoints.Count;
  if Count < 2 then Exit;

  SetLength(Components, Count * 4);
  SetLength(Locations, Count);

  for I := 0 to Count - 1 do
  begin
    Cp := Gradient.ColorPoints[I];
    Components[I * 4 + 0] := Cp.Color.Red / 255.0;
    Components[I * 4 + 1] := Cp.Color.Green / 255.0;
    Components[I * 4 + 2] := Cp.Color.Blue / 255.0;
    Components[I * 4 + 3] := Cp.Color.Alpha / 255.0;
    Locations[I] := Cp.Offset;
  end;

  Grad := CGGradientCreateWithColorComponents(FColorSpace,
    @Components[0], @Locations[0], Count);
  if Grad = nil then Exit;
  try
    CGContextSaveGState(FCG);
    try
      if HasRadius(Radius) then
      begin
        RoundedRectPath(X, Y, W, H, Radius);
        CGContextClip(FCG);
      end
      else
        CGContextClipToRect(FCG, CGRectMake(X, Y, W, H));

      CGContextDrawLinearGradient(FCG, Grad,
        CGPointMake(Gradient.StartPt.X, Gradient.StartPt.Y),
        CGPointMake(Gradient.EndPt.X, Gradient.EndPt.Y),
        kCGGradientDrawsBeforeStartLocation or
          kCGGradientDrawsAfterEndLocation);
    finally
      CGContextRestoreGState(FCG);
    end;
  finally
    CGGradientRelease(Grad);
  end;
end;

procedure TPixieCGCanvas.FillRadialGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieRadialGradientLayer);
var
  Components: array of CGFloat;
  Locations: array of CGFloat;
  I, Count: Integer;
  Cp: TPixieColorPoint;
  Grad: CGGradientRef;
  Cx, Cy, Rx, Ry: Single;
begin
  if (FCG = nil) or (Gradient = nil) then Exit;
  Count := Gradient.ColorPoints.Count;
  if Count < 2 then Exit;

  Cx := Gradient.Position.X;
  Cy := Gradient.Position.Y;
  Rx := Gradient.Radius.X;
  Ry := Gradient.Radius.Y;
  if (Rx < 0.001) or (Ry < 0.001) then Exit;

  SetLength(Components, Count * 4);
  SetLength(Locations, Count);

  for I := 0 to Count - 1 do
  begin
    Cp := Gradient.ColorPoints[I];
    Components[I * 4 + 0] := Cp.Color.Red / 255.0;
    Components[I * 4 + 1] := Cp.Color.Green / 255.0;
    Components[I * 4 + 2] := Cp.Color.Blue / 255.0;
    Components[I * 4 + 3] := Cp.Color.Alpha / 255.0;
    Locations[I] := Cp.Offset;
  end;

  Grad := CGGradientCreateWithColorComponents(FColorSpace,
    @Components[0], @Locations[0], Count);
  if Grad = nil then Exit;
  try
    CGContextSaveGState(FCG);
    try
      // Scale Y to form ellipse (same technique as Cairo)
      CGContextScaleCTM(FCG, 1.0, Ry / Rx);

      if HasRadius(Radius) then
      begin
        RoundedRectPath(X, Y * Rx / Ry, W, H * Rx / Ry, Radius);
        CGContextClip(FCG);
      end
      else
        CGContextClipToRect(FCG,
          CGRectMake(X, Y * Rx / Ry, W, H * Rx / Ry));

      CGContextDrawRadialGradient(FCG, Grad,
        CGPointMake(Cx, Cy * Rx / Ry), 0,
        CGPointMake(Cx, Cy * Rx / Ry), Rx,
        kCGGradientDrawsBeforeStartLocation or
          kCGGradientDrawsAfterEndLocation);
    finally
      CGContextRestoreGState(FCG);
    end;
  finally
    CGGradientRelease(Grad);
  end;
end;

procedure TPixieCGCanvas.FillConicGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieConicGradientLayer);
var
  Count, I, J, Steps: Integer;
  Cx, Cy, MaxR, Angle, Frac: Single;
  Cp: TPixieColorPoint;
  C: TPixieWebColor;
  StartAngle, SweepAngle, CosA, SinA, CosB, SinB: Single;
begin
  if (FCG = nil) or (Gradient = nil) then Exit;
  Count := Gradient.ColorPoints.Count;
  if Count < 2 then Exit;

  Cx := Gradient.Position.X;
  Cy := Gradient.Position.Y;
  MaxR := Max(Max(Abs(X + W - Cx), Abs(X - Cx)),
              Max(Abs(Y + H - Cy), Abs(Y - Cy))) * 1.5;
  if MaxR < 1 then MaxR := 1;

  SaveState;
  try
    if HasRadius(Radius) then
      SetClipRect(TPixiePosition.Create(X, Y, W, H), Radius)
    else
    begin
      CGContextSaveGState(FCG);
      CGContextClipToRect(FCG, CGRectMake(X, Y, W, H));
      if FStateTop > 0 then
        Inc(FStateStack[FStateTop - 1].ClipsPushed);
    end;

    Steps := 360;
    SweepAngle := 2 * Pi / Steps;

    for J := 0 to Steps - 1 do
    begin
      Angle := J / Steps;

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

      SetFillColor(C);

      StartAngle := (Gradient.Angle - 90 + J * (360.0 / Steps)) * Pi / 180.0;

      SinCos(StartAngle, SinA, CosA);
      SinCos(StartAngle + SweepAngle, SinB, CosB);

      CGContextBeginPath(FCG);
      CGContextMoveToPoint(FCG, Cx, Cy);
      CGContextAddLineToPoint(FCG, Cx + CosA * MaxR, Cy + SinA * MaxR);
      CGContextAddLineToPoint(FCG, Cx + CosB * MaxR, Cy + SinB * MaxR);
      CGContextClosePath(FCG);
      CGContextFillPath(FCG);
    end;
  finally
    RestoreState;
  end;
end;

// ---------------------------------------------------------------------------
// Borders
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.DrawBorderSide(const Border: TPixieBorder;
  X1, Y1, X2, Y2: Single);
var
  LineW, Offset, Dx, Dy, Len, Nx, Ny: Single;
  Dashes: array[0..1] of CGFloat;
begin
  if (Border.Width <= 0) or (Border.Style = bsNone) or
     (Border.Style = bsHidden) then
    Exit;

  SetStrokeColor(Border.Color);

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

    CGContextSetLineWidth(FCG, LineW);
    // Outer line
    CGContextBeginPath(FCG);
    CGContextMoveToPoint(FCG, X1 - Nx * Offset, Y1 - Ny * Offset);
    CGContextAddLineToPoint(FCG, X2 - Nx * Offset, Y2 - Ny * Offset);
    CGContextStrokePath(FCG);
    // Inner line
    CGContextBeginPath(FCG);
    CGContextMoveToPoint(FCG, X1 + Nx * Offset, Y1 + Ny * Offset);
    CGContextAddLineToPoint(FCG, X2 + Nx * Offset, Y2 + Ny * Offset);
    CGContextStrokePath(FCG);
    Exit;
  end;

  CGContextSetLineWidth(FCG, Border.Width);

  case Border.Style of
    bsDotted:
    begin
      Dashes[0] := Border.Width;
      Dashes[1] := Border.Width;
      CGContextSetLineDash(FCG, 0, @Dashes[0], 2);
    end;
    bsDashed:
    begin
      Dashes[0] := Border.Width * 3;
      Dashes[1] := Border.Width * 3;
      CGContextSetLineDash(FCG, 0, @Dashes[0], 2);
    end;
  else
    CGContextSetLineDash(FCG, 0, nil, 0);
  end;

  CGContextBeginPath(FCG);
  CGContextMoveToPoint(FCG, X1, Y1);
  CGContextAddLineToPoint(FCG, X2, Y2);
  CGContextStrokePath(FCG);

  CGContextSetLineDash(FCG, 0, nil, 0);
end;

procedure TPixieCGCanvas.DrawBorders(const Borders: TPixieBorders;
  const Pos: TPixiePosition; IsRoot: Boolean);
var
  X, Y, W, H: Single;
begin
  if FCG = nil then Exit;
  if not Borders.IsVisible then Exit;

  X := Pos.X;
  Y := Pos.Y;
  W := Pos.Width;
  H := Pos.Height;

  if HasRadius(Borders.Radius) then
  begin
    if (Borders.Top.Width > 0) and (Borders.Top.Style <> bsNone) then
    begin
      SetStrokeColor(Borders.Top.Color);
      CGContextSetLineWidth(FCG, Borders.Top.Width);
      RoundedRectPath(X, Y, W, H, Borders.Radius);
      CGContextStrokePath(FCG);
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

function TPixieCGCanvas.CreateFont(
  const Descr: TPixieFontDescription;
  out Metrics: TPixieFontMetrics): TPixieFontHandle;
var
  Info: TPixieCGFont;
  CFName: CFStringRef;
  BaseFont, StyledFont: CTFontRef;
  TraitValue, TraitMask: CTFontSymbolicTraits;
  Ascent, Descent, Leading: CGFloat;
  ResolvedFamily: string;
begin
  Result := 0;
  Info := TPixieCGFont.Create;
  Info.DecorationLine := Descr.DecorationLine;

  // Resolve CSS font-family list
  ResolvedFamily := PixieResolveFontFamily(Descr.Family, CheckCGFont);
  if ResolvedFamily <> '' then
    CFName := CFStringCreateWithCString(nil,
      PAnsiChar(ResolvedFamily), kCFStringEncodingUTF8)
  else
    CFName := CFStringCreateWithCString(nil,
      'Helvetica', kCFStringEncodingUTF8);

  // CoreText sizes are in points (72/inch); Descr.Size is CSS pixels (96/inch)
  BaseFont := CTFontCreateWithName(CFName, Descr.Size * 72.0 / 96.0, nil);
  CFRelease(CFName);

  // Apply bold/italic traits if needed
  TraitValue := 0;
  TraitMask := 0;

  if Descr.Weight >= 700 then
  begin
    TraitValue := TraitValue or kCTFontTraitBold;
    TraitMask := TraitMask or kCTFontTraitBold;
  end;

  if Descr.Style = fstItalic then
  begin
    TraitValue := TraitValue or kCTFontTraitItalic;
    TraitMask := TraitMask or kCTFontTraitItalic;
  end;

  if (TraitMask <> 0) and (BaseFont <> nil) then
  begin
    StyledFont := CTFontCreateCopyWithSymbolicTraits(
      BaseFont, 0, nil, TraitValue, TraitMask);
    if StyledFont <> nil then
    begin
      CFRelease(BaseFont);
      BaseFont := StyledFont;
    end;
    // If CTFontCreateCopyWithSymbolicTraits returns nil (font doesn't
    // have the requested trait), keep the base font.
  end;

  Info.Font := BaseFont;

  // Get metrics from CoreText
  if BaseFont <> nil then
  begin
    Ascent := CTFontGetAscent(BaseFont);
    Descent := CTFontGetDescent(BaseFont);
    Leading := CTFontGetLeading(BaseFont);

    Metrics.Ascent := Ascent;
    Metrics.Descent := Descent;
    Metrics.Height := Ascent + Descent + Leading;
    Metrics.XHeight := CTFontGetXHeight(BaseFont);
  end
  else
  begin
    Metrics.Height := Descr.Size * 1.2;
    Metrics.Ascent := Descr.Size * 0.8;
    Metrics.Descent := Metrics.Height - Metrics.Ascent;
    Metrics.XHeight := Descr.Size * 0.5;
  end;

  Metrics.FontSize := Descr.Size;
  Metrics.ChWidth := Descr.Size * 0.6;
  Metrics.DrawSpaces := True;
  Metrics.SubShift := 0;
  Metrics.SuperShift := 0;
  Info.Metrics := Metrics;

  Result := TPixieFontHandle(Info);
end;

procedure TPixieCGCanvas.DeleteFont(Handle: TPixieFontHandle);
begin
  if Handle <> 0 then
    TPixieCGFont(Handle).Free;
end;

function TPixieCGCanvas.MeasureText(const Text: string;
  Handle: TPixieFontHandle): TPixiePixel;
var
  Info: TPixieCGFont;
  CFText: CFStringRef;
  AttrStr: CFAttributedStringRef;
  Attrs: CFMutableDictionaryRef;
  Line: CTLineRef;
  Width: Float64;
begin
  Result := 0;
  if Handle = 0 then Exit;
  Info := TPixieCGFont(Handle);
  if Info.Font = nil then
  begin
    Result := Length(Text) * Info.Metrics.ChWidth;
    Exit;
  end;
  if Text = '' then Exit;

  CFText := CFStringCreateWithCString(nil,
    PAnsiChar(Text), kCFStringEncodingUTF8);
  if CFText = nil then Exit;
  try
    Attrs := CFDictionaryCreateMutable(nil, 1,
      @kCFTypeDictionaryKeyCallBacks, @kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(Attrs, kCTFontAttributeName, Info.Font);

    AttrStr := CFAttributedStringCreate(nil, CFText, Attrs);
    CFRelease(Attrs);
    if AttrStr = nil then Exit;
    try
      Line := CTLineCreateWithAttributedString(AttrStr);
      if Line = nil then Exit;
      try
        Width := CTLineGetTypographicBounds(Line, nil, nil, nil);
        Result := Width;
      finally
        CFRelease(Line);
      end;
    finally
      CFRelease(AttrStr);
    end;
  finally
    CFRelease(CFText);
  end;
end;

procedure TPixieCGCanvas.DrawText(const Text: string;
  Handle: TPixieFontHandle; Color: TPixieWebColor;
  X, Y, W, H: Single);
var
  Info: TPixieCGFont;
  CFText: CFStringRef;
  AttrStr: CFAttributedStringRef;
  Attrs: CFMutableDictionaryRef;
  Line: CTLineRef;
  CGColor_: CGColorRef;
  Components: array[0..3] of CGFloat;
begin
  if (Handle = 0) or (FCG = nil) then Exit;
  Info := TPixieCGFont(Handle);
  if Info.Font = nil then Exit;
  if Text = '' then Exit;

  CFText := CFStringCreateWithCString(nil,
    PAnsiChar(Text), kCFStringEncodingUTF8);
  if CFText = nil then Exit;
  try
    // Create color for text attribute
    Components[0] := Color.Red / 255.0;
    Components[1] := Color.Green / 255.0;
    Components[2] := Color.Blue / 255.0;
    Components[3] := Color.Alpha / 255.0;
    CGColor_ := CGColorCreate(FColorSpace, @Components[0]);

    Attrs := CFDictionaryCreateMutable(nil, 2,
      @kCFTypeDictionaryKeyCallBacks, @kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(Attrs, kCTFontAttributeName, Info.Font);
    CFDictionarySetValue(Attrs, kCTForegroundColorAttributeName, CGColor_);

    AttrStr := CFAttributedStringCreate(nil, CFText, Attrs);
    CFRelease(Attrs);
    CGColorRelease(CGColor_);
    if AttrStr = nil then Exit;
    try
      Line := CTLineCreateWithAttributedString(AttrStr);
      if Line = nil then Exit;
      try
        // CoreText draws from the baseline. In our flipped coordinate
        // system, Y increases downward. The text position Y should be
        // at Y + Ascent (the baseline measured from the top of the
        // text box).
        //
        // However, CTLineDraw uses the text matrix which operates in
        // the native CG coordinate system. Since Cocoa flips the view
        // (isFlipped = YES), the CGContext Y-axis goes top-down. But
        // CTLineDraw still expects the glyph Y-axis to go upward from
        // the baseline. We need to flip the text matrix locally.
        CGContextSaveGState(FCG);
        try
          // Flip vertically at the text position so glyphs render right-side up
          CGContextTranslateCTM(FCG, X, Y + Info.Metrics.Ascent);
          CGContextScaleCTM(FCG, 1, -1);
          CGContextSetTextPosition(FCG, 0, 0);
          CTLineDraw(Line, FCG);
        finally
          CGContextRestoreGState(FCG);
        end;

        // Text decoration is drawn at the element level (TPixieHtmlTag.DrawBackground)
      finally
        CFRelease(Line);
      end;
    finally
      CFRelease(AttrStr);
    end;
  finally
    CFRelease(CFText);
  end;
end;

function TPixieCGCanvas.PtToPx(Pt: Single): TPixiePixel;
begin
  Result := Trunc(Pt * 96.0 / 72.0);
end;

// ---------------------------------------------------------------------------
// Image loading
// ---------------------------------------------------------------------------

function TPixieCGCanvas.LoadSvgFile(
  const Path: string): TPixieImageHandle;
var
  Stream: TFileStream;
  Buf: Pointer;
  BufSize: Integer;
begin
  Result := 0;
  if not FileExists(Path) then Exit;
  try
    Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
    try
      BufSize := Stream.Size;
      if BufSize <= 0 then Exit;
      GetMem(Buf, BufSize);
      try
        Stream.ReadBuffer(Buf^, BufSize);
        Result := LoadSvgFromData(Buf, BufSize);
      finally
        FreeMem(Buf);
      end;
    finally
      Stream.Free;
    end;
  except
  end;
end;

function TPixieCGCanvas.LoadSvgFromData(Data: Pointer;
  Size: Integer): TPixieImageHandle;
var
  Info: TPixieCGImage;
  CFData_: CFDataRef;
  SvgDoc: Pointer;
  DocSize: CGSize;
begin
  Result := 0;
  if (Data = nil) or (Size <= 0) then Exit;

  EnsureCoreSVG;
  if not Assigned(CGSVGDocumentCreateFromData) or
     not Assigned(CGSVGDocumentGetCanvasSize) then Exit;

  CFData_ := CFDataCreate(nil, Data, Size);
  if CFData_ = nil then Exit;
  try
    SvgDoc := CGSVGDocumentCreateFromData(CFData_, nil);
  finally
    CFRelease(CFData_);
  end;

  if SvgDoc = nil then Exit;

  DocSize := CGSVGDocumentGetCanvasSize(SvgDoc);

  Info := TPixieCGImage.Create;
  Info.SvgDocument := SvgDoc;
  Info.ImgWidth := Round(DocSize.width);
  Info.ImgHeight := Round(DocSize.height);
  if Info.ImgWidth < 1 then Info.ImgWidth := 1;
  if Info.ImgHeight < 1 then Info.ImgHeight := 1;
  Result := TPixieImageHandle(Info);
end;

function TPixieCGCanvas.LoadImage(
  const Path: string): TPixieImageHandle;
var
  Info: TPixieCGImage;
  Resolved: string;
  CFPath: CFStringRef;
  FileUrl: CFURLRef;
  ImageSource: CGImageSourceRef;
  Img: CGImageRef;
begin
  Result := 0;

  Resolved := ExpandFileName(Path);
  if not FileExists(Resolved) then Exit;

  // SVG — render via CoreSVG
  if LowerCase(ExtractFileExt(Resolved)) = '.svg' then
  begin
    Result := LoadSvgFile(Resolved);
    Exit;
  end;

  // Raster images via ImageIO (supports PNG, JPEG, GIF, BMP, TIFF, ICO)
  CFPath := CFStringCreateWithCString(nil,
    PAnsiChar(Resolved), kCFStringEncodingUTF8);
  if CFPath = nil then Exit;
  try
    FileUrl := CFURLCreateWithFileSystemPath(nil, CFPath,
      kCFURLPOSIXPathStyle, False);
    if FileUrl = nil then Exit;
    try
      ImageSource := CGImageSourceCreateWithURL(FileUrl, nil);
      if ImageSource = nil then Exit;
      try
        Img := CGImageSourceCreateImageAtIndex(ImageSource, 0, nil);
        if Img = nil then Exit;

        Info := TPixieCGImage.Create;
        Info.Image := Img;
        Info.ImgWidth := CGImageGetWidth(Img);
        Info.ImgHeight := CGImageGetHeight(Img);
        Result := TPixieImageHandle(Info);
      finally
        CFRelease(ImageSource);
      end;
    finally
      CFRelease(FileUrl);
    end;
  finally
    CFRelease(CFPath);
  end;
end;

function TPixieCGCanvas.LoadImageFromPixels(Width, Height: Integer;
  Pixels: Pointer; Pitch: Integer): TPixieImageHandle;
var
  Info: TPixieCGImage;
  BmpCtx: CGContextRef;
  Img: CGImageRef;
  BufSize: Integer;
  PixelCopy: Pointer;
begin
  Result := 0;
  if (Width <= 0) or (Height <= 0) or (Pixels = nil) then Exit;

  // We need to copy the pixel data since CGBitmapContext doesn't own it
  BufSize := Pitch * Height;
  GetMem(PixelCopy, BufSize);
  Move(Pixels^, PixelCopy^, BufSize);

  BmpCtx := CGBitmapContextCreate(PixelCopy, Width, Height, 8, Pitch,
    FColorSpace,
    kCGImageAlphaPremultipliedFirst or kCGBitmapByteOrder32Little);

  if BmpCtx = nil then
  begin
    FreeMem(PixelCopy);
    Exit;
  end;

  Img := CGBitmapContextCreateImage(BmpCtx);
  CGContextRelease(BmpCtx);
  FreeMem(PixelCopy);

  if Img = nil then Exit;

  Info := TPixieCGImage.Create;
  Info.Image := Img;
  Info.ImgWidth := Width;
  Info.ImgHeight := Height;
  Result := TPixieImageHandle(Info);
end;

procedure TPixieCGCanvas.FreeImage(Handle: TPixieImageHandle);
begin
  if Handle <> 0 then
    TPixieCGImage(Handle).Free;
end;

procedure TPixieCGCanvas.GetImageSize(Handle: TPixieImageHandle;
  out W, H: Single);
var
  Info: TPixieCGImage;
begin
  W := 0;
  H := 0;
  if Handle = 0 then Exit;
  Info := TPixieCGImage(Handle);
  W := Info.ImgWidth;
  H := Info.ImgHeight;
end;

procedure TPixieCGCanvas.DrawImage(Handle: TPixieImageHandle;
  DstX, DstY, DstW, DstH: Single);
var
  Info: TPixieCGImage;
  Sx, Sy, BackingScale: Single;
  BmpCtx: CGContextRef;
  SvgImg: CGImageRef;
  PixW, PixH: Integer;
begin
  if (Handle = 0) or (FCG = nil) then Exit;
  Info := TPixieCGImage(Handle);
  if (Info.ImgWidth <= 0) or (Info.ImgHeight <= 0) then Exit;

  // SVG — render into an offscreen bitmap, then draw the bitmap.
  // CGContextDrawSVGDocument (private CoreSVG API) corrupts the caller's
  // CGContext state stack, so we must isolate it in a separate context.
  // The bitmap is created at device-pixel resolution (Retina-aware).
  if (Info.SvgDocument <> nil) and Assigned(pCGContextDrawSVGDocument) then
  begin
    // Scale bitmap to device pixels (Retina × zoom) for crisp rendering.
    BackingScale := FCanvasScale * FScale;
    if BackingScale < 1 then BackingScale := 1;

    PixW := Round(DstW * BackingScale);
    PixH := Round(DstH * BackingScale);
    if (PixW < 1) or (PixH < 1) then Exit;

    BmpCtx := CGBitmapContextCreate(nil, PixW, PixH, 8, PixW * 4,
      FColorSpace,
      kCGImageAlphaPremultipliedFirst or kCGBitmapByteOrder32Little);
    if BmpCtx = nil then Exit;
    try
      Sx := PixW / Info.ImgWidth;
      Sy := PixH / Info.ImgHeight;
      CGContextScaleCTM(BmpCtx, Sx, Sy);
      pCGContextDrawSVGDocument(BmpCtx, Info.SvgDocument);

      SvgImg := CGBitmapContextCreateImage(BmpCtx);
    finally
      CGContextRelease(BmpCtx);
    end;
    if SvgImg = nil then Exit;
    try
      CGContextSaveGState(FCG);
      try
        CGContextTranslateCTM(FCG, DstX, DstY + DstH);
        CGContextScaleCTM(FCG, 1, -1);
        CGContextDrawImage(FCG, CGRectMake(0, 0, DstW, DstH), SvgImg);
      finally
        CGContextRestoreGState(FCG);
      end;
    finally
      CGImageRelease(SvgImg);
    end;
    Exit;
  end;

  // Raster image
  if Info.Image = nil then Exit;

  // CGContextDrawImage draws images in the native CG coordinate system.
  // Since Cocoa's flipped view makes Y go top-down, images would appear
  // upside-down. We flip vertically around the destination rect center.
  CGContextSaveGState(FCG);
  try
    CGContextTranslateCTM(FCG, DstX, DstY + DstH);
    CGContextScaleCTM(FCG, 1, -1);
    CGContextDrawImage(FCG, CGRectMake(0, 0, DstW, DstH), Info.Image);
  finally
    CGContextRestoreGState(FCG);
  end;
end;

// ---------------------------------------------------------------------------
// Simple shapes (list markers)
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.FillEllipse(X, Y, W, H: Single;
  Color: TPixieWebColor);
begin
  if (FCG = nil) or (Color.Alpha = 0) then Exit;
  SetFillColor(Color);
  CGContextFillEllipseInRect(FCG, CGRectMake(X, Y, W, H));
end;

procedure TPixieCGCanvas.DrawEllipse(X, Y, W, H: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
begin
  if (FCG = nil) or (Color.Alpha = 0) then Exit;
  SetStrokeColor(Color);
  CGContextSetLineWidth(FCG, StrokeWidth);
  CGContextStrokeEllipseInRect(FCG, CGRectMake(X, Y, W, H));
end;

procedure TPixieCGCanvas.DrawRect(X, Y, W, H: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
begin
  if (FCG = nil) or (Color.Alpha = 0) then Exit;
  SetStrokeColor(Color);
  CGContextSetLineWidth(FCG, StrokeWidth);
  CGContextStrokeRect(FCG, CGRectMake(X, Y, W, H));
end;

procedure TPixieCGCanvas.DrawLine(X1, Y1, X2, Y2: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
begin
  if (FCG = nil) or (Color.Alpha = 0) then Exit;
  SetStrokeColor(Color);
  CGContextSetLineWidth(FCG, StrokeWidth);
  CGContextBeginPath(FCG);
  CGContextMoveToPoint(FCG, X1, Y1);
  CGContextAddLineToPoint(FCG, X2, Y2);
  CGContextStrokePath(FCG);
end;

procedure TPixieCGCanvas.StrokePolyline(const Points: array of Single;
  Color: TPixieWebColor; StrokeWidth: Single);
var
  Count, I: Integer;
begin
  Count := Length(Points) div 2;
  if (FCG = nil) or (Color.Alpha = 0) or (Count < 2) then Exit;
  SetStrokeColor(Color);
  CGContextSetLineWidth(FCG, StrokeWidth);
  CGContextSetLineCap(FCG, kCGLineCapRound);
  CGContextSetLineJoin(FCG, kCGLineJoinRound);
  CGContextBeginPath(FCG);
  CGContextMoveToPoint(FCG, Points[0], Points[1]);
  for I := 1 to Count - 1 do
    CGContextAddLineToPoint(FCG, Points[I * 2], Points[I * 2 + 1]);
  CGContextStrokePath(FCG);
  CGContextSetLineCap(FCG, kCGLineCapButt);
  CGContextSetLineJoin(FCG, kCGLineJoinMiter);
end;

// ---------------------------------------------------------------------------
// Scale / View size
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.SetViewSize(W, H: Integer; ACanvasScale: Single);
begin
  FViewWidth := W;
  FViewHeight := H;
  FCanvasScale := ACanvasScale;
end;

procedure TPixieCGCanvas.SetScale(Scale: Single);
begin
  FScale := Scale;
end;

end.
