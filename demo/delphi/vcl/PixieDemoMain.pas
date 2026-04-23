unit PixieDemoMain;

interface

uses
  Classes, SysUtils, Windows,
  System.Net.HttpClient, System.Math,
  Pixie.HtmlView.VCL, Pixie.NativeContainer, Pixie.Url,
  Pixie.Element, Pixie.Document, Pixie.PdfExport,
  Pixie.SvgView.VCL, Pixie.PaintBox.VCL, Pixie.DrawingCanvas,
  Pixie.TagBar.VCL, Pixie.TagBar.Base, Pixie.TagBar.Render, Pixie.WebColor,
  PixieDemoContent, PixieDemoPaintBox,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.Dialogs, Vcl.ComCtrls,
  Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TMainForm = class(TForm)
    StatusBar: TStatusBar;
    procedure FormCreate(Sender: TObject);
  private
    PageControl: TPageControl;
    TabHtmlView: TTabSheet;
    TabSvgView: TTabSheet;
    UrlPanel: TPanel;
    BtnOpen: TButton;
    BtnSavePdf: TButton;
    BtnGo: TButton;
    UrlEdit: TEdit;
    SvgToolbar: TPanel;
    BtnLoadSvg: TButton;
    CbAlignment: TComboBox;
    PixieHtmlView: TPixieHtmlView;
    PixieSvgView: TPixieSvgView;
    TabPaintBox: TTabSheet;
    PaintBoxToolbar: TPanel;
    LblZoom: TLabel;
    ZoomSlider: TTrackBar;
    LblZoomPct: TLabel;
    PixiePaintBox: TPixiePaintBox;
    TabTagBar: TTabSheet;
    TagBarToolbar: TPanel;
    CbTagShape: TComboBox;
    LblTagShape: TLabel;
    ChkTagAutoHeight: TCheckBox;
    TagBarEditor: TPixieTagBar;
    TagBarFilter: TPixieTagBar;
    TagBarAssign: TPixieTagBar;
    TagBarDisplay: TPixieTagBar;
    FPaintBoxScale: Single;
    FCardCount: Integer;
    FParseStart: Int64;
    FPaintStart: Int64;
    FFetchAccum: Int64;
    FNavWarningShown: Boolean;
    procedure BtnOpenClick(Sender: TObject);
    procedure BtnSavePdfClick(Sender: TObject);
    procedure BtnGoClick(Sender: TObject);
    procedure UrlEditKeyPress(Sender: TObject; var Key: Char);
    procedure BtnLoadSvgClick(Sender: TObject);
    procedure CbAlignmentChange(Sender: TObject);
    procedure ViewAnchorClick(Sender: TObject; const Url: string);
    function ViewElementClick(Sender: TObject; El: TObject): Boolean;
    procedure FetchUrl(Sender: TObject; const AUrl: string;
      Stream: TStream; var Success: Boolean);
    procedure ViewBeforeParse(Sender: TObject);
    procedure ViewAfterParse(Sender: TObject);
    procedure ViewBeforePaint(Sender: TObject);
    procedure ViewAfterPaint(Sender: TObject);
    procedure PaintBoxPaint(Sender: TObject; ACanvas: TPixieDrawingCanvas);
    procedure ZoomSliderChange(Sender: TObject);
    procedure NavigateToUrl(const Url: string);
    procedure CreateTagBarTab;
    procedure PopulateTagBarTags(Bar: TPixieTagBar);
    procedure TagBarShapeChange(Sender: TObject);
    procedure TagBarAutoHeightChange(Sender: TObject);
    function Scale(Value: Integer): Integer;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

function StopwatchNow: Int64;
begin
  QueryPerformanceCounter(Result);
end;

function StopwatchElapsedMs(Start: Int64): Double;
var
  Now, Freq: Int64;
begin
  QueryPerformanceCounter(Now);
  QueryPerformanceFrequency(Freq);
  Result := (Now - Start) * 1000.0 / Freq;
end;

function TMainForm.Scale(Value: Integer): Integer;
begin
  Result := MulDiv(Value, Self.PixelsPerInch, 96);
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  ImgPath, SvgPath: string;
  Stream: TFileStream;
begin
  ImgPath := ExtractFilePath(ParamStr(0)) + '..\resources\';
  if not DirectoryExists(ImgPath) then
    ImgPath := ExtractFilePath(ParamStr(0));
  SvgPath := ImgPath;
  Randomize;
  FCardCount := 0;
  FPaintBoxScale := 1.0;

  // Page control
  PageControl := TPageControl.Create(Self);
  PageControl.Parent := Self;
  PageControl.Align := alClient;

  // --- HTML View tab ---
  TabHtmlView := TTabSheet.Create(PageControl);
  TabHtmlView.PageControl := PageControl;
  TabHtmlView.Caption := 'HTML View';

  UrlPanel := TPanel.Create(TabHtmlView);
  UrlPanel.Parent := TabHtmlView;
  UrlPanel.Align := alTop;
  UrlPanel.Height := Scale(36);
  UrlPanel.BevelOuter := bvNone;

  BtnOpen := TButton.Create(UrlPanel);
  BtnOpen.Parent := UrlPanel;
  BtnOpen.Align := alLeft;
  BtnOpen.Width := Scale(130);
  BtnOpen.Caption := 'Load HTML from file';
  BtnOpen.OnClick := BtnOpenClick;
  BtnOpen.AlignWithMargins := True;
  BtnOpen.Margins.SetBounds(Scale(4), Scale(6), 0, Scale(6));

  BtnSavePdf := TButton.Create(UrlPanel);
  BtnSavePdf.Parent := UrlPanel;
  BtnSavePdf.Align := alLeft;
  BtnSavePdf.Width := Scale(90);
  BtnSavePdf.Caption := 'Save as PDF';
  BtnSavePdf.OnClick := BtnSavePdfClick;
  BtnSavePdf.AlignWithMargins := True;
  BtnSavePdf.Margins.SetBounds(Scale(4), Scale(6), 0, Scale(6));

  BtnGo := TButton.Create(UrlPanel);
  BtnGo.Parent := UrlPanel;
  BtnGo.Align := alRight;
  BtnGo.Width := Scale(50);
  BtnGo.Caption := 'Go';
  BtnGo.OnClick := BtnGoClick;
  BtnGo.AlignWithMargins := True;
  BtnGo.Margins.SetBounds(0, Scale(6), Scale(4), Scale(6));

  UrlEdit := TEdit.Create(UrlPanel);
  UrlEdit.Parent := UrlPanel;
  UrlEdit.Align := alClient;
  UrlEdit.TextHint := '...or try a simple web-site here';
  UrlEdit.OnKeyPress := UrlEditKeyPress;
  UrlEdit.AlignWithMargins := True;
  UrlEdit.Margins.SetBounds(Scale(8), Scale(6), Scale(8), Scale(6));

  PixieHtmlView := TPixieHtmlView.Create(Self);
  PixieHtmlView.Parent := TabHtmlView;
  PixieHtmlView.Align := alClient;
  PixieHtmlView.Color := clWhite;
  PixieHtmlView.OnAnchorClick := ViewAnchorClick;
  PixieHtmlView.OnElementClick := ViewElementClick;
  PixieHtmlView.OnFetchUrl := FetchUrl;
  PixieHtmlView.OnBeforeParse := ViewBeforeParse;
  PixieHtmlView.OnAfterParse := ViewAfterParse;
  PixieHtmlView.OnBeforePaint := ViewBeforePaint;
  PixieHtmlView.OnAfterPaint := ViewAfterPaint;

  // --- SVG View tab ---
  TabSvgView := TTabSheet.Create(PageControl);
  TabSvgView.PageControl := PageControl;
  TabSvgView.Caption := 'SVG View';

  SvgToolbar := TPanel.Create(TabSvgView);
  SvgToolbar.Parent := TabSvgView;
  SvgToolbar.Align := alTop;
  SvgToolbar.Height := Scale(36);
  SvgToolbar.BevelOuter := bvNone;

  BtnLoadSvg := TButton.Create(SvgToolbar);
  BtnLoadSvg.Parent := SvgToolbar;
  BtnLoadSvg.Align := alLeft;
  BtnLoadSvg.Width := Scale(100);
  BtnLoadSvg.Caption := 'Load SVG file';
  BtnLoadSvg.OnClick := BtnLoadSvgClick;
  BtnLoadSvg.AlignWithMargins := True;
  BtnLoadSvg.Margins.SetBounds(Scale(4), Scale(6), 0, Scale(6));

  CbAlignment := TComboBox.Create(SvgToolbar);
  CbAlignment.Parent := SvgToolbar;
  CbAlignment.Align := alRight;
  CbAlignment.Width := Scale(150);
  CbAlignment.Style := csDropDownList;
  CbAlignment.AlignWithMargins := True;
  CbAlignment.Margins.SetBounds(0, Scale(6), Scale(4), Scale(6));
  CbAlignment.Items.Add('Top Left');
  CbAlignment.Items.Add('Centre Horz');
  CbAlignment.Items.Add('Centre Vert');
  CbAlignment.Items.Add('Centre Both');
  CbAlignment.ItemIndex := 3;
  CbAlignment.OnChange := CbAlignmentChange;

  PixieSvgView := TPixieSvgView.Create(Self);
  PixieSvgView.Parent := TabSvgView;
  PixieSvgView.Align := alClient;
  PixieSvgView.Lines.Text := PixieDemoSampleSvg;

  // --- Paint Box tab ---
  TabPaintBox := TTabSheet.Create(PageControl);
  TabPaintBox.PageControl := PageControl;
  TabPaintBox.Caption := 'Paint Box';

  PaintBoxToolbar := TPanel.Create(TabPaintBox);
  PaintBoxToolbar.Parent := TabPaintBox;
  PaintBoxToolbar.Align := alTop;
  PaintBoxToolbar.Height := Scale(36);
  PaintBoxToolbar.BevelOuter := bvNone;

  LblZoom := TLabel.Create(PaintBoxToolbar);
  LblZoom.Parent := PaintBoxToolbar;
  LblZoom.Left := Scale(8);
  LblZoom.Top := Scale(10);
  LblZoom.Caption := 'Zoom:';

  ZoomSlider := TTrackBar.Create(PaintBoxToolbar);
  ZoomSlider.Parent := PaintBoxToolbar;
  ZoomSlider.Left := Scale(50);
  ZoomSlider.Top := Scale(4);
  ZoomSlider.Width := Scale(200);
  ZoomSlider.Min := 100;
  ZoomSlider.Max := 300;
  ZoomSlider.Frequency := 5;
  ZoomSlider.PageSize := 5;
  ZoomSlider.LineSize := 5;
  ZoomSlider.Position := 100;
  ZoomSlider.OnChange := ZoomSliderChange;

  LblZoomPct := TLabel.Create(PaintBoxToolbar);
  LblZoomPct.Parent := PaintBoxToolbar;
  LblZoomPct.Left := Scale(260);
  LblZoomPct.Top := Scale(10);
  LblZoomPct.Caption := '100%';

  PixiePaintBox := TPixiePaintBox.Create(Self);
  PixiePaintBox.Parent := TabPaintBox;
  PixiePaintBox.Align := alClient;
  PixiePaintBox.Color := clWhite;
  PixiePaintBox.OnPaint := PaintBoxPaint;

  // --- TagBar tab ---
  CreateTagBarTab;

  // Register images from streams
  if FileExists(ImgPath + 'firefox.png') then
  begin
    Stream := TFileStream.Create(ImgPath + 'firefox.png',
      fmOpenRead or fmShareDenyNone);
    try
      PixieHtmlView.RegisterImage('firefox', Stream);
    finally
      Stream.Free;
    end;
  end;
  if FileExists(ImgPath + 'chrome.png') then
  begin
    Stream := TFileStream.Create(ImgPath + 'chrome.png',
      fmOpenRead or fmShareDenyNone);
    try
      PixieHtmlView.RegisterImage('chrome', Stream);
    finally
      Stream.Free;
    end;
  end;

  PixieHtmlView.LoadFromString(PixieDemoHtmlContent(ImgPath, SvgPath), ImgPath);
end;

// ---------------------------------------------------------------------------
// TagBar tab
// ---------------------------------------------------------------------------

procedure TMainForm.CreateTagBarTab;
var
  ScrollBox: TScrollBox;
  Y: Integer;

  function AddLabel(const ACaption: string): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := ScrollBox;
    Result.Align := alTop;
    Result.Top := Y;
    Result.Caption := ACaption;
    Result.Font.Style := [fsBold];
    Result.AlignWithMargins := True;
    Result.Margins.SetBounds(Scale(8), Scale(8), Scale(4), Scale(2));
    Inc(Y, Scale(24));
  end;

  function AddBar(AOptions: TPixieTagBarOptions): TPixieTagBar;
  begin
    Result := TPixieTagBar.Create(Self);
    Result.Parent := ScrollBox;
    Result.Align := alTop;
    Result.Top := Y;
    Result.Color := clWindow;
    Result.ShowBorder := True;
    Result.TagShape := tsRoundedRect;
    Result.Options := AOptions;
    Result.AutoHeight := True;
    Result.TabStop := True;
    Result.AlignWithMargins := True;
    Result.Margins.SetBounds(Scale(4), 0, Scale(4), 0);
    Inc(Y, Scale(36));
  end;

begin
  TabTagBar := TTabSheet.Create(PageControl);
  TabTagBar.PageControl := PageControl;
  TabTagBar.Caption := 'TagBar';

  // Toolbar
  TagBarToolbar := TPanel.Create(TabTagBar);
  TagBarToolbar.Parent := TabTagBar;
  TagBarToolbar.Align := alTop;
  TagBarToolbar.Height := Scale(36);
  TagBarToolbar.BevelOuter := bvNone;

  LblTagShape := TLabel.Create(TagBarToolbar);
  LblTagShape.Parent := TagBarToolbar;
  LblTagShape.Left := Scale(8);
  LblTagShape.Top := Scale(10);
  LblTagShape.Caption := 'Shape:';

  CbTagShape := TComboBox.Create(TagBarToolbar);
  CbTagShape.Parent := TagBarToolbar;
  CbTagShape.Left := Scale(50);
  CbTagShape.Top := Scale(6);
  CbTagShape.Width := Scale(130);
  CbTagShape.Style := csDropDownList;
  CbTagShape.Items.Add('Pill');
  CbTagShape.Items.Add('Rounded Rect');
  CbTagShape.Items.Add('Rectangle');
  CbTagShape.ItemIndex := 1;
  CbTagShape.OnChange := TagBarShapeChange;

  ChkTagAutoHeight := TCheckBox.Create(TagBarToolbar);
  ChkTagAutoHeight.Parent := TagBarToolbar;
  ChkTagAutoHeight.Left := Scale(200);
  ChkTagAutoHeight.Top := Scale(8);
  ChkTagAutoHeight.Width := Scale(120);
  ChkTagAutoHeight.Caption := 'AutoHeight';
  ChkTagAutoHeight.Checked := True;
  ChkTagAutoHeight.OnClick := TagBarAutoHeightChange;

  // ScrollBox for tag bars
  ScrollBox := TScrollBox.Create(TabTagBar);
  ScrollBox.Parent := TabTagBar;
  ScrollBox.Align := alClient;
  ScrollBox.BorderStyle := bsNone;

  Y := Scale(4);

  // Editor
  AddLabel('Editor (full editing):');
  TagBarEditor := AddBar(TagBarEditorOpts);

  // Filter
  AddLabel('Filter (check only):');
  TagBarFilter := AddBar(TagBarFilterOpts);

  // Assign
  AddLabel('Assign (check + create):');
  TagBarAssign := AddBar(TagBarAssignOpts);

  // Display
  AddLabel('Display (read-only, checked tags only):');
  TagBarDisplay := AddBar(TagBarDisplayOpts);

  // Populate all bars
  PopulateTagBarTags(TagBarEditor);
  PopulateTagBarTags(TagBarFilter);
  PopulateTagBarTags(TagBarAssign);
  PopulateTagBarTags(TagBarDisplay);

  // Check some tags in Display so they are visible
  TagBarDisplay.CheckTag(TagBarDisplay.GetTag(0).ID, True);
  TagBarDisplay.CheckTag(TagBarDisplay.GetTag(2).ID, True);
  TagBarDisplay.CheckTag(TagBarDisplay.GetTag(4).ID, True);
end;

procedure TMainForm.PopulateTagBarTags(Bar: TPixieTagBar);
begin
  Bar.AddTag('Env:Production', TPixieWebColor.Create($F4, $43, $36),
    #$D83D#$DD34, '');  // Red circle
  Bar.AddTag('Env:Staging',    TPixieWebColor.Create($FF, $98, $00),
    #$D83D#$DFE0, '');  // Orange circle
  Bar.AddTag('DC:London',      TPixieWebColor.Create($21, $96, $F3),
    #$D83C#$DF0D, '');  // Globe
  Bar.AddTag('DC:New York',    TPixieWebColor.Create($4C, $AF, $50),
    #$D83D#$DCCD, '');  // Pin
  Bar.AddTag('Router',         TPixieWebColor.Create($9C, $27, $B0));
  Bar.AddTag('Server',         TPixieWebColor.Create($00, $96, $88),
    #$D83D#$DDCE, '');  // Server
  Bar.AddTag('Cloud',          TPixieWebColor.Create($79, $55, $48),
    #$2601, '');        // Cloud (BMP)
  Bar.AddTag('Critical',       TPixieWebColor.Create($60, $7D, $8B),
    #$26A0, '');        // Warning (BMP)
end;

procedure TMainForm.TagBarShapeChange(Sender: TObject);
var
  Shape: TPixieTagShape;
begin
  case CbTagShape.ItemIndex of
    0: Shape := tsPill;
    1: Shape := tsRoundedRect;
    2: Shape := tsRect;
  else
    Shape := tsPill;
  end;
  TagBarEditor.TagShape := Shape;
  TagBarFilter.TagShape := Shape;
  TagBarAssign.TagShape := Shape;
  TagBarDisplay.TagShape := Shape;
end;

procedure TMainForm.TagBarAutoHeightChange(Sender: TObject);
var
  Auto: Boolean;
begin
  Auto := ChkTagAutoHeight.Checked;
  TagBarEditor.AutoHeight := Auto;
  TagBarFilter.AutoHeight := Auto;
  TagBarAssign.AutoHeight := Auto;
  TagBarDisplay.AutoHeight := Auto;
end;

// ---------------------------------------------------------------------------
// PaintBox
// ---------------------------------------------------------------------------

procedure TMainForm.PaintBoxPaint(Sender: TObject; ACanvas: TPixieDrawingCanvas);
begin
  ACanvas.Canvas.ConcatMatrix(FPaintBoxScale, 0, 0, FPaintBoxScale, 0, 0);
  PixieDemoDraw(ACanvas,
    PixiePaintBox.ClientWidth / FPaintBoxScale,
    PixiePaintBox.ClientHeight / FPaintBoxScale);
end;

procedure TMainForm.ZoomSliderChange(Sender: TObject);
begin
  FPaintBoxScale := ZoomSlider.Position / 100;
  LblZoomPct.Caption := IntToStr(ZoomSlider.Position) + '%';
  PixiePaintBox.Invalidate;
end;

// ---------------------------------------------------------------------------
// SVG View
// ---------------------------------------------------------------------------

procedure TMainForm.BtnLoadSvgClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Filter := 'SVG files (*.svg)|*.svg|All files (*.*)|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if Dlg.Execute then
      PixieSvgView.Lines.LoadFromFile(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TMainForm.CbAlignmentChange(Sender: TObject);
begin
  case CbAlignment.ItemIndex of
    0: PixieSvgView.Alignment := saTopLeft;
    1: PixieSvgView.Alignment := saCenterHorz;
    2: PixieSvgView.Alignment := saCenterVert;
    3: PixieSvgView.Alignment := saCenterBoth;
  end;
end;

// ---------------------------------------------------------------------------
// HTTP fetching
// ---------------------------------------------------------------------------

procedure TMainForm.FetchUrl(Sender: TObject; const AUrl: string;
  Stream: TStream; var Success: Boolean);
var
  Client: THTTPClient;
  Resp: IHTTPResponse;
  T: Int64;
begin
  T := StopwatchNow;
  Client := THTTPClient.Create;
  try
    Client.UserAgent := 'Pixie/1.0';
    try
      Resp := Client.Get(AUrl, Stream);
      Success := (Resp.StatusCode >= 200) and (Resp.StatusCode < 400);
    except
      Success := False;
    end;
  finally
    Client.Free;
  end;
  Inc(FFetchAccum, StopwatchNow - T);
end;

procedure TMainForm.NavigateToUrl(const Url: string);
var
  Client: THTTPClient;
  Resp: IHTTPResponse;
  HtmlText: string;
  ActualUrl: string;
begin
  ActualUrl := Url;
  if (Pos('http://', LowerCase(ActualUrl)) <> 1) and
     (Pos('https://', LowerCase(ActualUrl)) <> 1) then
    ActualUrl := 'https://' + ActualUrl;

  Client := THTTPClient.Create;
  try
    Client.UserAgent := 'Pixie/1.0';
    try
      Resp := Client.Get(ActualUrl);
      HtmlText := Resp.ContentAsString;
    except
      on E: Exception do
      begin
        ShowMessage('Failed to load: ' + E.Message);
        Exit;
      end;
    end;
  finally
    Client.Free;
  end;

  UrlEdit.Text := ActualUrl;
  PixieHtmlView.LoadFromString(HtmlText, ActualUrl);
end;

// ---------------------------------------------------------------------------
// Toolbar actions
// ---------------------------------------------------------------------------

procedure TMainForm.BtnSavePdfClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  Pdf: TPixiePdfExport;
begin
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Filter := 'PDF files (*.pdf)|*.pdf';
    Dlg.DefaultExt := '.pdf';
    Dlg.FileName := 'document.pdf';
    if Dlg.Execute then
    begin
      Pdf := TPixiePdfExport.Create;
      try
        Pdf.Title := Caption;
        Pdf.SaveToFile(PixieHtmlView.Lines.Text, Dlg.FileName);
      finally
        Pdf.Free;
      end;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TMainForm.BtnOpenClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Filter := 'HTML files (*.html;*.htm)|*.html;*.htm|All files (*.*)|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if Dlg.Execute then
    begin
      UrlEdit.Text := '';
      PixieHtmlView.LoadFromFile(Dlg.FileName);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TMainForm.BtnGoClick(Sender: TObject);
begin
  if UrlEdit.Text = '' then Exit;
  if FNavWarningShown or
     (MessageDlg(
      PixieDemoNavigationWarning(UrlEdit.Text, sLineBreak),
      mtConfirmation, [mbYes, mbNo], 0) = mrYes) then
  begin
    FNavWarningShown := True;
    NavigateToUrl(UrlEdit.Text);
  end;
end;

procedure TMainForm.UrlEditKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    BtnGoClick(nil);
  end;
end;

// ---------------------------------------------------------------------------
// Document events
// ---------------------------------------------------------------------------

procedure TMainForm.ViewAnchorClick(Sender: TObject; const Url: string);
var
  FullUrl: string;
begin
  FullUrl := Url;
  if (Pos('://', FullUrl) = 0) and (PixieHtmlView.BaseUrl <> '') then
    FullUrl := PixieResolveUrl(TPixieUrl.Create(PixieHtmlView.BaseUrl),
      TPixieUrl.Create(FullUrl)).Str;

  if (Pos('http://', LowerCase(FullUrl)) = 1) or
     (Pos('https://', LowerCase(FullUrl)) = 1) then
  begin
    if FNavWarningShown or
       (MessageDlg(
        PixieDemoNavigationWarning(FullUrl, sLineBreak),
        mtConfirmation, [mbYes, mbNo], 0) = mrYes) then
    begin
      FNavWarningShown := True;
      NavigateToUrl(FullUrl);
    end;
  end
  else
    ShowMessage('Link clicked: ' + Url);
end;

function TMainForm.ViewElementClick(Sender: TObject; El: TObject): Boolean;
var
  PixEl: TPixieElement;
  ElId: string;
begin
  Result := False;
  if not (El is TPixieElement) then
    Exit;

  PixEl := TPixieElement(El);
  Result := PixieDemoHandleElementClick(
    PixieHtmlView.Document, PixEl, FCardCount);

  if not Result then
  begin
    ElId := PixEl.GetAttr('id');
    if ElId <> '' then
    begin
      ShowMessage('Clicked: ' + ElId);
      Result := True;
    end;
  end;
end;

procedure TMainForm.ViewBeforeParse(Sender: TObject);
begin
  FParseStart := StopwatchNow;
  FFetchAccum := 0;
end;

procedure TMainForm.ViewAfterParse(Sender: TObject);
var
  TotalMs, FetchMs: Double;
  Freq: Int64;
begin
  TotalMs := StopwatchElapsedMs(FParseStart);
  QueryPerformanceFrequency(Freq);
  FetchMs := FFetchAccum * 1000.0 / Freq;
  StatusBar.Panels[0].Text := Format('Parse: %.1f ms (net: %.1f ms)',
    [TotalMs - FetchMs, FetchMs]);
end;

procedure TMainForm.ViewBeforePaint(Sender: TObject);
begin
  FPaintStart := StopwatchNow;
end;

procedure TMainForm.ViewAfterPaint(Sender: TObject);
begin
  StatusBar.Panels[1].Text := Format('Paint: %.1f ms', [StopwatchElapsedMs(FPaintStart)]);
end;

end.
