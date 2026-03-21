unit Pixie.Element;

// Abstract DOM element base class.
//
// This is the base class for all DOM nodes. It holds:
//  - parent/children references (non-owning)
//  - CSS properties (owned)
//  - render item list (Pointer for Phase 5)
//  - used selector tracking
//  - counter values
// The document owns all element instances; elements do not free each other.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections,
  Pixie.Types, Pixie.StringId, Pixie.Html,
  Pixie.CssProperties, Pixie.Style,
  Pixie.CssSelector, Pixie.Stylesheet,
  Pixie.Container, Pixie.Background;

type
  TPixieElement = class;
  TPixieElementList = TObjectList<TPixieElement>;
  TPixiePointerList = TList<Pointer>;
  TPixieIntIntMap = TDictionary<Integer, Integer>;

  { TPixieElement }

  TPixieElement = class
  protected
    FParent: TPixieElement;
    FDoc: TObject;
    FChildren: TPixieElementList;
    FCss: TPixieCssProperties;
    FRenders: TPixiePointerList;
    FUsedStyles: TPixieUsedSelectorList;
    FCounterValues: TPixieIntIntMap;

    function AddBeforeAfter(AType: Integer;
      const AStyle: TPixieStyle): TPixieElement;

  private
    function GetSiblingsBefore: TPixieElementList;
    function FindCounter(CounterNameId: Integer;
      out FoundEl: TPixieElement; out FoundValue: Integer): Boolean;
  public
    procedure SelectAll(const Selector: TPixieCssSelector;
      Res: TPixieElementList); virtual;
    constructor Create(ADoc: TObject);
    destructor Destroy; override;

    // CSS properties
    function Css: TPixieCssProperties; inline;
    function CssW: TPixieCssProperties; inline;

    // Flow/display helpers
    function InNormalFlow: Boolean; inline;
    function IsInline: Boolean;
    function IsInlineBox: Boolean;
    function IsBlockBox: Boolean;
    function IsPositioned: Boolean; inline;
    function IsFloat_: Boolean; inline;
    function IsBlockFormattingContext: Boolean;
    function IsRoot: Boolean; inline;
    function IsTableSkip: Boolean;

    // Navigation
    function Parent: TPixieElement; inline;
    procedure SetParent(El: TPixieElement); inline;
    function GetDocument: TObject; inline;
    function Children: TPixieElementList; inline;

    // Virtual methods — stubs in base class
    function AppendChild(El: TPixieElement): Boolean; virtual;
    function InsertBefore(NewChild, RefChild: TPixieElement): Boolean; virtual;
    function RemoveChild(El: TPixieElement): Boolean; virtual;
    procedure ClearRecursive; virtual;

    function GetId: Integer; virtual;
    function GetTag: Integer; virtual;
    function GetTagName: string; virtual;
    procedure SetTagName(const ATag: string); virtual;
    procedure SetData(const AData: string); virtual;
    procedure SetAttr(const AName, AVal: string); virtual;
    function GetAttr(const AName: string;
      const ADef: string = ''): string; virtual;

    procedure ApplyStylesheet(
      Stylesheet: TPixieStylesheet); virtual;
    procedure RefreshStyles; virtual;
    procedure ComputeStyles(Recursive: Boolean = True); virtual;

    function Select(const SelectorList: TPixieCssSelectorList;
      ApplyPseudo: Boolean = True): Integer; virtual;
    function SelectSel(const Selector: TPixieCssSelector;
      ApplyPseudo: Boolean = True): Integer; virtual;
    function SelectCompound(
      const Selector: TPixieCompoundSelector;
      ApplyPseudo: Boolean = True): Integer; virtual;

    function FindAncestor(const Selector: TPixieCssSelector;
      ApplyPseudo: Boolean = True;
      IsPseudo: PBoolean = nil): TPixieElement; virtual;
    function IsAncestor(El: TPixieElement): Boolean; virtual;
    function FindAdjacentSibling(El: TPixieElement;
      const Selector: TPixieCssSelector;
      ApplyPseudo: Boolean = True;
      IsPseudo: PBoolean = nil): TPixieElement; virtual;
    function FindSibling(El: TPixieElement;
      const Selector: TPixieCssSelector;
      ApplyPseudo: Boolean = True;
      IsPseudo: PBoolean = nil): TPixieElement; virtual;

    function SetPseudoClass(Cls: Integer;
      Add: Boolean): Boolean; virtual;
    function IsWhiteSpace: Boolean; virtual;
    function IsSpace: Boolean; virtual;
    function IsComment: Boolean; virtual;
    function IsBody: Boolean; virtual;
    function IsBreak: Boolean; virtual;
    function IsText: Boolean; virtual;
    function IsReplaced: Boolean; virtual;

    function OnMouseOver: Boolean; virtual;
    function OnMouseLeave: Boolean; virtual;
    function OnLButtonDown: Boolean; virtual;
    function OnLButtonUp(IsClick: Boolean = True): Boolean; virtual;
    function OnLButtonDblClick: Boolean; virtual;
    procedure OnClick; virtual;

    // Focus and keyboard
    procedure OnFocus; virtual;
    procedure OnBlur; virtual;
    function OnKeyDown(Key: Word; Shift: TShiftState): Boolean; virtual;
    function OnUTF8KeyPress(const UTF8Char: string): Boolean; virtual;
    function IsFocusable: Boolean; virtual;
    function OnMouseDrag(X, Y: pixel_t): Boolean; virtual;
    function OnMouseWheel(Delta: Integer): Boolean; virtual;

    procedure GetText(var Text: string); virtual;
    function GetTextContent: string; virtual;
    procedure SetTextContent(const AText: string); virtual;
    procedure ParseAttributes; virtual;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: pixel_t); virtual;
    procedure AddStyle(const AStyle: TPixieStyle); virtual;
    procedure Draw(Hdc: PtrUInt; X, Y: pixel_t;
      Clip: PPixiePosition; Ri: Pointer); virtual;
    procedure DrawBackground(Hdc: PtrUInt; X, Y: pixel_t;
      Clip: PPixiePosition; Ri: Pointer); virtual;

    function IsNthChild(El: TPixieElement; Num, Off: Integer;
      OfType: Boolean;
      SelectorList: TPixieCssSelectorList = nil): Boolean; virtual;
    function IsNthLastChild(El: TPixieElement; Num, Off: Integer;
      OfType: Boolean;
      SelectorList: TPixieCssSelectorList = nil): Boolean; virtual;
    function IsOnlyChild(El: TPixieElement;
      OfType: Boolean): Boolean; virtual;
    function GetBackground(
      OwnOnly: Boolean = False): TPixieBackground; virtual;

    function CreateRenderItem(ParentRi: Pointer): Pointer; virtual;

    // Pseudo-elements
    function AddPseudoBefore(
      const AStyle: TPixieStyle): TPixieElement;
    function AddPseudoAfter(
      const AStyle: TPixieStyle): TPixieElement;

    // Counters
    function GetCounterValue(
      const CounterName: string): string;
    function GetCountersValue(
      const Params: TPixieStringVector): string;
    procedure IncrementCounter(CounterNameId: Integer;
      Increment: Integer = 1);
    procedure ResetCounter(CounterNameId: Integer;
      Value: Integer = 0);

    // Render tracking
    procedure AddRender(Ri: Pointer);
    procedure ClearRenders;
    function GetRenderItem: Pointer;
    procedure ClearUsedStyles;
    procedure ResetStyle; virtual;
    procedure ClearCounterValues;
    function RequiresStylesUpdate: Boolean;
    function FindStylesChanges(
      RedrawBoxes: TPixiePositionVector): Boolean;

    // Dump
    function DumpGetName: string; virtual;

    // Used styles access (for refresh)
    property UsedStyles: TPixieUsedSelectorList read FUsedStyles;
    property CounterValues: TPixieIntIntMap
      read FCounterValues;
  end;

implementation

uses
  Pixie.Document, Pixie.RenderItem, Pixie.RenderBlock,
  Pixie.RenderInline, Pixie.RenderImage, Pixie.RenderTable,
  Pixie.RenderFlex, Pixie.RenderGrid;

{ TPixieElement }

constructor TPixieElement.Create(ADoc: TObject);
begin
  inherited Create;
  FDoc := ADoc;
  FParent := nil;
  FChildren := TPixieElementList.Create(False); // non-owning
  FCss := TPixieCssProperties.Create;
  FRenders := TPixiePointerList.Create;
  FUsedStyles := nil;
  FCounterValues := nil;
end;

destructor TPixieElement.Destroy;
begin
  FCounterValues.Free;
  FUsedStyles.Free;
  FRenders.Free;
  FCss.Free;
  FChildren.Free;
  inherited Destroy;
end;

function TPixieElement.Css: TPixieCssProperties;
begin
  Result := FCss;
end;

function TPixieElement.CssW: TPixieCssProperties;
begin
  Result := FCss;
end;

// Inline helper functions

function TPixieElement.InNormalFlow: Boolean;
begin
  Result := (FCss.ElPosition <> epAbsolute) and
            (FCss.Display <> displayNone) and
            (FCss.ElPosition <> epFixed);
end;

function TPixieElement.IsInline: Boolean;
begin
  Result := (FCss.Display = displayInline) or
            (FCss.Display = displayInlineTable) or
            (FCss.Display = displayInlineBlock) or
            (FCss.Display = displayInlineText) or
            (FCss.Display = displayInlineFlex) or
            (FCss.Display = displayInlineGrid);
end;

function TPixieElement.IsInlineBox: Boolean;
begin
  Result := (FCss.Display = displayInlineTable) or
            (FCss.Display = displayInlineBlock) or
            (FCss.Display = displayInlineFlex) or
            (FCss.Display = displayInlineGrid);
end;

function TPixieElement.IsBlockBox: Boolean;
begin
  Result := (FCss.Display = displayBlock) or
            (FCss.Display = displayFlex) or
            (FCss.Display = displayGrid) or
            (FCss.Display = displayFlowRoot) or
            (FCss.Display = displayTable) or
            (FCss.Display = displayListItem);
end;

function TPixieElement.IsPositioned: Boolean;
begin
  Result := FCss.ElPosition > epStatic;
end;

function TPixieElement.IsFloat_: Boolean;
begin
  Result := FCss.Float_ <> efNone;
end;

function TPixieElement.IsBlockFormattingContext: Boolean;
var
  Par: TPixieElement;
begin
  if FCss.Display = displayBlock then
  begin
    Par := Parent;
    if (Par <> nil) and
       ((Par.Css.Display = displayInlineFlex) or
        (Par.Css.Display = displayFlex) or
        (Par.Css.Display = displayGrid) or
        (Par.Css.Display = displayInlineGrid)) then
      Exit(True);
  end;
  if (FCss.Display = displayInlineBlock) or
     (FCss.Display = displayTableCell) or
     (FCss.Display = displayInlineFlex) or
     (FCss.Display = displayFlex) or
     (FCss.Display = displayGrid) or
     (FCss.Display = displayInlineGrid) or
     (FCss.Display = displayFlowRoot) or
     (FCss.Display = displayTableCaption) or
     IsRoot or
     (FCss.Float_ <> efNone) or
     (FCss.ElPosition = epAbsolute) or
     (FCss.ElPosition = epFixed) or
     (FCss.Overflow > ovVisible) then
    Exit(True);
  Result := False;
end;

function TPixieElement.IsRoot: Boolean;
begin
  Result := FParent = nil;
end;

function TPixieElement.IsTableSkip: Boolean;
begin
  Result := IsSpace or IsComment or (FCss.Display = displayNone);
end;

function TPixieElement.Parent: TPixieElement;
begin
  Result := FParent;
end;

procedure TPixieElement.SetParent(El: TPixieElement);
begin
  FParent := El;
end;

function TPixieElement.GetDocument: TObject;
begin
  Result := FDoc;
end;

function TPixieElement.Children: TPixieElementList;
begin
  Result := FChildren;
end;

// Virtual stubs — base class returns default values

function TPixieElement.AppendChild(El: TPixieElement): Boolean;
begin
  Result := False;
end;

function TPixieElement.InsertBefore(NewChild,
  RefChild: TPixieElement): Boolean;
begin
  Result := False;
end;

function TPixieElement.RemoveChild(El: TPixieElement): Boolean;
begin
  Result := False;
end;

procedure TPixieElement.ClearRecursive;
begin
end;

function TPixieElement.GetId: Integer;
begin
  Result := -1;
end;

function TPixieElement.GetTag: Integer;
begin
  Result := -1;
end;

function TPixieElement.GetTagName: string;
begin
  Result := '';
end;

procedure TPixieElement.SetTagName(const ATag: string);
begin
end;

procedure TPixieElement.SetData(const AData: string);
begin
end;

procedure TPixieElement.SetAttr(const AName, AVal: string);
begin
end;

function TPixieElement.GetAttr(const AName: string;
  const ADef: string): string;
begin
  Result := ADef;
end;

procedure TPixieElement.ApplyStylesheet(Stylesheet: TPixieStylesheet);
begin
end;

procedure TPixieElement.RefreshStyles;
begin
end;

procedure TPixieElement.ComputeStyles(Recursive: Boolean);
begin
end;

function TPixieElement.Select(
  const SelectorList: TPixieCssSelectorList;
  ApplyPseudo: Boolean): Integer;
begin
  Result := SelectNoMatch;
end;

function TPixieElement.SelectSel(const Selector: TPixieCssSelector;
  ApplyPseudo: Boolean): Integer;
begin
  Result := SelectNoMatch;
end;

function TPixieElement.SelectCompound(
  const Selector: TPixieCompoundSelector;
  ApplyPseudo: Boolean): Integer;
begin
  Result := SelectNoMatch;
end;

function TPixieElement.FindAncestor(const Selector: TPixieCssSelector;
  ApplyPseudo: Boolean; IsPseudo: PBoolean): TPixieElement;
begin
  Result := nil;
end;

function TPixieElement.IsAncestor(El: TPixieElement): Boolean;
var
  Par: TPixieElement;
begin
  Par := Parent;
  while (Par <> nil) and (Par <> El) do
    Par := Par.Parent;
  Result := Par <> nil;
end;

function TPixieElement.FindAdjacentSibling(El: TPixieElement;
  const Selector: TPixieCssSelector; ApplyPseudo: Boolean;
  IsPseudo: PBoolean): TPixieElement;
begin
  Result := nil;
end;

function TPixieElement.FindSibling(El: TPixieElement;
  const Selector: TPixieCssSelector; ApplyPseudo: Boolean;
  IsPseudo: PBoolean): TPixieElement;
begin
  Result := nil;
end;

function TPixieElement.SetPseudoClass(Cls: Integer;
  Add: Boolean): Boolean;
begin
  Result := False;
end;

function TPixieElement.IsWhiteSpace: Boolean;
begin
  Result := False;
end;

function TPixieElement.IsSpace: Boolean;
begin
  Result := False;
end;

function TPixieElement.IsComment: Boolean;
begin
  Result := False;
end;

function TPixieElement.IsBody: Boolean;
begin
  Result := False;
end;

function TPixieElement.IsBreak: Boolean;
begin
  Result := False;
end;

function TPixieElement.IsText: Boolean;
begin
  Result := False;
end;

function TPixieElement.IsReplaced: Boolean;
begin
  Result := False;
end;

function TPixieElement.OnMouseOver: Boolean;
begin
  Result := False;
end;

function TPixieElement.OnMouseLeave: Boolean;
begin
  Result := False;
end;

function TPixieElement.OnLButtonDown: Boolean;
begin
  Result := False;
end;

function TPixieElement.OnLButtonUp(IsClick: Boolean): Boolean;
begin
  Result := False;
end;

function TPixieElement.OnLButtonDblClick: Boolean;
begin
  Result := False;
end;

procedure TPixieElement.OnClick;
begin
end;

procedure TPixieElement.OnFocus;
begin
end;

procedure TPixieElement.OnBlur;
begin
end;

function TPixieElement.OnKeyDown(Key: Word; Shift: TShiftState): Boolean;
begin
  Result := False;
end;

function TPixieElement.OnUTF8KeyPress(const UTF8Char: string): Boolean;
begin
  Result := False;
end;

function TPixieElement.IsFocusable: Boolean;
begin
  Result := False;
end;

function TPixieElement.OnMouseDrag(X, Y: pixel_t): Boolean;
begin
  Result := False;
end;

function TPixieElement.OnMouseWheel(Delta: Integer): Boolean;
begin
  Result := False;
end;

procedure TPixieElement.GetText(var Text: string);
begin
end;

function TPixieElement.GetTextContent: string;
begin
  Result := '';
  GetText(Result);
end;

procedure TPixieElement.SetTextContent(const AText: string);
begin
  // Base class stub — overridden in TPixieHtmlTag
end;

procedure TPixieElement.ParseAttributes;
begin
end;

procedure TPixieElement.GetContentSize(var Sz: TPixieSize;
  MaxWidth: pixel_t);
begin
end;

procedure TPixieElement.AddStyle(const AStyle: TPixieStyle);
begin
end;

procedure TPixieElement.Draw(Hdc: PtrUInt; X, Y: pixel_t;
  Clip: PPixiePosition; Ri: Pointer);
begin
end;

procedure TPixieElement.DrawBackground(Hdc: PtrUInt; X, Y: pixel_t;
  Clip: PPixiePosition; Ri: Pointer);
begin
end;

function TPixieElement.IsNthChild(El: TPixieElement;
  Num, Off: Integer; OfType: Boolean;
  SelectorList: TPixieCssSelectorList): Boolean;
begin
  Result := False;
end;

function TPixieElement.IsNthLastChild(El: TPixieElement;
  Num, Off: Integer; OfType: Boolean;
  SelectorList: TPixieCssSelectorList): Boolean;
begin
  Result := False;
end;

function TPixieElement.IsOnlyChild(El: TPixieElement;
  OfType: Boolean): Boolean;
begin
  Result := False;
end;

function TPixieElement.GetBackground(OwnOnly: Boolean): TPixieBackground;
begin
  Result := nil;
end;

function TPixieElement.CreateRenderItem(ParentRi: Pointer): Pointer;
var
  Ret: TPixieRenderItem;
  Disp: TPixieDisplay;
  I: Integer;
  ChildRi: TPixieRenderItem;
  Doc: TPixieDocument;
begin
  Ret := nil;
  Disp := FCss.Display;

  case Disp of
    displayTableColumn, displayTableColumnGroup,
    displayTableFooterGroup, displayTableHeaderGroup,
    displayTableRowGroup:
      Ret := TPixieRenderTablePart.Create(Self);
    displayTableRow:
      Ret := TPixieRenderTableRow.Create(Self);
    displayBlock, displayTableCell, displayTableCaption,
    displayListItem, displayInlineBlock, displayFlowRoot:
      Ret := TPixieRenderBlock.Create(Self);
    displayTable, displayInlineTable:
      Ret := TPixieRenderTable.Create(Self);
    displayInline, displayInlineText:
      Ret := TPixieRenderInline.Create(Self);
    displayFlex, displayInlineFlex:
      Ret := TPixieRenderFlex.Create(Self);
    displayGrid, displayInlineGrid:
      Ret := PixieRenderGridClass.Create(Self);
  end;

  if Ret <> nil then
  begin
    // Register tabular elements
    if Disp in [displayTable, displayInlineTable,
      displayTableCaption, displayTableCell,
      displayTableColumn, displayTableColumnGroup,
      displayTableFooterGroup, displayTableHeaderGroup,
      displayTableRow, displayTableRowGroup] then
    begin
      Assert(FDoc is TPixieDocument);
      Doc := TPixieDocument(FDoc);
      Doc.AddTabular(Ret);
    end;

    if ParentRi <> nil then
      Assert(TObject(ParentRi) is TPixieRenderItem);
    Ret.SetParent(TPixieRenderItem(ParentRi));
    for I := 0 to FChildren.Count - 1 do
    begin
      ChildRi := TPixieRenderItem(FChildren[I].CreateRenderItem(Ret));
      if ChildRi <> nil then
        Ret.AddChild(ChildRi);
    end;
  end;
  Result := Ret;
end;

function TPixieElement.DumpGetName: string;
begin
  Result := 'element';
end;

// Pseudo-element helpers

function TPixieElement.AddPseudoBefore(
  const AStyle: TPixieStyle): TPixieElement;
begin
  Result := AddBeforeAfter(0, AStyle);
end;

function TPixieElement.AddPseudoAfter(
  const AStyle: TPixieStyle): TPixieElement;
begin
  Result := AddBeforeAfter(1, AStyle);
end;

function TPixieElement.AddBeforeAfter(AType: Integer;
  const AStyle: TPixieStyle): TPixieElement;
begin
  // Will be implemented properly when Pixie.ElBeforeAfter is available.
  // Phase 4 step 6 will complete this; for now return nil.
  Result := nil;
end;

// Counter implementation

function TPixieElement.GetCounterValue(
  const CounterName: string): string;
var
  FoundEl: TPixieElement;
  FoundValue: Integer;
begin
  if FindCounter(PixieId(CounterName), FoundEl, FoundValue) then
    Result := IntToStr(FoundValue)
  else
    Result := '0';
end;

function TPixieElement.GetCountersValue(
  const Params: TPixieStringVector): string;
var
  CounterNameId: Integer;
  Delims: string;
  Values: TPixieStringVector;
  Current: TPixieElement;
  Val: Integer;
  I: Integer;
begin
  Result := '';
  if Params.Count < 2 then
    Exit;

  CounterNameId := PixieId(Params[0]);
  Delims := Params[1];
  Delims := PixieTrim(Delims, '"''');

  Values := TPixieStringVector.Create;
  try
    Current := Self;
    while Current <> nil do
    begin
      if (Current.FCounterValues <> nil) and
         Current.FCounterValues.TryGetValue(CounterNameId, Val) then
        Values.Add(IntToStr(Val));
      Current := Current.Parent;
    end;

    if Values.Count = 0 then
    begin
      // If no counter is found, instance one with value 0
      if FCounterValues = nil then
        FCounterValues := TPixieIntIntMap.Create;
      FCounterValues.AddOrSetValue(CounterNameId, 0);
      Result := '0';
    end
    else
    begin
      // Reverse the values (collected from child to root)
      Result := '';
      for I := Values.Count - 1 downto 0 do
      begin
        if Result <> '' then
          Result := Result + Delims;
        Result := Result + Values[I];
      end;
    end;
  finally
    Values.Free;
  end;
end;

function TPixieElement.FindCounter(CounterNameId: Integer;
  out FoundEl: TPixieElement; out FoundValue: Integer): Boolean;
var
  Current: TPixieElement;
  Siblings: TPixieElementList;
  I: Integer;
  Val: Integer;
begin
  Current := Self;
  while Current <> nil do
  begin
    if (Current.FCounterValues <> nil) and
       Current.FCounterValues.TryGetValue(CounterNameId, Val) then
    begin
      FoundEl := Current;
      FoundValue := Val;
      Exit(True);
    end;

    // Search previous siblings on each level
    Siblings := Current.GetSiblingsBefore;
    try
      for I := Siblings.Count - 1 downto 0 do
      begin
        if (Siblings[I].FCounterValues <> nil) and
           Siblings[I].FCounterValues.TryGetValue(
           CounterNameId, Val) then
        begin
          FoundEl := Siblings[I];
          FoundValue := Val;
          Exit(True);
        end;
      end;
    finally
      Siblings.Free;
    end;

    Current := Current.Parent;
  end;

  FoundEl := nil;
  FoundValue := 0;
  Result := False;
end;

function TPixieElement.GetSiblingsBefore: TPixieElementList;
var
  I: Integer;
begin
  Result := TPixieElementList.Create(False);
  if FParent <> nil then
    for I := 0 to FParent.FChildren.Count - 1 do
    begin
      if FParent.FChildren[I] = Self then
        Break;
      Result.Add(FParent.FChildren[I]);
    end;
end;

procedure TPixieElement.IncrementCounter(CounterNameId: Integer;
  Increment: Integer);
var
  FoundEl: TPixieElement;
  FoundValue: Integer;
begin
  if FindCounter(CounterNameId, FoundEl, FoundValue) then
  begin
    if FoundEl.FCounterValues = nil then
      FoundEl.FCounterValues := TPixieIntIntMap.Create;
    FoundEl.FCounterValues.AddOrSetValue(CounterNameId,
      FoundValue + Increment);
  end
  else
  begin
    if FCounterValues = nil then
      FCounterValues := TPixieIntIntMap.Create;
    FCounterValues.AddOrSetValue(CounterNameId, Increment);
  end;
end;

procedure TPixieElement.ResetCounter(CounterNameId: Integer;
  Value: Integer);
begin
  if FCounterValues = nil then
    FCounterValues := TPixieIntIntMap.Create;
  FCounterValues.AddOrSetValue(CounterNameId, Value);
end;

// Render tracking

procedure TPixieElement.AddRender(Ri: Pointer);
begin
  FRenders.Add(Ri);
end;

procedure TPixieElement.ClearRenders;
begin
  FRenders.Clear;
end;

function TPixieElement.GetRenderItem: Pointer;
begin
  if FRenders.Count = 0 then
    Result := nil
  else
    Result := FRenders[0];
end;

procedure TPixieElement.ClearUsedStyles;
begin
  FreeAndNil(FUsedStyles);
end;

procedure TPixieElement.ResetStyle;
begin
  // Base class stub — overridden in TPixieHtmlTag
end;

procedure TPixieElement.ClearCounterValues;
begin
  FreeAndNil(FCounterValues);
end;

function TPixieElement.RequiresStylesUpdate: Boolean;
var
  I, Res: Integer;
  UsedSel: TPixieUsedSelector;
begin
  if FUsedStyles = nil then
    Exit(False);
  for I := 0 to FUsedStyles.Count - 1 do
  begin
    UsedSel := FUsedStyles[I];
    if UsedSel.Selector.IsMediaValid then
    begin
      Res := SelectSel(UsedSel.Selector, True);
      if ((Res = SelectNoMatch) and UsedSel.Used) or
         ((Res = SelectMatch) and not UsedSel.Used) then
        Exit(True);
    end;
  end;
  Result := False;
end;

function TPixieElement.FindStylesChanges(
  RedrawBoxes: TPixiePositionVector): Boolean;
var
  I: Integer;
  El: TPixieElement;
begin
  if FCss.Display = displayInlineText then
    Exit(False);

  Result := False;

  if RequiresStylesUpdate then
  begin
    // Render box collection deferred to Phase 5
    RefreshStyles;
    ComputeStyles;
    Result := True;
  end;

  for I := 0 to FChildren.Count - 1 do
  begin
    El := FChildren[I];
    if El.FindStylesChanges(RedrawBoxes) then
      Result := True;
  end;
end;

// Select all / select one

procedure TPixieElement.SelectAll(
  const Selector: TPixieCssSelector; Res: TPixieElementList);
begin
  // Base implementation: do nothing
end;

end.
