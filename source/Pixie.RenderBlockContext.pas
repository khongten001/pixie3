unit Pixie.RenderBlockContext;

// Block formatting context — stacks block children vertically with
// margin collapsing, float placement, and relative positioning.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Math,
  Pixie.Types, Pixie.CssLength, Pixie.CssProperties,
  Pixie.Element, Pixie.FormattingContext,
  Pixie.RenderItem, Pixie.RenderBlock;

type
  { TPixieRenderBlockContext }
  TPixieRenderBlockContext = class(TPixieRenderBlock)
  protected
    function _RenderContent(X, Y: pixel_t; SecondPass: Boolean;
      const SelfSize: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext): pixel_t; override;
  public
    constructor Create(ASrcEl: TPixieElement); override;
    function Clone: TPixieRenderItem; override;
    function GetFirstBaseline: pixel_t; override;
    function GetLastBaseline: pixel_t; override;
  end;

implementation

uses
  Pixie.Document;

{ TPixieRenderBlockContext }

constructor TPixieRenderBlockContext.Create(ASrcEl: TPixieElement);
begin
  inherited Create(ASrcEl);
end;

function TPixieRenderBlockContext.Clone: TPixieRenderItem;
begin
  Result := TPixieRenderBlockContext.Create(FElement);
end;

function TPixieRenderBlockContext._RenderContent(X, Y: pixel_t;
  SecondPass: Boolean;
  const SelfSize: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext): pixel_t;
var
  ElPosition: TPixieElementPosition;
  RetWidth, ChildTop, LastMargin: pixel_t;
  IsFirst: Boolean;
  I: Integer;
  El: TPixieRenderItem;
  ElCss: TPixieCssProperties;
  ChildMargins: TPixieMargins;
  LastMarginEl: TPixieRenderItem;
  ChildX, ChildWidth, LineRight, TopMargin: pixel_t;
  LineLeft: pixel_t;
  Rw: pixel_t;
  MinRenderedWidth: pixel_t;
  NewTop, LnLeft, LnRight: pixel_t;
  AutoMargin: pixel_t;
begin
  RetWidth := 0;
  ChildTop := 0;
  LastMargin := 0;
  LastMarginEl := nil;
  IsFirst := True;

  for I := 0 to FChildren.Count - 1 do
  begin
    El := FChildren[I];
    ElCss := El.SrcEl.Css;

    // Skip absolute/fixed on second pass
    if SecondPass then
    begin
      ElPosition := ElCss.ElPosition;
      if (ElPosition = epAbsolute) or (ElPosition = epFixed) then
        Continue;
    end;

    if ElCss.Float_ <> efNone then
    begin
      Rw := PlaceFloat(El, ChildTop, SelfSize, FmtCtx);
      if Rw > RetWidth then
        RetWidth := Rw;
    end
    else if ElCss.Display <> displayNone then
    begin
      if (ElCss.ElPosition = epAbsolute) or (ElCss.ElPosition = epFixed) then
      begin
        MinRenderedWidth := El.Render(0, ChildTop, SelfSize, FmtCtx);
        if (MinRenderedWidth < El.Width) and ElCss.CssWidth.IsPredefined then
          El.Render(0, ChildTop, SelfSize.NewWidth(MinRenderedWidth), FmtCtx);
      end
      else
      begin
        ChildTop := FmtCtx.GetClearedTop(ElCss.Clear_, ElCss.Float_, ChildTop);
        ChildX := 0;
        ChildWidth := SelfSize.RenderWidth.Value;
        LineRight := SelfSize.RenderWidth.Value;
        TopMargin := FMargins.Top;

        El.CalcOutlines(SelfSize.Width.Value);

        // Adjust width for replaced/BFC/table elements with floats
        if El.SrcEl.IsReplaced or
           El.SrcEl.IsBlockFormattingContext or
           (ElCss.Display = displayTable) then
        begin
          LineLeft := 0;
          FmtCtx.GetLineLeftRight(ChildTop, ChildWidth, LineLeft, LineRight);
          if LineLeft <> ChildX then
            ChildX := LineLeft - El.MarginLeft;
          if LineRight <> SelfSize.RenderWidth.Value then
            LineRight := LineRight + El.MarginRight;
          if El.Css.CssWidth.IsPredefined then
            ChildWidth := LineRight - LineLeft;
        end;

        // Collapse top margin
        ChildMargins := El.GetMargins;
        if IsFirst and CollapseTopMargin then
        begin
          if ChildMargins.Top > 0 then
          begin
            ChildTop := ChildTop - ChildMargins.Top;
            if ChildMargins.Top > GetMargins.Top then
              TopMargin := ChildMargins.Top;
          end;
        end
        else
        begin
          if ChildMargins.Top > 0 then
          begin
            if LastMargin > ChildMargins.Top then
              ChildTop := ChildTop - ChildMargins.Top
            else
              ChildTop := ChildTop - LastMargin;
          end;
        end;

        Rw := El.Render(ChildX, ChildTop, SelfSize.NewWidth(ChildWidth), FmtCtx);
        // Table auto-width re-render
        if (ElCss.Display = displayTable) and (Rw < ChildWidth) and
           ElCss.CssWidth.IsPredefined then
          El.Render(ChildX, ChildTop, SelfSize.NewWidth(Rw), FmtCtx);
        ChildMargins := El.GetMargins;

        // Move block if it overflows float area
        if El.SrcEl.IsReplaced or
           El.SrcEl.IsBlockFormattingContext or
           (ElCss.Display = displayTable) then
        begin
          if El.Right > LineRight then
          begin
            LnLeft := 0;
            LnRight := El.Width;
            NewTop := FmtCtx.FindNextLineTop(ChildTop, El.Width, LnRight);
            if NewTop <> ChildTop then
            begin
              ChildTop := NewTop;
              FmtCtx.GetLineLeftRight(ChildTop, El.Width, LnLeft, LnRight);
              El.FPos.X := LnLeft + El.ContentOffsetLeft;
              El.FPos.Y := ChildTop + El.ContentOffsetTop;
              ChildTop := ChildTop - ChildMargins.Top;
              // Rollback top margin collapse
              if IsFirst and CollapseTopMargin then
                TopMargin := FMargins.Top;
            end;
          end;
        end;

        AutoMargin := El.CalcAutoMargins(ChildWidth);
        if AutoMargin <> 0 then
          El.FPos.X := El.FPos.X + AutoMargin;

        if Rw > RetWidth then
          RetWidth := Rw;

        FMargins.Top := TopMargin;
        ChildTop := ChildTop + El.Height;
        LastMargin := ChildMargins.Bottom;
        LastMarginEl := El;
        IsFirst := False;

        if ElCss.ElPosition = epRelative then
          El.ApplyRelativeShift(SelfSize);
      end;
    end;
  end;

  if (SelfSize.Height.ValueType <> cbcAuto) and (SelfSize.Height.Value > 0) then
    FPos.Height := SelfSize.Height.Value
  else
  begin
    FPos.Height := ChildTop;
    if CollapseBottomMargin then
    begin
      FPos.Height := FPos.Height - LastMargin;
      if FMargins.Bottom < LastMargin then
        FMargins.Bottom := LastMargin;
      if LastMarginEl <> nil then
        LastMarginEl.FMargins.Bottom := 0;
    end;
  end;

  Result := RetWidth;
end;

function TPixieRenderBlockContext.GetFirstBaseline: pixel_t;
var
  Item: TPixieRenderItem;
begin
  if FChildren.Count = 0 then
    Exit(Height - MarginBottom);
  Item := FChildren[0];
  Result := ContentOffsetTop + Item.Top + Item.GetFirstBaseline;
end;

function TPixieRenderBlockContext.GetLastBaseline: pixel_t;
var
  Item: TPixieRenderItem;
begin
  if FChildren.Count = 0 then
    Exit(Height - MarginBottom);
  Item := FChildren[FChildren.Count - 1];
  Result := ContentOffsetTop + Item.Top + Item.GetLastBaseline;
end;

initialization
  PixieRenderBlockContextClass := TPixieRenderBlockContext;

end.
