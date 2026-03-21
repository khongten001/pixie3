unit Pixie.SvgRenderer.FMX;

// SVG-to-FMX canvas renderer.
// Inherits SVG parsing from TPixieSvgRendererBase and overrides abstract
// drawing primitives to render via FMX TCanvas (TPathData, FillPath, etc.).
// Rasterises SVG into a TBitmap for use as an image handle.

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  System.UIConsts, System.Math, System.Math.Vectors,
  FMX.Graphics, FMX.Types, FMX.TextLayout,
  Pixie.SvgRenderer;

type
  { TPixieSvgCanvasRenderer }

  TPixieSvgCanvasRenderer = class(TPixieSvgRendererBase)
  private
    FCanvas: TCanvas;
    FPath: TPathData;
    FBrush: TBrush;
    FStrokeBrush: TStrokeBrush;
    FOpacity: Single;
    FOpacityStack: array[0..31] of Single;
    FOpacityTop: Integer;
    FStateStack: array[0..63] of TCanvasSaveState;
    FStateTop: Integer;
    FTextLayout: TTextLayout;
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
    procedure DoDrawText(const Text: string; X, Y: Single;
      const State: TPixieSvgState); override;
  public
    constructor Create;
    destructor Destroy; override;

    // Render SVG data into a newly created TBitmap. Caller owns result.
    // Returns nil on parse failure.
    class function RenderToBitmap(Data: Pointer;
      Size: Integer): TBitmap;
  end;

implementation

uses
  Pixie.WebColor;

function SvgColorToAlpha(const C: TPixieWebColor): TAlphaColor;
var
  Rec: TAlphaColorRec;
begin
  Rec.R := C.Red;
  Rec.G := C.Green;
  Rec.B := C.Blue;
  Rec.A := C.Alpha;
  Result := Rec.Color;
end;

// ===========================================================================
// Construction
// ===========================================================================

constructor TPixieSvgCanvasRenderer.Create;
begin
  inherited Create;
  FCanvas := nil;
  FPath := TPathData.Create;
  FBrush := TBrush.Create(TBrushKind.Solid, claBlack);
  FStrokeBrush := TStrokeBrush.Create(TBrushKind.Solid, claBlack);
  FTextLayout := TTextLayoutManager.DefaultTextLayout.Create;
  FOpacity := 1.0;
  FOpacityTop := 0;
  FStateTop := 0;
end;

destructor TPixieSvgCanvasRenderer.Destroy;
begin
  FTextLayout.Free;
  FPath.Free;
  FStrokeBrush.Free;
  FBrush.Free;
  inherited;
end;

// ===========================================================================
// Drawing primitives — path construction
// ===========================================================================

procedure TPixieSvgCanvasRenderer.DoMoveTo(X, Y: Single);
begin
  FPath.MoveTo(PointF(X, Y));
end;

procedure TPixieSvgCanvasRenderer.DoLineTo(X, Y: Single);
begin
  FPath.LineTo(PointF(X, Y));
end;

procedure TPixieSvgCanvasRenderer.DoCurveTo(X1, Y1, X2, Y2,
  X3, Y3: Single);
begin
  FPath.CurveTo(PointF(X1, Y1), PointF(X2, Y2), PointF(X3, Y3));
end;

procedure TPixieSvgCanvasRenderer.DoClosePath;
begin
  FPath.ClosePath;
end;

// ===========================================================================
// State management
// ===========================================================================

procedure TPixieSvgCanvasRenderer.DoSaveState;
begin
  if (FCanvas = nil) or (FStateTop > High(FStateStack)) then Exit;
  FStateStack[FStateTop] := FCanvas.SaveState;
  Inc(FStateTop);
end;

procedure TPixieSvgCanvasRenderer.DoRestoreState;
begin
  if (FCanvas = nil) or (FStateTop <= 0) then Exit;
  Dec(FStateTop);
  FCanvas.RestoreState(FStateStack[FStateTop]);
end;

procedure TPixieSvgCanvasRenderer.DoSetTransform(
  const M: TPixieSvgMatrix);
var
  Mat: TMatrix;
begin
  if FCanvas = nil then Exit;
  Mat.m11 := M.A; Mat.m12 := M.B; Mat.m13 := 0;
  Mat.m21 := M.C; Mat.m22 := M.D; Mat.m23 := 0;
  Mat.m31 := M.E; Mat.m32 := M.F; Mat.m33 := 1;
  FCanvas.MultiplyMatrix(Mat);
end;

// ===========================================================================
// Fill and stroke
// ===========================================================================

procedure TPixieSvgCanvasRenderer.DoFillAndStroke(
  const State: TPixieSvgState);
begin
  if FCanvas = nil then
  begin
    FPath.Clear;
    Exit;
  end;

  if State.HasFill then
  begin
    FBrush.Kind := TBrushKind.Solid;
    FBrush.Color := SvgColorToAlpha(State.FillColor);
    FCanvas.FillPath(FPath, FOpacity * State.FillOpacity, FBrush);
  end;

  if State.HasStroke then
  begin
    FStrokeBrush.Kind := TBrushKind.Solid;
    FStrokeBrush.Color := SvgColorToAlpha(State.StrokeColor);
    FStrokeBrush.Thickness := State.StrokeWidth;
    FStrokeBrush.Dash := TStrokeDash.Solid;
    FStrokeBrush.Cap := TStrokeCap.Flat;
    FCanvas.DrawPath(FPath, FOpacity * State.StrokeOpacity, FStrokeBrush);
  end;

  FPath.Clear;
end;

// ===========================================================================
// Opacity
// ===========================================================================

procedure TPixieSvgCanvasRenderer.DoBeginOpacity(Opacity: Single);
begin
  if FOpacityTop > High(FOpacityStack) then Exit;
  FOpacityStack[FOpacityTop] := FOpacity;
  Inc(FOpacityTop);
  FOpacity := FOpacity * Opacity;
end;

procedure TPixieSvgCanvasRenderer.DoEndOpacity;
begin
  if FOpacityTop <= 0 then Exit;
  Dec(FOpacityTop);
  FOpacity := FOpacityStack[FOpacityTop];
end;

// ===========================================================================
// Text
// ===========================================================================

procedure TPixieSvgCanvasRenderer.DoDrawText(const Text: string;
  X, Y: Single; const State: TPixieSvgState);
var
  R: TRectF;
  TextW, TextH: Single;
begin
  if FCanvas = nil then Exit;

  // Configure text layout for measurement
  FTextLayout.BeginUpdate;
  try
    FTextLayout.Font.Family := State.FontFamily;
    FTextLayout.Font.Size := State.FontSize;
    FTextLayout.Font.Style := [];
    if State.FontWeight >= 600 then
      FTextLayout.Font.Style := FTextLayout.Font.Style + [TFontStyle.fsBold];
    FTextLayout.Text := Text;
    FTextLayout.MaxSize := TSizeF.Create(100000, 100000);
    FTextLayout.WordWrap := False;
    FTextLayout.Trimming := TTextTrimming.None;
  finally
    FTextLayout.EndUpdate;
  end;

  TextW := FTextLayout.TextWidth;
  TextH := FTextLayout.TextHeight;

  // Set fill for text
  FCanvas.Fill.Kind := TBrushKind.Solid;
  FCanvas.Fill.Color := SvgColorToAlpha(State.FillColor);

  // Set font
  FCanvas.Font.Family := State.FontFamily;
  FCanvas.Font.Size := State.FontSize;
  FCanvas.Font.Style := [];
  if State.FontWeight >= 600 then
    FCanvas.Font.Style := FCanvas.Font.Style + [TFontStyle.fsBold];

  // SVG text Y is baseline; approximate by shifting up by ~80% of font size
  R := TRectF.Create(X, Y - TextH * 0.8, X + TextW + 10, Y + TextH * 0.2);
  FCanvas.FillText(R, Text, False, FOpacity * State.FillOpacity, [],
    TTextAlign.Leading, TTextAlign.Leading);
end;

// ===========================================================================
// Public API
// ===========================================================================

class function TPixieSvgCanvasRenderer.RenderToBitmap(Data: Pointer;
  Size: Integer): TBitmap;
var
  Renderer: TPixieSvgCanvasRenderer;
  W, H: Single;
  BmpW, BmpH: Integer;
begin
  Result := nil;
  Renderer := TPixieSvgCanvasRenderer.Create;
  try
    if not Renderer.ParseSvg(Data, Size, W, H) then Exit;
    if (W <= 0) or (H <= 0) then Exit;

    BmpW := Round(W);
    BmpH := Round(H);
    if BmpW < 1 then BmpW := 1;
    if BmpH < 1 then BmpH := 1;

    Result := TBitmap.Create(BmpW, BmpH);
    Result.Clear(0); // transparent background

    if Result.Canvas.BeginScene then
    try
      Renderer.FCanvas := Result.Canvas;
      Renderer.FOpacity := 1.0;
      Renderer.FOpacityTop := 0;
      Renderer.FStateTop := 0;

      // Apply viewBox scaling if dimensions differ
      if (Abs(W - Renderer.FViewBoxW) > 0.01) or
         (Abs(H - Renderer.FViewBoxH) > 0.01) then
      begin
        Renderer.FCanvas.MultiplyMatrix(
          TMatrix.CreateScaling(
            W / Renderer.FViewBoxW,
            H / Renderer.FViewBoxH));
      end;

      // Apply viewBox offset
      if (Abs(Renderer.FViewBoxX) > 0.01) or
         (Abs(Renderer.FViewBoxY) > 0.01) then
      begin
        Renderer.FCanvas.MultiplyMatrix(
          TMatrix.CreateTranslation(
            -Renderer.FViewBoxX,
            -Renderer.FViewBoxY));
      end;

      Renderer.RenderDocument;
    finally
      Result.Canvas.EndScene;
    end;
  finally
    Renderer.Free;
  end;
end;

end.
