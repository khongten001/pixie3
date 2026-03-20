unit Pixie.ScrollView;

// Scroll state management for overflow containers.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Math,
  Pixie.Types;

type
  TPixieScrollView = class
  protected
    FViewport: TPixiePosition;
    FScrollSize: TPixieSize;
    FLeft: pixel_t;
    FTop: pixel_t;
  public
    constructor Create(const AViewport: TPixiePosition;
      const AScrollSize: TPixieSize);

    function GetLeft: pixel_t;
    function GetTop: pixel_t;

    function GetMaxHScroll: pixel_t;
    function GetMaxVScroll: pixel_t;

    procedure SetViewport(const AViewport: TPixiePosition;
      const AScrollSize: TPixieSize);
    function IsHScrollable(DX: pixel_t): Boolean;
    function IsVScrollable(DY: pixel_t): Boolean;

    function HScroll(DX: pixel_t): pixel_t;
    function VScroll(DY: pixel_t): pixel_t;

    function IsPointInside(X, Y: pixel_t): Boolean;
  end;

implementation

function Clamp(V, Lo, Hi: pixel_t): pixel_t; inline;
begin
  if V < Lo then
    Result := Lo
  else if V > Hi then
    Result := Hi
  else
    Result := V;
end;

constructor TPixieScrollView.Create(const AViewport: TPixiePosition;
  const AScrollSize: TPixieSize);
begin
  inherited Create;
  FViewport := AViewport;
  FScrollSize := AScrollSize;
  FLeft := 0;
  FTop := 0;
end;

function TPixieScrollView.GetLeft: pixel_t;
begin
  Result := FLeft;
end;

function TPixieScrollView.GetTop: pixel_t;
begin
  Result := FTop;
end;

function TPixieScrollView.GetMaxHScroll: pixel_t;
begin
  Result := Max(0, FScrollSize.Width - FViewport.Width);
end;

function TPixieScrollView.GetMaxVScroll: pixel_t;
begin
  Result := Max(0, FScrollSize.Height - FViewport.Height);
end;

procedure TPixieScrollView.SetViewport(const AViewport: TPixiePosition;
  const AScrollSize: TPixieSize);
begin
  FViewport := AViewport;
  FScrollSize := AScrollSize;
  FLeft := Clamp(FLeft, 0, GetMaxHScroll);
  FTop := Clamp(FTop, 0, GetMaxVScroll);
end;

function TPixieScrollView.IsHScrollable(DX: pixel_t): Boolean;
begin
  if FScrollSize.Width = 0 then
    Exit(False);
  Result := FLeft <> Clamp(FLeft + DX, 0, GetMaxHScroll);
end;

function TPixieScrollView.IsVScrollable(DY: pixel_t): Boolean;
begin
  if FScrollSize.Height = 0 then
    Exit(False);
  Result := FTop <> Clamp(FTop + DY, 0, GetMaxVScroll);
end;

function TPixieScrollView.HScroll(DX: pixel_t): pixel_t;
var
  NewLeft: pixel_t;
begin
  if FScrollSize.Width = 0 then
    Exit(0);
  NewLeft := Clamp(FLeft + DX, 0, GetMaxHScroll);
  Result := NewLeft - FLeft;
  FLeft := NewLeft;
end;

function TPixieScrollView.VScroll(DY: pixel_t): pixel_t;
var
  NewTop: pixel_t;
begin
  if FScrollSize.Height = 0 then
    Exit(0);
  NewTop := Clamp(FTop + DY, 0, GetMaxVScroll);
  Result := NewTop - FTop;
  FTop := NewTop;
end;

function TPixieScrollView.IsPointInside(X, Y: pixel_t): Boolean;
begin
  Result := FViewport.IsPointInside(X, Y);
end;

end.
