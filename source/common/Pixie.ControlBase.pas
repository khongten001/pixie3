unit Pixie.ControlBase;

// TPixieControlBase — abstract base for all Pixie visual components (Lazarus).
// Creates a platform-specific TPixieCanvas and provides the Paint lifecycle.
// Subclasses override DoPaint to render their content.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Controls, Graphics, Forms, LMessages,
  Pixie.Types, Pixie.WebColor, Pixie.Canvas
  {$IF DEFINED(LCLqt) or DEFINED(LCLqt5) or DEFINED(LCLqt6)}
    , Pixie.Canvas.Qt
  {$ELSEIF DEFINED(MSWINDOWS)}
    , Pixie.Canvas.D2D
  {$ELSEIF DEFINED(DARWIN)}
    , Pixie.Canvas.CG
  {$ELSEIF DEFINED(UNIX)}
    , Pixie.Canvas.Cairo
  {$ENDIF};

type
  { TPixieControlBase }

  TPixieControlBase = class(TCustomControl)
  private
    FPixieCanvas: TPixieCanvas;
    procedure WMEraseBkgnd(var Msg: TLMEraseBkgnd); message LM_ERASEBKGND;
  protected
    procedure CreatePixieCanvas; virtual;
    function GetScaleFactor: Single; virtual;
    function GetBackgroundColor: TPixieWebColor; overload; virtual;
    function GetBackgroundColor(AColor: TColor): TPixieWebColor; overload;
    function GetPaintHandle: PtrUInt; virtual;
    procedure Paint; override;
    procedure DoPaint; virtual; abstract;
    property PixieCanvas: TPixieCanvas read FPixieCanvas;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieControlBase.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  CreatePixieCanvas;
end;

destructor TPixieControlBase.Destroy;
begin
  FreeAndNil(FPixieCanvas);
  inherited Destroy;
end;

procedure TPixieControlBase.CreatePixieCanvas;
begin
  {$IF DEFINED(LCLqt) or DEFINED(LCLqt5) or DEFINED(LCLqt6)}
  FPixieCanvas := TPixieQtCanvas.Create;
  {$ELSEIF DEFINED(MSWINDOWS)}
  FPixieCanvas := TPixieD2DCanvas.Create;
  {$ELSEIF DEFINED(DARWIN)}
  FPixieCanvas := TPixieCGCanvas.Create;
  {$ELSEIF DEFINED(UNIX)}
  FPixieCanvas := TPixieCairoCanvas.Create;
  {$ENDIF}
end;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function TPixieControlBase.GetScaleFactor: Single;
{$IFDEF MSWINDOWS}
var
  F: TCustomForm;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  F := GetParentForm(Self);
  if F <> nil then
    Result := F.PixelsPerInch / 96
  else
    Result := Screen.PixelsPerInch / 96;
  {$ELSE}
  // Non-Windows: ClientWidth/ClientHeight are already in logical points,
  // so no DPI compensation is needed for layout. The backing buffer density
  // (Retina 2x etc.) is handled separately via SetViewSize's ACanvasScale.
  Result := 1.0;
  {$ENDIF}
end;

function TPixieControlBase.GetBackgroundColor: TPixieWebColor;
begin
  Result := GetBackgroundColor(Self.Color);
end;

function TPixieControlBase.GetBackgroundColor(AColor: TColor): TPixieWebColor;
var
  Rgb: LongInt;
begin
  Rgb := ColorToRGB(AColor);
  Result := TPixieWebColor.Create(
    Byte(Rgb), Byte(Rgb shr 8), Byte(Rgb shr 16));
end;

function TPixieControlBase.GetPaintHandle: PtrUInt;
begin
  Result := PtrUInt(inherited Canvas.Handle);
end;

// ---------------------------------------------------------------------------
// Painting
// ---------------------------------------------------------------------------

procedure TPixieControlBase.Paint;
begin
  if FPixieCanvas = nil then
  begin
    inherited Canvas.Brush.Color := Self.Color;
    inherited Canvas.FillRect(ClientRect);
    Exit;
  end;
  DoPaint;
end;

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

procedure TPixieControlBase.WMEraseBkgnd(var Msg: TLMEraseBkgnd);
begin
  Msg.Result := 1;
end;

end.
