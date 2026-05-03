unit PixieDemoMain;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  System.Diagnostics,
  System.Net.HttpClient,
  FMX.Forms, FMX.Controls, FMX.Types, FMX.StdCtrls, FMX.Layouts,
  FMX.Edit, FMX.Dialogs, FMX.DialogService.Sync, FMX.TabControl,
  FMX.ListBox, FMX.Memo, FMX.ScrollBox,
  System.Math,
  Pixie.HtmlView.FMX, Pixie.NativeContainer, Pixie.Url,
  Pixie.Element, Pixie.Document, Pixie.PdfExport,
  Pixie.SvgView.FMX, Pixie.PaintBox.FMX, Pixie.DrawingCanvas,
  Pixie.MarkdownView.FMX,
  Pixie.TagBar.FMX, Pixie.TagBar.Base, Pixie.TagBar.Render,
  Pixie.WebColor,
  PixieDemoContent, PixieDemoPaintBox;

type
  TMainForm = class(TForm)
    StatusLayout: TLayout;
    StatusLabel1: TLabel;
    StatusLabel2: TLabel;
    procedure FormCreate(Sender: TObject);
  private
    TabControl: TTabControl;
    TabHtmlView: TTabItem;
    TabSvgView: TTabItem;
    UrlPanel: TLayout;
    BtnOpen: TButton;
    BtnSavePdf: TButton;
    BtnGo: TButton;
    UrlEdit: TEdit;
    SvgToolbar: TLayout;
    BtnLoadSvg: TButton;
    CbAlignment: TComboBox;
    PixieHtmlView: TPixieHtmlView;
    PixieSvgView: TPixieSvgView;
    TabPaintBox: TTabItem;
    PaintBoxToolbar: TLayout;
    LblZoom: TLabel;
    ZoomSlider: TTrackBar;
    LblZoomPct: TLabel;
    PixiePaintBox: TPixiePaintBox;
    TabTagBar: TTabItem;
    TagBarLayout: TLayout;
    TagBarToolbar: TLayout;
    CbTagShape: TComboBox;
    LblTagShape: TLabel;
    ChkTagAutoHeight: TCheckBox;
    TagBarEditor: TPixieTagBar;
    TagBarFilter: TPixieTagBar;
    TagBarAssign: TPixieTagBar;
    TagBarDisplay: TPixieTagBar;
    TagBarSettings: TPixieTagBar;
    TabMarkdownView: TTabItem;
    MdToolbar: TLayout;
    BtnLoadMd: TButton;
    BtnReloadMd: TButton;
    BtnSaveMdPdf: TButton;
    ChkMdDefaultStyles: TCheckBox;
    PixieMarkdownView: TPixieMarkdownView;
    FPaintBoxScale: Single;
    FCardCount: Integer;
    FParseTimer: TStopwatch;
    FPaintTimer: TStopwatch;
    FFetchAccum: Int64;
    FNavWarningShown: Boolean;
    FMdPath: string;
    procedure BtnOpenClick(Sender: TObject);
    procedure BtnSavePdfClick(Sender: TObject);
    procedure BtnGoClick(Sender: TObject);
    procedure UrlEditKeyDown(Sender: TObject; var Key: Word;
      var KeyChar: WideChar; Shift: TShiftState);
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
    procedure CreateMarkdownTab(const ResourcePath: string);
    procedure LoadMarkdownFile(const Path: string);
    procedure BtnLoadMdClick(Sender: TObject);
    procedure BtnReloadMdClick(Sender: TObject);
    procedure BtnSaveMdPdfClick(Sender: TObject);
    procedure MdDefaultStylesChange(Sender: TObject);
    procedure PopulateTagBarTags(Bar: TPixieTagBar);
    procedure PopulateTagBarTagsPlain(Bar: TPixieTagBar);
    procedure TagBarShapeChange(Sender: TObject);
    procedure TagBarAutoHeightChange(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.fmx}

procedure TMainForm.FormCreate(Sender: TObject);
var
  ImgPath, SvgPath: string;
  Stream: TFileStream;
  HtmlLayout, SvgLayout: TLayout;
begin
  ImgPath := ExtractFilePath(ParamStr(0)) + '..\resources\';
  if not DirectoryExists(ImgPath) then
    ImgPath := ExtractFilePath(ParamStr(0));
  SvgPath := ImgPath;
  Randomize;
  FCardCount := 0;
  FPaintBoxScale := 1.0;

  // Tab control
  TabControl := TTabControl.Create(Self);
  TabControl.Parent := Self;
  TabControl.Align := TAlignLayout.Client;

  // --- HTML View tab ---
  TabHtmlView := TTabItem.Create(TabControl);
  TabHtmlView.Text := 'HTML View';
  TabControl.AddObject(TabHtmlView);

  HtmlLayout := TLayout.Create(TabHtmlView);
  HtmlLayout.Parent := TabHtmlView;
  HtmlLayout.Align := TAlignLayout.Client;

  UrlPanel := TLayout.Create(HtmlLayout);
  UrlPanel.Parent := HtmlLayout;
  UrlPanel.Align := TAlignLayout.Top;
  UrlPanel.Height := 36;

  BtnSavePdf := TButton.Create(UrlPanel);
  BtnSavePdf.Parent := UrlPanel;
  BtnSavePdf.Align := TAlignLayout.Left;
  BtnSavePdf.Width := 90;
  BtnSavePdf.Text := 'Save as PDF';
  BtnSavePdf.OnClick := BtnSavePdfClick;
  BtnSavePdf.Margins.Left := 4;
  BtnSavePdf.Margins.Top := 4;
  BtnSavePdf.Margins.Bottom := 4;

  BtnOpen := TButton.Create(UrlPanel);
  BtnOpen.Parent := UrlPanel;
  BtnOpen.Align := TAlignLayout.Left;
  BtnOpen.Width := 130;
  BtnOpen.Text := 'Load HTML from file';
  BtnOpen.OnClick := BtnOpenClick;
  BtnOpen.Margins.Left := 4;
  BtnOpen.Margins.Top := 4;
  BtnOpen.Margins.Bottom := 4;

  BtnGo := TButton.Create(UrlPanel);
  BtnGo.Parent := UrlPanel;
  BtnGo.Align := TAlignLayout.Right;
  BtnGo.Width := 50;
  BtnGo.Text := 'Go';
  BtnGo.OnClick := BtnGoClick;
  BtnGo.Margins.Right := 4;
  BtnGo.Margins.Top := 4;
  BtnGo.Margins.Bottom := 4;

  UrlEdit := TEdit.Create(UrlPanel);
  UrlEdit.Parent := UrlPanel;
  UrlEdit.Align := TAlignLayout.Client;
  UrlEdit.OnKeyDown := UrlEditKeyDown;
  UrlEdit.Margins.Left := 8;
  UrlEdit.Margins.Right := 8;
  UrlEdit.Margins.Top := 4;
  UrlEdit.Margins.Bottom := 4;

  PixieHtmlView := TPixieHtmlView.Create(Self);
  PixieHtmlView.Parent := HtmlLayout;
  PixieHtmlView.Align := TAlignLayout.Client;
  PixieHtmlView.OnAnchorClick := ViewAnchorClick;
  PixieHtmlView.OnElementClick := ViewElementClick;
  PixieHtmlView.OnFetchUrl := FetchUrl;
  PixieHtmlView.OnBeforeParse := ViewBeforeParse;
  PixieHtmlView.OnAfterParse := ViewAfterParse;
  PixieHtmlView.OnBeforePaint := ViewBeforePaint;
  PixieHtmlView.OnAfterPaint := ViewAfterPaint;

  // --- SVG View tab ---
  TabSvgView := TTabItem.Create(TabControl);
  TabSvgView.Text := 'SVG View';
  TabControl.AddObject(TabSvgView);

  SvgLayout := TLayout.Create(TabSvgView);
  SvgLayout.Parent := TabSvgView;
  SvgLayout.Align := TAlignLayout.Client;

  SvgToolbar := TLayout.Create(SvgLayout);
  SvgToolbar.Parent := SvgLayout;
  SvgToolbar.Align := TAlignLayout.Top;
  SvgToolbar.Height := 36;

  BtnLoadSvg := TButton.Create(SvgToolbar);
  BtnLoadSvg.Parent := SvgToolbar;
  BtnLoadSvg.Align := TAlignLayout.Left;
  BtnLoadSvg.Width := 100;
  BtnLoadSvg.Text := 'Load SVG file';
  BtnLoadSvg.OnClick := BtnLoadSvgClick;
  BtnLoadSvg.Margins.Left := 4;
  BtnLoadSvg.Margins.Top := 4;
  BtnLoadSvg.Margins.Bottom := 4;

  CbAlignment := TComboBox.Create(SvgToolbar);
  CbAlignment.Parent := SvgToolbar;
  CbAlignment.Align := TAlignLayout.Right;
  CbAlignment.Width := 150;
  CbAlignment.Margins.Right := 4;
  CbAlignment.Margins.Top := 4;
  CbAlignment.Margins.Bottom := 4;
  CbAlignment.Items.Add('Top Left');
  CbAlignment.Items.Add('Centre Horz');
  CbAlignment.Items.Add('Centre Vert');
  CbAlignment.Items.Add('Centre Both');
  CbAlignment.ItemIndex := 3;
  CbAlignment.OnChange := CbAlignmentChange;

  PixieSvgView := TPixieSvgView.Create(Self);
  PixieSvgView.Parent := SvgLayout;
  PixieSvgView.Align := TAlignLayout.Client;
  PixieSvgView.Lines.Text := PixieDemoSampleSvg;

  // --- Paint Box tab ---
  TabPaintBox := TTabItem.Create(TabControl);
  TabPaintBox.Text := 'Paint Box';
  TabControl.AddObject(TabPaintBox);

  PaintBoxToolbar := TLayout.Create(TabPaintBox);
  PaintBoxToolbar.Parent := TabPaintBox;
  PaintBoxToolbar.Align := TAlignLayout.Top;
  PaintBoxToolbar.Height := 36;

  LblZoom := TLabel.Create(PaintBoxToolbar);
  LblZoom.Parent := PaintBoxToolbar;
  LblZoom.Position.X := 8;
  LblZoom.Position.Y := 8;
  LblZoom.Text := 'Zoom:';

  ZoomSlider := TTrackBar.Create(PaintBoxToolbar);
  ZoomSlider.Parent := PaintBoxToolbar;
  ZoomSlider.Position.X := 60;
  ZoomSlider.Position.Y := 4;
  ZoomSlider.Width := 200;
  ZoomSlider.Min := 100;
  ZoomSlider.Max := 300;
  ZoomSlider.Frequency := 5;
  ZoomSlider.Value := 100;
  ZoomSlider.OnChange := ZoomSliderChange;

  LblZoomPct := TLabel.Create(PaintBoxToolbar);
  LblZoomPct.Parent := PaintBoxToolbar;
  LblZoomPct.Position.X := 270;
  LblZoomPct.Position.Y := 8;
  LblZoomPct.Text := '100%';

  PixiePaintBox := TPixiePaintBox.Create(Self);
  PixiePaintBox.Parent := TabPaintBox;
  PixiePaintBox.Align := TAlignLayout.Client;
  PixiePaintBox.OnPaint := PaintBoxPaint;

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

  // --- Markdown tab ---
  CreateMarkdownTab(ImgPath);

  // --- TagBar tab ---
  CreateTagBarTab;
end;

// ---------------------------------------------------------------------------
// Markdown
// ---------------------------------------------------------------------------

procedure TMainForm.CreateMarkdownTab(const ResourcePath: string);
begin
  TabMarkdownView := TTabItem.Create(TabControl);
  TabMarkdownView.Parent := TabControl;
  TabMarkdownView.Text := 'Markdown View';

  MdToolbar := TLayout.Create(TabMarkdownView);
  MdToolbar.Parent := TabMarkdownView;
  MdToolbar.Align := TAlignLayout.Top;
  MdToolbar.Height := 36;

  BtnLoadMd := TButton.Create(MdToolbar);
  BtnLoadMd.Parent := MdToolbar;
  BtnLoadMd.SetBounds(4, 6, 120, 24);
  BtnLoadMd.Text := 'Load .md file';
  BtnLoadMd.OnClick := BtnLoadMdClick;

  BtnReloadMd := TButton.Create(MdToolbar);
  BtnReloadMd.Parent := MdToolbar;
  BtnReloadMd.SetBounds(128, 6, 70, 24);
  BtnReloadMd.Text := 'Reload';
  BtnReloadMd.OnClick := BtnReloadMdClick;

  BtnSaveMdPdf := TButton.Create(MdToolbar);
  BtnSaveMdPdf.Parent := MdToolbar;
  BtnSaveMdPdf.SetBounds(202, 6, 90, 24);
  BtnSaveMdPdf.Text := 'Save as PDF';
  BtnSaveMdPdf.OnClick := BtnSaveMdPdfClick;

  ChkMdDefaultStyles := TCheckBox.Create(MdToolbar);
  ChkMdDefaultStyles.Parent := MdToolbar;
  ChkMdDefaultStyles.SetBounds(304, 8, 160, 24);
  ChkMdDefaultStyles.Text := 'Use default styles';
  ChkMdDefaultStyles.IsChecked := True;
  ChkMdDefaultStyles.OnChange := MdDefaultStylesChange;

  PixieMarkdownView := TPixieMarkdownView.Create(Self);
  PixieMarkdownView.Parent := TabMarkdownView;
  PixieMarkdownView.Align := TAlignLayout.Client;

  if FileExists(ResourcePath + 'sample.md') then
    LoadMarkdownFile(ResourcePath + 'sample.md');
end;

procedure TMainForm.LoadMarkdownFile(const Path: string);
begin
  FMdPath := Path;
  PixieMarkdownView.LoadMarkdownFromFile(Path);
end;

procedure TMainForm.BtnLoadMdClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Filter := 'Markdown files (*.md;*.markdown)|*.md;*.markdown|' +
      'All files (*.*)|*.*';
    Dlg.Options := Dlg.Options + [TOpenOption.ofFileMustExist];
    if Dlg.Execute then
      LoadMarkdownFile(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TMainForm.BtnReloadMdClick(Sender: TObject);
begin
  if FMdPath <> '' then
    LoadMarkdownFile(FMdPath);
end;

procedure TMainForm.BtnSaveMdPdfClick(Sender: TObject);
var
  Dlg: TSaveDialog;
begin
  if FMdPath = '' then Exit;
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Filter := 'PDF files (*.pdf)|*.pdf';
    Dlg.DefaultExt := '.pdf';
    Dlg.FileName := 'markdown.pdf';
    if not Dlg.Execute then Exit;
    try
      PixieDemoSaveMarkdownAsPdf(FMdPath, Dlg.FileName);
      StatusLabel1.Text := 'PDF saved.';
    except
      on E: Exception do
        ShowMessage(E.ClassName + ': ' + E.Message);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TMainForm.MdDefaultStylesChange(Sender: TObject);
begin
  PixieMarkdownView.UseDefaultStyles := ChkMdDefaultStyles.IsChecked;
end;

// ---------------------------------------------------------------------------
// TagBar
// ---------------------------------------------------------------------------

procedure TMainForm.CreateTagBarTab;
var
  Y: Single;

  function AddLabel(const ACaption: string): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := TagBarLayout;
    Result.Align := TAlignLayout.Top;
    Result.Position.Y := Y;
    Result.Text := ACaption;
    Result.Font.Style := [TFontStyle.fsBold];
    Result.Margins.Left := 8;
    Result.Margins.Top := 8;
    Result.Margins.Bottom := 2;
    Y := Y + 24;
  end;

  function AddBar(AOptions: TPixieTagBarOptions): TPixieTagBar;
  begin
    Result := TPixieTagBar.Create(Self);
    Result.Parent := TagBarLayout;
    Result.Align := TAlignLayout.Top;
    Result.Position.Y := Y;
    Result.ShowBorder := True;
    Result.TagShape := tsRoundedRect;
    Result.Options := AOptions;
    Result.AutoHeight := True;
    Result.Margins.Left := 4;
    Result.Margins.Right := 4;
    Y := Y + 36;
  end;

begin
  TabTagBar := TTabItem.Create(TabControl);
  TabTagBar.Text := 'TagBar';
  TabControl.AddObject(TabTagBar);

  TagBarLayout := TLayout.Create(TabTagBar);
  TagBarLayout.Parent := TabTagBar;
  TagBarLayout.Align := TAlignLayout.Client;

  // Toolbar
  TagBarToolbar := TLayout.Create(TagBarLayout);
  TagBarToolbar.Parent := TagBarLayout;
  TagBarToolbar.Align := TAlignLayout.Top;
  TagBarToolbar.Height := 36;

  LblTagShape := TLabel.Create(TagBarToolbar);
  LblTagShape.Parent := TagBarToolbar;
  LblTagShape.Position.X := 8;
  LblTagShape.Position.Y := 8;
  LblTagShape.Text := 'Shape:';

  CbTagShape := TComboBox.Create(TagBarToolbar);
  CbTagShape.Parent := TagBarToolbar;
  CbTagShape.Position.X := 60;
  CbTagShape.Position.Y := 4;
  CbTagShape.Width := 130;
  CbTagShape.Items.Add('Pill');
  CbTagShape.Items.Add('Rounded Rect');
  CbTagShape.Items.Add('Rectangle');
  CbTagShape.ItemIndex := 1;
  CbTagShape.OnChange := TagBarShapeChange;

  ChkTagAutoHeight := TCheckBox.Create(TagBarToolbar);
  ChkTagAutoHeight.Parent := TagBarToolbar;
  ChkTagAutoHeight.Position.X := 210;
  ChkTagAutoHeight.Position.Y := 8;
  ChkTagAutoHeight.Text := 'Auto Height';
  ChkTagAutoHeight.IsChecked := True;
  ChkTagAutoHeight.OnChange := TagBarAutoHeightChange;

  Y := 4;

  // Editor
  AddLabel('Editor (full editing):');
  TagBarEditor := AddBar(TagBarEditorOpts);
  TagBarEditor.EmptyMessage := 'No tags — click + to add one';

  // Filter
  AddLabel('Filter (check only):');
  TagBarFilter := AddBar(TagBarFilterOpts);

  // Assign
  AddLabel('Assign (check + create):');
  TagBarAssign := AddBar(TagBarAssignOpts);

  // Display
  AddLabel('Display (read-only, checked tags only):');
  TagBarDisplay := AddBar(TagBarDisplayOpts);

  // Settings
  AddLabel('Settings (always checked, colour swatches, no toggle):');
  TagBarSettings := AddBar(TagBarSettingsOpts);

  // Populate all bars
  PopulateTagBarTags(TagBarEditor);
  PopulateTagBarTags(TagBarFilter);
  PopulateTagBarTags(TagBarAssign);
  PopulateTagBarTags(TagBarDisplay);
  PopulateTagBarTagsPlain(TagBarSettings);

  // Check some tags in Display so they are visible
  TagBarDisplay.CheckTag(TagBarDisplay.GetTag(0).ID, True);
  TagBarDisplay.CheckTag(TagBarDisplay.GetTag(2).ID, True);
  TagBarDisplay.CheckTag(TagBarDisplay.GetTag(4).ID, True);
end;

procedure TMainForm.PopulateTagBarTags(Bar: TPixieTagBar);
begin
  Bar.AddTag('Env:Production', TPixieWebColor.Create($F4, $43, $36),
    #$D83D#$DD34, '');
  Bar.AddTag('Env:Staging',    TPixieWebColor.Create($FF, $98, $00),
    #$D83D#$DFE0, '');
  Bar.AddTag('DC:London',      TPixieWebColor.Create($21, $96, $F3),
    #$D83C#$DF0D, '');
  Bar.AddTag('DC:New York',    TPixieWebColor.Create($4C, $AF, $50),
    #$D83D#$DCCD, '');
  Bar.AddTag('Router',         TPixieWebColor.Create($9C, $27, $B0));
  Bar.AddTag('Server',         TPixieWebColor.Create($00, $96, $88),
    #$D83D#$DDCE, '');
  Bar.AddTag('Cloud',          TPixieWebColor.Create($79, $55, $48),
    #$2601, '');
  Bar.AddTag('Critical',       TPixieWebColor.Create($60, $7D, $8B),
    #$26A0, '');
end;

procedure TMainForm.PopulateTagBarTagsPlain(Bar: TPixieTagBar);
begin
  Bar.AddTag('Production', TPixieWebColor.Create($F4, $43, $36));
  Bar.AddTag('Staging',    TPixieWebColor.Create($FF, $98, $00));
  Bar.AddTag('London',     TPixieWebColor.Create($21, $96, $F3));
  Bar.AddTag('New York',   TPixieWebColor.Create($4C, $AF, $50));
  Bar.AddTag('Router',     TPixieWebColor.Create($9C, $27, $B0));
  Bar.AddTag('Server',     TPixieWebColor.Create($00, $96, $88));
  Bar.AddTag('Cloud',      TPixieWebColor.Create($79, $55, $48));
  Bar.AddTag('Critical',   TPixieWebColor.Create($60, $7D, $8B));
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
  TagBarSettings.TagShape := Shape;
end;

procedure TMainForm.TagBarAutoHeightChange(Sender: TObject);
var
  Auto: Boolean;
begin
  Auto := ChkTagAutoHeight.IsChecked;
  TagBarEditor.AutoHeight := Auto;
  TagBarFilter.AutoHeight := Auto;
  TagBarAssign.AutoHeight := Auto;
  TagBarDisplay.AutoHeight := Auto;
  TagBarSettings.AutoHeight := Auto;
end;

// ---------------------------------------------------------------------------
// PaintBox
// ---------------------------------------------------------------------------

procedure TMainForm.PaintBoxPaint(Sender: TObject; ACanvas: TPixieDrawingCanvas);
begin
  ACanvas.Canvas.ConcatMatrix(FPaintBoxScale, 0, 0, FPaintBoxScale, 0, 0);
  PixieDemoDraw(ACanvas,
    PixiePaintBox.Width / FPaintBoxScale,
    PixiePaintBox.Height / FPaintBoxScale);
end;

procedure TMainForm.ZoomSliderChange(Sender: TObject);
begin
  FPaintBoxScale := ZoomSlider.Value / 100;
  LblZoomPct.Text := IntToStr(Round(ZoomSlider.Value)) + '%';
  PixiePaintBox.Repaint;
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
  T: TStopwatch;
begin
  T := TStopwatch.StartNew;
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
  Inc(FFetchAccum, T.ElapsedTicks);
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
     (TDialogServiceSync.MessageDialog(
      PixieDemoNavigationWarning(UrlEdit.Text, sLineBreak),
      TMsgDlgType.mtConfirmation,
      [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
      TMsgDlgBtn.mbNo, 0) = mrYes) then
  begin
    FNavWarningShown := True;
    NavigateToUrl(UrlEdit.Text);
  end;
end;

procedure TMainForm.UrlEditKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: WideChar; Shift: TShiftState);
begin
  if Key = vkReturn then
  begin
    Key := 0;
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
       (TDialogServiceSync.MessageDialog(
        PixieDemoNavigationWarning(FullUrl, sLineBreak),
        TMsgDlgType.mtConfirmation,
        [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
        TMsgDlgBtn.mbNo, 0) = mrYes) then
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
  FParseTimer := TStopwatch.StartNew;
  FFetchAccum := 0;
end;

procedure TMainForm.ViewAfterParse(Sender: TObject);
var
  TotalMs, FetchMs: Double;
begin
  FParseTimer.Stop;
  TotalMs := FParseTimer.Elapsed.TotalMilliseconds;
  FetchMs := FFetchAccum * 1000.0 / TStopwatch.Frequency;
  StatusLabel1.Text := Format('Parse: %.1f ms (net: %.1f ms)',
    [TotalMs - FetchMs, FetchMs]);
end;

procedure TMainForm.ViewBeforePaint(Sender: TObject);
begin
  FPaintTimer := TStopwatch.StartNew;
end;

procedure TMainForm.ViewAfterPaint(Sender: TObject);
begin
  FPaintTimer.Stop;
  StatusLabel2.Text := Format('Paint: %.1f ms',
    [FPaintTimer.Elapsed.TotalMilliseconds]);
end;

end.
