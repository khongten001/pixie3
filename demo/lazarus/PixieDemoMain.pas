unit PixieDemoMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ComCtrls,
  StdCtrls, ExtCtrls, Buttons,
  {$ifdef windows}Windows,{$endif}
  fphttpclient, opensslsockets,
  Pixie.HtmlView, Pixie.NativeContainer, Pixie.Url,
  Pixie.Element, Pixie.Document, Pixie.PdfExport,
  Pixie.SvgView, Pixie.PaintBox, Pixie.DrawingCanvas,
  PixieDemoContent, PixieDemoPaintBox;

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
    procedure NavigateToUrl(const Url: string);
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
