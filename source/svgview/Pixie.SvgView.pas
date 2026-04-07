unit Pixie.SvgView;

// TPixieSvgView — displays SVG content rendered via TPixieCanvas.
// Scales proportionally and supports alignment options.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Controls, Graphics, Math,
  Pixie.Types, Pixie.WebColor, Pixie.Canvas,
  Pixie.SvgRenderer, Pixie.SvgRenderer.Canvas,
  Pixie.ControlBase;

type
  TPixieSvgAlign = (
    saTopLeft,
    saCenterHorz,
    saCenterVert,
    saCenterBoth
  );

  { TPixieSvgView }

  TPixieSvgView = class(TPixieControlBase)
  private
    FLines: TStringList;
    FRenderer: TPixieSvgCanvasRenderer;
    FAlignment: TPixieSvgAlign;
    FSvgW: Single;
    FSvgH: Single;
    FParsed: Boolean;

    procedure LinesChanged(Sender: TObject);
    procedure ParseSvg;
    function GetLines: TStrings;
    procedure SetLines(Value: TStrings);
    procedure SetAlignment(Value: TPixieSvgAlign);
  protected
    procedure DoPaint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadFromFile(const FileName: string);
    procedure LoadFromStream(Stream: TStream);
    procedure LoadFromResource(const ResName: string); overload;
    procedure LoadFromResource(Instance: THandle; const ResName: string); overload;
  published
    property Lines: TStrings read GetLines write SetLines;
    property Alignment: TPixieSvgAlign
      read FAlignment write SetAlignment default saCenterBoth;

    property Align;
    property Anchors;
    property BorderSpacing;
    property Color default clNone;
    property Constraints;
    property Enabled;
    property Visible;

    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseMove;
    property OnMouseUp;
    property OnResize;
  end;

implementation

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieSvgView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle - [csOpaque];
  Color := clNone;
  Width := 100;
  Height := 100;

  FLines := TStringList.Create;
  FLines.OnChange := LinesChanged;
  FRenderer := TPixieSvgCanvasRenderer.Create(PixieCanvas);
  FAlignment := saCenterBoth;
  FSvgW := 0;
  FSvgH := 0;
  FParsed := False;
end;

destructor TPixieSvgView.Destroy;
begin
  FreeAndNil(FRenderer);
  FreeAndNil(FLines);
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Properties
// ---------------------------------------------------------------------------

function TPixieSvgView.GetLines: TStrings;
begin
  Result := FLines;
end;

procedure TPixieSvgView.SetLines(Value: TStrings);
begin
  FLines.Assign(Value);
end;

procedure TPixieSvgView.SetAlignment(Value: TPixieSvgAlign);
begin
  if FAlignment <> Value then
  begin
    FAlignment := Value;
    Invalidate;
  end;
end;

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

procedure TPixieSvgView.LoadFromFile(const FileName: string);
begin
  FLines.LoadFromFile(FileName);
end;

procedure TPixieSvgView.LoadFromStream(Stream: TStream);
begin
  FLines.LoadFromStream(Stream);
end;

procedure TPixieSvgView.LoadFromResource(const ResName: string);
begin
  LoadFromResource(HInstance, ResName);
end;

procedure TPixieSvgView.LoadFromResource(Instance: THandle;
  const ResName: string);
var
  Stream: TResourceStream;
begin
  Stream := TResourceStream.Create(Instance, ResName, PChar(10)); // RT_RCDATA
  try
    LoadFromStream(Stream);
  finally
    Stream.Free;
  end;
end;

// ---------------------------------------------------------------------------
// SVG parsing
// ---------------------------------------------------------------------------

procedure TPixieSvgView.LinesChanged(Sender: TObject);
begin
  FParsed := False;
  Invalidate;
end;

procedure TPixieSvgView.ParseSvg;
var
  Xml: string;
begin
  FParsed := True;
  FSvgW := 0;
  FSvgH := 0;
  FRenderer.ClearDocument;

  Xml := FLines.Text;
  if Xml = '' then Exit;

  FRenderer.ParseSvg(Pointer(Xml), Length(Xml) * SizeOf(Char), FSvgW, FSvgH);
end;

// ---------------------------------------------------------------------------
// Painting
// ---------------------------------------------------------------------------

procedure TPixieSvgView.DoPaint;
var
  CW, CH: Single;
  Sx, Sy, Scale, DstW, DstH, OffX, OffY: Single;
  BgColor: TPixieWebColor;
begin
  CW := ClientWidth;
  CH := ClientHeight;

  PixieCanvas.SetViewSize(Round(CW), Round(CH), GetCanvasScaleFactor);
  PixieCanvas.BeginPaint(GetPaintHandle);
  try
    // Background: use parent colour when Color = clNone (simulate transparency)
    if Color = clNone then
      BgColor := GetBackgroundColor(ColorToRGB(clBtnFace))
    else
      BgColor := GetBackgroundColor;
    PixieCanvas.FillRect(0, 0, CW, CH, BgColor);

    // Parse if needed
    if not FParsed then
      ParseSvg;

    if (FSvgW < 0.01) or (FSvgH < 0.01) then Exit;

    // Calculate proportional scale
    Sx := CW / FSvgW;
    Sy := CH / FSvgH;
    Scale := Min(Sx, Sy);
    DstW := FSvgW * Scale;
    DstH := FSvgH * Scale;

    // Alignment offset
    case FAlignment of
      saTopLeft:
        begin
          OffX := 0;
          OffY := 0;
        end;
      saCenterHorz:
        begin
          OffX := (CW - DstW) * 0.5;
          OffY := 0;
        end;
      saCenterVert:
        begin
          OffX := 0;
          OffY := (CH - DstH) * 0.5;
        end;
      saCenterBoth:
        begin
          OffX := (CW - DstW) * 0.5;
          OffY := (CH - DstH) * 0.5;
        end;
    end;

    FRenderer.RenderToRect(OffX, OffY, DstW, DstH);
  finally
    PixieCanvas.EndPaint;
  end;
end;

end.
