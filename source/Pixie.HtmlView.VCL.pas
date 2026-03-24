unit Pixie.HtmlView.VCL;

// TPixieHtmlView — Delphi VCL visual component that renders HTML content
// using the Pixie engine with Direct2D/DirectWrite graphics.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Windows, Messages,
  Vcl.Controls, Vcl.Graphics, Vcl.Forms, Vcl.ExtCtrls,
  Pixie.Types, Pixie.WebColor, Pixie.Document,
  Pixie.Canvas, Pixie.NativeContainer,
  Pixie.Canvas.D2D,
  Pixie.HtmlView.Base;

type
  { TPixieHtmlView }

  TPixieHtmlView = class(TCustomControl)
  private
    FCore: TPixieHtmlViewCore;
    FCaretTimer: TTimer;
    FBorderStyle: TBorderStyle;

    procedure DoCaretTimer(Sender: TObject);
    procedure SetBorderStyle(Value: TBorderStyle);
    procedure WMEraseBkgnd(var Msg: TWMEraseBkgnd); message WM_ERASEBKGND;
    procedure WMGetDlgCode(var Msg: TWMGetDlgCode); message WM_GETDLGCODE;
    procedure CMMouseLeave(var Msg: TMessage); message CM_MOUSELEAVE;
    procedure WMIMEStartComposition(var Msg: TMessage); message WM_IME_STARTCOMPOSITION;
    procedure UpdateIMEPosition;
    function GetScaleFactor: Single;

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
    function GetAutoScrollSpeed: Integer;
    procedure SetAutoScrollSpeed(Value: Integer);
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
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Loaded; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: Char); override;
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
  published
    property BorderStyle: TBorderStyle read FBorderStyle
      write SetBorderStyle default bsSingle;
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
    property OnScrollChanged: TNotifyEvent
      read GetOnScrollChanged write SetOnScrollChanged;

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
  Vcl.Clipbrd, Winapi.Imm;

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieHtmlView.Create(AOwner: TComponent);
begin
  FCore := nil;
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FBorderStyle := bsSingle;
  Color := clWhite;
  Width := 400;
  Height := 300;
  TabStop := True;

  FCore := TPixieHtmlViewCore.Create(TPixieD2DCanvas.Create);
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
// Border style
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.SetBorderStyle(Value: TBorderStyle);
begin
  if FBorderStyle <> Value then
  begin
    FBorderStyle := Value;
    RecreateWnd;
  end;
end;

procedure TPixieHtmlView.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  if FBorderStyle = bsSingle then
    Params.ExStyle := Params.ExStyle or WS_EX_CLIENTEDGE;
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
  if CanFocus then
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
begin
  Result := GetScaleFactor;
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

function TPixieHtmlView.GetAutoScrollSpeed: Integer;
begin
  Result := FCore.AutoScrollSpeed;
end;

procedure TPixieHtmlView.SetAutoScrollSpeed(Value: Integer);
begin
  FCore.AutoScrollSpeed := Value;
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
// DPI / Scale
// ---------------------------------------------------------------------------

function TPixieHtmlView.GetScaleFactor: Single;
var
  F: TCustomForm;
begin
  F := GetParentForm(Self);
  if F <> nil then
    Result := F.PixelsPerInch / 96
  else
    Result := 1.0;
end;

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.WMEraseBkgnd(var Msg: TWMEraseBkgnd);
begin
  Msg.Result := 1;
end;

procedure TPixieHtmlView.WMGetDlgCode(var Msg: TWMGetDlgCode);
begin
  inherited;
  Msg.Result := Msg.Result or DLGC_WANTARROWS or DLGC_WANTTAB;
end;

procedure TPixieHtmlView.CMMouseLeave(var Msg: TMessage);
begin
  inherited;
  if FCore <> nil then
    FCore.HandleMouseLeave;
end;

// ---------------------------------------------------------------------------
// IME
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.UpdateIMEPosition;
var
  DocX, DocY, H: TPixiePixel;
  Imc: HIMC;
  CompForm: TCompositionForm;
begin
  if FCore.Document = nil then Exit;
  if not FCore.Document.GetFocusedCaretPos(DocX, DocY, H) then Exit;

  Imc := ImmGetContext(Handle);
  if Imc <> 0 then
  begin
    CompForm.dwStyle := CFS_POINT;
    CompForm.ptCurrentPos.X := Round(DocX * FCore.Zoom);
    CompForm.ptCurrentPos.Y := Round((DocY - FCore.ScrollY) * FCore.Zoom);
    ImmSetCompositionWindow(Imc, @CompForm);
    ImmReleaseContext(Handle, Imc);
  end;
end;

procedure TPixieHtmlView.WMIMEStartComposition(var Msg: TMessage);
begin
  inherited;
  UpdateIMEPosition;
end;

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
  FCore.Canvas.SetViewSize(ClientWidth, ClientHeight, GetScaleFactor);
  FCore.HandlePaint(NativeUInt(inherited Canvas.Handle));
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
  if FCore.HandleKeyDown(Key, Shift, ssCtrl in Shift) then
    Key := 0;
end;

procedure TPixieHtmlView.KeyPress(var Key: Char);
var
  S: string;
begin
  inherited KeyPress(Key);
  if Ord(Key) >= 32 then
  begin
    S := Key;
    if FCore.HandleCharInput(S) then
      Key := #0;
  end;
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
