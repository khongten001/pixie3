unit Pixie.RenderInput;

// Render item for <input type="checkbox"> and <input type="radio"> —
// replaced elements with intrinsic size, no aspect ratio logic needed.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Pixie.Types, Pixie.CssLength, Pixie.CssProperties,
  Pixie.Element, Pixie.FormattingContext, Pixie.RenderItem;

type
  { TPixieRenderInput }
  TPixieRenderInput = class(TPixieRenderItem)
  protected
    function _Render(X, Y: TPixiePixel;
      const CbContext: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext;
      SecondPass: Boolean): TPixiePixel; override;
  public
    constructor Create(ASrcEl: TPixieElement); override;
    function Clone: TPixieRenderItem; override;
  end;

implementation

uses
  Pixie.Document;

{ TPixieRenderInput }

constructor TPixieRenderInput.Create(ASrcEl: TPixieElement);
begin
  inherited Create(ASrcEl);
end;

function TPixieRenderInput.Clone: TPixieRenderItem;
begin
  Result := TPixieRenderInput.Create(FElement);
end;

function TPixieRenderInput._Render(X, Y: TPixiePixel;
  const CbContext: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext;
  SecondPass: Boolean): TPixiePixel;
var
  ParentWidth: TPixiePixel;
  SelfSize: TPixieContainingBlockContext;
  Sz: TPixieSize;
begin
  ParentWidth := CbContext.Width.Value;
  SelfSize := CalculateContainingBlockContext(CbContext);

  CalcOutlines(ParentWidth);

  FPos.MoveTo(X, Y);

  SrcEl.GetContentSize(Sz, ParentWidth);

  // Use CSS width if set, else intrinsic
  if not SrcEl.Css.CssWidth.IsPredefined then
    FPos.Width := SrcEl.Css.CssWidth.CalcPercent(ParentWidth)
  else
    FPos.Width := Sz.Width;

  // Use CSS height if set, else intrinsic
  if not SrcEl.Css.CssHeight.IsPredefined then
  begin
    if (SelfSize.Height.ValueType <> cbcAuto) and
       (SelfSize.Height.Value > 0) then
      FPos.Height := SelfSize.Height.Value
    else
      FPos.Height := Sz.Height;
  end
  else
    FPos.Height := Sz.Height;

  FPos.X := FPos.X + ContentOffsetLeft;
  FPos.Y := FPos.Y + ContentOffsetTop;

  Result := FPos.Width + ContentOffsetLeft + ContentOffsetRight;
end;

end.
