unit Pixie.RenderImage;

// Image element render item — handles <img> layout with
// aspect ratio preservation and max-width/max-height clamping.

{$mode delphi}

interface

uses
  Pixie.Types, Pixie.CssLength, Pixie.CssProperties,
  Pixie.Element, Pixie.FormattingContext, Pixie.RenderItem;

type
  { TPixieRenderImage }
  TPixieRenderImage = class(TPixieRenderItem)
  protected
    function CalcMaxHeight(ImageHeight, ContainingBlockHeight: pixel_t): pixel_t;
    function _Render(X, Y: pixel_t;
      const CbContext: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext;
      SecondPass: Boolean): pixel_t; override;
  public
    constructor Create(ASrcEl: TPixieElement); override;
    function Clone: TPixieRenderItem; override;
  end;

implementation

uses
  Pixie.Document;

{ TPixieRenderImage }

constructor TPixieRenderImage.Create(ASrcEl: TPixieElement);
begin
  inherited Create(ASrcEl);
end;

function TPixieRenderImage.Clone: TPixieRenderItem;
begin
  Result := TPixieRenderImage.Create(FElement);
end;

function TPixieRenderImage.CalcMaxHeight(ImageHeight, ContainingBlockHeight: pixel_t): pixel_t;
var
  Doc: TPixieDocument;
  CbHeight: pixel_t;
begin
  Assert(SrcEl.GetDocument is TPixieDocument);
  Doc := TPixieDocument(SrcEl.GetDocument);
  if ContainingBlockHeight = 0 then
    CbHeight := ImageHeight
  else
    CbHeight := ContainingBlockHeight;
  Result := Doc.ToPixels(Css.CssMaxHeight, Css.FontMetrics, CbHeight);
end;

function TPixieRenderImage._Render(X, Y: pixel_t;
  const CbContext: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext;
  SecondPass: Boolean): pixel_t;
var
  ParentWidth: pixel_t;
  SelfSize: TPixieContainingBlockContext;
  Doc: TPixieDocument;
  Sz: TPixieSize;
  MaxWidth, MaxHeight: pixel_t;
  Lh: TPixieCssLineHeight;
begin
  ParentWidth := CbContext.Width.Value;
  SelfSize := CalculateContainingBlockContext(CbContext);

  CalcOutlines(ParentWidth);

  FPos.MoveTo(X, Y);

  Assert(SrcEl.GetDocument is TPixieDocument);
  Doc := TPixieDocument(SrcEl.GetDocument);

  SrcEl.GetContentSize(Sz, CbContext.Width.Value);

  FPos.Width := Sz.Width;
  FPos.Height := Sz.Height;

  Lh := SrcEl.Css.LineHeight;
  Lh.ComputedValue := Height;
  SrcEl.CssW.LineHeight := Lh;

  if SrcEl.Css.CssHeight.IsPredefined and SrcEl.Css.CssWidth.IsPredefined then
  begin
    // Both auto — use intrinsic size
    FPos.Height := Sz.Height;
    FPos.Width := Sz.Width;

    // check for max-width
    if not SrcEl.Css.CssMaxWidth.IsPredefined then
    begin
      MaxWidth := Doc.ToPixels(Css.CssMaxWidth, Css.FontMetrics, ParentWidth);
      if FPos.Width > MaxWidth then
        FPos.Width := MaxWidth;
      if Sz.Width <> 0 then
        FPos.Height := FPos.Width * Sz.Height / Sz.Width
      else
        FPos.Height := Sz.Height;
    end;

    // check for max-height
    if not SrcEl.Css.CssMaxHeight.IsPredefined then
    begin
      MaxHeight := CalcMaxHeight(Sz.Height, CbContext.Height.Value);
      if FPos.Height > MaxHeight then
        FPos.Height := MaxHeight;
      if Sz.Height <> 0 then
        FPos.Width := FPos.Height * Sz.Width / Sz.Height
      else
        FPos.Width := Sz.Width;
    end;
  end
  else if (not SrcEl.Css.CssHeight.IsPredefined) and SrcEl.Css.CssWidth.IsPredefined then
  begin
    // Height set, width auto
    if (SelfSize.Height.ValueType <> cbcAuto) and (SelfSize.Height.Value > 0) then
      FPos.Height := SelfSize.Height.Value;

    // check for max-height
    if not SrcEl.Css.CssMaxHeight.IsPredefined then
    begin
      MaxHeight := CalcMaxHeight(Sz.Height, CbContext.Height.Value);
      if FPos.Height > MaxHeight then
        FPos.Height := MaxHeight;
    end;

    if Sz.Height <> 0 then
      FPos.Width := FPos.Height * Sz.Width / Sz.Height
    else
      FPos.Width := Sz.Width;
  end
  else if SrcEl.Css.CssHeight.IsPredefined and (not SrcEl.Css.CssWidth.IsPredefined) then
  begin
    // Width set, height auto
    FPos.Width := SrcEl.Css.CssWidth.CalcPercent(ParentWidth);

    // check for max-width
    if not SrcEl.Css.CssMaxWidth.IsPredefined then
    begin
      MaxWidth := Doc.ToPixels(Css.CssMaxWidth, Css.FontMetrics, ParentWidth);
      if FPos.Width > MaxWidth then
        FPos.Width := MaxWidth;
    end;

    if Sz.Width <> 0 then
      FPos.Height := FPos.Width * Sz.Height / Sz.Width
    else
      FPos.Height := Sz.Height;
  end
  else
  begin
    // Both set
    FPos.Width := SrcEl.Css.CssWidth.CalcPercent(ParentWidth);
    FPos.Height := 0;
    if (SelfSize.Height.ValueType <> cbcAuto) and (SelfSize.Height.Value > 0) then
      FPos.Height := SelfSize.Height.Value;

    // check for max-height
    if not SrcEl.Css.CssMaxHeight.IsPredefined then
    begin
      MaxHeight := CalcMaxHeight(Sz.Height, CbContext.Height.Value);
      if FPos.Height > MaxHeight then
        FPos.Height := MaxHeight;
    end;

    // check for max-width
    if not SrcEl.Css.CssMaxWidth.IsPredefined then
    begin
      MaxWidth := Doc.ToPixels(Css.CssMaxWidth, Css.FontMetrics, ParentWidth);
      if FPos.Width > MaxWidth then
        FPos.Width := MaxWidth;
    end;
  end;

  FPos.X := FPos.X + ContentOffsetLeft;
  FPos.Y := FPos.Y + ContentOffsetTop;

  Result := FPos.Width + ContentOffsetLeft + ContentOffsetRight;
end;

end.
