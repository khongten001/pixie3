unit PixieDemoMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  {$ifdef windows}Windows,{$endif}
  fphttpclient, opensslsockets,
  Pixie.HtmlView, Pixie.NativeContainer, Pixie.Url,
  Pixie.Element, Pixie.Document, Pixie.PdfExport,
  Pixie.SvgView, Pixie.PaintBox, Pixie.DrawingCanvas,
  Pixie.TagBar, Pixie.TagBar.Base, Pixie.TagBar.Render, Pixie.WebColor,
  PixieDemoContent, PixieDemoPaintBox,
  Forms, Controls, Graphics, Dialogs, ComCtrls, StdCtrls, ExtCtrls, Buttons;

type
  TMainForm = class(TForm)
    BtnOpen: TSpeedButton;
    BtnSavePdf: TSpeedButton;
    BtnGo: TButton;
    UrlEdit: TEdit;
    UrlPanel: TPanel;
    StatusBar: TStatusBar;
    PageControl: TPageControl;
    TabHtmlView: TTabSheet;
    PixieHtmlView: TPixieHtmlView;
    TabPaintBox: TTabSheet;
    PaintBoxToolbar: TPanel;
    LblZoom: TLabel;
    ZoomSlider: TTrackBar;
    LblZoomPct: TLabel;
    PixiePaintBox: TPixiePaintBox;
    TabSvgView: TTabSheet;
    SvgToolbar: TPanel;
    BtnLoadSvg: TSpeedButton;
    CbAlignment: TComboBox;
    PixieSvgView: TPixieSvgView;
    procedure BtnSavePdfClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure BtnOpenClick(Sender: TObject);
    procedure BtnGoClick(Sender: TObject);
    procedure UrlEditKeyPress(Sender: TObject; var Key: Char);
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
    procedure BtnLoadSvgClick(Sender: TObject);
    procedure CbAlignmentChange(Sender: TObject);
  private
    FCardCount: Integer;
    FPaintBoxScale: Single;
    FParseStart: Int64;
    FPaintStart: Int64;
    FFetchAccum: Int64;
    FNavWarningShown: Boolean;
    TabTagBar: TTabSheet;
    TagBarToolbar: TPanel;
    CbTagShape: TComboBox;
    LblTagShape: TLabel;
    ChkTagAutoHeight: TCheckBox;
    TagBarEditor: TPixieTagBar;
    TagBarFilter: TPixieTagBar;
    TagBarAssign: TPixieTagBar;
    TagBarDisplay: TPixieTagBar;
    TagBarSettings: TPixieTagBar;
    procedure NavigateToUrl(const Url: string);
    procedure CreateTagBarTab;
    procedure PopulateTagBarTags(Bar: TPixieTagBar);
    procedure PopulateTagBarTagsPlain(Bar: TPixieTagBar);
    procedure TagBarShapeChange(Sender: TObject);
    procedure TagBarAutoHeightChange(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{$ifdef windows}
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
{$else}
function StopwatchNow: Int64;
begin
  Result := GetTickCount64;
end;

function StopwatchElapsedMs(Start: Int64): Double;
begin
  Result := GetTickCount64 - Start;
end;
{$endif}

procedure TMainForm.FormCreate(Sender: TObject);
var
  ImgPath, SvgPath: string;
  Stream: TFileStream;
begin
  Caption := Caption + ' — ' + {$I %FPCTARGETOS%} + ' ' +
    {$I %FPCTARGETCPU%} + ' ' +
    {$IF DEFINED(LCLqt6)}'qt6'
    {$ELSEIF DEFINED(LCLqt5)}'qt5'
    {$ELSEIF DEFINED(LCLqt)}'qt4'
    {$ELSEIF DEFINED(LCLGTK3)}'gtk3'
    {$ELSEIF DEFINED(LCLGTK2)}'gtk2'
    {$ELSEIF DEFINED(LCLCocoa)}'cocoa'
    {$ELSEIF DEFINED(MSWindows)}'win32'
    {$ELSE}'unknown'
    {$ENDIF};
  ImgPath := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'resources' + PathDelim;
  if not DirectoryExists(ImgPath) then
    ImgPath := ExtractFilePath(ParamStr(0));
  SvgPath := ImgPath;
  Randomize;
  FCardCount := 0;
  FPaintBoxScale := 1.0;

  // Register images from streams for #name syntax
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

  if (ParamCount > 0) and FileExists(ParamStr(1)) then
  begin
    PixieHtmlView.LoadFromFile(ParamStr(1));
    Exit;
  end;

  PixieHtmlView.LoadFromString(PixieDemoHtmlContent(ImgPath, SvgPath), ImgPath);

  // SVG view: sample content and alignment combo
  PixieSvgView.Lines.Text := PixieDemoSampleSvg;
  CbAlignment.Items.Add('Top Left');
  CbAlignment.Items.Add('Centre Horz');
  CbAlignment.Items.Add('Centre Vert');
  CbAlignment.Items.Add('Centre Both');
  CbAlignment.ItemIndex := 3;

  // TagBar tab
  CreateTagBarTab;
end;

// ---------------------------------------------------------------------------
// TagBar tab
// ---------------------------------------------------------------------------

procedure TMainForm.CreateTagBarTab;
var
  ScrollBox: TScrollBox;
  Lbl: TLabel;
  Y: Integer;
begin
  TabTagBar := TTabSheet.Create(PageControl);
  TabTagBar.PageControl := PageControl;
  TabTagBar.Caption := 'TagBar';

  // --- Toolbar ---
  TagBarToolbar := TPanel.Create(TabTagBar);
  TagBarToolbar.Parent := TabTagBar;
  TagBarToolbar.Align := alTop;
  TagBarToolbar.Height := 36;
  TagBarToolbar.BevelOuter := bvNone;

  LblTagShape := TLabel.Create(TagBarToolbar);
  LblTagShape.Parent := TagBarToolbar;
  LblTagShape.Left := 8;
  LblTagShape.Top := 10;
  LblTagShape.Caption := 'Shape:';

  CbTagShape := TComboBox.Create(TagBarToolbar);
  CbTagShape.Parent := TagBarToolbar;
  CbTagShape.Left := 56;
  CbTagShape.Top := 6;
  CbTagShape.Width := 130;
  CbTagShape.Style := csDropDownList;
  CbTagShape.Items.Add('Pill');
  CbTagShape.Items.Add('Rounded Rect');
  CbTagShape.Items.Add('Rectangle');
  CbTagShape.ItemIndex := 1;
  CbTagShape.OnChange := @TagBarShapeChange;

  ChkTagAutoHeight := TCheckBox.Create(TagBarToolbar);
  ChkTagAutoHeight.Parent := TagBarToolbar;
  ChkTagAutoHeight.Left := 200;
  ChkTagAutoHeight.Top := 8;
  ChkTagAutoHeight.Width := 100;
  ChkTagAutoHeight.Caption := 'AutoHeight';
  ChkTagAutoHeight.Checked := True;
  ChkTagAutoHeight.OnChange := @TagBarAutoHeightChange;

  // --- ScrollBox for tag bars ---
  ScrollBox := TScrollBox.Create(TabTagBar);
  ScrollBox.Parent := TabTagBar;
  ScrollBox.Align := alClient;
  ScrollBox.BorderStyle := bsNone;

  Y := 4;

  // Editor
  Lbl := TLabel.Create(ScrollBox);
  Lbl.Parent := ScrollBox;
  Lbl.Align := alTop;
  Lbl.Top := Y;
  Lbl.Caption := 'Editor (full editing):';
  Lbl.Font.Style := [fsBold];
  Lbl.BorderSpacing.Left := 8;
  Lbl.BorderSpacing.Top := 8;
  Lbl.BorderSpacing.Right := 4;
  Lbl.BorderSpacing.Bottom := 2;
  Inc(Y, 24);

  TagBarEditor := TPixieTagBar.Create(Self);
  TagBarEditor.Parent := ScrollBox;
  TagBarEditor.Align := alTop;
  TagBarEditor.Top := Y;
  TagBarEditor.Color := clWindow;
  TagBarEditor.ShowBorder := True;
  TagBarEditor.TagShape := tsRoundedRect;
  TagBarEditor.AutoHeight := True;
  TagBarEditor.Options := TagBarEditorOpts;
  TagBarEditor.BorderSpacing.Left := 4;
  TagBarEditor.BorderSpacing.Right := 4;
  PopulateTagBarTags(TagBarEditor);
  Inc(Y, 36);

  // Filter
  Lbl := TLabel.Create(ScrollBox);
  Lbl.Parent := ScrollBox;
  Lbl.Align := alTop;
  Lbl.Top := Y;
  Lbl.Caption := 'Filter (check only):';
  Lbl.Font.Style := [fsBold];
  Lbl.BorderSpacing.Left := 8;
  Lbl.BorderSpacing.Top := 8;
  Lbl.BorderSpacing.Right := 4;
  Lbl.BorderSpacing.Bottom := 2;
  Inc(Y, 24);

  TagBarFilter := TPixieTagBar.Create(Self);
  TagBarFilter.Parent := ScrollBox;
  TagBarFilter.Align := alTop;
  TagBarFilter.Top := Y;
  TagBarFilter.Color := clWindow;
  TagBarFilter.ShowBorder := True;
  TagBarFilter.TagShape := tsRoundedRect;
  TagBarFilter.AutoHeight := True;
  TagBarFilter.Options := TagBarFilterOpts;
  TagBarFilter.BorderSpacing.Left := 4;
  TagBarFilter.BorderSpacing.Right := 4;
  PopulateTagBarTags(TagBarFilter);
  Inc(Y, 36);

  // Assign
  Lbl := TLabel.Create(ScrollBox);
  Lbl.Parent := ScrollBox;
  Lbl.Align := alTop;
  Lbl.Top := Y;
  Lbl.Caption := 'Assign (check + create):';
  Lbl.Font.Style := [fsBold];
  Lbl.BorderSpacing.Left := 8;
  Lbl.BorderSpacing.Top := 8;
  Lbl.BorderSpacing.Right := 4;
  Lbl.BorderSpacing.Bottom := 2;
  Inc(Y, 24);

  TagBarAssign := TPixieTagBar.Create(Self);
  TagBarAssign.Parent := ScrollBox;
  TagBarAssign.Align := alTop;
  TagBarAssign.Top := Y;
  TagBarAssign.Color := clWindow;
  TagBarAssign.ShowBorder := True;
  TagBarAssign.TagShape := tsRoundedRect;
  TagBarAssign.AutoHeight := True;
  TagBarAssign.Options := TagBarAssignOpts;
  TagBarAssign.BorderSpacing.Left := 4;
  TagBarAssign.BorderSpacing.Right := 4;
  PopulateTagBarTags(TagBarAssign);
  Inc(Y, 36);

  // Display
  Lbl := TLabel.Create(ScrollBox);
  Lbl.Parent := ScrollBox;
  Lbl.Align := alTop;
  Lbl.Top := Y;
  Lbl.Caption := 'Display (read-only, checked tags only):';
  Lbl.Font.Style := [fsBold];
  Lbl.BorderSpacing.Left := 8;
  Lbl.BorderSpacing.Top := 8;
  Lbl.BorderSpacing.Right := 4;
  Lbl.BorderSpacing.Bottom := 2;
  Inc(Y, 24);

  TagBarDisplay := TPixieTagBar.Create(Self);
  TagBarDisplay.Parent := ScrollBox;
  TagBarDisplay.Align := alTop;
  TagBarDisplay.Top := Y;
  TagBarDisplay.Color := clWindow;
  TagBarDisplay.ShowBorder := True;
  TagBarDisplay.TagShape := tsRoundedRect;
  TagBarDisplay.AutoHeight := True;
  TagBarDisplay.Options := TagBarDisplayOpts;
  TagBarDisplay.BorderSpacing.Left := 4;
  TagBarDisplay.BorderSpacing.Right := 4;
  PopulateTagBarTags(TagBarDisplay);
  TagBarDisplay.CheckTag(TagBarDisplay.GetTag(0).ID, True);
  TagBarDisplay.CheckTag(TagBarDisplay.GetTag(2).ID, True);
  TagBarDisplay.CheckTag(TagBarDisplay.GetTag(4).ID, True);
  Inc(Y, 36);

  Lbl := TLabel.Create(ScrollBox);
  Lbl.Parent := ScrollBox;
  Lbl.Align := alTop;
  Lbl.Top := Y;
  Lbl.Caption := 'Settings (always checked, colour swatches, no toggle):';
  Lbl.Font.Style := [fsBold];
  Lbl.BorderSpacing.Left := 8;
  Lbl.BorderSpacing.Top := 8;
  Lbl.BorderSpacing.Right := 4;
  Lbl.BorderSpacing.Bottom := 2;
  Inc(Y, 24);

  TagBarSettings := TPixieTagBar.Create(Self);
  TagBarSettings.Parent := ScrollBox;
  TagBarSettings.Align := alTop;
  TagBarSettings.Top := Y;
  TagBarSettings.Color := clWindow;
  TagBarSettings.ShowBorder := True;
  TagBarSettings.TagShape := tsRoundedRect;
  TagBarSettings.AutoHeight := True;
  TagBarSettings.Options := TagBarSettingsOpts;
  TagBarSettings.BorderSpacing.Left := 4;
  TagBarSettings.BorderSpacing.Right := 4;
  PopulateTagBarTagsPlain(TagBarSettings);
end;

procedure TMainForm.PopulateTagBarTags(Bar: TPixieTagBar);
begin
  Bar.AddTag('Env:Production', TPixieWebColor.Create($F4, $43, $36), '🔴', '');
  Bar.AddTag('Env:Staging',    TPixieWebColor.Create($FF, $98, $00), '🟠', '');
  Bar.AddTag('DC:London',      TPixieWebColor.Create($21, $96, $F3), '🌍', '');
  Bar.AddTag('DC:New York',    TPixieWebColor.Create($4C, $AF, $50), '📍', '');
  Bar.AddTag('Router',         TPixieWebColor.Create($9C, $27, $B0));
  Bar.AddTag('Server',         TPixieWebColor.Create($00, $96, $88), '🖥', '');
  Bar.AddTag('Cloud',          TPixieWebColor.Create($79, $55, $48), '☁', '');
  Bar.AddTag('Critical',       TPixieWebColor.Create($60, $7D, $8B), '⚠', '');
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
  AH: Boolean;
begin
  AH := ChkTagAutoHeight.Checked;
  TagBarEditor.AutoHeight := AH;
  TagBarFilter.AutoHeight := AH;
  TagBarAssign.AutoHeight := AH;
  TagBarDisplay.AutoHeight := AH;
  TagBarSettings.AutoHeight := AH;
end;

// ---------------------------------------------------------------------------
// HTTP fetching
// ---------------------------------------------------------------------------

procedure TMainForm.FetchUrl(Sender: TObject; const AUrl: string;
  Stream: TStream; var Success: Boolean);
var
  Client: TFPHTTPClient;
  T: Int64;
begin
  T := StopwatchNow;
  Client := TFPHTTPClient.Create(nil);
  try
    Client.AllowRedirect := True;
    Client.AddHeader('User-Agent', 'Pixie/1.0');
    try
      Client.Get(AUrl, Stream);
      Success := True;
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
  Client: TFPHTTPClient;
  HtmlText: string;
  ActualUrl: string;
begin
  ActualUrl := Url;
  if (Pos('http://', LowerCase(ActualUrl)) <> 1) and
     (Pos('https://', LowerCase(ActualUrl)) <> 1) then
    ActualUrl := 'https://' + ActualUrl;

  Client := TFPHTTPClient.Create(nil);
  try
    Client.AllowRedirect := True;
    Client.AddHeader('User-Agent', 'Pixie/1.0');
    try
      HtmlText := Client.Get(ActualUrl);
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
        Pdf.BaseUrl := PixieHtmlView.BaseUrl;
        Pdf.OnFetchUrl := @FetchUrl;
        try
          Pdf.SaveToFile(PixieHtmlView.Lines.Text, Dlg.FileName);
          StatusBar.Panels[0].Text := 'PDF saved.';
        except
          on E: Exception do
            ShowMessage(E.ClassName + ' at ' +
              IntToHex({$IFDEF FPC}PtrUInt(ExceptAddr){$ELSE}0{$ENDIF}, 8) +
              ': ' + E.Message);
        end;
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
     (MessageDlg('Navigate to URL',
      PixieDemoNavigationWarning(UrlEdit.Text, LineEnding),
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
  // Resolve relative URLs against current base
  if (Pos('://', FullUrl) = 0) and (PixieHtmlView.BaseUrl <> '') then
    FullUrl := PixieResolveUrl(TPixieUrl.Create(PixieHtmlView.BaseUrl),
      TPixieUrl.Create(FullUrl)).Str;

  if (Pos('http://', LowerCase(FullUrl)) = 1) or
     (Pos('https://', LowerCase(FullUrl)) = 1) then
  begin
    if FNavWarningShown or
       (MessageDlg('Navigate to URL',
        PixieDemoNavigationWarning(FullUrl, LineEnding),
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
  {$ifdef windows}
  Freq: Int64;
  {$endif}
begin
  TotalMs := StopwatchElapsedMs(FParseStart);
  {$ifdef windows}
  QueryPerformanceFrequency(Freq);
  FetchMs := FFetchAccum * 1000.0 / Freq;
  {$else}
  FetchMs := FFetchAccum;
  {$endif}
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

// ---------------------------------------------------------------------------
// PaintBox tab
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
// SVG View tab
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

end.
