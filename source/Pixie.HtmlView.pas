unit Pixie.HtmlView;

// TPixieHtmlView — Lazarus visual component that renders HTML content
// using the Pixie engine with platform-native graphics.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Controls, Graphics, Forms, ExtCtrls,
  LMessages, LCLType,
  Pixie.Types, Pixie.WebColor, Pixie.Document,
  Pixie.Canvas, Pixie.NativeContainer,
  Pixie.HtmlView.Base
  {$IF DEFINED(LCLqt5) or DEFINED(LCLqt6)}
    , Pixie.Canvas.Qt
  {$ELSEIF DEFINED(MSWINDOWS)}
    , JwaWinUser, Pixie.Canvas.D2D
  {$ELSEIF DEFINED(DARWIN)}
    , Pixie.Canvas.CG
  {$ELSEIF DEFINED(UNIX)}
    , Pixie.Canvas.Cairo
  {$ENDIF};


type
  { TPixieHtmlView }

  TPixieHtmlView = class(TCustomControl)
  private
    FCore: TPixieHtmlViewCore;
    FCaretTimer: TTimer;

    procedure DoCaretTimer(Sender: TObject);
    procedure WMEraseBkgnd(var Msg: TLMEraseBkgnd); message LM_ERASEBKGND;
    procedure CMMouseLeave(var Msg: TLMessage); message CM_MOUSELEAVE;
    {$IFDEF MSWINDOWS}
    procedure WMIMEStartComposition(var Msg: TLMessage); message WM_IME_STARTCOMPOSITION;
    {$ENDIF}
    {$IF DEFINED(LCLqt5) or DEFINED(LCLqt6)}
    procedure LMIMQuery(var Msg: TLMessage); message LM_IM_QUERY;
    {$ENDIF}
    {$IFDEF WITH_GTK2_IM}
    procedure LMIMComposition(var Msg: TLMessage); message LM_IM_COMPOSITION;
    {$ENDIF}
    procedure UpdateIMEPosition;

    // Host callbacks
    procedure HostInvalidate;
    procedure HostSetCursor(ACursor: TPixieCursorKind);
    procedure HostSetFocus;
    function HostGetViewWidth: TPixiePixel;
    function HostGetViewHeight: TPixiePixel;
    function HostGetScaleFactor: Single;
    function HostGetBackgroundColor: TPixieWebColor;
    procedure HostCopyToClipboard(const Text: string);
    function HostGetTickCount: UInt64;
    procedure HostResetCaret;
    procedure HostUpdateIME;

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
  protected
    procedure Loaded; override;
    procedure Paint; override;
    procedure Resize; override;
    {$IF DEFINED(LCLGTK2) or DEFINED(LCLGTK3)}
    procedure DoEnter; override;
    procedure DoExit; override;
    {$ENDIF}
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure LoadFromString(const AHtml: string;
      const ABaseUrl: string = '');
    procedure LoadFromFile(const AFileName: string; const ABaseUrl: string = '');
    procedure LoadFromStream(AStream: TStream;
      const ABaseUrl: string = '');
    procedure RegisterImage(const Name: string; Stream: TStream);
    procedure UnregisterImage(const Name: string);

    property Document: TPixieDocument read GetDocument;
    property Scrollbar: TPixieScrollbarSettings read GetScrollbar;
    property ContentHeight: TPixiePixel read GetContentHeight;
    property ScrollY: TPixiePixel read GetScrollY write SetScrollY;
  published
    property BorderSpacing;
    property TabOrder;
    property TabStop;
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

    property Align;
    property Anchors;
    property Color;
    property Constraints;
    property Enabled;
    property PopupMenu;
    property Visible;

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

uses
  Clipbrd
  {$IFDEF MSWINDOWS}
  , Windows, imm
  {$ENDIF}
  {$IFDEF LCLGTK2}
  , Glib2, Gdk2, Gtk2
  {$IFDEF WITH_GTK2_IM}
  , Gtk2Globals
  {$ENDIF}
  {$ENDIF}
  {$IFDEF LCLGTK3}
  , LazGdk3, LazGtk3, LazGLib2, LazGObject2, Gtk3Widgets
  {$ENDIF};

const
  ssCtrlOS = {$IFDEF DARWIN}ssMeta{$ELSE}ssCtrl{$ENDIF};

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieHtmlView.Create(AOwner: TComponent);
var
  PxCanvas: TPixieCanvas;
begin
  FCore := nil;
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Color := clWhite;
  Width := 400;
  Height := 300;
  TabStop := True;

  PxCanvas := nil;
  {$IF DEFINED(LCLqt5) or DEFINED(LCLqt6)}
  PxCanvas := TPixieQtCanvas.Create;
  {$ELSEIF DEFINED(MSWINDOWS)}
  PxCanvas := TPixieD2DCanvas.Create;
  {$ELSEIF DEFINED(DARWIN)}
  PxCanvas := TPixieCGCanvas.Create;
  {$ELSEIF DEFINED(UNIX)}
  PxCanvas := TPixieCairoCanvas.Create;
  {$ENDIF}

  FCore := TPixieHtmlViewCore.Create(PxCanvas);
  FCore.Owner := Self;
  FCore.OnHostInvalidate := HostInvalidate;
  FCore.OnHostSetCursor := HostSetCursor;
  FCore.OnHostSetFocus := HostSetFocus;
  FCore.OnHostGetViewWidth := HostGetViewWidth;
  FCore.OnHostGetViewHeight := HostGetViewHeight;
  FCore.OnHostGetScaleFactor := HostGetScaleFactor;
  FCore.OnHostGetBackgroundColor := HostGetBackgroundColor;
  FCore.OnHostCopyToClipboard := HostCopyToClipboard;
  FCore.OnHostGetTickCount := HostGetTickCount;
  FCore.OnHostResetCaret := HostResetCaret;
  FCore.OnHostUpdateIME := HostUpdateIME;

  FCaretTimer := TTimer.Create(Self);
  FCaretTimer.Interval := 530;
  FCaretTimer.OnTimer := DoCaretTimer;
  FCaretTimer.Enabled := True;
end;

destructor TPixieHtmlView.Destroy;
begin
  FreeAndNil(FCaretTimer);
  FreeAndNil(FCore);
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Host callbacks
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.HostInvalidate;
begin
  Invalidate;
end;

procedure TPixieHtmlView.HostSetCursor(ACursor: TPixieCursorKind);
const
  CursorMap: array[TPixieCursorKind] of TCursor = (
    crDefault, crHandPoint, crIBeam, crCross, crSizeAll);
begin
  Self.Cursor := CursorMap[ACursor];
end;

procedure TPixieHtmlView.HostSetFocus;
begin
  SetFocus;
end;

function TPixieHtmlView.HostGetViewWidth: TPixiePixel;
begin
  Result := ClientWidth;
end;

function TPixieHtmlView.HostGetViewHeight: TPixiePixel;
begin
  Result := ClientHeight;
end;

function TPixieHtmlView.HostGetScaleFactor: Single;
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
  Result := GetCanvasScaleFactor;
  {$ENDIF}
end;

function TPixieHtmlView.HostGetBackgroundColor: TPixieWebColor;
var
  Rgb: LongInt;
begin
  Rgb := ColorToRGB(Self.Color);
  Result := TPixieWebColor.Create(
    Byte(Rgb), Byte(Rgb shr 8), Byte(Rgb shr 16));
end;

procedure TPixieHtmlView.HostCopyToClipboard(const Text: string);
begin
  Clipboard.AsText := Text;
end;

function TPixieHtmlView.HostGetTickCount: UInt64;
begin
  Result := GetTickCount64;
end;

procedure TPixieHtmlView.HostResetCaret;
begin
  FCaretTimer.Enabled := False;
  FCaretTimer.Enabled := True;
end;

procedure TPixieHtmlView.HostUpdateIME;
begin
  UpdateIMEPosition;
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

function TPixieHtmlView.GetScrollbar: TPixieScrollbarSettings;
begin
  Result := FCore.Scrollbar;
end;

procedure TPixieHtmlView.SetZoom(const Value: Double);
begin
  FCore.Zoom := Value;
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
// Messages
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.WMEraseBkgnd(var Msg: TLMEraseBkgnd);
begin
  Msg.Result := 1;
end;

procedure TPixieHtmlView.CMMouseLeave(var Msg: TLMessage);
begin
  inherited;
  if FCore <> nil then
    FCore.HandleMouseLeave;
end;

// ---------------------------------------------------------------------------
// IME
// ---------------------------------------------------------------------------

{$IF DEFINED(LCLGTK2) or DEFINED(LCLGTK3)}
{$IFNDEF WITH_GTK2_IM}
var
  PixieGtkIMContext: PGtkIMContext = nil;
  PixieGtkIMEOwner: TPixieHtmlView = nil;
{$ENDIF}
{$ENDIF}

procedure TPixieHtmlView.UpdateIMEPosition;
var
  DocX, DocY, H: TPixiePixel;
  ClientX, ClientY: Integer;
  {$IFDEF MSWINDOWS}
  Imc: HIMC;
  CompForm: COMPOSITIONFORM;
  {$ENDIF}
  {$IF DEFINED(LCLGTK2) or DEFINED(LCLGTK3)}
  Area: TGdkRectangle;
  {$ENDIF}
begin
  if FCore.Document = nil then Exit;
  if not FCore.Document.GetFocusedCaretPos(DocX, DocY, H) then Exit;

  ClientX := Round(DocX * FCore.Zoom);
  ClientY := Round((DocY - FCore.ScrollY) * FCore.Zoom);

  {$IFDEF MSWINDOWS}
  Imc := ImmGetContext(Handle);
  if Imc <> 0 then
  begin
    CompForm.dwStyle := CFS_POINT;
    CompForm.ptCurrentPos.X := ClientX;
    CompForm.ptCurrentPos.Y := ClientY;
    ImmSetCompositionWindow(Imc, @CompForm);
    ImmReleaseContext(Handle, Imc);
  end;
  {$ENDIF}

  {$IF DEFINED(LCLGTK2) or DEFINED(LCLGTK3)}
  Area.x := ClientX;
  Area.y := ClientY;
  Area.width := 1;
  Area.height := Round(H * FCore.Zoom);
  {$IFDEF WITH_GTK2_IM}
  if im_context <> nil then
    gtk_im_context_set_cursor_location(im_context, @Area);
  {$ELSE}
  if PixieGtkIMContext <> nil then
    gtk_im_context_set_cursor_location(PixieGtkIMContext, @Area);
  {$ENDIF}
  {$ENDIF}
end;

{$IFDEF MSWINDOWS}
procedure TPixieHtmlView.WMIMEStartComposition(var Msg: TLMessage);
begin
  inherited;
  UpdateIMEPosition;
end;
{$ENDIF}

{$IF DEFINED(LCLqt5) or DEFINED(LCLqt6)}
procedure TPixieHtmlView.LMIMQuery(var Msg: TLMessage);
var
  DocX, DocY, H: TPixiePixel;
  P: ^TPoint;
begin
  if (Msg.LParam <> 0) and (FCore.Document <> nil) and
     FCore.Document.GetFocusedCaretPos(DocX, DocY, H) then
  begin
    P := Pointer(Msg.LParam);
    P^.X := Round(DocX * FCore.Zoom);
    P^.Y := Round((DocY - FCore.ScrollY) * FCore.Zoom);
  end;
end;
{$ENDIF}

{$IFDEF WITH_GTK2_IM}
procedure TPixieHtmlView.LMIMComposition(var Msg: TLMessage);
var
  S: string;
begin
  if (Msg.WParam and GTK_IM_FLAG_COMMIT) <> 0 then
  begin
    S := PChar(Msg.LParam);
    if FCore.HandleCharInput(S) then
      UpdateIMEPosition;
  end;
end;
{$ENDIF}

{$IF DEFINED(LCLGTK2) or DEFINED(LCLGTK3)}
{$IFNDEF WITH_GTK2_IM}
procedure PixieGtkIMCommitCb(Context: PGtkIMContext; Str: PGChar;
  Data: Pointer); cdecl;
var
  S: string;
begin
  if PixieGtkIMEOwner <> nil then
  begin
    S := Str;
    PixieGtkIMEOwner.FCore.HandleCharInput(S);
    PixieGtkIMEOwner.UpdateIMEPosition;
  end;
end;
{$ENDIF}
{$ENDIF}

{$IF DEFINED(LCLGTK2) or DEFINED(LCLGTK3)}
procedure TPixieHtmlView.DoEnter;
{$IFNDEF WITH_GTK2_IM}
var
  GdkWin: PGdkWindow;
  ParentForm: TCustomForm;
{$ENDIF}
begin
  inherited;

  {$IFNDEF WITH_GTK2_IM}
  ParentForm := GetParentForm(Self);
  if ParentForm = nil then Exit;

  {$IFDEF LCLGTK2}
  GdkWin := PGtkWidget(ParentForm.Handle)^.window;
  {$ELSE}
  if TGtk3Widget(ParentForm.Handle) = nil then Exit;
  GdkWin := gtk_widget_get_window(TGtk3Widget(ParentForm.Handle).Widget);
  {$ENDIF}
  if GdkWin = nil then Exit;

  if PixieGtkIMContext = nil then
  begin
    PixieGtkIMContext := PGtkIMContext(gtk_im_multicontext_new());
    {$IFDEF LCLGTK2}
    g_signal_connect(PixieGtkIMContext, 'commit',
      TGCallback(@PixieGtkIMCommitCb), nil);
    {$ELSE}
    g_signal_connect_data(PixieGtkIMContext, 'commit',
      TGCallback(@PixieGtkIMCommitCb), nil, nil, G_CONNECT_DEFAULT);
    {$ENDIF}
  end;

  gtk_im_context_set_client_window(PixieGtkIMContext, GdkWin);
  gtk_im_context_focus_in(PixieGtkIMContext);
  PixieGtkIMEOwner := Self;
  {$ENDIF}

  UpdateIMEPosition;
end;

procedure TPixieHtmlView.DoExit;
begin
  {$IFNDEF WITH_GTK2_IM}
  if PixieGtkIMContext <> nil then
  begin
    gtk_im_context_focus_out(PixieGtkIMContext);
    gtk_im_context_reset(PixieGtkIMContext);
  end;
  PixieGtkIMEOwner := nil;
  {$ENDIF}
  inherited;
end;
{$ENDIF}

// ---------------------------------------------------------------------------
// Painting and layout
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.Loaded;
begin
  inherited Loaded;
  FCore.HandleLoaded;
end;

procedure TPixieHtmlView.Paint;
begin
  if (FCore = nil) or (FCore.Canvas = nil) then
  begin
    inherited Canvas.Brush.Color := Self.Color;
    inherited Canvas.FillRect(ClientRect);
    Exit;
  end;
  FCore.Canvas.SetViewSize(ClientWidth, ClientHeight, GetCanvasScaleFactor);
  FCore.HandlePaint(PtrUInt(inherited Canvas.Handle));
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

procedure TPixieHtmlView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if FCore.HandleKeyDown(Key, Shift, ssCtrlOS in Shift) then
    Key := 0;
end;

procedure TPixieHtmlView.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  inherited UTF8KeyPress(UTF8Key);
  if FCore.HandleCharInput(UTF8Key) then
    UTF8Key := '';
end;

// ---------------------------------------------------------------------------
// Mouse
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  FCore.HandleMouseDown(Button = mbLeft, ssDouble in Shift, X, Y);
end;

procedure TPixieHtmlView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  FCore.HandleMouseMove(X, Y);
end;

procedure TPixieHtmlView.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FCore.HandleMouseUp(Button = mbLeft, X, Y);
end;

function TPixieHtmlView.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  Result := FCore.HandleMouseWheel(WheelDelta, ssCtrl in Shift,
    Round(MousePos.X / FCore.Zoom), Round(MousePos.Y / FCore.Zoom));
end;

end.
