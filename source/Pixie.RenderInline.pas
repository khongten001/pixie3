unit Pixie.RenderInline;

// Inline element render item — wraps inline containers (<span> etc.)
// that can span multiple lines via inline boxes.

{$mode delphi}

interface

uses
  Pixie.Types, Pixie.Element, Pixie.RenderItem;

type
  { TPixieRenderInline }
  TPixieRenderInline = class(TPixieRenderItem)
  protected
    FBoxes: TPixiePositionVector;
  public
    constructor Create(ASrcEl: TPixieElement); override;
    destructor Destroy; override;
    function Clone: TPixieRenderItem; override;

    procedure GetInlineBoxes(Boxes: TPixiePositionVector); override;
    procedure AddInlineBox(const Box: TPixiePosition); override;
    procedure ClearInlineBoxes; override;

    function GetFirstBaseline: pixel_t; override;
    function GetLastBaseline: pixel_t; override;

    procedure YShift(Delta: pixel_t); override;
  end;

implementation

{ TPixieRenderInline }

constructor TPixieRenderInline.Create(ASrcEl: TPixieElement);
begin
  inherited Create(ASrcEl);
  FBoxes := TPixiePositionVector.Create;
end;

destructor TPixieRenderInline.Destroy;
begin
  FBoxes.Free;
  inherited Destroy;
end;

function TPixieRenderInline.Clone: TPixieRenderItem;
begin
  Result := TPixieRenderInline.Create(FElement);
end;

procedure TPixieRenderInline.GetInlineBoxes(Boxes: TPixiePositionVector);
var
  I: Integer;
begin
  Boxes.Clear;
  for I := 0 to FBoxes.Count - 1 do
    Boxes.Add(FBoxes[I]);
end;

procedure TPixieRenderInline.AddInlineBox(const Box: TPixiePosition);
begin
  FBoxes.Add(Box);
end;

procedure TPixieRenderInline.ClearInlineBoxes;
begin
  FBoxes.Clear;
end;

function TPixieRenderInline.GetFirstBaseline: pixel_t;
begin
  Result := SrcEl.Css.FontMetrics.Height - SrcEl.Css.FontMetrics.BaseLine;
end;

function TPixieRenderInline.GetLastBaseline: pixel_t;
begin
  Result := SrcEl.Css.FontMetrics.Height - SrcEl.Css.FontMetrics.BaseLine;
end;

procedure TPixieRenderInline.YShift(Delta: pixel_t);
var
  I: Integer;
  Tmp: TPixiePosition;
begin
  if Css.Display = displayInlineText then
    inherited YShift(Delta);
  for I := 0 to FBoxes.Count - 1 do
  begin
    Tmp := FBoxes[I];
    Tmp.Y := Tmp.Y + Delta;
    FBoxes[I] := Tmp;
  end;
end;

end.
