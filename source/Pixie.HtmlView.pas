unit Pixie.HtmlView;

// TPixieHtmlView — Lazarus visual component that renders HTML content
// using the Pixie engine with platform-native graphics.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Controls, Graphics, Forms, ExtCtrls,
  LMessages, LCLType,
  Pixie.Types, Pixie.WebColor, Pixie.Borders, Pixie.Document,
  Pixie.MasterCss, Pixie.Canvas, Pixie.NativeContainer,
  Pixie.RenderBlockContext, Pixie.RenderInlineContext
  {$IF defined(LCLqt5) or defined(LCLqt6)}
    , Pixie.Canvas.Qt
  {$ELSEIF defined(MSWINDOWS)}
    , JwaWinUser, Pixie.Canvas.D2D
  {$ELSEIF defined(DARWIN)}
    , Pixie.Canvas.CG
  {$ELSEIF defined(UNIX)}
    , Pixie.Canvas.Cairo
  {$ENDIF};


type
  TPixieAnchorClickEvent = procedure(Sender: TObject;
    const Url: string) of object;
  TPixieElementClickEvent = function(Sender: TObject;
    El: TObject): Boolean of object;

  { TPixieHtmlView }

  TPixieHtmlView = class(TCustomControl)
  private
    FDocument: TPixieDocument;
    FContainer: TPixieNativeContainer;
    FCanvas: TPixieCanvas;
    FHtmlLines: TStrings;
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
    FDragging: Boolean;
    FScrollDragging: Boolean;
    FScrollDragOffset: TPixiePixel;
    FCaretTimer: TTimer;
    FOnBeforeParse: TNotifyEvent;
    FOnAfterParse: TNotifyEvent;
    FOnBeforePaint: TNotifyEvent;
    FOnAfterPaint: TNotifyEvent;

    procedure SetHtmlLines(const Value: TStrings);
    procedure SetBaseUrl(const Value: string);
    procedure SetUserCss(const Value: string);
    procedure SetZoom(const Value: Double);
    procedure RebuildDocument;
    procedure DoAnchorClick(Sender: TObject; const Url: string);
    function DoElementClick(Sender: TObject; El: TObject): Boolean;
    procedure DoFetchUrl(Sender: TObject; const Url: string;
      Stream: TStream; var Success: Boolean);
    procedure DoDocumentChange(Sender: TObject);
    procedure DoCaretTimer(Sender: TObject);
    procedure WMEraseBkgnd(var Msg: TLMEraseBkgnd); message LM_ERASEBKGND;
    procedure CMMouseLeave(var Msg: TLMessage); message CM_MOUSELEAVE;
    {$IFDEF MSWINDOWS}
    procedure WMIMEStartComposition(var Msg: TLMessage); message WM_IME_STARTCOMPOSITION;
    {$ENDIF}
    {$IF defined(LCLqt5) or defined(LCLqt6)}
    procedure LMIMQuery(var Msg: TLMessage); message LM_IM_QUERY;
    {$ENDIF}
    procedure UpdateIMEPosition;
    procedure UpdateCursorFromCss;
  protected
    procedure Loaded; override;
    procedure Paint; override;
    procedure Resize; override;
    {$IF defined(LCLGTK2) or defined(LCLGTK3)}
    procedure DoEnter; override;
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

    procedure LoadHtml(const AHtml: string;
      const ABaseUrl: string = '');
    procedure RegisterImage(const Name: string; Stream: TStream);
    procedure UnregisterImage(const Name: string);

    property Document: TPixieDocument read FDocument;
    property ContentHeight: TPixiePixel read FContentHeight;
    property ScrollY: TPixiePixel read FScrollY write FScrollY;
  published
    property BorderSpacing;
    property TabOrder;
    property TabStop;
    property Html: TStrings read FHtmlLines write SetHtmlLines;
    property BaseUrl: string read FBaseUrl write SetBaseUrl;
    property UserCss: string read FUserCss write SetUserCss;
    property Zoom: Double read FZoom write SetZoom;
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
  Clipbrd, Pixie.Element
  {$IFDEF MSWINDOWS}
  , Windows, imm
  {$ENDIF}
  {$IFDEF LCLGTK2}
  , Glib2, Gdk2, Gtk2
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
begin
  FCanvas := nil;
  FContainer := nil;
  FDocument := nil;
  FRedrawBoxes := nil;
  FHtmlLines := TStringList.Create;
  FNeedsLayout := True;
  FScrollY := 0;
  FContentHeight := 0;
  FZoom := 1.0;
  FDragging := False;
  FScrollDragging := False;

  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Color := clWhite;
  Width := 400;
  Height := 300;
  TabStop := True;

  {$IF defined(LCLqt5) or defined(LCLqt6)}
  FCanvas := TPixieQtCanvas.Create;
  {$ELSEIF defined(MSWINDOWS)}
  FCanvas := TPixieD2DCanvas.Create;
  {$ELSEIF defined(DARWIN)}
  FCanvas := TPixieCGCanvas.Create;
  {$ELSEIF defined(UNIX)}
  FCanvas := TPixieCairoCanvas.Create;
  {$ENDIF}

  FContainer := TPixieNativeContainer.Create(FCanvas);
  FContainer.OnAnchorClickEvent := DoAnchorClick;
  FContainer.OnElementClickEvent := DoElementClick;
  FContainer.OnFetchUrlEvent := DoFetchUrl;
  FRedrawBoxes := TPixiePositionVector.Create;

  FCaretTimer := TTimer.Create(Self);
  FCaretTimer.Interval := 530;
  FCaretTimer.OnTimer := DoCaretTimer;
  FCaretTimer.Enabled := True;
end;

destructor TPixieHtmlView.Destroy;
begin
  // FreeAndNil is critical: inherited Destroy may fire widget toolkit events
  // (CM_MOUSELEAVE, Paint, Resize) whose handlers check these fields.
  FreeAndNil(FCaretTimer);
  FreeAndNil(FDocument);
  FreeAndNil(FContainer);
  FreeAndNil(FCanvas);
  FreeAndNil(FRedrawBoxes);
  FreeAndNil(FHtmlLines);
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Properties
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.SetHtmlLines(const Value: TStrings);
begin
  FHtmlLines.Assign(Value);
  RebuildDocument;
end;

procedure TPixieHtmlView.SetBaseUrl(const Value: string);
begin
  if FBaseUrl = Value then Exit;
  FBaseUrl := Value;
  FContainer.BaseUrl := Value;
  RebuildDocument;
end;

procedure TPixieHtmlView.SetUserCss(const Value: string);
begin
  if FUserCss = Value then Exit;
  FUserCss := Value;
  RebuildDocument;
end;

procedure TPixieHtmlView.SetZoom(const Value: Double);
var
  NewZoom: Double;
begin
  NewZoom := Value;
  if NewZoom < 0.25 then NewZoom := 0.25;
  if NewZoom > 4.0 then NewZoom := 4.0;
  if FZoom = NewZoom then Exit;
  FZoom := NewZoom;
  FCanvas.SetScale(FZoom);
  FNeedsLayout := True;
  Invalidate;
end;

// ---------------------------------------------------------------------------
// Document management
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.RebuildDocument;
begin
  FreeAndNil(FDocument);
  FScrollY := 0;
  FContentHeight := 0;
  FNeedsLayout := True;
  FDragging := False;
  FScrollDragging := False;

  if (FHtmlLines.Count > 0) and (FCanvas <> nil) then
  begin
    if PixieIsBinaryString(FHtmlLines.Text) then
      raise EPixieBinaryContent.Create(SPixieBinaryContent);
    if Assigned(FOnBeforeParse) then
      FOnBeforeParse(Self);
    FContainer.BaseUrl := FBaseUrl;
    FContainer.ViewportWidth := ClientWidth;
    FContainer.ViewportHeight := ClientHeight;
    FDocument := TPixieDocument.CreateFromString(FHtmlLines.Text, FContainer,
      PixieMasterCss, FUserCss);
    FDocument.OnChange := DoDocumentChange;
    if Assigned(FOnAfterParse) then
      FOnAfterParse(Self);
  end;

  Invalidate;
end;

procedure TPixieHtmlView.LoadHtml(const AHtml: string;
  const ABaseUrl: string);
begin
  FBaseUrl := ABaseUrl;
  FContainer.BaseUrl := ABaseUrl;
  FHtmlLines.Text := AHtml;
  RebuildDocument;
end;

procedure TPixieHtmlView.DoAnchorClick(Sender: TObject;
  const Url: string);
begin
  if Assigned(FOnAnchorClick) then
    FOnAnchorClick(Self, Url);
end;

function TPixieHtmlView.DoElementClick(Sender: TObject;
  El: TObject): Boolean;
begin
  if Assigned(FOnElementClick) then
    Result := FOnElementClick(Self, El)
  else
    Result := False;
end;

procedure TPixieHtmlView.DoFetchUrl(Sender: TObject; const Url: string;
  Stream: TStream; var Success: Boolean);
begin
  if Assigned(FOnFetchUrl) then
    FOnFetchUrl(Self, Url, Stream, Success);
end;

procedure TPixieHtmlView.DoDocumentChange(Sender: TObject);
begin
  FNeedsLayout := True;
  Invalidate;
end;

// ---------------------------------------------------------------------------
// Image registration
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.RegisterImage(const Name: string; Stream: TStream);
begin
  FContainer.RegisterImage(Name, Stream);
end;

procedure TPixieHtmlView.UnregisterImage(const Name: string);
begin
  FContainer.UnregisterImage(Name);
end;

// ---------------------------------------------------------------------------
// Painting
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.WMEraseBkgnd(var Msg: TLMEraseBkgnd);
begin
  // Prevent background erase flicker
  Msg.Result := 1;
end;

procedure TPixieHtmlView.CMMouseLeave(var Msg: TLMessage);
begin
  inherited;
  if FDocument <> nil then
  begin
    FRedrawBoxes.Clear;
    if FDocument.OnMouseLeave(FRedrawBoxes) then
      Invalidate;
  end;
  Self.Cursor := crDefault;
end;

procedure TPixieHtmlView.UpdateCursorFromCss;
var
  S: string;
begin
  S := FContainer.Cursor;
  if (S = 'pointer') then
    Self.Cursor := crHandPoint
  else if (S = 'text') then
    Self.Cursor := crIBeam
  else if (S = 'crosshair') then
    Self.Cursor := crCross
  else if (S = 'move') then
    Self.Cursor := crSizeAll
  else
    Self.Cursor := crDefault;
end;

{$IF defined(LCLGTK2) or defined(LCLGTK3)}
var
  PixieGtkIMContext: PGtkIMContext = nil;
  PixieGtkIMEOwner: TPixieHtmlView = nil;
{$ENDIF}

// ---------------------------------------------------------------------------
// IME candidate window positioning
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.UpdateIMEPosition;
var
  DocX, DocY, H: TPixiePixel;
  ClientX, ClientY: Integer;
  {$IFDEF MSWINDOWS}
  Imc: HIMC;
  CompForm: COMPOSITIONFORM;
  {$ENDIF}
  {$IF defined(LCLGTK2) or defined(LCLGTK3)}
  Area: TGdkRectangle;
  {$ENDIF}
begin
  if FDocument = nil then Exit;
  if not FDocument.GetFocusedCaretPos(DocX, DocY, H) then Exit;

  ClientX := Round(DocX * FZoom);
  ClientY := Round((DocY - FScrollY) * FZoom);

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

  {$IF defined(LCLGTK2) or defined(LCLGTK3)}
  if PixieGtkIMContext <> nil then
  begin
    Area.x := ClientX;
    Area.y := ClientY;
    Area.width := 1;
    Area.height := Round(H * FZoom);
    gtk_im_context_set_cursor_location(PixieGtkIMContext, @Area);
  end;
  {$ENDIF}
end;

{$IFDEF MSWINDOWS}
procedure TPixieHtmlView.WMIMEStartComposition(var Msg: TLMessage);
begin
  inherited;
  UpdateIMEPosition;
end;
{$ENDIF}

{$IF defined(LCLqt5) or defined(LCLqt6)}
procedure TPixieHtmlView.LMIMQuery(var Msg: TLMessage);
var
  DocX, DocY, H: TPixiePixel;
  P: ^TPoint;
begin
  if (Msg.LParam <> 0) and (FDocument <> nil) and
     FDocument.GetFocusedCaretPos(DocX, DocY, H) then
  begin
    P := Pointer(Msg.LParam);
    P^.X := Round(DocX * FZoom);
    P^.Y := Round((DocY - FScrollY) * FZoom);
  end;
end;
{$ENDIF}

{$IF defined(LCLGTK2) or defined(LCLGTK3)}
procedure PixieGtkIMCommitCb(Context: PGtkIMContext; Str: PGChar;
  Data: Pointer); cdecl;
var
  S: string;
begin
  if PixieGtkIMEOwner <> nil then
  begin
    S := Str;
    if (PixieGtkIMEOwner.FDocument <> nil) and
       PixieGtkIMEOwner.FDocument.DispatchUTF8KeyPress(S) then
    begin
      PixieGtkIMEOwner.FContainer.CaretVisible := True;
      PixieGtkIMEOwner.FCaretTimer.Enabled := False;
      PixieGtkIMEOwner.FCaretTimer.Enabled := True;
      PixieGtkIMEOwner.Invalidate;
    end;
    PixieGtkIMEOwner.UpdateIMEPosition;
  end;
end;

procedure TPixieHtmlView.DoEnter;
var
  GdkWin: PGdkWindow;
begin
  inherited;

  {$IFDEF LCLGTK2}
  GdkWin := PGtkWidget(PtrUInt(Handle))^.window;
  {$ELSE}
  if TGtk3Widget(Handle) = nil then Exit;
  GdkWin := gtk_widget_get_window(TGtk3Widget(Handle).Widget);
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
end;
{$ENDIF}

procedure TPixieHtmlView.Loaded;
begin
  inherited Loaded;
  if FHtmlLines.Count > 0 then
    RebuildDocument;
end;

procedure TPixieHtmlView.Paint;
var
  ClipPos: TPixiePosition;
  BgColor: TPixieWebColor;
  Rgb: LongInt;
  LayoutWidth: Integer;
  ViewW, ViewH: Single;
  BarW, BarMargin, TrackH, ThumbH, ThumbX, ThumbY, MaxScroll: TPixiePixel;
  IndicatorColor: TPixieWebColor;
  IndicatorRadius: TPixieBorderRadiuses;
begin
  if FCanvas = nil then
  begin
    inherited Canvas.Brush.Color := Self.Color;
    inherited Canvas.FillRect(ClientRect);
    Exit;
  end;

  // Tell the canvas our actual pixel size (needed for D2D BindDC)
  FCanvas.SetViewSize(ClientWidth, ClientHeight, GetCanvasScaleFactor);

  if Assigned(FOnBeforePaint) then
    FOnBeforePaint(Self);

  FCanvas.BeginPaint(PtrUInt(inherited Canvas.Handle));
  try
    // Virtual (content) dimensions after zoom
    ViewW := ClientWidth / FZoom;
    ViewH := ClientHeight / FZoom;
    LayoutWidth := Round(ViewW);

    // Layout if needed (must happen inside BeginPaint so text measurement works)
    if FNeedsLayout and (FDocument <> nil) then
    begin
      FContainer.ViewportWidth := LayoutWidth;
      FContainer.ViewportHeight := Round(ViewH);
      FDocument.Render(LayoutWidth);
      FContentHeight := FDocument.Height;
      FNeedsLayout := False;
    end;

    // Clear background (in virtual coordinates — canvas applies scale)
    Rgb := ColorToRGB(Self.Color);
    BgColor := TPixieWebColor.Create(
      Byte(Rgb), Byte(Rgb shr 8), Byte(Rgb shr 16));
    FCanvas.FillRect(0, 0, ViewW, ViewH, BgColor);

    if FDocument <> nil then
    begin
      ClipPos := TPixiePosition.Create(0, 0, ViewW, ViewH);
      FDocument.Draw(0, 0, -FScrollY, @ClipPos);

      // Scroll position indicator
      if FContentHeight > ViewH then
      begin
        BarW := 4;
        BarMargin := 2;
        TrackH := ViewH - BarMargin * 2;
        ThumbH := TrackH * (ViewH / FContentHeight);
        if ThumbH < 16 then ThumbH := 16;
        MaxScroll := FContentHeight - ViewH;
        if MaxScroll > 0 then
          ThumbY := BarMargin + (FScrollY / MaxScroll) * (TrackH - ThumbH)
        else
          ThumbY := BarMargin;
        ThumbX := ViewW - BarW - BarMargin;

        IndicatorRadius.TopLeftX := BarW / 2;
        IndicatorRadius.TopLeftY := BarW / 2;
        IndicatorRadius.TopRightX := BarW / 2;
        IndicatorRadius.TopRightY := BarW / 2;
        IndicatorRadius.BottomRightX := BarW / 2;
        IndicatorRadius.BottomRightY := BarW / 2;
        IndicatorRadius.BottomLeftX := BarW / 2;
        IndicatorRadius.BottomLeftY := BarW / 2;
        IndicatorColor := TPixieWebColor.Create(128, 128, 128, 160);
        FCanvas.FillRoundedRect(ThumbX, ThumbY, BarW, ThumbH,
          IndicatorRadius, IndicatorColor);
      end;
    end;
  finally
    FCanvas.EndPaint;
  end;
  if Assigned(FOnAfterPaint) then
    FOnAfterPaint(Self);
end;

procedure TPixieHtmlView.Resize;
begin
  inherited Resize;
  FNeedsLayout := True;
  if FContainer <> nil then
  begin
    FContainer.ViewportWidth := ClientWidth;
    FContainer.ViewportHeight := ClientHeight;
  end;
  Invalidate;
end;

// ---------------------------------------------------------------------------
// Caret blink timer
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.DoCaretTimer(Sender: TObject);
begin
  if FContainer <> nil then
  begin
    FContainer.CaretVisible := not FContainer.CaretVisible;
    if (FDocument <> nil) and (FDocument.FocusedElement <> nil) then
      Invalidate;
  end;
end;

// ---------------------------------------------------------------------------
// Keyboard and mouse events
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.KeyDown(var Key: Word; Shift: TShiftState);
var
  NewScroll, MaxScroll, ViewH: TPixiePixel;
begin
  inherited KeyDown(Key, Shift);

  // Tab / Shift+Tab cycles focus between focusable elements
  if (Key = VK_TAB) and (FDocument <> nil) then
  begin
    if ssShift in Shift then
      FDocument.FocusPrev
    else
      FDocument.FocusNext;
    FContainer.CaretVisible := True;
    FCaretTimer.Enabled := False;
    FCaretTimer.Enabled := True;
    Invalidate;
    Key := 0;
    Exit;
  end;

  // Dispatch to focused element first
  if (FDocument <> nil) and FDocument.DispatchKeyDown(Key, Shift) then
  begin
    // Reset caret blink so it stays visible during typing
    FContainer.CaretVisible := True;
    FCaretTimer.Enabled := False;
    FCaretTimer.Enabled := True;
    UpdateIMEPosition;
    Invalidate;
    Key := 0;
    Exit;
  end;

  // Ctrl+C (Cmd+C on macOS) copies selected text
  if (ssCtrlOS in Shift) and (Key = Ord('C')) then
  begin
    if (FDocument <> nil) and FDocument.HasSelection then
    begin
      Clipboard.AsText := FDocument.GetSelectedText;
      Key := 0;
    end;
  end;
  // Ctrl+0 (Cmd+0 on macOS) resets zoom to 100%
  if (ssCtrlOS in Shift) and (Key = VK_0) then
  begin
    SetZoom(1.0);
    Key := 0;
  end;
  // Home / End scroll to top / bottom
  if Key in [VK_HOME, VK_END] then
  begin
    ViewH := ClientHeight / FZoom;
    MaxScroll := FContentHeight - ViewH;
    if MaxScroll < 0 then MaxScroll := 0;
    if Key = VK_HOME then
      NewScroll := 0
    else
      NewScroll := MaxScroll;
    if NewScroll <> FScrollY then
    begin
      FScrollY := NewScroll;
      Invalidate;
    end;
    Key := 0;
  end;
  // Arrow and page keys scroll the viewport
  if Key in [VK_UP, VK_DOWN, VK_PRIOR, VK_NEXT] then
  begin
    ViewH := ClientHeight / FZoom;
    MaxScroll := FContentHeight - ViewH;
    if MaxScroll < 0 then MaxScroll := 0;
    NewScroll := FScrollY;
    case Key of
      VK_UP:    NewScroll := FScrollY - 40;
      VK_DOWN:  NewScroll := FScrollY + 40;
      VK_PRIOR: NewScroll := FScrollY - ViewH;
      VK_NEXT:  NewScroll := FScrollY + ViewH;
    end;
    if NewScroll < 0 then NewScroll := 0;
    if NewScroll > MaxScroll then NewScroll := MaxScroll;
    if NewScroll <> FScrollY then
    begin
      FScrollY := NewScroll;
      Invalidate;
    end;
    Key := 0;
  end;
end;

procedure TPixieHtmlView.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  inherited UTF8KeyPress(UTF8Key);
  if (FDocument <> nil) and FDocument.DispatchUTF8KeyPress(UTF8Key) then
  begin
    FContainer.CaretVisible := True;
    FCaretTimer.Enabled := False;
    FCaretTimer.Enabled := True;
    UpdateIMEPosition;
    Invalidate;
    UTF8Key := '';
  end;
end;

procedure TPixieHtmlView.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Vx, Vy: Integer;
  InputFocused: Boolean;
  ViewH, TrackH, ThumbH, ThumbY, MaxScroll, NewScroll: TPixiePixel;
begin
  inherited MouseDown(Button, Shift, X, Y);
  SetFocus;
  if (Button = mbLeft) and (FDocument <> nil) then
  begin
    Vx := Round(X / FZoom);
    Vy := Round(Y / FZoom);

    // Scrollbar interaction
    ViewH := ClientHeight / FZoom;
    if (FContentHeight > ViewH) and (Vx >= Round(ClientWidth / FZoom) - 12) then
    begin
      TrackH := ViewH - 4;
      ThumbH := TrackH * (ViewH / FContentHeight);
      if ThumbH < 16 then ThumbH := 16;
      MaxScroll := FContentHeight - ViewH;
      if MaxScroll > 0 then
        ThumbY := 2 + (FScrollY / MaxScroll) * (TrackH - ThumbH)
      else
        ThumbY := 2;
      if (Vy >= ThumbY) and (Vy < ThumbY + ThumbH) then
      begin
        FScrollDragging := True;
        FScrollDragOffset := Vy - ThumbY;
      end
      else
      begin
        NewScroll := FScrollY;
        if Vy < ThumbY then
          NewScroll := FScrollY - ViewH
        else
          NewScroll := FScrollY + ViewH;
        if NewScroll < 0 then NewScroll := 0;
        if NewScroll > MaxScroll then NewScroll := MaxScroll;
        FScrollY := NewScroll;
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
      // Input has focus — let it handle selection internally
      if ssDouble in Shift then
        FDocument.DispatchDblClick;
      FDragging := True;
      FContainer.CaretVisible := True;
      FCaretTimer.Enabled := False;
      FCaretTimer.Enabled := True;
      UpdateIMEPosition;
      Invalidate;
    end
    else if (FDocument.ActiveElement <> nil) and
      FDocument.ActiveElement.IsReplaced then
    begin
      // Replaced element (button, checkbox) — no text selection
    end
    else
    begin
      // Normal document-level text selection
      if FDocument.HasSelection then
      begin
        FDocument.ClearSelection;
        Invalidate;
      end;
      if ssDouble in Shift then
      begin
        if FDocument.SelectWord(Vx, Vy + FScrollY) then
          Invalidate;
      end
      else
      begin
        FDocument.SelectionStart(Vx, Vy + FScrollY, Vx, Vy);
        FDragging := True;
      end;
    end;
  end;
end;

procedure TPixieHtmlView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Vx, Vy: Integer;
  ViewH, TrackH, ThumbH, MaxScroll, NewThumbY, NewScroll: TPixiePixel;
begin
  inherited MouseMove(Shift, X, Y);
  if FScrollDragging then
  begin
    Vy := Round(Y / FZoom);
    ViewH := ClientHeight / FZoom;
    TrackH := ViewH - 4;
    ThumbH := TrackH * (ViewH / FContentHeight);
    if ThumbH < 16 then ThumbH := 16;
    MaxScroll := FContentHeight - ViewH;
    NewThumbY := Vy - FScrollDragOffset;
    if NewThumbY < 2 then NewThumbY := 2;
    if NewThumbY > 2 + TrackH - ThumbH then
      NewThumbY := 2 + TrackH - ThumbH;
    if TrackH > ThumbH then
      NewScroll := (NewThumbY - 2) / (TrackH - ThumbH) * MaxScroll
    else
      NewScroll := 0;
    if NewScroll < 0 then NewScroll := 0;
    if NewScroll > MaxScroll then NewScroll := MaxScroll;
    if NewScroll <> FScrollY then
    begin
      FScrollY := NewScroll;
      Invalidate;
    end;
    Exit;
  end;
  if FDocument <> nil then
  begin
    Vx := Round(X / FZoom);
    Vy := Round(Y / FZoom);
    FRedrawBoxes.Clear;
    if FDocument.OnMouseOver(Vx, Vy + FScrollY, Vx, Vy,
      FRedrawBoxes) then
      Invalidate;
    UpdateCursorFromCss;
    if FDragging then
    begin
      if (FDocument.FocusedElement <> nil) and
         FDocument.FocusedElement.IsFocusable then
      begin
        // Dispatch drag to focused text input
        if FDocument.DispatchMouseDrag(Vx, Vy + FScrollY) then
          Invalidate;
      end
      else
      begin
        // Document-level text selection
        if FDocument.SelectionMove(Vx, Vy + FScrollY, Vx, Vy) then
          Invalidate;
      end;
    end;
  end;
end;

procedure TPixieHtmlView.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Vx, Vy: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button = mbLeft) and FScrollDragging then
  begin
    FScrollDragging := False;
    Exit;
  end;
  if (Button = mbLeft) and (FDocument <> nil) then
  begin
    Vx := Round(X / FZoom);
    Vy := Round(Y / FZoom);
    FDragging := False;
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

function TPixieHtmlView.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  Vx, Vy: Integer;
  NewScroll: TPixiePixel;
  MaxScroll: TPixiePixel;
  NewZoom: Double;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;

  // Ctrl+wheel zooms
  if ssCtrl in Shift then
  begin
    if WheelDelta > 0 then
      NewZoom := FZoom * 1.1
    else
      NewZoom := FZoom / 1.1;
    SetZoom(NewZoom);
    Result := True;
    Exit;
  end;

  // Dispatch to element under mouse (textarea scrolling)
  if FDocument <> nil then
  begin
    Vx := Round(MousePos.X / FZoom);
    Vy := Round(MousePos.Y / FZoom);
    if FDocument.DispatchMouseWheel(Vx, Vy + FScrollY, WheelDelta) then
    begin
      Invalidate;
      Result := True;
      Exit;
    end;
  end;

  MaxScroll := FContentHeight - ClientHeight / FZoom;
  if MaxScroll < 0 then MaxScroll := 0;

  NewScroll := FScrollY - (WheelDelta / 120) * 40;
  if NewScroll < 0 then NewScroll := 0;
  if NewScroll > MaxScroll then NewScroll := MaxScroll;

  if NewScroll <> FScrollY then
  begin
    FScrollY := NewScroll;
    Invalidate;
  end;
  Result := True;
end;

end.
