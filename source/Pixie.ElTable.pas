unit Pixie.ElTable;

// Table elements: <table>, <tr>, <td>/<th>.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils,
  Pixie.Types,
  Pixie.Element, Pixie.HtmlTag;

type
  { TPixieElTable }

  TPixieElTable = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    function AppendChild(El: TPixieElement): Boolean; override;
    procedure ParseAttributes; override;
  end;

  { TPixieElTr }

  TPixieElTr = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
  end;

  { TPixieElTd }

  TPixieElTd = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
  end;

implementation

uses
  Pixie.StringId, Pixie.Style;

{ TPixieElTable }

constructor TPixieElTable.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

function TPixieElTable.AppendChild(El: TPixieElement): Boolean;
var
  ChildTag: Integer;
begin
  ChildTag := El.GetTag;
  if (ChildTag = Ord(psid_tbody)) or (ChildTag = Ord(psid_thead)) or
     (ChildTag = Ord(psid_tfoot)) or (ChildTag = Ord(psid_caption)) then
    Result := inherited AppendChild(El)
  else
    Result := False;
end;

procedure TPixieElTable.ParseAttributes;
var
  Val: string;
begin
  Val := GetAttr('width');
  if Val <> '' then
    MapToDimensionPropertyIgnoreZero(Ord(psid_width), Val);

  Val := GetAttr('height');
  if Val <> '' then
    MapToDimensionProperty(Ord(psid_height), Val);

  Val := GetAttr('cellspacing');
  if Val <> '' then
    MapToPixelLengthProperty(Ord(psid_border_spacing), Val);

  Val := GetAttr('border');
  if Val <> '' then
    MapToPixelLengthPropertyWithDefault(
      Ord(psid_border_width), Val, 1);

  Val := GetAttr('bgcolor');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_background_color), Val);

  Val := GetAttr('align');
  if SameText(Val, 'center') then
  begin
    FStyle.AddProperty(Ord(psid_margin_left), 'auto');
    FStyle.AddProperty(Ord(psid_margin_right), 'auto');
  end;

  inherited ParseAttributes;
end;

{ TPixieElTr }

constructor TPixieElTr.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

procedure TPixieElTr.ParseAttributes;
var
  Val: string;
begin
  Val := GetAttr('height');
  if Val <> '' then
    MapToDimensionProperty(Ord(psid_height), Val);

  Val := GetAttr('align');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_text_align), Val);

  Val := GetAttr('valign');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_vertical_align), Val);

  Val := GetAttr('bgcolor');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_background_color), Val);

  inherited ParseAttributes;
end;

{ TPixieElTd }

constructor TPixieElTd.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

procedure TPixieElTd.ParseAttributes;
var
  Val: string;
begin
  Val := GetAttr('width');
  if Val <> '' then
    MapToDimensionPropertyIgnoreZero(Ord(psid_width), Val);

  Val := GetAttr('height');
  if Val <> '' then
    MapToDimensionPropertyIgnoreZero(Ord(psid_height), Val);

  Val := GetAttr('background');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_background_image), 'url(''' + Val + ''')');

  Val := GetAttr('bgcolor');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_background_color), Val);

  Val := GetAttr('align');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_text_align), Val);

  Val := GetAttr('valign');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_vertical_align), Val);

  inherited ParseAttributes;
end;

end.
