unit Pixie.HtmlView.Base;

// TPixieHtmlViewCore — shared logic for all TPixieHtmlView implementations.
// Contains document management, input handling, scrolling, layout, and painting.
// Concrete classes (Lazarus, VCL, FMX) create a core instance and wire
// host callbacks for platform-specific operations.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Math,
  {$IFDEF FPC}ExtCtrls,{$ENDIF}
  {$IFDEF FRAMEWORK_FMX}FMX.Types,{$ENDIF}
  {$IFDEF FRAMEWORK_VCL}Vcl.ExtCtrls,{$ENDIF}
  Pixie.Types, Pixie.WebColor, Pixie.Borders, Pixie.Document,
  Pixie.Html, Pixie.MasterCss, Pixie.Canvas, Pixie.NativeContainer,
  Pixie.RenderBlockContext, Pixie.RenderInlineContext,
  Pixie.SvgRenderer, Pixie.SvgRenderer.Canvas;

type
  TPixieCursorKind = (
    pxCurDefault, pxCurHandPoint, pxCurIBeam, pxCurCross, pxCurSizeAll);

  TPixieAnchorClickEvent = procedure(Sender: TObject;
    const Url: string) of object;
  TPixieElementClickEvent = function(Sender: TObject;
    El: TObject): Boolean of object;

const
  pxVK_TAB   = 9;
  pxVK_HOME  = 36;
  pxVK_END   = 35;
  pxVK_UP    = 38;
  pxVK_DOWN  = 40;
  pxVK_PRIOR = 33;
  pxVK_NEXT  = 34;
  pxVK_0     = 48;

type
  TPixieHostNotify    = procedure of object;
  TPixieHostSetCursor = procedure(ACursor: TPixieCursorKind) of object;
  TPixieHostGetPixel  = function: TPixiePixel of object;
  TPixieHostGetFloat  = function: Single of object;
  TPixieHostGetColor  = function: TPixieWebColor of object;
  TPixieHostCopyText  = procedure(const Text: string) of object;
  TPixieHostGetTick   = function: UInt64 of object;

  TPixieScrollbarVisibility = (svShow, svHide, svAuto);

  { TPixieScrollbarSettings }

  TPixieScrollbarSettings = class
  private
    FWidth: Integer;
    FMargin: Integer;
    FMinThumbHeight: Integer;
    FThumbColor: TPixieWebColor;
    FTrackColor: TPixieWebColor;
    FVisibility: TPixieScrollbarVisibility;
    FOnChanged: TPixieHostNotify;
    procedure SetWidth(Value: Integer);
    procedure SetMargin(Value: Integer);
    procedure SetMinThumbHeight(Value: Integer);
    procedure SetThumbColor(const Value: TPixieWebColor);
    procedure SetTrackColor(const Value: TPixieWebColor);
    procedure SetVisibility(Value: TPixieScrollbarVisibility);
    procedure Changed;
  public
    constructor Create;
    property Width: Integer read FWidth write SetWidth;
    property Margin: Integer read FMargin write SetMargin;
    property MinThumbHeight: Integer read FMinThumbHeight write SetMinThumbHeight;
    property ThumbColor: TPixieWebColor read FThumbColor write SetThumbColor;
    property TrackColor: TPixieWebColor read FTrackColor write SetTrackColor;
    property Visibility: TPixieScrollbarVisibility read FVisibility write SetVisibility;
    property OnChanged: TPixieHostNotify read FOnChanged write FOnChanged;
  end;

  { TPixieHtmlViewCore }

  TPixieHtmlViewCore = class
  private
    FDocument: TPixieDocument;
    FSvgRenderer: TPixieSvgCanvasRenderer;
    FSvgWidth, FSvgHeight: Single;
    FContainer: TPixieNativeContainer;
    FCanvas: TPixieCanvas;
    FLines: TStrings;
    FBaseUrl: string;
    FUserCss: string;
    FNeedsLayout: Boolean;
    FScrollY: TPixiePixel;
    FContentHeight: TPixiePixel;
    FZoom: Double;
    FOnAnchorClick: TPixieAnchorClickEvent;
    FOnElementClick: TPixieElementClickEvent;
    FOnFetchUrl: TPixieFetchUrlEvent;
    FRedrawBoxes: TPixiePositionVector;
    FScrollbar: TPixieScrollbarSettings;
    FDragging: Boolean;
    FWordDragging: Boolean;
    FScrollDragging: Boolean;
    FScrollDragOffset: TPixiePixel;
    FAutoScrollTimer: TTimer;
    FAutoScrollDY: TPixiePixel;
    FAutoScrollSpeed: Integer;
    FAutoScrollAccel: Integer;
    FAutoScrollEdge: Integer;
    FAutoScrollAccelThreshold: Integer;
    FAutoScrollAccelMax: Integer;
    FLastDragVx: Integer;
    FLastDragVy: Integer;
    FAnchorScrollTick: UInt64;
    FScrollbarOpacity: Single;
    FScrollbarHoverZone: Boolean;
    FScrollbarHideTimer: TTimer;
    FOnBeforeParse: TNotifyEvent;
    FOnAfterParse: TNotifyEvent;
    FOnBeforePaint: TNotifyEvent;
    FOnAfterPaint: TNotifyEvent;
    FOnScrollChanged: TNotifyEvent;

    procedure SetLines(const Value: TStrings);
    procedure SetBaseUrl(const Value: string);
    procedure SetUserCss(const Value: string);
    procedure SetZoom(const Value: Double);
    procedure SetScrollY(Value: TPixiePixel);
    procedure DoScrollChanged;
    function GetEffectiveScale: Double;
    procedure RebuildDocument;
    procedure DoAnchorClick(Sender: TObject; const Url: string);
    function DoElementClick(Sender: TObject; El: TObject): Boolean;
    procedure DoFetchUrl(Sender: TObject; const Url: string;
      Stream: TStream; var Success: Boolean);
    procedure DoDocumentChange(Sender: TObject);
    procedure UpdateCursorFromCss;
    procedure ResetCaret;
    procedure Invalidate;
    procedure DoAutoScrollTimer(Sender: TObject);
    procedure UpdateAutoScroll(Vy: Integer; ViewH: TPixiePixel;
      DeltaX: Integer);
    procedure StopAutoScroll;
    function ShouldDrawScrollbar: Boolean;
    procedure ShowScrollbar;
    procedure StartScrollbarHide;
    procedure DoScrollbarHideTimer(Sender: TObject);
  public
    // Host callbacks — set by concrete class in its constructor
    Owner: TObject;
    OnHostInvalidate: TPixieHostNotify;
    OnHostSetCursor: TPixieHostSetCursor;
    OnHostSetFocus: TPixieHostNotify;
    OnHostGetViewWidth: TPixieHostGetPixel;
    OnHostGetViewHeight: TPixieHostGetPixel;
    OnHostGetScaleFactor: TPixieHostGetFloat;
    OnHostGetBackgroundColor: TPixieHostGetColor;
    OnHostCopyToClipboard: TPixieHostCopyText;
    OnHostGetTickCount: TPixieHostGetTick;
    OnHostResetCaret: TPixieHostNotify;
    OnHostUpdateIME: TPixieHostNotify;

    constructor Create(ACanvas: TPixieCanvas);
    destructor Destroy; override;

    procedure LoadFromString(const AHtml: string;
      const ABaseUrl: string = '');
    procedure LoadFromFile(const AFileName: string;
      const ABaseUrl: string = '');
    procedure LoadFromStream(AStream: TStream;
      const ABaseUrl: string = '');
    procedure RegisterImage(const Name: string; Stream: TStream);
    procedure UnregisterImage(const Name: string);

    procedure HandleLoaded;
    procedure HandlePaint(ACanvasHandle: PtrUInt);
    procedure HandleResize;
    procedure HandleCaretTimer;
    procedure HandleMouseDown(IsLeft, IsDouble: Boolean; X, Y: Integer);
    procedure HandleMouseMove(X, Y: Integer);
    procedure HandleMouseUp(IsLeft: Boolean; X, Y: Integer);
    procedure HandleMouseLeave;
    function HandleMouseWheel(WheelDelta: Integer; CtrlDown: Boolean;
      MouseX, MouseY: Integer): Boolean;
    function HandleKeyDown(Key: Word; Shift: TShiftState;
      CtrlDown: Boolean): Boolean;
    function HandleCharInput(const Ch: string): Boolean;

    property Document: TPixieDocument read FDocument;
    property Container: TPixieNativeContainer read FContainer;
    property Canvas: TPixieCanvas read FCanvas;
    property Lines: TStrings read FLines write SetLines;
    property BaseUrl: string read FBaseUrl write SetBaseUrl;
    property UserCss: string read FUserCss write SetUserCss;
    property Zoom: Double read FZoom write SetZoom;
    property Scrollbar: TPixieScrollbarSettings read FScrollbar;
    property ContentHeight: TPixiePixel read FContentHeight;
    property ScrollY: TPixiePixel read FScrollY write SetScrollY;
    property NeedsLayout: Boolean read FNeedsLayout write FNeedsLayout;
    property AutoScrollSpeed: Integer read FAutoScrollSpeed write FAutoScrollSpeed;
    property AutoScrollEdge: Integer read FAutoScrollEdge write FAutoScrollEdge;
    property AutoScrollAccelThreshold: Integer read FAutoScrollAccelThreshold write FAutoScrollAccelThreshold;
    property AutoScrollAccelMax: Integer read FAutoScrollAccelMax write FAutoScrollAccelMax;
    property OnAnchorClick: TPixieAnchorClickEvent
      read FOnAnchorClick write FOnAnchorClick;
    property OnElementClick: TPixieElementClickEvent
      read FOnElementClick write FOnElementClick;
    property OnFetchUrl: TPixieFetchUrlEvent
      read FOnFetchUrl write FOnFetchUrl;
    property OnBeforeParse: TNotifyEvent
      read FOnBeforeParse write FOnBeforeParse;
    property OnAfterParse: TNotifyEvent
      read FOnAfterParse write FOnAfterParse;
    property OnBeforePaint: TNotifyEvent
      read FOnBeforePaint write FOnBeforePaint;
    property OnAfterPaint: TNotifyEvent
      read FOnAfterPaint write FOnAfterPaint;
    property OnScrollChanged: TNotifyEvent
      read FOnScrollChanged write FOnScrollChanged;
  end;

implementation

uses
  Pixie.Element, Pixie.RenderItem;

// ---------------------------------------------------------------------------
// TPixieScrollbarSettings
// ---------------------------------------------------------------------------

constructor TPixieScrollbarSettings.Create;
begin
  inherited Create;
  FWidth := 4;
  FMargin := 2;
  FMinThumbHeight := 16;
  FThumbColor := TPixieWebColor.Create(128, 128, 128, 160);
  FTrackColor := TPixieWebColor.Create(0, 0, 0, 0);
  FVisibility := svAuto;
end;

procedure TPixieScrollbarSettings.Changed;
begin
  if Assigned(FOnChanged) then
    FOnChanged;
end;

procedure TPixieScrollbarSettings.SetWidth(Value: Integer);
begin
  if FWidth = Value then Exit;
  FWidth := Value;
  Changed;
end;

procedure TPixieScrollbarSettings.SetMargin(Value: Integer);
begin
  if FMargin = Value then Exit;
  FMargin := Value;
  Changed;
end;

procedure TPixieScrollbarSettings.SetMinThumbHeight(Value: Integer);
begin
  if FMinThumbHeight = Value then Exit;
  FMinThumbHeight := Value;
  Changed;
end;

procedure TPixieScrollbarSettings.SetThumbColor(const Value: TPixieWebColor);
begin
  if (FThumbColor.Red = Value.Red) and (FThumbColor.Green = Value.Green) and
     (FThumbColor.Blue = Value.Blue) and (FThumbColor.Alpha = Value.Alpha) then Exit;
  FThumbColor := Value;
  Changed;
end;

procedure TPixieScrollbarSettings.SetTrackColor(const Value: TPixieWebColor);
begin
  if (FTrackColor.Red = Value.Red) and (FTrackColor.Green = Value.Green) and
     (FTrackColor.Blue = Value.Blue) and (FTrackColor.Alpha = Value.Alpha) then Exit;
  FTrackColor := Value;
  Changed;
end;

procedure TPixieScrollbarSettings.SetVisibility(Value: TPixieScrollbarVisibility);
begin
  if FVisibility = Value then Exit;
  FVisibility := Value;
  Changed;
end;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewCore.Invalidate;
begin
  if Assigned(OnHostInvalidate) then
    OnHostInvalidate;
end;

procedure TPixieHtmlViewCore.ResetCaret;
begin
  if FContainer <> nil then
    FContainer.CaretVisible := True;
  if Assigned(OnHostResetCaret) then
    OnHostResetCaret;
end;

procedure TPixieHtmlViewCore.UpdateCursorFromCss;
var
  S: string;
  Kind: TPixieCursorKind;
begin
  if not Assigned(OnHostSetCursor) then Exit;
  S := FContainer.Cursor;
  if S = 'pointer' then
    Kind := pxCurHandPoint
  else if S = 'text' then
    Kind := pxCurIBeam
  else if S = 'crosshair' then
    Kind := pxCurCross
  else if S = 'move' then
    Kind := pxCurSizeAll
  else
    Kind := pxCurDefault;
  OnHostSetCursor(Kind);
end;

// ---------------------------------------------------------------------------
// Auto-scroll and scrollbar fade
// ---------------------------------------------------------------------------

const
  ScrollbarFadeDuration = 500; // ms for the fade-out animation
  ScrollbarFadeInterval = 50;  // ms between fade ticks (~20 fps)

procedure TPixieHtmlViewCore.UpdateAutoScroll(Vy: Integer;
  ViewH: TPixiePixel; DeltaX: Integer);
var
  Dir: Integer;
begin
  if ViewH <= FAutoScrollEdge * 2 then
    Exit;
  if Vy < FAutoScrollEdge then
    Dir := -1
  else if Vy > Round(ViewH) - FAutoScrollEdge then
    Dir := 1
  else
  begin
    StopAutoScroll;
    Exit;
  end;

  // Horizontal jiggling accelerates scroll speed
  if DeltaX >= FAutoScrollAccelThreshold then
  begin
    if FAutoScrollAccel < FAutoScrollAccelMax then
      Inc(FAutoScrollAccel);
  end;

  FAutoScrollDY := FAutoScrollSpeed * (1 + FAutoScrollAccel) * Dir;
  if not FAutoScrollTimer.Enabled then
    FAutoScrollTimer.Enabled := True;
end;

procedure TPixieHtmlViewCore.StopAutoScroll;
begin
  if FAutoScrollTimer.Enabled then
    FAutoScrollTimer.Enabled := False;
  FAutoScrollDY := 0;
  FAutoScrollAccel := 0;
end;

// ---------------------------------------------------------------------------
// Scrollbar auto-show/hide for svAuto
// ---------------------------------------------------------------------------

function TPixieHtmlViewCore.ShouldDrawScrollbar: Boolean;
begin
  case FScrollbar.Visibility of
    svShow: Result := True;
    svHide: Result := False;
    svAuto: Result := FScrollbarOpacity > 0;
  else
    Result := True;
  end;
end;

procedure TPixieHtmlViewCore.ShowScrollbar;
begin
  FScrollbarHideTimer.Enabled := False;
  if FScrollbarOpacity < 1 then
  begin
    FScrollbarOpacity := 1;
    Invalidate;
  end;
end;

procedure TPixieHtmlViewCore.StartScrollbarHide;
begin
  if FScrollbarOpacity <= 0 then Exit;
  if FScrollbarHoverZone or FScrollDragging then Exit;
  FScrollbarHideTimer.Interval := ScrollbarFadeInterval;
  FScrollbarHideTimer.Enabled := True;
end;

procedure TPixieHtmlViewCore.DoScrollbarHideTimer(Sender: TObject);
var
  Step: Single;
begin
  if FScrollbarHoverZone or FScrollDragging then
  begin
    FScrollbarHideTimer.Enabled := False;
    Exit;
  end;
  Step := ScrollbarFadeInterval / ScrollbarFadeDuration;
  FScrollbarOpacity := FScrollbarOpacity - Step;
  if FScrollbarOpacity <= 0 then
  begin
    FScrollbarOpacity := 0;
    FScrollbarHideTimer.Enabled := False;
  end;
  Invalidate;
end;

procedure TPixieHtmlViewCore.DoAutoScrollTimer(Sender: TObject);
var
  NewScroll, MaxScroll, ViewH: TPixiePixel;
begin
  if (FDocument = nil) or not FDragging then
  begin
    StopAutoScroll;
    Exit;
  end;

  ViewH := OnHostGetViewHeight / GetEffectiveScale;
  MaxScroll := FContentHeight - ViewH;
  if MaxScroll < 0 then MaxScroll := 0;

  NewScroll := FScrollY + FAutoScrollDY;
  if NewScroll < 0 then NewScroll := 0;
  if NewScroll > MaxScroll then NewScroll := MaxScroll;

  if NewScroll = FScrollY then
  begin
    StopAutoScroll;
    Exit;
  end;

  SetScrollY(NewScroll);

  // Decay acceleration each tick — must keep jiggling to maintain speed
  if FAutoScrollAccel > 0 then
  begin
    Dec(FAutoScrollAccel);
    if FAutoScrollDY > 0 then
      FAutoScrollDY := FAutoScrollSpeed * (1 + FAutoScrollAccel)
    else
      FAutoScrollDY := -FAutoScrollSpeed * (1 + FAutoScrollAccel);
  end;

  // Update selection at last known mouse position with new scroll offset
  if (FDocument.FocusedElement <> nil) and
     FDocument.FocusedElement.IsFocusable then
  begin
    FDocument.DispatchMouseDrag(FLastDragVx, FLastDragVy + FScrollY);
  end
  else if FWordDragging then
    FDocument.SelectionMoveWord(FLastDragVx, FLastDragVy + FScrollY,
      FLastDragVx, FLastDragVy)
  else
    FDocument.SelectionMove(FLastDragVx, FLastDragVy + FScrollY,
      FLastDragVx, FLastDragVy);

  Invalidate;
end;

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieHtmlViewCore.Create(ACanvas: TPixieCanvas);
begin
  inherited Create;
  FCanvas := ACanvas;
  FDocument := nil;
  FContainer := nil;
  FRedrawBoxes := nil;
  FLines := TStringList.Create;
  FNeedsLayout := True;
  FScrollY := 0;
  FContentHeight := 0;
  FZoom := 1.0;
  FDragging := False;
  FWordDragging := False;
  FScrollDragging := False;
  FAutoScrollSpeed := 20;
  FAutoScrollEdge := 10;
  FAutoScrollAccelThreshold := 3;
  FAutoScrollAccelMax := 3;
  FAutoScrollTimer := TTimer.Create(nil);
  FAutoScrollTimer.Interval := 50;
  FAutoScrollTimer.OnTimer := DoAutoScrollTimer;
  FAutoScrollTimer.Enabled := False;
  FScrollbarOpacity := 0;
  FScrollbarHoverZone := False;
  FScrollbarHideTimer := TTimer.Create(nil);
  FScrollbarHideTimer.OnTimer := DoScrollbarHideTimer;
  FScrollbarHideTimer.Enabled := False;
  FScrollbar := TPixieScrollbarSettings.Create;
  FScrollbar.OnChanged := Invalidate;

  FContainer := TPixieNativeContainer.Create(FCanvas);
  FContainer.OnAnchorClickEvent := DoAnchorClick;
  FContainer.OnElementClickEvent := DoElementClick;
  FContainer.OnFetchUrlEvent := DoFetchUrl;
  FRedrawBoxes := TPixiePositionVector.Create;
end;

destructor TPixieHtmlViewCore.Destroy;
begin
  FreeAndNil(FAutoScrollTimer);
  FreeAndNil(FScrollbarHideTimer);
  FreeAndNil(FSvgRenderer);
  FreeAndNil(FDocument);
  FreeAndNil(FContainer);
  FreeAndNil(FCanvas);
  FreeAndNil(FRedrawBoxes);
  FreeAndNil(FScrollbar);
  FreeAndNil(FLines);
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Properties
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewCore.SetLines(const Value: TStrings);
begin
  FLines.Assign(Value);
  RebuildDocument;
end;

procedure TPixieHtmlViewCore.SetBaseUrl(const Value: string);
begin
  if FBaseUrl = Value then Exit;
  FBaseUrl := Value;
  FContainer.BaseUrl := Value;
  RebuildDocument;
end;

procedure TPixieHtmlViewCore.SetUserCss(const Value: string);
begin
  if FUserCss = Value then Exit;
  FUserCss := Value;
  RebuildDocument;
end;

procedure TPixieHtmlViewCore.SetZoom(const Value: Double);
var
  NewZoom: Double;
begin
  NewZoom := Value;
  if NewZoom < 0.25 then NewZoom := 0.25;
  if NewZoom > 4.0 then NewZoom := 4.0;
  if FZoom = NewZoom then Exit;
  FZoom := NewZoom;
  FCanvas.SetScale(GetEffectiveScale);
  FNeedsLayout := True;
  Invalidate;
end;

function TPixieHtmlViewCore.GetEffectiveScale: Double;
begin
  Result := FZoom;
  if Assigned(OnHostGetScaleFactor) then
    Result := Result * OnHostGetScaleFactor();
end;

procedure TPixieHtmlViewCore.SetScrollY(Value: TPixiePixel);
begin
  if FScrollY = Value then Exit;
  FScrollY := Value;
  DoScrollChanged;
end;

procedure TPixieHtmlViewCore.DoScrollChanged;
begin
  if Assigned(FOnScrollChanged) then
    FOnScrollChanged(Owner);
end;

// ---------------------------------------------------------------------------
// Document management
// ---------------------------------------------------------------------------


procedure TPixieHtmlViewCore.RebuildDocument;
var
  W, H: Integer;
  SvgData: UTF8String;
begin
  FreeAndNil(FDocument);
  FreeAndNil(FSvgRenderer);
  if (FScrollY <> 0) or (FContentHeight <> 0) then
  begin
    FScrollY := 0;
    FContentHeight := 0;
    DoScrollChanged;
  end;
  FNeedsLayout := True;
  StopAutoScroll;
  FDragging := False;
  FWordDragging := False;
  FScrollDragging := False;

  if (FLines.Count > 0) and (FCanvas <> nil) then
  begin
    if PixieIsBinaryString(FLines.Text) then
      raise EPixieBinaryContent.Create(SPixieBinaryContent);

    // Detect standalone SVG content
    if PixieIsLikelySvg(FLines.Text) then
    begin
      SvgData := UTF8Encode(FLines.Text);
      FSvgRenderer := TPixieSvgCanvasRenderer.Create(FCanvas);
      if not FSvgRenderer.ParseSvg(@SvgData[1], Length(SvgData),
        FSvgWidth, FSvgHeight) then
        FreeAndNil(FSvgRenderer);
      Invalidate;
      Exit;
    end;

    if Assigned(FOnBeforeParse) then
      FOnBeforeParse(Owner);
    FContainer.BaseUrl := FBaseUrl;
    W := Round(OnHostGetViewWidth() / GetEffectiveScale);
    H := Round(OnHostGetViewHeight() / GetEffectiveScale);
    FContainer.ViewportWidth := W;
    FContainer.ViewportHeight := H;
    FDocument := TPixieDocument.CreateFromString(FLines.Text, FContainer,
      PixieMasterCss, FUserCss);
    FDocument.OnChange := DoDocumentChange;
    if Assigned(FOnAfterParse) then
      FOnAfterParse(Owner);
  end;

  Invalidate;
end;

procedure TPixieHtmlViewCore.LoadFromString(const AHtml: string;
  const ABaseUrl: string);
begin
  FBaseUrl := ABaseUrl;
  FContainer.BaseUrl := ABaseUrl;
  FContainer.ClearCssCache;
  FLines.Text := AHtml;
  RebuildDocument;
end;

procedure TPixieHtmlViewCore.LoadFromFile(const AFileName: string;
  const ABaseUrl: string);
var
  Stream: TFileStream;
  Bytes: TBytes;
  Html: string;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Bytes, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Bytes[0], Stream.Size);
  finally
    Stream.Free;
  end;
  Html := PixieDecodeHtmlBytes(Bytes);
  if ABaseUrl <> '' then
    LoadFromString(Html, ABaseUrl)
  else
    LoadFromString(Html, ExtractFilePath(AFileName));
end;

procedure TPixieHtmlViewCore.LoadFromStream(AStream: TStream;
  const ABaseUrl: string);
var
  Bytes: TBytes;
  Size: Int64;
begin
  Size := AStream.Size - AStream.Position;
  SetLength(Bytes, Size);
  if Size > 0 then
    AStream.ReadBuffer(Bytes[0], Size);
  LoadFromString(PixieDecodeHtmlBytes(Bytes), ABaseUrl);
end;

procedure TPixieHtmlViewCore.DoAnchorClick(Sender: TObject;
  const Url: string);
var
  El: TPixieElement;
  Ri, Walk: TPixieRenderItem;
  NewScroll, MaxScroll, ViewH, AbsY: TPixiePixel;
begin
  if (Length(Url) > 1) and (Url[1] = '#') then
  begin
    El := FDocument.FindAnchorTarget(Copy(Url, 2, MaxInt));
    if El <> nil then
    begin
      Ri := TPixieRenderItem(El.GetRenderItem);
      if Ri <> nil then
      begin
        AbsY := Ri.Pos.Y;
        Walk := Ri.GetParent;
        while Walk <> nil do
        begin
          AbsY := AbsY + Walk.Pos.Y;
          Walk := Walk.GetParent;
        end;
        ViewH := OnHostGetViewHeight / GetEffectiveScale;
        MaxScroll := FContentHeight - ViewH;
        if MaxScroll < 0 then MaxScroll := 0;
        NewScroll := AbsY;
        if NewScroll > MaxScroll then NewScroll := MaxScroll;
        if NewScroll < 0 then NewScroll := 0;
        SetScrollY(NewScroll);
        if Assigned(OnHostGetTickCount) then
          FAnchorScrollTick := OnHostGetTickCount;
        Invalidate;
      end;
    end;
    Exit;
  end;

  if Assigned(FOnAnchorClick) then
    FOnAnchorClick(Owner, Url);
end;

function TPixieHtmlViewCore.DoElementClick(Sender: TObject;
  El: TObject): Boolean;
begin
  if Assigned(FOnElementClick) then
    Result := FOnElementClick(Owner, El)
  else
    Result := False;
end;

procedure TPixieHtmlViewCore.DoFetchUrl(Sender: TObject; const Url: string;
  Stream: TStream; var Success: Boolean);
begin
  if Assigned(FOnFetchUrl) then
    FOnFetchUrl(Owner, Url, Stream, Success);
end;

procedure TPixieHtmlViewCore.DoDocumentChange(Sender: TObject);
begin
  FNeedsLayout := True;
  Invalidate;
end;

// ---------------------------------------------------------------------------
// Image registration
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewCore.RegisterImage(const Name: string;
  Stream: TStream);
begin
  FContainer.RegisterImage(Name, Stream);
end;

procedure TPixieHtmlViewCore.UnregisterImage(const Name: string);
begin
  FContainer.UnregisterImage(Name);
end;

// ---------------------------------------------------------------------------
// Component lifecycle
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewCore.HandleLoaded;
begin
  if FLines.Count > 0 then
    RebuildDocument;
end;

// ---------------------------------------------------------------------------
// Painting
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewCore.HandlePaint(ACanvasHandle: PtrUInt);
var
  ClipPos: TPixiePosition;
  BgColor: TPixieWebColor;
  LayoutWidth: Integer;
  ViewW, ViewH: Single;
  OldContentHeight: TPixiePixel;
  BarW, BarMargin, TrackH, ThumbH, ThumbX, ThumbY, MaxScroll: TPixiePixel;
  IndicatorRadius: TPixieBorderRadiuses;
  FadedColor: TPixieWebColor;
begin
  if Assigned(FOnBeforePaint) then
    FOnBeforePaint(Owner);

  FCanvas.SetScale(GetEffectiveScale);
  FCanvas.BeginPaint(ACanvasHandle);
  try
    ViewW := OnHostGetViewWidth / GetEffectiveScale;
    ViewH := OnHostGetViewHeight / GetEffectiveScale;
    LayoutWidth := Round(ViewW);

    BgColor := OnHostGetBackgroundColor();
    FCanvas.FillRect(0, 0, ViewW, ViewH, BgColor);

    // Standalone SVG mode — render SVG and skip HTML pipeline
    if FSvgRenderer <> nil then
    begin
      FSvgRenderer.RenderToRect(0, 0, ViewW, ViewH);
    end
    else
    begin

    if FNeedsLayout and (FDocument <> nil) then
    begin
      FContainer.ViewportWidth := LayoutWidth;
      FContainer.ViewportHeight := Round(ViewH);
      OldContentHeight := FContentHeight;
      FDocument.Render(LayoutWidth);
      FContentHeight := FDocument.Height;
      if FContentHeight <> OldContentHeight then
        DoScrollChanged;
      FNeedsLayout := False;
    end;

    if FDocument <> nil then
    begin
      ClipPos := TPixiePosition.Create(0, 0, ViewW, ViewH);
      FDocument.Draw(0, 0, -FScrollY, @ClipPos);

      if (FContentHeight > ViewH) and ShouldDrawScrollbar then
      begin
        BarW := FScrollbar.Width;
        BarMargin := FScrollbar.Margin;
        TrackH := ViewH - BarMargin * 2;
        ThumbH := TrackH * (ViewH / FContentHeight);
        if ThumbH < FScrollbar.MinThumbHeight then
          ThumbH := FScrollbar.MinThumbHeight;
        MaxScroll := FContentHeight - ViewH;
        if MaxScroll > 0 then
          ThumbY := BarMargin + (FScrollY / MaxScroll) * (TrackH - ThumbH)
        else
          ThumbY := BarMargin;
        ThumbX := ViewW - BarW - BarMargin;

        // Draw track background
        if FScrollbar.TrackColor.Alpha > 0 then
        begin
          FadedColor := FScrollbar.TrackColor;
          if FScrollbar.Visibility = svAuto then
            FadedColor.Alpha := Round(FadedColor.Alpha * FScrollbarOpacity);
          FCanvas.FillRect(ThumbX, BarMargin, BarW, TrackH, FadedColor);
        end;

        // Draw thumb
        FadedColor := FScrollbar.ThumbColor;
        if FScrollbar.Visibility = svAuto then
          FadedColor.Alpha := Round(FadedColor.Alpha * FScrollbarOpacity);
        IndicatorRadius.TopLeftX := BarW / 2;
        IndicatorRadius.TopLeftY := BarW / 2;
        IndicatorRadius.TopRightX := BarW / 2;
        IndicatorRadius.TopRightY := BarW / 2;
        IndicatorRadius.BottomRightX := BarW / 2;
        IndicatorRadius.BottomRightY := BarW / 2;
        IndicatorRadius.BottomLeftX := BarW / 2;
        IndicatorRadius.BottomLeftY := BarW / 2;
        FCanvas.FillRoundedRect(ThumbX, ThumbY, BarW, ThumbH,
          IndicatorRadius, FadedColor);
      end;
    end;

    end; // else (HTML mode)
  finally
    FCanvas.EndPaint;
  end;

  if Assigned(FOnAfterPaint) then
    FOnAfterPaint(Owner);
end;

// ---------------------------------------------------------------------------
// Resize
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewCore.HandleResize;
var
  W, H: Integer;
begin
  W := Round(OnHostGetViewWidth() / GetEffectiveScale);
  H := Round(OnHostGetViewHeight() / GetEffectiveScale);
  if FContainer <> nil then
  begin
    FContainer.ViewportWidth := W;
    FContainer.ViewportHeight := H;
  end;
  if (FDocument <> nil) and FDocument.CheckMediaChanged then
    RebuildDocument
  else
    FNeedsLayout := True;
  Invalidate;
end;

// ---------------------------------------------------------------------------
// Caret blink timer
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewCore.HandleCaretTimer;
begin
  if FContainer <> nil then
  begin
    FContainer.CaretVisible := not FContainer.CaretVisible;
    if (FDocument <> nil) and (FDocument.FocusedElement <> nil) then
      Invalidate;
  end;
end;

// ---------------------------------------------------------------------------
// Keyboard
// ---------------------------------------------------------------------------

function TPixieHtmlViewCore.HandleKeyDown(Key: Word; Shift: TShiftState;
  CtrlDown: Boolean): Boolean;
var
  NewScroll, MaxScroll, ViewH: TPixiePixel;
begin
  Result := False;

  // Tab / Shift+Tab cycles focus between focusable elements
  if (Key = pxVK_TAB) and (FDocument <> nil) then
  begin
    if ssShift in Shift then
      FDocument.FocusPrev
    else
      FDocument.FocusNext;
    ResetCaret;
    Invalidate;
    Exit(True);
  end;

  // Dispatch to focused element first
  if (FDocument <> nil) and FDocument.DispatchKeyDown(Key, Shift) then
  begin
    ResetCaret;
    if Assigned(OnHostUpdateIME) then OnHostUpdateIME;
    Invalidate;
    Exit(True);
  end;

  // Ctrl+A selects all text
  if CtrlDown and (Key = Ord('A')) then
  begin
    if FDocument <> nil then
    begin
      FDocument.SelectAll;
      Invalidate;
    end;
    Exit(True);
  end;

  // Ctrl+C copies selected text
  if CtrlDown and (Key = Ord('C')) then
  begin
    if (FDocument <> nil) and FDocument.HasSelection then
    begin
      if Assigned(OnHostCopyToClipboard) then
        OnHostCopyToClipboard(FDocument.GetSelectedText);
    end;
    Exit(True);
  end;

  // Ctrl+0 resets zoom to 100%
  if CtrlDown and (Key = pxVK_0) then
  begin
    SetZoom(1.0);
    Exit(True);
  end;

  // Home / End scroll to top / bottom
  if Key in [pxVK_HOME, pxVK_END] then
  begin
    ViewH := OnHostGetViewHeight / GetEffectiveScale;
    MaxScroll := FContentHeight - ViewH;
    if MaxScroll < 0 then MaxScroll := 0;
    if Key = pxVK_HOME then
      NewScroll := 0
    else
      NewScroll := MaxScroll;
    if NewScroll <> FScrollY then
    begin
      if FScrollbar.Visibility = svAuto then
        ShowScrollbar;
      SetScrollY(NewScroll);
      Invalidate;
    end;
    if FScrollbar.Visibility = svAuto then
      StartScrollbarHide;
    Exit(True);
  end;

  // Arrow and page keys scroll the viewport
  if Key in [pxVK_UP, pxVK_DOWN, pxVK_PRIOR, pxVK_NEXT] then
  begin
    ViewH := OnHostGetViewHeight / GetEffectiveScale;
    MaxScroll := FContentHeight - ViewH;
    if MaxScroll < 0 then MaxScroll := 0;
    NewScroll := FScrollY;
    case Key of
      pxVK_UP:    NewScroll := FScrollY - 40;
      pxVK_DOWN:  NewScroll := FScrollY + 40;
      pxVK_PRIOR: NewScroll := FScrollY - ViewH;
      pxVK_NEXT:  NewScroll := FScrollY + ViewH;
    end;
    if NewScroll < 0 then NewScroll := 0;
    if NewScroll > MaxScroll then NewScroll := MaxScroll;
    if NewScroll <> FScrollY then
    begin
      if FScrollbar.Visibility = svAuto then
        ShowScrollbar;
      SetScrollY(NewScroll);
      Invalidate;
    end;
    if FScrollbar.Visibility = svAuto then
      StartScrollbarHide;
    Exit(True);
  end;
end;

function TPixieHtmlViewCore.HandleCharInput(const Ch: string): Boolean;
begin
  Result := False;
  if (Ch = '') or (FDocument = nil) then Exit;
  if FDocument.DispatchUTF8KeyPress(Ch) then
  begin
    ResetCaret;
    if Assigned(OnHostUpdateIME) then OnHostUpdateIME;
    Invalidate;
    Result := True;
  end;
end;

// ---------------------------------------------------------------------------
// Mouse events
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewCore.HandleMouseDown(IsLeft, IsDouble: Boolean;
  X, Y: Integer);
var
  Vx, Vy: Integer;
  InputFocused: Boolean;
  ViewH, ViewW, BarMargin, TrackH, ThumbH, ThumbY, MaxScroll,
    NewScroll: TPixiePixel;
begin
  if Assigned(OnHostSetFocus) then OnHostSetFocus;
  if not IsLeft or (FDocument = nil) then Exit;

  Vx := Round(X / GetEffectiveScale);
  Vy := Round(Y / GetEffectiveScale);

  // Scrollbar interaction
  ViewW := OnHostGetViewWidth / GetEffectiveScale;
  ViewH := OnHostGetViewHeight / GetEffectiveScale;
  BarMargin := FScrollbar.Margin;
  if ShouldDrawScrollbar and (FContentHeight > ViewH) and
     (Vx >= Round(ViewW) - FScrollbar.Width - BarMargin * 2) then
  begin
    TrackH := ViewH - BarMargin * 2;
    ThumbH := TrackH * (ViewH / FContentHeight);
    if ThumbH < FScrollbar.MinThumbHeight then
      ThumbH := FScrollbar.MinThumbHeight;
    MaxScroll := FContentHeight - ViewH;
    if MaxScroll > 0 then
      ThumbY := BarMargin + (FScrollY / MaxScroll) * (TrackH - ThumbH)
    else
      ThumbY := BarMargin;
    if (Vy >= ThumbY) and (Vy < ThumbY + ThumbH) then
    begin
      FScrollDragging := True;
      FScrollDragOffset := Vy - ThumbY;
    end
    else
    begin
      if Vy < ThumbY then
        NewScroll := FScrollY - ViewH
      else
        NewScroll := FScrollY + ViewH;
      if NewScroll < 0 then NewScroll := 0;
      if NewScroll > MaxScroll then NewScroll := MaxScroll;
      SetScrollY(NewScroll);
    end;
    Invalidate;
    Exit;
  end;

  FRedrawBoxes.Clear;
  if FDocument.OnLButtonDown(Vx, Vy + FScrollY, Vx, Vy,
    FRedrawBoxes) then
    Invalidate;

  InputFocused := (FDocument.FocusedElement <> nil) and
    FDocument.FocusedElement.IsFocusable;

  if InputFocused then
  begin
    if IsDouble then
      FDocument.DispatchDblClick;
    FDragging := True;
    ResetCaret;
    if Assigned(OnHostUpdateIME) then OnHostUpdateIME;
    Invalidate;
  end
  else if (FDocument.ActiveElement <> nil) and
    FDocument.ActiveElement.IsReplaced then
  begin
    // Replaced element (button, checkbox) — no text selection
  end
  else
  begin
    if FDocument.HasSelection then
    begin
      FDocument.ClearSelection;
      Invalidate;
    end;
    if IsDouble then
    begin
      if FDocument.SelectWord(Vx, Vy + FScrollY) then
      begin
        FWordDragging := True;
        FDragging := True;
        Invalidate;
      end;
    end
    else
    begin
      FWordDragging := False;
      FDocument.SelectionStart(Vx, Vy + FScrollY, Vx, Vy);
      FDragging := True;
    end;
  end;
end;

procedure TPixieHtmlViewCore.HandleMouseMove(X, Y: Integer);
var
  Vx, Vy, DeltaX: Integer;
  ViewW, ViewH, TrackH, ThumbH, MaxScroll, NewThumbY, NewScroll: TPixiePixel;
  InGutter: Boolean;
begin
  if FScrollDragging then
  begin
    Vy := Round(Y / GetEffectiveScale);
    ViewH := OnHostGetViewHeight / GetEffectiveScale;
    TrackH := ViewH - FScrollbar.Margin * 2;
    ThumbH := TrackH * (ViewH / FContentHeight);
    if ThumbH < FScrollbar.MinThumbHeight then
      ThumbH := FScrollbar.MinThumbHeight;
    MaxScroll := FContentHeight - ViewH;
    NewThumbY := Vy - FScrollDragOffset;
    if NewThumbY < FScrollbar.Margin then
      NewThumbY := FScrollbar.Margin;
    if NewThumbY > FScrollbar.Margin + TrackH - ThumbH then
      NewThumbY := FScrollbar.Margin + TrackH - ThumbH;
    if TrackH > ThumbH then
      NewScroll := (NewThumbY - FScrollbar.Margin) / (TrackH - ThumbH) * MaxScroll
    else
      NewScroll := 0;
    if NewScroll < 0 then NewScroll := 0;
    if NewScroll > MaxScroll then NewScroll := MaxScroll;
    if NewScroll <> FScrollY then
    begin
      SetScrollY(NewScroll);
      Invalidate;
    end;
    Exit;
  end;
  if FDocument <> nil then
  begin
    Vx := Round(X / GetEffectiveScale);
    Vy := Round(Y / GetEffectiveScale);

    // Gutter hover detection for svAuto
    if FScrollbar.Visibility = svAuto then
    begin
      ViewW := OnHostGetViewWidth / GetEffectiveScale;
      ViewH := OnHostGetViewHeight / GetEffectiveScale;
      InGutter := (FContentHeight > ViewH) and
        (Vx >= Round(ViewW) - Max(16, FScrollbar.Width + FScrollbar.Margin * 2));
      if InGutter and not FScrollbarHoverZone then
      begin
        FScrollbarHoverZone := True;
        ShowScrollbar;
      end;
      if not InGutter and FScrollbarHoverZone then
      begin
        FScrollbarHoverZone := False;
        StartScrollbarHide;
      end;
    end;

    FRedrawBoxes.Clear;
    if FDocument.OnMouseOver(Vx, Vy + FScrollY, Vx, Vy,
      FRedrawBoxes) then
      Invalidate;
    UpdateCursorFromCss;
    if FDragging then
    begin
      DeltaX := Abs(Vx - FLastDragVx);
      FLastDragVx := Vx;
      FLastDragVy := Vy;
      UpdateAutoScroll(Vy, OnHostGetViewHeight / GetEffectiveScale,
        DeltaX);
      if (FDocument.FocusedElement <> nil) and
         FDocument.FocusedElement.IsFocusable then
      begin
        if FDocument.DispatchMouseDrag(Vx, Vy + FScrollY) then
          Invalidate;
      end
      else
      begin
        if FWordDragging then
        begin
          if FDocument.SelectionMoveWord(Vx, Vy + FScrollY, Vx, Vy) then
            Invalidate;
        end
        else if FDocument.SelectionMove(Vx, Vy + FScrollY, Vx, Vy) then
          Invalidate;
      end;
    end;
  end;
end;

procedure TPixieHtmlViewCore.HandleMouseUp(IsLeft: Boolean; X, Y: Integer);
var
  Vx, Vy: Integer;
begin
  if IsLeft and FScrollDragging then
  begin
    FScrollDragging := False;
    if FScrollbar.Visibility = svAuto then
      StartScrollbarHide;
    Exit;
  end;
  if IsLeft and (FDocument <> nil) then
  begin
    Vx := Round(X / GetEffectiveScale);
    Vy := Round(Y / GetEffectiveScale);
    StopAutoScroll;
    FDragging := False;
    FWordDragging := False;
    FDocument.SelectionEnd;
    if FDocument.HasSelection then
      Invalidate
    else
    begin
      FRedrawBoxes.Clear;
      if FDocument.OnLButtonUp(Vx, Vy + FScrollY, Vx, Vy,
        FRedrawBoxes) then
        Invalidate;
    end;
  end;
end;

procedure TPixieHtmlViewCore.HandleMouseLeave;
begin
  StopAutoScroll;
  if FScrollbarHoverZone then
  begin
    FScrollbarHoverZone := False;
    if FScrollbar.Visibility = svAuto then
      StartScrollbarHide;
  end;
  if FDocument <> nil then
  begin
    FRedrawBoxes.Clear;
    if FDocument.OnMouseLeave(FRedrawBoxes) then
      Invalidate;
  end;
  if Assigned(OnHostSetCursor) then
    OnHostSetCursor(pxCurDefault);
end;

function TPixieHtmlViewCore.HandleMouseWheel(WheelDelta: Integer;
  CtrlDown: Boolean; MouseX, MouseY: Integer): Boolean;
var
  NewScroll, MaxScroll: TPixiePixel;
  NewZoom: Double;
  Tick: UInt64;
begin
  // Suppress wheel inertia after anchor scroll
  if FAnchorScrollTick > 0 then
  begin
    if Assigned(OnHostGetTickCount) then
    begin
      Tick := OnHostGetTickCount;
      if Tick - FAnchorScrollTick < 200 then
      begin
        FAnchorScrollTick := Tick;
        Exit(True);
      end;
    end;
    FAnchorScrollTick := 0;
  end;

  // Ctrl+wheel zooms
  if CtrlDown then
  begin
    if WheelDelta > 0 then
      NewZoom := FZoom * 1.1
    else
      NewZoom := FZoom / 1.1;
    SetZoom(NewZoom);
    Exit(True);
  end;

  // Dispatch to element under mouse (textarea scrolling)
  if FDocument <> nil then
  begin
    if FDocument.DispatchMouseWheel(MouseX,
      MouseY + Round(FScrollY), WheelDelta) then
    begin
      Invalidate;
      Exit(True);
    end;
  end;

  MaxScroll := FContentHeight - OnHostGetViewHeight / GetEffectiveScale;
  if MaxScroll < 0 then MaxScroll := 0;

  NewScroll := FScrollY - (WheelDelta / 120) * 40;
  if NewScroll < 0 then NewScroll := 0;
  if NewScroll > MaxScroll then NewScroll := MaxScroll;

  if NewScroll <> FScrollY then
  begin
    if FScrollbar.Visibility = svAuto then
      ShowScrollbar;
    SetScrollY(NewScroll);
    Invalidate;
  end;

  if FScrollbar.Visibility = svAuto then
    StartScrollbarHide;

  Result := True;
end;

end.
