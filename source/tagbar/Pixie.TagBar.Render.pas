unit Pixie.TagBar.Render;

// Standalone pill measurement, drawing, and hit-testing.
// No LCL dependency — works with any TPixieCanvas backend.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math,
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.Canvas, Pixie.TagBar.Colors;

type
  TPixieTagShape = (tsRect, tsRoundedRect, tsPill);

  TPixieTagPillState = (
    tpsRest, tpsHover, tpsPress,
    tpsChecked, tpsCheckedHover, tpsCheckedPress,
    tpsInactive, tpsEditing
  );

  TPixieTagPillOption = (tpoShowDismiss, tpoIsAddButton);
  TPixieTagPillOptions = set of TPixieTagPillOption;

  TPixieTagHitZone = (thzNone, thzPill, thzLeadIcon, thzDismiss);

  TPixieTagPillMetrics = record
    TotalWidth: Single;
    TotalHeight: Single;
    TextX: Single;
    TextWidth: Single;
    LeadIconRect: TPixiePosition;
    TrailIconRect: TPixiePosition;
    DismissRect: TPixiePosition;
    ContentRect: TPixiePosition;
  end;

function MeasureTagPill(
  Canvas: TPixieCanvas;
  Font: TPixieFontHandle;
  const Text: string;
  const LeadIcon: string;
  const TrailIcon: string;
  PillHeight: Single;
  Options: TPixieTagPillOptions): TPixieTagPillMetrics;

procedure DrawTagPill(
  Canvas: TPixieCanvas;
  Font: TPixieFontHandle;
  const FontMetrics: TPixieFontMetrics;
  const Text: string;
  const LeadIcon: string;
  const TrailIcon: string;
  X, Y, PillHeight: Single;
  const Base: TPixieWebColor;
  State: TPixieTagPillState;
  Shape: TPixieTagShape;
  Options: TPixieTagPillOptions;
  const Metrics: TPixieTagPillMetrics);

function HitTestTagPill(LocalX, LocalY: Single;
  const M: TPixieTagPillMetrics): TPixieTagHitZone;

implementation

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

function MeasureTagPill(
  Canvas: TPixieCanvas;
  Font: TPixieFontHandle;
  const Text: string;
  const LeadIcon: string;
  const TrailIcon: string;
  PillHeight: Single;
  Options: TPixieTagPillOptions): TPixieTagPillMetrics;
var
  PadH, DismW, Gap, CurX, TextW, LeadW, TrailW: Single;
begin
  Result.LeadIconRect.Clear;
  Result.TrailIconRect.Clear;
  Result.DismissRect.Clear;

  if tpoIsAddButton in Options then
  begin
    PadH := PillHeight * 0.25;
    TextW := Canvas.MeasureText(Text, Font);
    Result.TextX := PadH;
    Result.TextWidth := TextW;
    Result.TotalWidth := PadH + TextW + PadH;
    Result.TotalHeight := PillHeight;
    Result.ContentRect := TPixiePosition.Create(0, 0,
      Result.TotalWidth, PillHeight);
    Exit;
  end;

  PadH  := PillHeight * 0.35;
  DismW := PillHeight * 0.55;
  Gap   := PillHeight * 0.2;
  TextW := Canvas.MeasureText(Text, Font);

  CurX := PadH;

  // Lead icon
  if LeadIcon <> '' then
  begin
    LeadW := Canvas.MeasureText(LeadIcon, Font);
    Result.LeadIconRect := TPixiePosition.Create(
      CurX, 0, LeadW, PillHeight);
    CurX := CurX + LeadW + Gap;
  end;

  Result.TextX := CurX;
  Result.TextWidth := TextW;
  CurX := CurX + TextW;

  // Trail icon
  if TrailIcon <> '' then
  begin
    CurX := CurX + Gap;
    TrailW := Canvas.MeasureText(TrailIcon, Font);
    Result.TrailIconRect := TPixiePosition.Create(
      CurX, 0, TrailW, PillHeight);
    CurX := CurX + TrailW;
  end;

  if tpoShowDismiss in Options then
  begin
    CurX := CurX + Gap;
    Result.DismissRect := TPixiePosition.Create(
      CurX, 0, DismW, PillHeight);
    CurX := CurX + DismW;
  end;

  CurX := CurX + PadH;
  Result.TotalWidth := CurX;
  Result.TotalHeight := PillHeight;
  Result.ContentRect := TPixiePosition.Create(0, 0,
    Result.TotalWidth, PillHeight);
end;

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

procedure DrawTagPill(
  Canvas: TPixieCanvas;
  Font: TPixieFontHandle;
  const FontMetrics: TPixieFontMetrics;
  const Text: string;
  const LeadIcon: string;
  const TrailIcon: string;
  X, Y, PillHeight: Single;
  const Base: TPixieWebColor;
  State: TPixieTagPillState;
  Shape: TPixieTagShape;
  Options: TPixieTagPillOptions;
  const Metrics: TPixieTagPillMetrics);
var
  FillColor, TxtColor, BrdColor: TPixieWebColor;
  Radius, InnerRadius: TPixieBorderRadiuses;
  Bw, R, TextY, Arm, Cx, Cy: Single;
  IsChecked: Boolean;
begin
  // Compute colours from state
  IsChecked := State in [tpsChecked, tpsCheckedHover, tpsCheckedPress];
  case State of
    tpsRest:         FillColor := PixieTagRestFill(Base);
    tpsHover:        FillColor := PixieTagHoverFill(Base);
    tpsPress:        FillColor := PixieTagPressFill(Base);
    tpsChecked:      FillColor := PixieTagCheckedFill(Base);
    tpsCheckedHover: FillColor := PixieTagBlend(Base, TPixieWebColor.White, 0.15);
    tpsCheckedPress: FillColor := PixieTagBlend(Base, TPixieWebColor.Black, 0.15);
    tpsInactive:     FillColor := PixieTagInactiveFill(Base);
    tpsEditing:      FillColor := PixieTagRestFill(Base);
  end;
  TxtColor := PixieTagTextColor(Base, IsChecked);
  BrdColor := PixieTagBorderColor(Base);

  // Compute radii from shape
  case Shape of
    tsRect:        R := 0;
    tsRoundedRect: R := PillHeight * 0.2;
    tsPill:        R := PillHeight / 2;
  end;

  Radius.TopLeftX := R;     Radius.TopLeftY := R;
  Radius.TopRightX := R;    Radius.TopRightY := R;
  Radius.BottomRightX := R; Radius.BottomRightY := R;
  Radius.BottomLeftX := R;  Radius.BottomLeftY := R;

  // Inner radius (outer minus border width)
  Bw := 1.0;
  if R > Bw then
  begin
    InnerRadius.TopLeftX := R - Bw;     InnerRadius.TopLeftY := R - Bw;
    InnerRadius.TopRightX := R - Bw;    InnerRadius.TopRightY := R - Bw;
    InnerRadius.BottomRightX := R - Bw; InnerRadius.BottomRightY := R - Bw;
    InnerRadius.BottomLeftX := R - Bw;  InnerRadius.BottomLeftY := R - Bw;
  end
  else
    InnerRadius.Init;

  // Border (outer rounded rect)
  Canvas.FillRoundedRect(X, Y,
    Metrics.TotalWidth, PillHeight, Radius, BrdColor);

  // Fill (inset rounded rect)
  Canvas.FillRoundedRect(X + Bw, Y + Bw,
    Metrics.TotalWidth - 2 * Bw, PillHeight - 2 * Bw,
    InnerRadius, FillColor);

  // Lead icon
  if not Metrics.LeadIconRect.IsEmpty then
  begin
    TextY := Y + (PillHeight - FontMetrics.Height) / 2;
    Canvas.DrawText(LeadIcon, Font, TxtColor,
      X + Metrics.LeadIconRect.X, TextY,
      Metrics.LeadIconRect.Width, FontMetrics.Height);
  end;

  // Text
  TextY := Y + (PillHeight - FontMetrics.Height) / 2;
  Canvas.DrawText(Text, Font, TxtColor,
    X + Metrics.TextX, TextY,
    Metrics.TextWidth, FontMetrics.Height);

  // Trail icon
  if not Metrics.TrailIconRect.IsEmpty then
  begin
    TextY := Y + (PillHeight - FontMetrics.Height) / 2;
    Canvas.DrawText(TrailIcon, Font, TxtColor,
      X + Metrics.TrailIconRect.X, TextY,
      Metrics.TrailIconRect.Width, FontMetrics.Height);
  end;

  // Dismiss cross
  if tpoShowDismiss in Options then
  begin
    Cx := X + Metrics.DismissRect.X + Metrics.DismissRect.Width / 2;
    Cy := Y + PillHeight / 2;
    Arm := Min(Metrics.DismissRect.Width, PillHeight) * 0.18;
    Canvas.DrawLine(Cx - Arm, Cy - Arm, Cx + Arm, Cy + Arm,
      TxtColor, 1.5);
    Canvas.DrawLine(Cx + Arm, Cy - Arm, Cx - Arm, Cy + Arm,
      TxtColor, 1.5);
  end;
end;

// ---------------------------------------------------------------------------
// Hit testing (coordinates relative to pill origin)
// ---------------------------------------------------------------------------

function HitTestTagPill(LocalX, LocalY: Single;
  const M: TPixieTagPillMetrics): TPixieTagHitZone;
begin
  // Outside content rect?
  if not M.ContentRect.IsPointInside(LocalX, LocalY) then
    Exit(thzNone);

  // Dismiss zone first (rightmost)
  if not M.DismissRect.IsEmpty and
     M.DismissRect.IsPointInside(LocalX, LocalY) then
    Exit(thzDismiss);

  // Lead icon
  if not M.LeadIconRect.IsEmpty and
     M.LeadIconRect.IsPointInside(LocalX, LocalY) then
    Exit(thzLeadIcon);

  Result := thzPill;
end;

end.
