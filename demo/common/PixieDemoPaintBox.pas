unit PixieDemoPaintBox;

// Shared PaintBox demo drawing — no framework dependencies.
// Draws a dashboard-style visualisation showcasing TPixieDrawingCanvas.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math,
  Pixie.Types, Pixie.WebColor, Pixie.Borders, Pixie.Canvas,
  Pixie.DrawingCanvas;

procedure PixieDemoDraw(C: TPixieDrawingCanvas; W, H: Single);

implementation

// ---------------------------------------------------------------------------
// Colour palette
// ---------------------------------------------------------------------------

const
  Teal:    TPixieWebColor = (Red: 0;   Green: 150; Blue: 136; Alpha: 255; IsCurrentColor: False);
  Coral:   TPixieWebColor = (Red: 255; Green: 111; Blue:  97; Alpha: 255; IsCurrentColor: False);
  Amber:   TPixieWebColor = (Red: 255; Green: 179; Blue:   0; Alpha: 255; IsCurrentColor: False);
  Sky:     TPixieWebColor = (Red:  66; Green: 165; Blue: 245; Alpha: 255; IsCurrentColor: False);
  Indigo:  TPixieWebColor = (Red:  92; Green: 107; Blue: 192; Alpha: 255; IsCurrentColor: False);
  Slate:   TPixieWebColor = (Red:  69; Green:  90; Blue: 100; Alpha: 255; IsCurrentColor: False);
  Emerald: TPixieWebColor = (Red: 102; Green: 187; Blue: 106; Alpha: 255; IsCurrentColor: False);
  Rose:    TPixieWebColor = (Red: 236; Green:  64; Blue: 122; Alpha: 255; IsCurrentColor: False);
  LightBg:    TPixieWebColor = (Red: 245; Green: 245; Blue: 248; Alpha: 255; IsCurrentColor: False);
  CardBg:     TPixieWebColor = (Red: 255; Green: 255; Blue: 255; Alpha: 255; IsCurrentColor: False);
  CardBorder: TPixieWebColor = (Red: 220; Green: 220; Blue: 225; Alpha: 255; IsCurrentColor: False);
  MutedText:  TPixieWebColor = (Red: 140; Green: 140; Blue: 150; Alpha: 255; IsCurrentColor: False);

const
  {$IFDEF FPC}
  ArrowUp   = #$E2#$96#$B2;  // UTF-8 for U+25B2 ▲
  ArrowDown = #$E2#$96#$BD;  // UTF-8 for U+25BD ▽
  EmDash    = #$E2#$80#$94;  // UTF-8 for U+2014 —
  {$ELSE}
  ArrowUp   = #$25B2;
  ArrowDown = #$25BD;
  EmDash    = #$2014;
  {$ENDIF}

function WithAlpha(Color: TPixieWebColor; A: Byte): TPixieWebColor;
begin
  Result := Color;
  Result.Alpha := A;
end;

// ---------------------------------------------------------------------------
// Sparkline metric card
// ---------------------------------------------------------------------------

procedure DrawSparklineCard(C: TPixieDrawingCanvas; X, Y, W, H: Single;
  const Title, Value, Delta: string; Color: TPixieWebColor);
const
  Spark: array[0..9] of Single = (0.3, 0.5, 0.4, 0.7, 0.6, 0.8, 0.75, 0.9, 0.85, 0.95);
var
  Points: array[0..9] of TPixiePointF;
  I: Integer;
  SX, SY, SW, SH: Single;
begin
  // Card
  C.Brush.Color := CardBg;
  C.Pen.Color := CardBorder;
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  C.RoundRect(X, Y, W, H, 8);

  // Metric label
  C.Font.Size := 10;
  C.Font.Style := [];
  C.Font.Color := MutedText;
  C.TextOut(X + 14, Y + 10, Title);

  // Value
  C.Font.Size := 22;
  C.Font.Style := [fsBold];
  C.Font.Color := Slate;
  C.TextOut(X + 14, Y + 28, Value);

  // Delta
  C.Font.Size := 11;
  C.Font.Style := [];
  C.Font.Color := Color;
  C.TextOut(X + 14, Y + 56, Delta);

  // Sparkline area
  SW := W * 0.35;
  SH := H * 0.35;
  SX := X + W - SW - 14;
  SY := Y + H * 0.35;
  for I := 0 to 9 do
  begin
    Points[I].X := SX + I * (SW / 9);
    Points[I].Y := SY + SH - SH * Spark[I];
  end;

  // Fill under sparkline via raw canvas path
  C.Canvas.BeginPath;
  C.Canvas.MoveTo(Points[0].X, SY + SH);
  for I := 0 to 9 do
    C.Canvas.LineTo(Points[I].X, Points[I].Y);
  C.Canvas.LineTo(Points[9].X, SY + SH);
  C.Canvas.ClosePath;
  C.Canvas.FillPath(WithAlpha(Color, 25));

  // Line
  C.Pen.Style := psSolid;
  C.Pen.Color := Color;
  C.Pen.Width := 2;
  C.Polyline(Points);

  // Dot at end
  C.Brush.Color := Color;
  C.Pen.Style := psClear;
  C.Circle(Points[9].X, Points[9].Y, 3);
end;

// ---------------------------------------------------------------------------
// Bar chart
// ---------------------------------------------------------------------------

procedure DrawBarChart(C: TPixieDrawingCanvas; X, Y, W, H: Single);
const
  BarData: array[0..5] of Single = (0.82, 0.65, 0.93, 0.47, 0.71, 0.58);
  Labels: array[0..5] of string = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun');
var
  BarColors: array[0..5] of TPixieWebColor;
  I: Integer;
  BarW, Gap, BX, BY, BH, ChartH, ChartY: Single;
begin
  BarColors[0] := Teal;
  BarColors[1] := Coral;
  BarColors[2] := Amber;
  BarColors[3] := Sky;
  BarColors[4] := Indigo;
  BarColors[5] := Emerald;

  // Card background
  C.Brush.Color := CardBg;
  C.Pen.Color := CardBorder;
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  C.RoundRect(X, Y, W, H, 8);

  // Title
  C.Font.Size := 14;
  C.Font.Style := [fsBold];
  C.Font.Color := Slate;
  C.TextOut(X + 16, Y + 12, 'Monthly Revenue');

  C.Font.Size := 11;
  C.Font.Style := [];
  C.Font.Color := MutedText;
  C.TextOut(X + 16, Y + 32, 'Jan ' + EmDash + ' Jun 2026 (thousands)');

  // Chart area
  ChartY := Y + 56;
  ChartH := H - 90;
  Gap := 10;
  BarW := (W - 32 - Gap * 5) / 6;

  // Gridlines
  C.Pen.Style := psDot;
  C.Pen.Color := CardBorder;
  C.Pen.Width := 1;
  for I := 0 to 4 do
  begin
    BY := ChartY + ChartH - ChartH * I / 4;
    C.Line(X + 16, BY, X + W - 16, BY);
  end;

  // Bars with shadow
  C.Pen.Style := psClear;
  for I := 0 to 5 do
  begin
    BX := X + 16 + I * (BarW + Gap);
    BH := ChartH * BarData[I];
    BY := ChartY + ChartH - BH;

    // Shadow
    C.Brush.Color := WithAlpha(TPixieWebColor.Black, 15);
    C.RoundRect(BX + 2, BY + 2, BarW, BH, 4);

    // Bar
    C.Brush.Color := BarColors[I];
    C.RoundRect(BX, BY, BarW, BH, 4);

    // Highlight overlay on upper portion
    C.Brush.Color := WithAlpha(TPixieWebColor.White, 50);
    C.FillRect(BX + 1, BY + 1, BarW - 2, BH * 0.3);

    // Label below
    C.Font.Size := 10;
    C.Font.Style := [];
    C.Font.Color := Slate;
    C.TextRect(BX, ChartY + ChartH + 4, BarW, 16, Labels[I], taCenter, vaTop);
  end;
end;

// ---------------------------------------------------------------------------
// Pie wedge path helper (filled sector, no stroke)
// ---------------------------------------------------------------------------

procedure EmitPieWedge(Canvas: TPixieCanvas; CX, CY, R: Single;
  StartAngle, SweepAngle: Single);
var
  Theta, DTheta, SegAngle, Alpha, T: Single;
  Segments, Seg: Integer;
  Cos1, Sin1, Cos2, Sin2: Single;
begin
  Theta := DegToRad(StartAngle);
  DTheta := DegToRad(SweepAngle);
  Segments := Ceil(Abs(DTheta) / (Pi * 0.5));
  if Segments < 1 then Segments := 1;
  SegAngle := DTheta / Segments;
  Alpha := 4.0 / 3.0 * Tan(SegAngle * 0.25);

  T := Theta;
  SinCos(T, Sin1, Cos1);

  Canvas.BeginPath;
  Canvas.MoveTo(CX, CY);
  Canvas.LineTo(CX + R * Cos1, CY + R * Sin1);

  for Seg := 0 to Segments - 1 do
  begin
    SinCos(T + SegAngle, Sin2, Cos2);
    Canvas.CurveTo(
      CX + R * (Cos1 - Alpha * Sin1),
      CY + R * (Sin1 + Alpha * Cos1),
      CX + R * (Cos2 + Alpha * Sin2),
      CY + R * (Sin2 - Alpha * Cos2),
      CX + R * Cos2,
      CY + R * Sin2);
    T := T + SegAngle;
    Cos1 := Cos2;
    Sin1 := Sin2;
  end;

  Canvas.ClosePath;
end;

// ---------------------------------------------------------------------------
// Donut chart
// ---------------------------------------------------------------------------

procedure DrawDonutChart(C: TPixieDrawingCanvas; X, Y, W, H: Single);
const
  Segments: array[0..4] of Single = (35, 25, 20, 12, 8);
  SegLabels: array[0..4] of string = ('Direct', 'Search', 'Social', 'E-mail', 'Other');
var
  SegColors: array[0..4] of TPixieWebColor;
  CX, CY, R, Angle, Sweep: Single;
  I: Integer;
  LX, LY: Single;
begin
  SegColors[0] := Teal;
  SegColors[1] := Coral;
  SegColors[2] := Amber;
  SegColors[3] := Indigo;
  SegColors[4] := Emerald;

  // Card background
  C.Brush.Color := CardBg;
  C.Pen.Color := CardBorder;
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  C.RoundRect(X, Y, W, H, 8);

  // Title
  C.Font.Size := 14;
  C.Font.Style := [fsBold];
  C.Font.Color := Slate;
  C.TextOut(X + 16, Y + 12, 'Traffic Sources');

  // Donut chart via filled pie wedges + white centre
  CX := X + W * 0.42;
  CY := Y + H * 0.55;
  R := Min(W, H) * 0.28;

  Angle := -90;  // start at top
  C.Pen.Style := psClear;
  for I := 0 to 4 do
  begin
    Sweep := Segments[I] / 100 * 360;
    EmitPieWedge(C.Canvas, CX, CY, R, Angle, Sweep);
    C.Canvas.FillPath(SegColors[I]);
    Angle := Angle + Sweep;
  end;

  // White centre to make it a donut
  C.Brush.Style := bsSolid;
  C.Brush.Color := CardBg;
  C.Circle(CX, CY, R * 0.55);

  // Centre text
  C.Font.Size := 18;
  C.Font.Style := [fsBold];
  C.Font.Color := Slate;
  C.TextRect(CX - 30, CY - 14, 60, 20, '14.2K', taCenter, vaMiddle);
  C.Font.Size := 9;
  C.Font.Style := [];
  C.Font.Color := MutedText;
  C.TextRect(CX - 30, CY + 6, 60, 14, 'visitors', taCenter, vaMiddle);

  // Legend
  LX := X + W * 0.72;
  LY := Y + 50;
  C.Font.Size := 10;
  C.Font.Color := Slate;
  for I := 0 to 4 do
  begin
    C.Brush.Color := SegColors[I];
    C.Pen.Style := psClear;
    C.RoundRect(LX, LY, 10, 10, 2);
    C.TextOut(LX + 16, LY - 1, SegLabels[I] + '  ' + IntToStr(Round(Segments[I])) + '%');
    LY := LY + 22;
  end;
  C.Brush.Style := bsSolid;
end;

// ---------------------------------------------------------------------------
// Overlapping circles
// ---------------------------------------------------------------------------

procedure DrawOverlappingCircles(C: TPixieDrawingCanvas; X, Y, W, H: Single);
var
  CX, CY, R: Single;
begin
  // Card background
  C.Brush.Color := CardBg;
  C.Pen.Color := CardBorder;
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  C.RoundRect(X, Y, W, H, 8);

  // Title
  C.Font.Size := 14;
  C.Font.Style := [fsBold];
  C.Font.Color := Slate;
  C.TextOut(X + 16, Y + 12, 'Overlap Analysis');

  CX := X + W * 0.5;
  CY := Y + H * 0.55;
  R := Min(W, H) * 0.22;

  C.Pen.Style := psClear;

  // Three overlapping translucent circles
  C.Brush.Color := WithAlpha(Coral, 100);
  C.Circle(CX - R * 0.55, CY - R * 0.3, R);

  C.Brush.Color := WithAlpha(Sky, 100);
  C.Circle(CX + R * 0.55, CY - R * 0.3, R);

  C.Brush.Color := WithAlpha(Emerald, 100);
  C.Circle(CX, CY + R * 0.35, R);

  // Labels
  C.Font.Size := 10;
  C.Font.Style := [];
  C.Font.Color := TPixieWebColor.Create(100, 100, 110);
  C.TextRect(CX - R * 1.3, CY - R * 1.1, R, 14, 'Users', taCenter, vaMiddle);
  C.TextRect(CX + R * 0.3, CY - R * 1.1, R, 14, 'Revenue', taCenter, vaMiddle);
  C.TextRect(CX - R * 0.5, CY + R * 0.9, R, 14, 'Growth', taCenter, vaMiddle);
end;

// ---------------------------------------------------------------------------
// Star polygon
// ---------------------------------------------------------------------------

procedure DrawStar(C: TPixieDrawingCanvas; CX, CY, R: Single);
const
  NumPoints = 5;
var
  Pts: array[0..9] of TPixiePointF;
  I: Integer;
  Angle, InnerR: Single;
begin
  InnerR := R * 0.4;
  for I := 0 to NumPoints * 2 - 1 do
  begin
    Angle := -Pi / 2 + I * Pi / NumPoints;
    if I mod 2 = 0 then
    begin
      Pts[I].X := CX + R * Cos(Angle);
      Pts[I].Y := CY + R * Sin(Angle);
    end
    else
    begin
      Pts[I].X := CX + InnerR * Cos(Angle);
      Pts[I].Y := CY + InnerR * Sin(Angle);
    end;
  end;

  C.Brush.Color := WithAlpha(Amber, 180);
  C.Pen.Color := WithAlpha(Amber, 240);
  C.Pen.Style := psSolid;
  C.Pen.Width := 2;
  C.Polygon(Pts);
end;

// ---------------------------------------------------------------------------
// Pen styles + diagonal stripes card
// ---------------------------------------------------------------------------

procedure DrawPenStylesCard(C: TPixieDrawingCanvas; X, Y, W, H: Single);
var
  I: Integer;
  Colors: array[0..5] of TPixieWebColor;
  Radius: TPixieBorderRadiuses;
  StepY, LY1, LY2: Single;
begin
  Colors[0] := Teal;
  Colors[1] := Coral;
  Colors[2] := Amber;
  Colors[3] := Sky;
  Colors[4] := Indigo;
  Colors[5] := Rose;

  // Card
  C.Brush.Color := CardBg;
  C.Pen.Color := CardBorder;
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  C.RoundRect(X, Y, W, H, 8);

  C.Font.Size := 14;
  C.Font.Style := [fsBold];
  C.Font.Color := Slate;
  C.TextOut(X + 16, Y + 12, 'Pen Styles');

  // Clip to card interior
  C.SaveState;
  Radius.Init;
  C.Canvas.SetClipRect(
    TPixiePosition.Create(X + 1, Y + 38, W - 2, H - 40), Radius);

  // Diagonal stripes with varying width and opacity
  StepY := (H - 38) / 8;
  for I := 0 to 7 do
  begin
    LY1 := Y + 38 + I * StepY;
    LY2 := LY1 - H * 0.35;

    C.Pen.Width := 3 + I * 1.5;
    C.Pen.Color := WithAlpha(Colors[I mod 6], 140 + I * 12);

    // Alternate solid and dash
    if I mod 3 = 2 then
      C.Pen.Style := psDash
    else
      C.Pen.Style := psSolid;

    C.Line(X, LY1, X + W, LY2);
  end;

  C.RestoreState;

  // Star polygon in the centre
  DrawStar(C, X + W * 0.5, Y + 38 + (H - 38) * 0.5, Min(W, H - 38) * 0.2);
end;

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

procedure PixieDemoDraw(C: TPixieDrawingCanvas; W, H: Single);
const
  Margin = 16;
  CardGap = 14;
var
  Col1W, Col2W, TopH, BotH, CardH, CardW: Single;
begin
  // Background
  C.Brush.Color := LightBg;
  C.Pen.Style := psClear;
  C.FillRect(0, 0, W, H);

  // Layout: 4 sparkline cards across the top, then 2x2 grid below
  CardH := 80;
  CardW := (W - Margin * 2 - CardGap * 3) / 4;
  Col1W := (W - Margin * 3) * 0.58;
  Col2W := W - Margin * 3 - Col1W;
  TopH := (H - Margin * 2 - CardGap * 2 - CardH) * 0.55;
  BotH := H - Margin * 2 - CardGap * 2 - CardH - TopH;

  // Sparkline cards
  DrawSparklineCard(C,
    Margin, Margin, CardW, CardH,
    'Total Users', '24,521', ArrowUp + ' +12.5%', Emerald);

  DrawSparklineCard(C,
    Margin + (CardW + CardGap), Margin, CardW, CardH,
    'Revenue', '$48.2K', ArrowUp + ' +8.1%', Teal);

  DrawSparklineCard(C,
    Margin + (CardW + CardGap) * 2, Margin, CardW, CardH,
    'Bounce Rate', '32.1%', ArrowDown + ' -3.2%', Coral);

  DrawSparklineCard(C,
    Margin + (CardW + CardGap) * 3, Margin, CardW, CardH,
    'Avg. Session', '4m 12s', ArrowUp + ' +5.7%', Sky);

  // Bar chart — left column, middle row
  DrawBarChart(C,
    Margin, Margin + CardH + CardGap, Col1W, TopH);

  // Donut chart — right column, middle row
  DrawDonutChart(C,
    Margin * 2 + Col1W, Margin + CardH + CardGap, Col2W, TopH);

  // Overlapping circles — left column, bottom row
  DrawOverlappingCircles(C,
    Margin, Margin + CardH + CardGap + TopH + CardGap, Col1W, BotH);

  // Pen styles card — right column, bottom row
  DrawPenStylesCard(C,
    Margin * 2 + Col1W, Margin + CardH + CardGap + TopH + CardGap, Col2W, BotH);
end;

end.
