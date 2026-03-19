unit Pixie.ElImage;

// Image element (<img>).

{$mode delphi}

interface

uses
  SysUtils,
  Pixie.Types, Pixie.CssLength, Pixie.Background,
  Pixie.Container,
  Pixie.Element, Pixie.HtmlTag;

type
  { TPixieElImage }

  TPixieElImage = class(TPixieHtmlTag)
  private
    FSrc: string;
  public
    constructor Create(ADoc: TObject);

    function IsReplaced: Boolean; override;
    procedure ParseAttributes; override;
    procedure ComputeStyles(Recursive: Boolean = True); override;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: pixel_t); override;
    procedure Draw(Hdc: PtrUInt; X, Y: pixel_t;
      Clip: PPixiePosition; Ri: Pointer); override;
    function CreateRenderItem(ParentRi: Pointer): Pointer; override;
    function DumpGetName: string; override;
  end;

implementation

uses
  Pixie.StringId, Pixie.RenderItem, Pixie.RenderImage;

{ TPixieElImage }

constructor TPixieElImage.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
  FCss.Display := displayInlineBlock;
end;

function TPixieElImage.IsReplaced: Boolean;
begin
  Result := True;
end;

procedure TPixieElImage.ParseAttributes;
var
  Val: string;
begin
  FSrc := GetAttr('src');

  Val := GetAttr('width');
  if Val <> '' then
    MapToDimensionProperty(Ord(psid_width), Val);

  Val := GetAttr('height');
  if Val <> '' then
    MapToDimensionProperty(Ord(psid_height), Val);

  inherited ParseAttributes;
end;

procedure TPixieElImage.ComputeStyles(Recursive: Boolean);
var
  Cont: TPixieContainer;
  ForceLoad: Boolean;
begin
  inherited ComputeStyles(Recursive);

  if FSrc <> '' then
  begin
    Cont := GetDocContainer;
    if Cont <> nil then
    begin
      ForceLoad := (not FCss.CssWidth.IsPredefined) and
                   (not FCss.CssHeight.IsPredefined);
      Cont.LoadImage(FSrc, '', ForceLoad);
    end;
  end;
end;

procedure TPixieElImage.GetContentSize(var Sz: TPixieSize;
  MaxWidth: pixel_t);
var
  Cont: TPixieContainer;
begin
  Sz.Width := 0;
  Sz.Height := 0;
  Cont := GetDocContainer;
  if Cont <> nil then
    Cont.GetImageSize(FSrc, '', Sz);
end;

procedure TPixieElImage.Draw(Hdc: PtrUInt; X, Y: pixel_t;
  Clip: PPixiePosition; Ri: Pointer);
var
  RenderIt: TPixieRenderItem;
  P: TPixiePosition;
  Layer: TPixieBackgroundLayer;
  Cont: TPixieContainer;
begin
  inherited Draw(Hdc, X, Y, Clip, Ri);

  RenderIt := TPixieRenderItem(Ri);
  P := RenderIt.Pos;
  P.X := P.X + X;
  P.Y := P.Y + Y;
  P.DoRound;

  if (Clip <> nil) and (not P.DoesIntersect(Clip^)) then
    Exit;
  if (P.Width <= 0) or (P.Height <= 0) then
    Exit;

  Layer.Init;
  Layer.ClipBox := P;
  Layer.OriginBox := P;
  Layer.BorderBox := P;
  Layer.BorderBox.X := Layer.BorderBox.X - RenderIt.GetPaddings.Left - RenderIt.GetBorders.Left;
  Layer.BorderBox.Y := Layer.BorderBox.Y - RenderIt.GetPaddings.Top - RenderIt.GetBorders.Top;
  Layer.BorderBox.Width := Layer.BorderBox.Width + RenderIt.GetPaddings.Width + RenderIt.GetBorders.Width;
  Layer.BorderBox.Height := Layer.BorderBox.Height + RenderIt.GetPaddings.Height + RenderIt.GetBorders.Height;
  Layer.Repeat_ := brNoRepeat;
  Layer.BorderRadius := FCss.CssBorders.Radius.CalcPercents(
    Layer.BorderBox.Width, Layer.BorderBox.Height);

  Cont := GetDocContainer;
  if Cont <> nil then
    Cont.DrawImage(Hdc, Layer, FSrc, '');
end;

function TPixieElImage.CreateRenderItem(ParentRi: Pointer): Pointer;
var
  Ret: TPixieRenderImage;
begin
  Ret := TPixieRenderImage.Create(Self);
  Ret.SetParent(TPixieRenderItem(ParentRi));
  Result := Ret;
end;

function TPixieElImage.DumpGetName: string;
begin
  Result := 'img src="' + FSrc + '"';
end;

end.
