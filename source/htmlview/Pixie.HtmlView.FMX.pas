unit Pixie.HtmlView.FMX;

// TPixieHtmlView — Delphi FMX visual component that renders HTML content
// using the Pixie engine with FireMonkey graphics. Enables cross-platform
// HTML rendering on Windows, macOS, iOS, and Android.

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  System.Rtti,
  FMX.Controls, FMX.Graphics, FMX.Types, FMX.Platform,
  FMX.Text, FMX.Forms,
  Pixie.Types, Pixie.WebColor, Pixie.Document,
  Pixie.Canvas, Pixie.NativeContainer,
  Pixie.CustomControl.FMX,
  Pixie.HtmlView.Base;

type
  { TPixieHtmlView }

  TPixieHtmlView = class(TPixieFmxCustomControl, ITextInput)
  private
    FCore: TPixieHtmlViewCore;
    FCaretTimer: TTimer;
    FTextService: TTextService;
    FLastMouseX: Single;
    FLastMouseY: Single;

    procedure DoCaretTimer(Sender: TObject);
    procedure ClipboardCopy(const S: string);

    // ITextInput
    function GetTextService: TTextService;
    function GetTargetClausePointF: TPointF;
    procedure StartIMEInput;
    procedure EndIMEInput;
    procedure IMEStateUpdated;
    function GetSelection: string;
    function GetSelectionRect: TRectF;
    function GetSelectionBounds: TRect;
    function GetSelectionPointSize: TSizeF;
    function HasText: Boolean;

    // Host callbacks
    procedure HostInvalidate;
    procedure HostSetCursor(ACursor: TPixieCursorKind);
    procedure HostSetFocus;
    function HostGetViewWidth: TPixiePixel;
    function HostGetViewHeight: TPixiePixel;
    function HostGetBackgroundColor: TPixieWebColor;
    procedure HostCopyToClipboard(const Text: string);
    function HostGetTickCount: UInt64;
    procedure HostResetCaret;

    // Property forwarding
    function GetDocument: TPixieDocument;
    function GetContentHeight: TPixiePixel;
    function GetScrollY: TPixiePixel;
    procedure SetScrollY(Value: TPixiePixel);
    function GetLines: TStrings;
    procedure SetLines(const Value: TStrings);
    function GetBaseUrl: string;
    procedure SetBaseUrl(const Value: string);
    function GetUserCss: string;
    procedure SetUserCss(const Value: string);
    function GetZoom: Double;
    procedure SetZoom(const Value: Double);
    function GetScrollbar: TPixieScrollbarSettings;
    function GetAutoScrollSpeed: Integer;
    procedure SetAutoScrollSpeed(Value: Integer);
    function GetAutoScrollEdge: Integer;
    procedure SetAutoScrollEdge(Value: Integer);
    function GetAutoScrollAccelThreshold: Integer;
    procedure SetAutoScrollAccelThreshold(Value: Integer);
    function GetAutoScrollAccelMax: Integer;
    procedure SetAutoScrollAccelMax(Value: Integer);
    function GetOnAnchorClick: TPixieAnchorClickEvent;
    procedure SetOnAnchorClick(Value: TPixieAnchorClickEvent);
    function GetOnElementClick: TPixieElementClickEvent;
    procedure SetOnElementClick(Value: TPixieElementClickEvent);
    function GetOnFetchUrl: TPixieFetchUrlEvent;
    procedure SetOnFetchUrl(Value: TPixieFetchUrlEvent);
    function GetOnBeforeParse: TNotifyEvent;
    procedure SetOnBeforeParse(Value: TNotifyEvent);
    function GetOnAfterParse: TNotifyEvent;
    procedure SetOnAfterParse(Value: TNotifyEvent);
    function GetOnBeforePaint: TNotifyEvent;
    procedure SetOnBeforePaint(Value: TNotifyEvent);
    function GetOnAfterPaint: TNotifyEvent;
    procedure SetOnAfterPaint(Value: TNotifyEvent);
    function GetOnScrollChanged: TNotifyEvent;
    procedure SetOnScrollChanged(Value: TNotifyEvent);
  protected
    procedure Loaded; override;
    procedure DoPaint; override;
    procedure DoMouseLeave; override;
    procedure Resize; override;
    procedure DialogKey(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer;
      var Handled: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure LoadFromString(const AHtml: string;
      const ABaseUrl: string = '');
    procedure LoadFromFile(const AFileName: string;
      const ABaseUrl: string = '');
    procedure LoadFromStream(AStream: TStream;
      const ABaseUrl: string = '');
    procedure RegisterImage(const Name: string; Stream: TStream);
    procedure UnregisterImage(const Name: string);

    property Document: TPixieDocument read GetDocument;
    property Scrollbar: TPixieScrollbarSettings read GetScrollbar;
    property ContentHeight: TPixiePixel read GetContentHeight;
    property ScrollY: TPixiePixel read GetScrollY write SetScrollY;
    property AutoScrollSpeed: Integer read GetAutoScrollSpeed
      write SetAutoScrollSpeed;
    property AutoScrollEdge: Integer read GetAutoScrollEdge
      write SetAutoScrollEdge;
    property AutoScrollAccelThreshold: Integer read GetAutoScrollAccelThreshold
      write SetAutoScrollAccelThreshold;
    property AutoScrollAccelMax: Integer read GetAutoScrollAccelMax
      write SetAutoScrollAccelMax;
  published
    property Lines: TStrings read GetLines write SetLines;
    property BaseUrl: string read GetBaseUrl write SetBaseUrl;
    property UserCss: string read GetUserCss write SetUserCss;
    property Zoom: Double read GetZoom write SetZoom;
    property OnAnchorClick: TPixieAnchorClickEvent
      read GetOnAnchorClick write SetOnAnchorClick;
    property OnElementClick: TPixieElementClickEvent
      read GetOnElementClick write SetOnElementClick;
    property OnFetchUrl: TPixieFetchUrlEvent
      read GetOnFetchUrl write SetOnFetchUrl;
    property OnBeforeParse: TNotifyEvent
      read GetOnBeforeParse write SetOnBeforeParse;
    property OnAfterParse: TNotifyEvent
      read GetOnAfterParse write SetOnAfterParse;
    property OnBeforePaint: TNotifyEvent
      read GetOnBeforePaint write SetOnBeforePaint;
    property OnAfterPaint: TNotifyEvent
      read GetOnAfterPaint write SetOnAfterPaint;
    property OnScrollChanged: TNotifyEvent
      read GetOnScrollChanged write SetOnScrollChanged;

    property Align;
    property Anchors;
    property ClipChildren default True;
    property ClipParent default False;
    property Enabled;
    property Height;
    property HitTest default True;
    property Locked default False;
    property Margins;
    property Opacity;
    property Padding;
    property PopupMenu;
    property Position;
    property RotationAngle;
    property RotationCenter;
    property Scale;
    property Size;
    property TabOrder;
    property Visible;
    property Width;

    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseMove;
    property OnMouseUp;
    property OnMouseWheel;
    property OnResize;
  end;

implementation

// ---------------------------------------------------------------------------
// Clipboard helpers via FMX platform services
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.ClipboardCopy(const S: string);
var
  Svc: IFMXClipboardService;
begin
  if TPlatformServices.Current.SupportsPlatformService(
    IFMXClipboardService, Svc) then
    Svc.SetClipboard(TValue.From<string>(S));
end;

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieHtmlView.Create(AOwner: TComponent);
var
  TextSvc: IFMXTextService;
begin
  FCore := nil;
  FTextService := nil;
  FLastMouseX := 0;
  FLastMouseY := 0;

  inherited Create(AOwner);
  ClipChildren := True;
  AutoCapture := True;
  Width := 400;
  Height := 300;
  CanFocus := True;

  if not (csDesigning in ComponentState) then
    if TPlatformServices.Current.SupportsPlatformService(
      IFMXTextService, TextSvc) then
      FTextService := TextSvc.GetTextServiceClass.Create(Self, False);

  FCore := TPixieHtmlViewCore.Create(PixieCanvas);
  FCore.Owner := Self;
  FCore.OnHostInvalidate := HostInvalidate;
  FCore.OnHostSetCursor := HostSetCursor;
  FCore.OnHostSetFocus := HostSetFocus;
  FCore.OnHostGetViewWidth := HostGetViewWidth;
  FCore.OnHostGetViewHeight := HostGetViewHeight;
  FCore.OnHostGetBackgroundColor := HostGetBackgroundColor;
  FCore.OnHostCopyToClipboard := HostCopyToClipboard;
  FCore.OnHostGetTickCount := HostGetTickCount;
  FCore.OnHostResetCaret := HostResetCaret;

  FCaretTimer := TTimer.Create(Self);
  FCaretTimer.Interval := 530;
  FCaretTimer.OnTimer := DoCaretTimer;
  FCaretTimer.Enabled := True;
end;

destructor TPixieHtmlView.Destroy;
begin
  FreeAndNil(FCaretTimer);
  FreeAndNil(FTextService);
  FreeAndNil(FCore);
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Host callbacks
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.HostInvalidate;
begin
  InvalidateRect(LocalRect);
end;

procedure TPixieHtmlView.HostSetCursor(ACursor: TPixieCursorKind);
begin
  SetPixieCursor(ACursor);
end;

procedure TPixieHtmlView.HostSetFocus;
begin
  SetFocus;
end;

function TPixieHtmlView.HostGetViewWidth: TPixiePixel;
begin
  Result := Width;
end;

function TPixieHtmlView.HostGetViewHeight: TPixiePixel;
begin
  Result := Height;
end;

function TPixieHtmlView.HostGetBackgroundColor: TPixieWebColor;
begin
  Result := GetBackgroundColor;
end;

procedure TPixieHtmlView.HostCopyToClipboard(const Text: string);
begin
  ClipboardCopy(Text);
end;

function TPixieHtmlView.HostGetTickCount: UInt64;
begin
  Result := UInt64(TThread.GetTickCount);
end;

procedure TPixieHtmlView.HostResetCaret;
begin
  FCaretTimer.Enabled := False;
  FCaretTimer.Enabled := True;
end;

// ---------------------------------------------------------------------------
// Property forwarding
// ---------------------------------------------------------------------------

function TPixieHtmlView.GetDocument: TPixieDocument;
begin
  Result := FCore.Document;
end;

function TPixieHtmlView.GetContentHeight: TPixiePixel;
begin
  Result := FCore.ContentHeight;
end;

function TPixieHtmlView.GetScrollY: TPixiePixel;
begin
  Result := FCore.ScrollY;
end;

procedure TPixieHtmlView.SetScrollY(Value: TPixiePixel);
begin
  FCore.ScrollY := Value;
end;

function TPixieHtmlView.GetLines: TStrings;
begin
  Result := FCore.Lines;
end;

procedure TPixieHtmlView.SetLines(const Value: TStrings);
begin
  FCore.Lines := Value;
end;

function TPixieHtmlView.GetBaseUrl: string;
begin
  Result := FCore.BaseUrl;
end;

procedure TPixieHtmlView.SetBaseUrl(const Value: string);
begin
  FCore.BaseUrl := Value;
end;

function TPixieHtmlView.GetUserCss: string;
begin
  Result := FCore.UserCss;
end;

procedure TPixieHtmlView.SetUserCss(const Value: string);
begin
  FCore.UserCss := Value;
end;

function TPixieHtmlView.GetZoom: Double;
begin
  Result := FCore.Zoom;
end;

procedure TPixieHtmlView.SetZoom(const Value: Double);
begin
  FCore.Zoom := Value;
end;

function TPixieHtmlView.GetScrollbar: TPixieScrollbarSettings;
begin
  Result := FCore.Scrollbar;
end;

function TPixieHtmlView.GetAutoScrollSpeed: Integer;
begin
  Result := FCore.AutoScrollSpeed;
end;

procedure TPixieHtmlView.SetAutoScrollSpeed(Value: Integer);
begin
  FCore.AutoScrollSpeed := Value;
end;

function TPixieHtmlView.GetAutoScrollEdge: Integer;
begin
  Result := FCore.AutoScrollEdge;
end;

procedure TPixieHtmlView.SetAutoScrollEdge(Value: Integer);
begin
  FCore.AutoScrollEdge := Value;
end;

function TPixieHtmlView.GetAutoScrollAccelThreshold: Integer;
begin
  Result := FCore.AutoScrollAccelThreshold;
end;

procedure TPixieHtmlView.SetAutoScrollAccelThreshold(Value: Integer);
begin
  FCore.AutoScrollAccelThreshold := Value;
end;

function TPixieHtmlView.GetAutoScrollAccelMax: Integer;
begin
  Result := FCore.AutoScrollAccelMax;
end;

procedure TPixieHtmlView.SetAutoScrollAccelMax(Value: Integer);
begin
  FCore.AutoScrollAccelMax := Value;
end;

function TPixieHtmlView.GetOnAnchorClick: TPixieAnchorClickEvent;
begin
  Result := FCore.OnAnchorClick;
end;

procedure TPixieHtmlView.SetOnAnchorClick(Value: TPixieAnchorClickEvent);
begin
  FCore.OnAnchorClick := Value;
end;

function TPixieHtmlView.GetOnElementClick: TPixieElementClickEvent;
begin
  Result := FCore.OnElementClick;
end;

procedure TPixieHtmlView.SetOnElementClick(Value: TPixieElementClickEvent);
begin
  FCore.OnElementClick := Value;
end;

function TPixieHtmlView.GetOnFetchUrl: TPixieFetchUrlEvent;
begin
  Result := FCore.OnFetchUrl;
end;

procedure TPixieHtmlView.SetOnFetchUrl(Value: TPixieFetchUrlEvent);
begin
  FCore.OnFetchUrl := Value;
end;

function TPixieHtmlView.GetOnBeforeParse: TNotifyEvent;
begin
  Result := FCore.OnBeforeParse;
end;

procedure TPixieHtmlView.SetOnBeforeParse(Value: TNotifyEvent);
begin
  FCore.OnBeforeParse := Value;
end;

function TPixieHtmlView.GetOnAfterParse: TNotifyEvent;
begin
  Result := FCore.OnAfterParse;
end;

procedure TPixieHtmlView.SetOnAfterParse(Value: TNotifyEvent);
begin
  FCore.OnAfterParse := Value;
end;

function TPixieHtmlView.GetOnBeforePaint: TNotifyEvent;
begin
  Result := FCore.OnBeforePaint;
end;

procedure TPixieHtmlView.SetOnBeforePaint(Value: TNotifyEvent);
begin
  FCore.OnBeforePaint := Value;
end;

function TPixieHtmlView.GetOnAfterPaint: TNotifyEvent;
begin
  Result := FCore.OnAfterPaint;
end;

procedure TPixieHtmlView.SetOnAfterPaint(Value: TNotifyEvent);
begin
  FCore.OnAfterPaint := Value;
end;

function TPixieHtmlView.GetOnScrollChanged: TNotifyEvent;
begin
  Result := FCore.OnScrollChanged;
end;

procedure TPixieHtmlView.SetOnScrollChanged(Value: TNotifyEvent);
begin
  FCore.OnScrollChanged := Value;
end;

// ---------------------------------------------------------------------------
// Public methods (forwarded)
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.LoadFromString(const AHtml: string;
  const ABaseUrl: string);
begin
  FCore.LoadFromString(AHtml, ABaseUrl);
end;

procedure TPixieHtmlView.LoadFromFile(const AFileName: string;
  const ABaseUrl: string);
begin
  FCore.LoadFromFile(AFileName, ABaseUrl);
end;

procedure TPixieHtmlView.LoadFromStream(AStream: TStream;
  const ABaseUrl: string);
begin
  FCore.LoadFromStream(AStream, ABaseUrl);
end;

procedure TPixieHtmlView.RegisterImage(const Name: string; Stream: TStream);
begin
  FCore.RegisterImage(Name, Stream);
end;

procedure TPixieHtmlView.UnregisterImage(const Name: string);
begin
  FCore.UnregisterImage(Name);
end;

// ---------------------------------------------------------------------------
// ITextInput
// ---------------------------------------------------------------------------

function TPixieHtmlView.GetTextService: TTextService;
begin
  Result := FTextService;
end;

function TPixieHtmlView.GetTargetClausePointF: TPointF;
var
  DocX, DocY, H: TPixiePixel;
begin
  Result := TPointF.Zero;
  if (FCore.Document <> nil) and
     FCore.Document.GetFocusedCaretPos(DocX, DocY, H) then
  begin
    Result.X := DocX * FCore.Zoom;
    Result.Y := (DocY - FCore.ScrollY + H) * FCore.Zoom + 2;
    Result := LocalToAbsolute(Result);
  end;
end;

procedure TPixieHtmlView.StartIMEInput;
begin
end;

procedure TPixieHtmlView.EndIMEInput;
begin
end;

procedure TPixieHtmlView.IMEStateUpdated;
begin
  Repaint;
end;

function TPixieHtmlView.GetSelection: string;
begin
  if (FCore.Document <> nil) and FCore.Document.HasSelection then
    Result := FCore.Document.GetSelectedText
  else
    Result := '';
end;

function TPixieHtmlView.GetSelectionRect: TRectF;
var
  DocX, DocY, H: TPixiePixel;
begin
  if (FCore.Document <> nil) and
     FCore.Document.GetFocusedCaretPos(DocX, DocY, H) then
  begin
    Result.Left := DocX * FCore.Zoom;
    Result.Top := (DocY - FCore.ScrollY) * FCore.Zoom;
    Result.Right := Result.Left + 2;
    Result.Bottom := Result.Top + H * FCore.Zoom;
  end
  else
    Result := TRectF.Empty;
end;

function TPixieHtmlView.GetSelectionBounds: TRect;
begin
  Result := TRect.Create(
    TPoint.Create(Round(LocalRect.Left), Round(LocalRect.Top)),
    Round(LocalRect.Width), Round(LocalRect.Height));
end;

function TPixieHtmlView.GetSelectionPointSize: TSizeF;
begin
  Result := TSizeF.Create(LocalRect.Width, LocalRect.Height);
end;

function TPixieHtmlView.HasText: Boolean;
begin
  Result := FCore.Document <> nil;
end;

// ---------------------------------------------------------------------------
// Focus — text service enter/exit for IME
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.DoEnter;
var
  Form: TCommonCustomForm;
begin
  inherited;
  if (FTextService <> nil) and (Root <> nil) and
     (Root.GetObject is TCommonCustomForm) then
  begin
    Form := TCommonCustomForm(Root.GetObject);
    FTextService.EnterControl(Form.Handle);
  end;
end;

procedure TPixieHtmlView.DoExit;
var
  Form: TCommonCustomForm;
begin
  if (FTextService <> nil) and (Root <> nil) and
     (Root.GetObject is TCommonCustomForm) then
  begin
    Form := TCommonCustomForm(Root.GetObject);
    FTextService.ExitControl(Form.Handle);
  end;
  inherited;
end;

// ---------------------------------------------------------------------------
// Painting and layout
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.Loaded;
begin
  inherited Loaded;
  FCore.HandleLoaded;
end;

procedure TPixieHtmlView.DoPaint;
begin
  if FCore = nil then Exit;
  FCore.HandlePaint(GetPaintHandle);
end;

procedure TPixieHtmlView.DoMouseLeave;
begin
  inherited;
  if FCore <> nil then
    FCore.HandleMouseLeave;
end;

procedure TPixieHtmlView.Resize;
begin
  inherited Resize;
  if FCore <> nil then
    FCore.HandleResize;
end;

// ---------------------------------------------------------------------------
// Caret timer
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.DoCaretTimer(Sender: TObject);
begin
  FCore.HandleCaretTimer;
end;

// ---------------------------------------------------------------------------
// Keyboard
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.DialogKey(var Key: Word; Shift: TShiftState);
begin
  if (Key = vkTab) and (FCore.Document <> nil) then
  begin
    if FCore.HandleKeyDown(Key, Shift,
      {$IFDEF MACOS}ssCommand{$ELSE}ssCtrl{$ENDIF} in Shift) then
    begin
      Key := 0;
      Exit;
    end;
  end;
  inherited;
end;

procedure TPixieHtmlView.KeyDown(var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
var
  S: string;
  CtrlDown: Boolean;
begin
  inherited KeyDown(Key, KeyChar, Shift);

  {$IFDEF MACOS}
  CtrlDown := ssCommand in Shift;
  {$ELSE}
  CtrlDown := ssCtrl in Shift;
  {$ENDIF}

  // Dispatch virtual key to core
  if (Key <> 0) and FCore.HandleKeyDown(Key, Shift, CtrlDown) then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;

  // Printable character input for focused text elements
  if KeyChar >= ' ' then
  begin
    S := KeyChar;
    if FCore.HandleCharInput(S) then
    begin
      Key := 0;
      KeyChar := #0;
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Mouse
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  inherited MouseDown(Button, Shift, X, Y);
  FLastMouseX := Round(X / FCore.Zoom);
  FLastMouseY := Round(Y / FCore.Zoom);
  FCore.HandleMouseDown(Button = TMouseButton.mbLeft, ssDouble in Shift,
    Round(X), Round(Y));
end;

procedure TPixieHtmlView.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  inherited MouseMove(Shift, X, Y);
  FCore.HandleMouseMove(Round(X), Round(Y));
end;

procedure TPixieHtmlView.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FCore.HandleMouseUp(Button = TMouseButton.mbLeft, Round(X), Round(Y));
end;

procedure TPixieHtmlView.MouseWheel(Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
var
  CtrlDown: Boolean;
begin
  inherited MouseWheel(Shift, WheelDelta, Handled);
  if Handled then Exit;

  {$IFDEF MACOS}
  CtrlDown := ssCommand in Shift;
  {$ELSE}
  CtrlDown := ssCtrl in Shift;
  {$ENDIF}

  Handled := FCore.HandleMouseWheel(WheelDelta, CtrlDown,
    Round(FLastMouseX), Round(FLastMouseY));
end;

end.
