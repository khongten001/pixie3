unit Pixie.SvgView.FMX;

// TPixieSvgView — Delphi FMX SVG display component.
// Renders SVG via FMX canvas, scales proportionally.

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Types, System.UITypes,
  FMX.Controls, FMX.Types, FMX.Graphics,
  Pixie.Types, Pixie.WebColor, Pixie.Canvas, Pixie.Canvas.FMX,
  Pixie.SvgRenderer, Pixie.SvgRenderer.Canvas;

type
  TPixieSvgAlign = (
    saTopLeft,
    saCenterHorz,
    saCenterVert,
    saCenterBoth
  );

  { TPixieSvgView }

  TPixieSvgView = class(TControl)
  private
    FPixieCanvas: TPixieCanvas;
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
    procedure Paint; override;
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
    property Size;
    property Visible;
  end;

implementation

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
// Construction
// ---------------------------------------------------------------------------

constructor TPixieSvgView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 100;
  Height := 100;

  FPixieCanvas := TPixieFmxCanvas.Create;
  FLines := TStringList.Create;
  FLines.OnChange := LinesChanged;
  FRenderer := TPixieSvgCanvasRenderer.Create(FPixieCanvas);
  FAlignment := saCenterBoth;
  FSvgW := 0;
  FSvgH := 0;
  FParsed := False;
end;

destructor TPixieSvgView.Destroy;
begin
  FreeAndNil(FRenderer);
  FreeAndNil(FLines);
  FreeAndNil(FPixieCanvas);
  inherited Destroy;
end;

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
    Repaint;
  end;
end;

procedure TPixieSvgView.LinesChanged(Sender: TObject);
begin
  FParsed := False;
  Repaint;
end;

procedure TPixieSvgView.ParseSvg;
var
  Xml: string;
  Utf8: UTF8String;
begin
  FParsed := True;
  FSvgW := 0;
  FSvgH := 0;
  FRenderer.ClearDocument;
  Xml := FLines.Text;
  if Xml = '' then Exit;
  Utf8 := UTF8String(Xml);
  FRenderer.ParseSvg(Pointer(Utf8), Length(Utf8), FSvgW, FSvgH);
end;

procedure TPixieSvgView.Paint;
var
  CW, CH: Single;
  Sx, Sy, Scale, DstW, DstH, OffX, OffY: Single;
  BgColor: TPixieWebColor;
begin
  if (FPixieCanvas = nil) or (Canvas = nil) then Exit;
  CW := Width;
  CH := Height;

  FPixieCanvas.SetViewSize(Round(CW), Round(CH), 1);
  FPixieCanvas.BeginPaint(PtrUInt(Pointer(Canvas)));
  try
    // Background (light grey default for FMX)
    BgColor := TPixieWebColor.Create($F0, $F0, $F0);
    FPixieCanvas.FillRect(0, 0, CW, CH, BgColor);

    if not FParsed then
      ParseSvg;
    if (FSvgW < 0.01) or (FSvgH < 0.01) then Exit;

    Sx := CW / FSvgW;
    Sy := CH / FSvgH;
    Scale := Min(Sx, Sy);
    DstW := FSvgW * Scale;
    DstH := FSvgH * Scale;

    OffX := 0;
    OffY := 0;
    case FAlignment of
      saCenterHorz:
        OffX := (CW - DstW) * 0.5;
      saCenterVert:
        OffY := (CH - DstH) * 0.5;
      saCenterBoth:
        begin OffX := (CW - DstW) * 0.5; OffY := (CH - DstH) * 0.5; end;
    end;

    FRenderer.RenderToRect(OffX, OffY, DstW, DstH);
  finally
    FPixieCanvas.EndPaint;
  end;
end;

end.
