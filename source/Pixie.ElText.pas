unit Pixie.ElText;

// Text and whitespace DOM nodes.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils,
  Pixie.Types, Pixie.CssProperties,
  Pixie.Container, Pixie.Element;

type
  { TPixieElText }

  TPixieElText = class(TPixieElement)
  protected
    FText: string;
    FTransformedText: string;
    FSize: TPixieSize;
    FUseTransformed: Boolean;
    FDrawSpaces: Boolean;
  public
    constructor Create(const AText: string; ADoc: TObject);

    procedure GetText(var Text: string); override;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: TPixiePixel); override;
    function IsText: Boolean; override;
    procedure ComputeStyles(Recursive: Boolean = True); override;
    procedure Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; Ri: Pointer); override;
    function CreateRenderItem(ParentRi: Pointer): Pointer; override;
    function DumpGetName: string; override;
  end;

  { TPixieElSpace }

  TPixieElSpace = class(TPixieElText)
  public
    constructor Create(const AText: string; ADoc: TObject);

    function IsWhiteSpace: Boolean; override;
    function IsBreak: Boolean; override;
    function IsSpace: Boolean; override;
    function DumpGetName: string; override;
  end;

implementation

uses
  Pixie.StringId, Pixie.Html, Pixie.HtmlTag,
  Pixie.WebColor, Pixie.RenderItem, Pixie.Document;

const
  PixieSelectionColor: TPixieWebColor = (
    Red: 51; Green: 153; Blue: 255; Alpha: 102;
    IsCurrentColor: False);

{ TPixieElText }

constructor TPixieElText.Create(const AText: string; ADoc: TObject);
begin
  inherited Create(ADoc);
  FText := AText;
  FUseTransformed := False;
  FDrawSpaces := True;
  FCss.Display := displayInlineText;
end;

procedure TPixieElText.GetText(var Text: string);
begin
  Text := Text + FText;
end;

procedure TPixieElText.GetContentSize(var Sz: TPixieSize;
  MaxWidth: TPixiePixel);
begin
  Sz := FSize;
end;

function TPixieElText.IsText: Boolean;
begin
  Result := True;
end;

procedure TPixieElText.ComputeStyles(Recursive: Boolean);
var
  Par: TPixieElement;
  Cont: TPixieContainer;
  Txt: string;
  WS: TPixieWhiteSpace;
begin
  Par := Parent;
  if Par = nil then
    Exit;

  // Inherit properties from parent
  FCss.LineHeight := Par.Css.LineHeight;
  FCss.Font := Par.Css.Font;
  FCss.FontMetrics := Par.Css.FontMetrics;
  FCss.WhiteSpace := Par.Css.WhiteSpace;
  FCss.OverflowWrap := Par.Css.OverflowWrap;
  FCss.TextTransform := Par.Css.TextTransform;
  FCss.FontSize := Par.Css.FontSize;

  // Get container from nearest html_tag ancestor
  Cont := nil;
  if Par is TPixieHtmlTag then
    Cont := TPixieHtmlTag(Par).GetDocContainer;

  if FCss.TextTransform <> ttNone then
  begin
    FTransformedText := FText;
    if Cont <> nil then
      Cont.TransformText(FTransformedText, FCss.TextTransform);
    FUseTransformed := True;
  end
  else
    FUseTransformed := False;

  // Handle whitespace transformations
  WS := FCss.WhiteSpace;
  if IsWhiteSpace then
  begin
    FTransformedText := ' ';
    FUseTransformed := True;
  end
  else
  begin
    if not FUseTransformed then
      FTransformedText := FText;

    // Tab replacement
    if Pos(#9, FTransformedText) > 0 then
    begin
      FTransformedText := StringReplace(FTransformedText,
        #9, '    ', [rfReplaceAll]);
      FUseTransformed := True;
    end;

    // Newline handling in non-pre modes
    if (WS <> wsNowrap) and (WS <> wsPre) and
       (WS <> wsPreWrap) and (WS <> wsPreLine) then
    begin
      if Pos(#10, FTransformedText) > 0 then
      begin
        FTransformedText := StringReplace(FTransformedText,
          #10, '', [rfReplaceAll]);
        FUseTransformed := True;
      end;
      if Pos(#13, FTransformedText) > 0 then
      begin
        FTransformedText := StringReplace(FTransformedText,
          #13, '', [rfReplaceAll]);
        FUseTransformed := True;
      end;
    end;
  end;

  // Inherit position if parent is relative
  if Par.Css.ElPosition = epRelative then
  begin
    FCss.ElPosition := epRelative;
    FCss.CssOffsets := Par.Css.CssOffsets;
  end;

  // Compute size
  if FUseTransformed then
    Txt := FTransformedText
  else
    Txt := FText;

  FSize.Height := 0;
  FSize.Width := 0;

  if (not IsBreak) and (FCss.Font <> 0) then
  begin
    FSize.Height := FCss.FontMetrics.Height;
    if (Txt <> '') and (Cont <> nil) then
      FSize.Width := Cont.TextWidth(Txt, FCss.Font);
  end;

  FDrawSpaces := FCss.FontMetrics.DrawSpaces;
end;

procedure TPixieElText.Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
  Clip: PPixiePosition; Ri: Pointer);
var
  Pos: TPixiePosition;
  ElParent: TPixieElement;
  Doc: TPixieDocument;
  HFont: PtrUInt;
  Color: TPixieWebColor;
  Txt: string;
begin
  if IsWhiteSpace and (not FDrawSpaces) then
    Exit;

  Assert(TObject(Ri) is TPixieRenderItem);
  Pos := TPixieRenderItem(Ri).Pos;
  Pos.X := Pos.X + X;
  Pos.Y := Pos.Y + Y;
  Pos.DoRound;

  if (Clip = nil) or Pos.DoesIntersect(Clip^) then
  begin
    ElParent := Parent;
    if ElParent <> nil then
    begin
      Assert(FDoc is TPixieDocument);
      Doc := TPixieDocument(FDoc);
      if Doc.IsSelected(Self) then
        Doc.Container.DrawHighlight(Hdc, Pos, PixieSelectionColor);
      HFont := ElParent.Css.Font;
      if HFont <> 0 then
      begin
        Color := ElParent.Css.Color;
        if FUseTransformed then
          Txt := FTransformedText
        else
          Txt := FText;
        Doc.Container.DrawText(Hdc, Txt, HFont, Color, Pos);
      end;
    end;
  end;
end;

function TPixieElText.CreateRenderItem(ParentRi: Pointer): Pointer;
begin
  Result := inherited CreateRenderItem(ParentRi);
end;

function TPixieElText.DumpGetName: string;
var
  S: string;
begin
  S := FText;
  S := StringReplace(S, #10, '\n', [rfReplaceAll]);
  S := StringReplace(S, #13, '\r', [rfReplaceAll]);
  S := StringReplace(S, #9, '\t', [rfReplaceAll]);
  Result := 'text: "' + S + '"';
end;

{ TPixieElSpace }

constructor TPixieElSpace.Create(const AText: string; ADoc: TObject);
begin
  inherited Create(AText, ADoc);
end;

function TPixieElSpace.IsWhiteSpace: Boolean;
begin
  case FCss.WhiteSpace of
    wsNormal, wsNowrap, wsPreLine:
      Result := True;
  else
    Result := False;
  end;
end;

function TPixieElSpace.IsBreak: Boolean;
begin
  Result := False;
  case FCss.WhiteSpace of
    wsPre, wsPreLine, wsPreWrap:
      Result := FText = #10;
    else
      ;
  end;
end;

function TPixieElSpace.IsSpace: Boolean;
begin
  Result := True;
end;

function TPixieElSpace.DumpGetName: string;
var
  S: string;
begin
  S := FText;
  S := StringReplace(S, #10, '\n', [rfReplaceAll]);
  S := StringReplace(S, #13, '\r', [rfReplaceAll]);
  S := StringReplace(S, #9, '\t', [rfReplaceAll]);
  Result := 'space: "' + S + '"';
end;

end.
