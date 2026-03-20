unit Pixie.Canvas;

// Platform-independent drawing canvas interface.
// Concrete implementations: Pixie.Canvas.D2D (Windows), Pixie.Canvas.Cairo (Linux).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Classes,
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.Background, Pixie.FontDescription;

type
  TPixieFontHandle = PtrUInt;
  TPixieImageHandle = PtrUInt;

  { TPixieCanvas }

  TPixieCanvas = class
  public
    // Lifecycle — bind to a platform device context for painting
    procedure BeginPaint(DC: PtrUInt); virtual; abstract;
    procedure EndPaint; virtual; abstract;

    // Graphics state save/restore (used for push/pop clipping)
    procedure SaveState; virtual; abstract;
    procedure RestoreState; virtual; abstract;

    // Opacity layers
    procedure PushOpacity(AOpacity: Single); virtual;
    procedure PopOpacity; virtual;

    // Clipping
    procedure SetClipRect(const R: TPixiePosition;
      const Radius: TPixieBorderRadiuses); virtual; abstract;

    // Solid colour fill
    procedure FillRect(X, Y, W, H: Single;
      Color: TPixieWebColor); virtual; abstract;

    // Rounded-rect path fill
    procedure FillRoundedRect(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      Color: TPixieWebColor); virtual; abstract;

    // Linear gradient fill
    procedure FillLinearGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieLinearGradientLayer); virtual; abstract;

    // Radial gradient fill
    procedure FillRadialGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieRadialGradientLayer); virtual; abstract;

    // Conic gradient fill (software fallback acceptable)
    procedure FillConicGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieConicGradientLayer); virtual; abstract;

    // Border drawing
    procedure DrawBorders(const Borders: TPixieBorders;
      const Pos: TPixiePosition; IsRoot: Boolean); virtual; abstract;

    // Font management
    function CreateFont(const Descr: TPixieFontDescription;
      out Metrics: TPixieFontMetrics): TPixieFontHandle; virtual; abstract;
    procedure DeleteFont(Handle: TPixieFontHandle); virtual; abstract;

    // Text
    function MeasureText(const Text: string;
      Handle: TPixieFontHandle): pixel_t; virtual; abstract;
    procedure DrawText(const Text: string; Handle: TPixieFontHandle;
      Color: TPixieWebColor; X, Y, W, H: Single); virtual; abstract;

    // Unit conversion
    function PtToPx(Pt: Single): pixel_t; virtual; abstract;

    // Image
    function LoadImage(const Path: string): TPixieImageHandle; virtual; abstract;
    function LoadImageFromPixels(Width, Height: Integer;
      Pixels: Pointer; Pitch: Integer): TPixieImageHandle; virtual; abstract;
    procedure FreeImage(Handle: TPixieImageHandle); virtual; abstract;
    procedure GetImageSize(Handle: TPixieImageHandle;
      out W, H: Single); virtual; abstract;
    procedure DrawImage(Handle: TPixieImageHandle;
      DstX, DstY, DstW, DstH: Single); virtual; abstract;
    function LoadImageFromStream(Stream: TStream): TPixieImageHandle; virtual;
    function LoadSvgFromData(Data: Pointer;
      Size: Integer): TPixieImageHandle; virtual;

    // Simple shapes (for list markers and form controls)
    procedure FillEllipse(X, Y, W, H: Single;
      Color: TPixieWebColor); virtual; abstract;
    procedure DrawEllipse(X, Y, W, H: Single;
      Color: TPixieWebColor; StrokeWidth: Single); virtual; abstract;
    procedure DrawRect(X, Y, W, H: Single;
      Color: TPixieWebColor; StrokeWidth: Single); virtual; abstract;
    procedure DrawLine(X1, Y1, X2, Y2: Single;
      Color: TPixieWebColor; StrokeWidth: Single); virtual; abstract;
    procedure StrokePolyline(const Points: array of Single;
      Color: TPixieWebColor; StrokeWidth: Single); virtual; abstract;

    // View size hint for render targets that need explicit sizing
    procedure SetViewSize(W, H: Integer; ACanvasScale: Single = 1); virtual;
    // Scale/zoom — applies a uniform scale transform to all drawing
    procedure SetScale(Scale: Single); virtual;
  end;

implementation

procedure TPixieCanvas.PushOpacity(AOpacity: Single);
begin
  // no-op by default
end;

procedure TPixieCanvas.PopOpacity;
begin
  // no-op by default
end;

procedure TPixieCanvas.SetViewSize(W, H: Integer; ACanvasScale: Single);
begin
  // no-op by default
end;

procedure TPixieCanvas.SetScale(Scale: Single);
begin
  // no-op by default
end;

function TPixieCanvas.LoadImageFromStream(
  Stream: TStream): TPixieImageHandle;
begin
  Result := 0;
end;

function TPixieCanvas.LoadSvgFromData(Data: Pointer;
  Size: Integer): TPixieImageHandle;
begin
  Result := 0;
end;

end.
