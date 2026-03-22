unit Pixie.HtmlView.FMX;

// TPixieHtmlView — Delphi FMX visual component that renders HTML content
// using the Pixie engine with FireMonkey graphics. Enables cross-platform
// HTML rendering on Windows, macOS, iOS, and Android.

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  System.UIConsts, System.Rtti, System.Math,
  FMX.Controls, FMX.Graphics, FMX.Types, FMX.Platform,
  FMX.Text, FMX.Forms,
  Pixie.Types, Pixie.WebColor, Pixie.Borders, Pixie.Document,
  Pixie.MasterCss, Pixie.Canvas, Pixie.NativeContainer,
  Pixie.RenderBlockContext, Pixie.RenderInlineContext,
  Pixie.Canvas.FMX;

type
  TPixieAnchorClickEvent = procedure(Sender: TObject;
    const Url: string) of object;
  TPixieElementClickEvent = function(Sender: TObject;
    El: TObject): Boolean of object;

  { TPixieHtmlView }

  TPixieHtmlView = class(TControl, ITextInput)
  private
    FDocument: TPixieDocument;
    FContainer: TPixieNativeContainer;
    FPixieCanvas: TPixieCanvas;
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
    FDragging: Boolean;
    FScrollDragging: Boolean;
    FScrollDragOffset: TPixiePixel;
    FCaretTimer: TTimer;
    FLastMouseX: Single;
    FLastMouseY: Single;
    FOnBeforeParse: TNotifyEvent;
    FOnAfterParse: TNotifyEvent;
    FOnBeforePaint: TNotifyEvent;
    FOnAfterPaint: TNotifyEvent;
    FTextService: TTextService;

    procedure SetLines(const Value: TStrings);
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
    procedure UpdateCursorFromCss;
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
  protected
    procedure Loaded; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure DialogKey(var Key: Word; Shift: TShiftState); override;
    procedure DoMouseLeave; override;
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
    procedure LoadFromFile(const AFileName: string; const ABaseUrl: string = '');
    procedure LoadFromStream(AStream: TStream;
      const ABaseUrl: string = '');
    procedure RegisterImage(const Name: string; Stream: TStream);
    procedure UnregisterImage(const Name: string);

    property Document: TPixieDocument read FDocument;
    property ContentHeight: TPixiePixel read FContentHeight;
    property ScrollY: TPixiePixel read FScrollY write FScrollY;
  published
    property Lines: TStrings read FLines write SetLines;
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

uses
  Pixie.Element, Pixie.Container;

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
  FPixieCanvas := nil;
  FContainer := nil;
  FDocument := nil;
  FRedrawBoxes := nil;
  FTextService := nil;
  FLines := TStringList.Create;
  FNeedsLayout := True;
  FScrollY := 0;
  FContentHeight := 0;
  FZoom := 1.0;
  FDragging := False;
  FScrollDragging := False;
  FLastMouseX := 0;
  FLastMouseY := 0;

  inherited Create(AOwner);
  ClipChildren := True;
  HitTest := True;
  AutoCapture := True;
  Width := 400;
  Height := 300;
  CanFocus := True;

  if not (csDesigning in ComponentState) then
    if TPlatformServices.Current.SupportsPlatformService(
      IFMXTextService, TextSvc) then
      FTextService := TextSvc.GetTextServiceClass.Create(Self, False);

  FPixieCanvas := TPixieFmxCanvas.Create;

  FContainer := TPixieNativeContainer.Create(FPixieCanvas);
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
  FreeAndNil(FCaretTimer);
  FreeAndNil(FTextService);
  FreeAndNil(FDocument);
  FreeAndNil(FContainer);
  FreeAndNil(FPixieCanvas);
  FreeAndNil(FRedrawBoxes);
  FreeAndNil(FLines);
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Properties
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.SetLines(const Value: TStrings);
begin
  FLines.Assign(Value);
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
  FPixieCanvas.SetScale(FZoom);
  FNeedsLayout := True;
  Repaint;
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
  if (FDocument <> nil) and FDocument.GetFocusedCaretPos(DocX, DocY, H) then
  begin
    Result.X := DocX * FZoom;
    Result.Y := (DocY - FScrollY + H) * FZoom + 2;
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
  if (FDocument <> nil) and FDocument.HasSelection then
    Result := FDocument.GetSelectedText
  else
    Result := '';
end;

function TPixieHtmlView.GetSelectionRect: TRectF;
var
  DocX, DocY, H: TPixiePixel;
begin
  if (FDocument <> nil) and FDocument.GetFocusedCaretPos(DocX, DocY, H) then
  begin
    Result.Left := DocX * FZoom;
    Result.Top := (DocY - FScrollY) * FZoom;
    Result.Right := Result.Left + 2;
    Result.Bottom := Result.Top + H * FZoom;
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
  Result := FDocument <> nil;
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
// Component lifecycle
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.Loaded;
begin
  inherited Loaded;
  if FLines.Count > 0 then
    RebuildDocument;
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

  if (FLines.Count > 0) and (FPixieCanvas <> nil) then
  begin
    if PixieIsBinaryString(FLines.Text) then
      raise EPixieBinaryContent.Create(SPixieBinaryContent);
    if Assigned(FOnBeforeParse) then
      FOnBeforeParse(Self);
    FContainer.BaseUrl := FBaseUrl;
    FContainer.ViewportWidth := Width;
    FContainer.ViewportHeight := Height;
    FDocument := TPixieDocument.CreateFromString(FLines.Text, FContainer,
      PixieMasterCss, FUserCss);
    FDocument.OnChange := DoDocumentChange;
    if Assigned(FOnAfterParse) then
      FOnAfterParse(Self);
  end;

  Repaint;
end;

procedure TPixieHtmlView.LoadFromString(const AHtml: string;
  const ABaseUrl: string);
begin
  FBaseUrl := ABaseUrl;
  FContainer.BaseUrl := ABaseUrl;
  FLines.Text := AHtml;
  RebuildDocument;
end;

procedure TPixieHtmlView.LoadFromFile(const AFileName: string;
  const ABaseUrl: string);
var
  Sl: TStringList;
begin
  Sl := TStringList.Create;
  try
    Sl.LoadFromFile(AFileName);
    if ABaseUrl <> '' then
      LoadFromString(Sl.Text, ABaseUrl)
    else
      LoadFromString(Sl.Text, ExtractFilePath(AFileName));
  finally
    Sl.Free;
  end;
end;

procedure TPixieHtmlView.LoadFromStream(AStream: TStream;
  const ABaseUrl: string);
var
  Sl: TStringList;
begin
  Sl := TStringList.Create;
  try
    Sl.LoadFromStream(AStream);
    LoadFromString(Sl.Text, ABaseUrl);
  finally
    Sl.Free;
  end;
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
  Repaint;
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

procedure TPixieHtmlView.Paint;
var
  ClipPos: TPixiePosition;
  BgColor: TPixieWebColor;
  LayoutWidth: Integer;
  ViewW, ViewH: Single;
  BarW, BarMargin, TrackH, ThumbH, ThumbX, ThumbY, MaxScroll: TPixiePixel;
  IndicatorColor: TPixieWebColor;
  IndicatorRadius: TPixieBorderRadiuses;
begin
  if FPixieCanvas = nil then Exit;

  if Assigned(FOnBeforePaint) then
    FOnBeforePaint(Self);

  // FMX canvas is already active during Paint
  FPixieCanvas.BeginPaint(PtrUInt(Pointer(Canvas)));
  try
    // Virtual (content) dimensions after zoom
    ViewW := Width / FZoom;
    ViewH := Height / FZoom;
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

    // Clear background
    BgColor := TPixieWebColor.Create(255, 255, 255);
    FPixieCanvas.FillRect(0, 0, ViewW, ViewH, BgColor);

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
        FPixieCanvas.FillRoundedRect(ThumbX, ThumbY, BarW, ThumbH,
          IndicatorRadius, IndicatorColor);
      end;
    end;
  finally
    FPixieCanvas.EndPaint;
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
    FContainer.ViewportWidth := Width;
    FContainer.ViewportHeight := Height;
  end;
  Repaint;
end;

// ---------------------------------------------------------------------------
// Cursor
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.UpdateCursorFromCss;
var
  S: string;
begin
  S := FContainer.Cursor;
  if S = 'pointer' then
    Self.Cursor := crHandPoint
  else if S = 'text' then
    Self.Cursor := crIBeam
  else if S = 'crosshair' then
    Self.Cursor := crCross
  else if S = 'move' then
    Self.Cursor := crSizeAll
  else
    Self.Cursor := crDefault;
end;

procedure TPixieHtmlView.DoMouseLeave;
begin
  inherited;
  if FDocument <> nil then
  begin
    FRedrawBoxes.Clear;
    if FDocument.OnMouseLeave(FRedrawBoxes) then
      Repaint;
  end;
  Self.Cursor := crDefault;
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
      Repaint;
  end;
end;

// ---------------------------------------------------------------------------
// Keyboard
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.DialogKey(var Key: Word; Shift: TShiftState);
begin
  if (Key = vkTab) and (FDocument <> nil) then
  begin
    if ssShift in Shift then
      FDocument.FocusPrev
    else
      FDocument.FocusNext;
    FContainer.CaretVisible := True;
    FCaretTimer.Enabled := False;
    FCaretTimer.Enabled := True;
    Repaint;
    Key := 0;
    Exit;
  end;
  inherited;
end;

procedure TPixieHtmlView.KeyDown(var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
var
  NewScroll, MaxScroll, ViewH: TPixiePixel;
  S: string;
  CtrlDown: Boolean;
begin
  inherited KeyDown(Key, KeyChar, Shift);

  {$IFDEF MACOS}
  CtrlDown := ssCommand in Shift;
  {$ELSE}
  CtrlDown := ssCtrl in Shift;
  {$ENDIF}

  // Dispatch to focused element first
  if (Key <> 0) and (FDocument <> nil) and
    FDocument.DispatchKeyDown(Key, Shift) then
  begin
    FContainer.CaretVisible := True;
    FCaretTimer.Enabled := False;
    FCaretTimer.Enabled := True;
    Repaint;
    Key := 0;
    KeyChar := #0;
    Exit;
  end;

  // Printable character input for focused text elements
  if (KeyChar >= ' ') and (FDocument <> nil) then
  begin
    S := KeyChar;
    if FDocument.DispatchUTF8KeyPress(S) then
    begin
      FContainer.CaretVisible := True;
      FCaretTimer.Enabled := False;
      FCaretTimer.Enabled := True;
      Repaint;
      Key := 0;
      KeyChar := #0;
      Exit;
    end;
  end;

  // Ctrl+C / Cmd+C copies selected text
  if CtrlDown and (Key = vkC) then
  begin
    if (FDocument <> nil) and FDocument.HasSelection then
    begin
      ClipboardCopy(FDocument.GetSelectedText);
      Key := 0;
      KeyChar := #0;
    end;
  end;

  // Ctrl+0 / Cmd+0 resets zoom
  if CtrlDown and (Key = vk0) then
  begin
    SetZoom(1.0);
    Key := 0;
    KeyChar := #0;
  end;

  // Home / End scroll to top / bottom
  if Key in [vkHome, vkEnd] then
  begin
    ViewH := Height / FZoom;
    MaxScroll := FContentHeight - ViewH;
    if MaxScroll < 0 then MaxScroll := 0;
    if Key = vkHome then
      NewScroll := 0
    else
      NewScroll := MaxScroll;
    if NewScroll <> FScrollY then
    begin
      FScrollY := NewScroll;
      Repaint;
    end;
    Key := 0;
    KeyChar := #0;
  end;

  // Arrow and page keys scroll the viewport
  if Key in [vkUp, vkDown, vkPrior, vkNext] then
  begin
    ViewH := Height / FZoom;
    MaxScroll := FContentHeight - ViewH;
    if MaxScroll < 0 then MaxScroll := 0;
    NewScroll := FScrollY;
    case Key of
      vkUp:    NewScroll := FScrollY - 40;
      vkDown:  NewScroll := FScrollY + 40;
      vkPrior: NewScroll := FScrollY - ViewH;
      vkNext:  NewScroll := FScrollY + ViewH;
    end;
    if NewScroll < 0 then NewScroll := 0;
    if NewScroll > MaxScroll then NewScroll := MaxScroll;
    if NewScroll <> FScrollY then
    begin
      FScrollY := NewScroll;
      Repaint;
    end;
    Key := 0;
    KeyChar := #0;
  end;
end;

// ---------------------------------------------------------------------------
// Mouse events
// ---------------------------------------------------------------------------

procedure TPixieHtmlView.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  Vx, Vy: Integer;
  InputFocused: Boolean;
  ViewH, TrackH, ThumbH, ThumbY, MaxScroll, NewScroll: TPixiePixel;
begin
  inherited MouseDown(Button, Shift, X, Y);
  SetFocus;
  if (Button = TMouseButton.mbLeft) and (FDocument <> nil) then
  begin
    Vx := Round(X / FZoom);
    Vy := Round(Y / FZoom);
    FLastMouseX := Vx;
    FLastMouseY := Vy;

    // Scrollbar interaction
    ViewH := Height / FZoom;
    if (FContentHeight > ViewH) and (Vx >= Round(Width / FZoom) - 12) then
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
        if Vy < ThumbY then
          NewScroll := FScrollY - ViewH
        else
          NewScroll := FScrollY + ViewH;
        if NewScroll < 0 then NewScroll := 0;
        if NewScroll > MaxScroll then NewScroll := MaxScroll;
        FScrollY := NewScroll;
      end;
      Repaint;
      Exit;
    end;

    FRedrawBoxes.Clear;
    if FDocument.OnLButtonDown(Vx, Vy + FScrollY, Vx, Vy,
      FRedrawBoxes) then
      Repaint;

    InputFocused := (FDocument.FocusedElement <> nil) and
      FDocument.FocusedElement.IsFocusable;

    if InputFocused then
    begin
      if ssDouble in Shift then
        FDocument.DispatchDblClick;
      FDragging := True;
      FContainer.CaretVisible := True;
      FCaretTimer.Enabled := False;
      FCaretTimer.Enabled := True;
      Repaint;
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
        Repaint;
      end;
      if ssDouble in Shift then
      begin
        if FDocument.SelectWord(Vx, Vy + FScrollY) then
          Repaint;
      end
      else
      begin
        FDocument.SelectionStart(Vx, Vy + FScrollY, Vx, Vy);
        FDragging := True;
      end;
    end;
  end;
end;

procedure TPixieHtmlView.MouseMove(Shift: TShiftState; X, Y: Single);
var
  Vx, Vy: Integer;
  ViewH, TrackH, ThumbH, MaxScroll, NewThumbY, NewScroll: TPixiePixel;
begin
  inherited MouseMove(Shift, X, Y);
  if FScrollDragging then
  begin
    Vy := Round(Y / FZoom);
    ViewH := Height / FZoom;
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
      Repaint;
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
      Repaint;
    UpdateCursorFromCss;
    if FDragging then
    begin
      if (FDocument.FocusedElement <> nil) and
         FDocument.FocusedElement.IsFocusable then
      begin
        if FDocument.DispatchMouseDrag(Vx, Vy + FScrollY) then
          Repaint;
      end
      else
      begin
        if FDocument.SelectionMove(Vx, Vy + FScrollY, Vx, Vy) then
          Repaint;
      end;
    end;
  end;
end;

procedure TPixieHtmlView.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  Vx, Vy: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button = TMouseButton.mbLeft) and FScrollDragging then
  begin
    FScrollDragging := False;
    Exit;
  end;
  if (Button = TMouseButton.mbLeft) and (FDocument <> nil) then
  begin
    Vx := Round(X / FZoom);
    Vy := Round(Y / FZoom);
    FDragging := False;
    FDocument.SelectionEnd;
    if FDocument.HasSelection then
      Repaint
    else
    begin
      FRedrawBoxes.Clear;
      if FDocument.OnLButtonUp(Vx, Vy + FScrollY, Vx, Vy,
        FRedrawBoxes) then
        Repaint;
    end;
  end;
end;

procedure TPixieHtmlView.MouseWheel(Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
var
  NewScroll: TPixiePixel;
  MaxScroll: TPixiePixel;
  NewZoom: Double;
  CtrlDown: Boolean;
begin
  inherited MouseWheel(Shift, WheelDelta, Handled);
  if Handled then Exit;

  {$IFDEF MACOS}
  CtrlDown := ssCommand in Shift;
  {$ELSE}
  CtrlDown := ssCtrl in Shift;
  {$ENDIF}

  // Ctrl+wheel zooms
  if CtrlDown then
  begin
    if WheelDelta > 0 then
      NewZoom := FZoom * 1.1
    else
      NewZoom := FZoom / 1.1;
    SetZoom(NewZoom);
    Handled := True;
    Exit;
  end;

  // Dispatch to element under mouse (textarea scrolling)
  if FDocument <> nil then
  begin
    if FDocument.DispatchMouseWheel(Round(FLastMouseX),
      Round(FLastMouseY + FScrollY), WheelDelta) then
    begin
      Repaint;
      Handled := True;
      Exit;
    end;
  end;

  MaxScroll := FContentHeight - Height / FZoom;
  if MaxScroll < 0 then MaxScroll := 0;

  NewScroll := FScrollY - (WheelDelta / 120) * 40;
  if NewScroll < 0 then NewScroll := 0;
  if NewScroll > MaxScroll then NewScroll := MaxScroll;

  if NewScroll <> FScrollY then
  begin
    FScrollY := NewScroll;
    Repaint;
  end;
  Handled := True;
end;

end.
