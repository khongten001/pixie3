unit PixieDemoMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ComCtrls, StdCtrls,
  ExtCtrls, Buttons,
  {$ifdef windows}Windows,{$endif}
  fphttpclient, opensslsockets,
  Pixie.HtmlView, Pixie.NativeContainer, Pixie.Url,
  Pixie.Element, Pixie.Document, Pixie.PdfExport;

type
  TMainForm = class(TForm)
    BtnOpen: TSpeedButton;
    BtnSavePdf: TSpeedButton;
    BtnGo: TButton;
    UrlEdit: TEdit;
    UrlPanel: TPanel;
    StatusBar: TStatusBar;
    PixieHtmlView: TPixieHtmlView;
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
  private
    FCardCount: Integer;
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
  ImgPath := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'resources' + PathDelim;
  SvgPath := ImgPath;
  Randomize;
  FCardCount := 0;

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

  PixieHtmlView.LoadHtml(
    '<html><head><style>' +
    'a { color: #0066cc; text-decoration: underline; cursor: pointer; }' +
    'a:hover { color: #ff4400; }' +
    'a:active { color: #cc0000; }' +
    '.btn { display: inline-block; padding: 8px 20px; margin: 4px; ' +
      'border-radius: 6px; cursor: pointer; font-weight: bold; color: white; }' +
    '.btn-blue { background: #336699; }' +
    '.btn-blue:hover { background: #4488bb; }' +
    '.btn-blue:active { background: #224466; }' +
    '.btn-green { background: #339944; }' +
    '.btn-green:hover { background: #44bb55; }' +
    '.btn-green:active { background: #226633; }' +
    '.btn-red { background: #cc3333; }' +
    '.btn-red:hover { background: #ee5555; }' +
    '.btn-red:active { background: #992222; }' +
    '.hover-row { padding: 6px 10px; margin: 2px 0; border-radius: 4px; }' +
    '.hover-row:hover { background: #e8f0fe; color: #1a73e8; }' +
    '.focus-input { border: 2px solid #ccc; border-radius: 6px; padding: 4px 8px; background-color: #fff; }' +
    '.focus-input:focus { border-color: #9b59b6; background-color: #f9f0ff; }' +
    '</style></head>' +
    '<body style="font-family: Segoe UI, Arial, sans-serif; margin: 16px; color: #222;">' +

    // ---- Header ----
    '<h1 style="color: #336699; border-bottom: 2px solid #336699; padding-bottom: 6px;">' +
    'Pixie HTML Rendering Engine &#x2B50;</h1>' +

    // ---- Intro text with logo ----
    '<div style="margin-bottom: 12px;">' +
    '<img src="@PIXIELOGO" width="96" height="96" ' +
      'style="float: left; margin: 0 14px 8px 0;">' +
    '<p style="color: #555;">The <b>Pixie</b> engine is a complete HTML/CSS rendering implementation ' +
    'in <i>Free Pascal &amp; Delphi</i>. It supports tables, lists, flexbox, CSS grid, ' +
    'gradients, images and more.</p>' +
    '<p style="color: #555;">Движок <b>Pixie</b> — это полная реализация рендеринга HTML/CSS ' +
    'на <i>Free Pascal &amp; Delphi</i>. Поддерживаются таблицы, списки, флексбокс, CSS-гриды, ' +
    'градиенты, изображения и многое другое.</p>' +
    '</div>' +
    '<div style="clear: both;"></div>' +

    // ---- Text styling ----
    '<h2 style="color: #994422;">Text Styling</h2>' +
    '<p><b>Bold text</b>, <i>italic text</i>, <u>underlined</u>, ' +
    '<s>Chromium required</s>, and <b><i>bold italic</i></b>. ' +
    'Sizes: <span style="font-size: 10px;">fine print</span>, normal, ' +
    '<span style="font-size: 22px;">LOUD</span>. ' +
    'Colours: <span style="color: #c00;">stop</span>, ' +
    '<span style="color: #070;">go</span>, ' +
    '<span style="color: #00c;">404</span>.</p>' +

    // ---- Borders and backgrounds ----
    '<h2 style="color: #994422;">Borders &amp; Backgrounds</h2>' +
    '<div style="display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 12px;">' +
      '<div style="padding: 10px; border: 2px solid #c44; border-radius: 8px; ' +
        'background: #fff0f0; flex: 1;">Solid &amp; rounded, like a polite rectangle</div>' +
      '<div style="padding: 10px; border: 2px dashed #4a4; ' +
        'background: #f0fff0; flex: 1;">Dashed, like cutting instructions</div>' +
      '<div style="padding: 10px; border: 3px double #44c; ' +
        'background: #f0f0ff; flex: 1;">Double, for extra importance</div>' +
    '</div>' +

    // ---- Gradients ----
    '<h2 style="color: #994422;">Gradients</h2>' +
    '<div style="display: flex; gap: 10px; margin-bottom: 12px;">' +
      '<div style="width: 150px; height: 60px; border-radius: 8px; ' +
        'background: linear-gradient(to right, #ff6b6b, #ffd93d, #6bcb77);"></div>' +
      '<div style="width: 150px; height: 60px; border-radius: 8px; ' +
        'background: linear-gradient(135deg, #667eea, #764ba2);"></div>' +
      '<div style="width: 150px; height: 60px; border-radius: 50%; ' +
        'background: radial-gradient(circle, #fff, #0077cc);"></div>' +
    '</div>' +

    // ---- Images ----
    '<h2 style="color: #994422;">Images</h2>' +
    '<p>' +
      '<img src="' + ImgPath + 'firefox.png" style="vertical-align: middle;"> Firefox ' +
      '<img src="' + ImgPath + 'chrome.png" style="vertical-align: middle;"> Chrome (alpha) ' +
      '<img src="' + ImgPath + 'opera.png" style="vertical-align: middle;"> Opera ' +
      '<img src="' + ImgPath + 'steam.png" style="vertical-align: middle;"> Steam' +
    '</p>' +
    '<p>SVG images (Direct2D native): ' +
      '<img src="' + SvgPath + 'about.svg" width="48" height="48" style="vertical-align: middle;"> ' +
      '<img src="' + SvgPath + 'copy_direct.svg" width="48" height="48" style="vertical-align: middle;"> ' +
      '<img src="' + SvgPath + 'export.svg" width="48" height="48" style="vertical-align: middle;"> ' +
      '<img src="' + SvgPath + 'edit_image.svg" width="48" height="48" style="vertical-align: middle;">' +
    '</p>' +

    // ---- Stream-registered images ----
    '<h2 style="color: #994422;">Stream-Registered Images (#name)</h2>' +
    '<p>' +
      '<img src="#firefox" style="vertical-align: middle;"> Firefox (from stream) ' +
      '<img src="#chrome" style="vertical-align: middle;"> Chrome with alpha (from stream)' +
    '</p>' +

    // ---- Resource-embedded images ----
    '<h2 style="color: #994422;">Resource-Embedded Images (@resname)</h2>' +
    '<p>' +
      '<img src="@FIREFOX" style="vertical-align: middle;"> Firefox (from resource) ' +
      '<img src="@CHROME" style="vertical-align: middle;"> Chrome with alpha (from resource) ' +
      '<img src="@OPERA" style="vertical-align: middle;"> Opera (from resource) ' +
      '<img src="@STEAM" style="vertical-align: middle;"> Steam (from resource) ' +
      '<img src="@ABOUTSVG" width="48" height="48" style="vertical-align: middle;"> SVG (from resource)' +
    '</p>' +

    // ---- Inline base64 data URI ----
    '<h2 style="color: #994422;">Inline Data URI (base64)</h2>' +
    '<p>' +
      '<img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0' +
        'NAAAAQ0lEQVR4nGNgGNLg/0zj/9gw1Qwiy2BiDSPKUFINI2goVQ0k1zCcho4aOAgNHPzpkF' +
        'xD8RpGqqFEGcZAhMEkGzSoAAAomEQ/wkqkJQAAAABJRU5ErkJggg==" ' +
        'style="vertical-align: middle;"> ' +
      'Inline PNG (20x20 orange circle embedded as base64 in the HTML source)' +
    '</p>' +

    // ---- Table ----
    '<h2 style="color: #994422;">Table</h2>' +
    '<table style="border-collapse: collapse; width: 100%; margin-bottom: 12px;">' +
      '<tr style="background: #336699; color: white;">' +
        '<th style="padding: 8px; border: 1px solid #ccc;">Browser</th>' +
        '<th style="padding: 8px; border: 1px solid #ccc;">Engine</th>' +
        '<th style="padding: 8px; border: 1px solid #ccc;">Year</th>' +
      '</tr>' +
      '<tr style="background: #f9f9f9;">' +
        '<td style="padding: 8px; border: 1px solid #ddd;">Firefox</td>' +
        '<td style="padding: 8px; border: 1px solid #ddd;">Gecko</td>' +
        '<td style="padding: 8px; border: 1px solid #ddd;">2004</td>' +
      '</tr>' +
      '<tr>' +
        '<td style="padding: 8px; border: 1px solid #ddd;">Chrome</td>' +
        '<td style="padding: 8px; border: 1px solid #ddd;">Blink</td>' +
        '<td style="padding: 8px; border: 1px solid #ddd;">2008</td>' +
      '</tr>' +
      '<tr style="background: #f9f9f9;">' +
        '<td style="padding: 8px; border: 1px solid #ddd;" colspan="2">' +
          '<b>Pixie</b> — our engine</td>' +
        '<td style="padding: 8px; border: 1px solid #ddd;">2025</td>' +
      '</tr>' +
    '</table>' +

    // ---- Lists ----
    '<h2 style="color: #994422;">Lists</h2>' +
    '<div style="display: flex; gap: 30px;">' +
      '<div>' +
        '<ul>' +
          '<li>Write HTML renderer</li>' +
          '<li>Support CSS' +
            '<ul><li>Flexbox</li><li>Grid</li></ul>' +
          '</li>' +
          '<li>Skip JavaScript entirely</li>' +
        '</ul>' +
      '</div>' +
      '<div>' +
        '<ol>' +
          '<li>Parse HTML</li>' +
          '<li>Compute styles</li>' +
          '<li>Ship it</li>' +
        '</ol>' +
      '</div>' +
    '</div>' +

    // ---- Flexbox ----
    '<h2 style="color: #994422;">Flexbox</h2>' +
    '<div style="display: flex; gap: 8px; margin-bottom: 12px;">' +
      '<div style="flex: 1; padding: 12px; background: #e8f4fd; text-align: center; ' +
        'border-radius: 6px;">I flex</div>' +
      '<div style="flex: 2; padding: 12px; background: #fde8e8; text-align: center; ' +
        'border-radius: 6px;">I flex harder</div>' +
      '<div style="flex: 1; padding: 12px; background: #e8fde8; text-align: center; ' +
        'border-radius: 6px;">Me too</div>' +
    '</div>' +

    // ---- CSS Grid ----

    // 1. Equal columns
    '<h2 style="color: #994422;">CSS Grid: Equal Columns (1fr 1fr 1fr)</h2>' +
    '<div style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 8px; margin-bottom: 12px;">' +
      '<div style="padding: 14px; background: #e8f4fd; border-radius: 6px; text-align: center;">1fr</div>' +
      '<div style="padding: 14px; background: #fde8e8; border-radius: 6px; text-align: center;">1fr</div>' +
      '<div style="padding: 14px; background: #e8fde8; border-radius: 6px; text-align: center;">1fr</div>' +
    '</div>' +

    // 2. Mixed track sizes
    '<h2 style="color: #994422;">CSS Grid: Mixed Track Sizes (200px 1fr 2fr)</h2>' +
    '<div style="display: grid; grid-template-columns: 200px 1fr 2fr; gap: 8px; margin-bottom: 12px;">' +
      '<div style="padding: 14px; background: #336699; color: white; border-radius: 6px;">200px fixed</div>' +
      '<div style="padding: 14px; background: #dfe6e9; border-radius: 6px;">1fr</div>' +
      '<div style="padding: 14px; background: #b2bec3; border-radius: 6px;">2fr</div>' +
    '</div>' +

    // 3. Row & column gap
    '<h2 style="color: #994422;">CSS Grid: Row &amp; Column Gap</h2>' +
    '<div style="display: grid; grid-template-columns: 1fr 1fr 1fr; row-gap: 12px; column-gap: 24px; margin-bottom: 12px;">' +
      '<div style="padding: 10px; background: #ffeaa7; border-radius: 4px; text-align: center;">A</div>' +
      '<div style="padding: 10px; background: #fab1a0; border-radius: 4px; text-align: center;">B</div>' +
      '<div style="padding: 10px; background: #81ecec; border-radius: 4px; text-align: center;">C</div>' +
      '<div style="padding: 10px; background: #a29bfe; border-radius: 4px; text-align: center;">D</div>' +
      '<div style="padding: 10px; background: #55efc4; border-radius: 4px; text-align: center;">E</div>' +
      '<div style="padding: 10px; background: #fd79a8; border-radius: 4px; text-align: center;">F</div>' +
    '</div>' +

    // 4. Explicit placement
    '<h2 style="color: #994422;">CSS Grid: Explicit Placement</h2>' +
    '<div style="display: grid; grid-template-columns: 100px 100px 100px 100px; ' +
      'grid-template-rows: 60px 60px 60px; gap: 4px; background: #f0f0f0; padding: 4px; ' +
      'border-radius: 6px; margin-bottom: 12px;">' +
      '<div style="grid-column: 1 / 3; grid-row: 1 / 2; background: #e17055; ' +
        'border-radius: 4px; padding: 8px; color: white;">col 1-2, row 1</div>' +
      '<div style="grid-column: 3 / 5; grid-row: 1 / 2; background: #00b894; ' +
        'border-radius: 4px; padding: 8px; color: white;">col 3-4, row 1</div>' +
      '<div style="grid-column: 1 / 2; grid-row: 2 / 4; background: #0984e3; ' +
        'border-radius: 4px; padding: 8px; color: white;">col 1, row 2-3</div>' +
      '<div style="grid-column: 2 / 4; grid-row: 2 / 3; background: #6c5ce7; ' +
        'border-radius: 4px; padding: 8px; color: white;">col 2-3, row 2</div>' +
      '<div style="grid-column: 4 / 5; grid-row: 2 / 3; background: #fdcb6e; ' +
        'border-radius: 4px; padding: 8px;">col 4, row 2</div>' +
      '<div style="grid-column: 2 / 5; grid-row: 3 / 4; background: #e84393; ' +
        'border-radius: 4px; padding: 8px; color: white;">col 2-4, row 3</div>' +
    '</div>' +

    // 5. Column spanning
    '<h2 style="color: #994422;">CSS Grid: Column Spanning (span N)</h2>' +
    '<div style="display: grid; grid-template-columns: 1fr 1fr 1fr 1fr; gap: 6px; margin-bottom: 12px;">' +
      '<div style="grid-column: span 4; padding: 12px; ' +
        'background: linear-gradient(to right, #667eea, #764ba2); ' +
        'color: white; border-radius: 6px; text-align: center;">Full width (span 4)</div>' +
      '<div style="grid-column: span 2; padding: 10px; background: #dfe6e9; ' +
        'border-radius: 4px; text-align: center;">Span 2</div>' +
      '<div style="grid-column: span 2; padding: 10px; background: #b2bec3; ' +
        'border-radius: 4px; text-align: center;">Span 2</div>' +
      '<div style="padding: 10px; background: #ffeaa7; border-radius: 4px; text-align: center;">1</div>' +
      '<div style="grid-column: span 2; padding: 10px; background: #55efc4; ' +
        'border-radius: 4px; text-align: center;">Span 2</div>' +
      '<div style="padding: 10px; background: #fab1a0; border-radius: 4px; text-align: center;">1</div>' +
    '</div>' +

    // 6. Alignment
    '<h2 style="color: #994422;">CSS Grid: Alignment</h2>' +
    '<div style="display: grid; grid-template-columns: 120px 120px 120px; ' +
      'grid-template-rows: 80px 80px; gap: 4px; justify-items: center; align-items: center; ' +
      'background: #f5f5f5; padding: 4px; border-radius: 6px; margin-bottom: 12px;">' +
      '<div style="width: 60px; height: 40px; background: #e17055; border-radius: 4px;"></div>' +
      '<div style="width: 60px; height: 40px; background: #00b894; border-radius: 4px;"></div>' +
      '<div style="width: 60px; height: 40px; background: #0984e3; border-radius: 4px;"></div>' +
      '<div style="width: 60px; height: 40px; background: #6c5ce7; border-radius: 4px;"></div>' +
      '<div style="width: 60px; height: 40px; background: #fdcb6e; border-radius: 4px;"></div>' +
      '<div style="width: 60px; height: 40px; background: #e84393; border-radius: 4px;"></div>' +
    '</div>' +

    // 6b. Per-item overrides
    '<h2 style="color: #994422;">CSS Grid: Per-Item Alignment Overrides</h2>' +
    '<div style="display: grid; grid-template-columns: 150px 150px 150px; ' +
      'grid-template-rows: 80px 80px; gap: 4px; justify-items: center; align-items: center; ' +
      'background: #f5f5f5; padding: 4px; border-radius: 6px; margin-bottom: 12px;">' +
      '<div style="width: 60px; height: 40px; background: #e17055; border-radius: 4px; ' +
        'justify-self: start;"></div>' +
      '<div style="width: 60px; height: 40px; background: #00b894; border-radius: 4px;"></div>' +
      '<div style="width: 60px; height: 40px; background: #0984e3; border-radius: 4px; ' +
        'justify-self: end;"></div>' +
      '<div style="width: 60px; height: 40px; background: #6c5ce7; border-radius: 4px; ' +
        'align-self: start;"></div>' +
      '<div style="width: 60px; height: 40px; background: #fdcb6e; border-radius: 4px; ' +
        'align-self: end;"></div>' +
      '<div style="width: 60px; height: 40px; background: #e84393; border-radius: 4px; ' +
        'justify-self: end; align-self: end;"></div>' +
    '</div>' +

    // 7. Auto-placement flow
    '<h2 style="color: #994422;">CSS Grid: Auto-Placement Flow</h2>' +
    '<div style="display: grid; grid-template-columns: 1fr 1fr 1fr 1fr 1fr; gap: 6px; margin-bottom: 12px;">' +
      '<div style="padding: 10px; background: #ff7675; border-radius: 4px; text-align: center; color: white;">1</div>' +
      '<div style="padding: 10px; background: #74b9ff; border-radius: 4px; text-align: center; color: white;">2</div>' +
      '<div style="padding: 10px; background: #a29bfe; border-radius: 4px; text-align: center; color: white;">3</div>' +
      '<div style="padding: 10px; background: #fd79a8; border-radius: 4px; text-align: center; color: white;">4</div>' +
      '<div style="padding: 10px; background: #00cec9; border-radius: 4px; text-align: center; color: white;">5</div>' +
      '<div style="padding: 10px; background: #ffeaa7; border-radius: 4px; text-align: center;">6</div>' +
      '<div style="padding: 10px; background: #55efc4; border-radius: 4px; text-align: center;">7</div>' +
      '<div style="padding: 10px; background: #dfe6e9; border-radius: 4px; text-align: center;">8</div>' +
      '<div style="padding: 10px; background: #b2bec3; border-radius: 4px; text-align: center;">9</div>' +
    '</div>' +

    // 8. Holy grail layout
    '<h2 style="color: #994422;">CSS Grid: Holy Grail Layout</h2>' +
    '<div style="display: grid; grid-template-columns: 180px 1fr 180px; ' +
      'grid-template-rows: auto 1fr auto; gap: 8px; min-height: 300px; margin-bottom: 12px;">' +
      '<div style="grid-column: 1 / 4; padding: 14px; background: #2d3436; color: white; ' +
        'border-radius: 6px 6px 0 0; text-align: center; font-weight: bold;">Header (the important bit)</div>' +
      '<div style="padding: 14px; background: #dfe6e9; border-radius: 0 0 0 6px;">Left sidebar (ads go here)</div>' +
      '<div style="padding: 14px; background: #f5f5f5;">' +
        '<p style="margin-bottom: 8px;">Main content area. This column uses <b>1fr</b> to claim all ' +
          'remaining space, like a cat on a keyboard.</p>' +
        '<p>No floats were harmed in the making of this layout.</p>' +
      '</div>' +
      '<div style="padding: 14px; background: #dfe6e9; border-radius: 0 0 6px 0;">Right sidebar (more ads)</div>' +
      '<div style="grid-column: 1 / 4; padding: 10px; background: #636e72; color: white; ' +
        'border-radius: 0 0 6px 6px; text-align: center; font-size: 12px;">Footer &copy; 2025 &mdash; no cookies, we promise</div>' +
    '</div>' +

    // ---- Positioned box ----
    '<div style="position: relative; height: 60px; background: #f5f5f5; ' +
      'border: 1px solid #ddd; border-radius: 4px; margin-bottom: 12px;">' +
      '<div style="position: absolute; top: 10px; left: 10px; padding: 4px 10px; ' +
        'background: #336699; color: white; border-radius: 4px;">I live top-left</div>' +
      '<div style="position: absolute; bottom: 10px; right: 10px; padding: 4px 10px; ' +
        'background: #993366; color: white; border-radius: 4px;">And I live bottom-right</div>' +
    '</div>' +

    // ---- Opacity ----
    '<h2 style="color: #994422;">Opacity</h2>' +
    '<div style="display: flex; gap: 10px; margin-bottom: 12px;">' +
      '<div style="padding: 14px; background: #336699; color: white; border-radius: 6px; ' +
        'text-align: center; opacity: 1.0;">100%</div>' +
      '<div style="padding: 14px; background: #336699; color: white; border-radius: 6px; ' +
        'text-align: center; opacity: 0.75;">75%</div>' +
      '<div style="padding: 14px; background: #336699; color: white; border-radius: 6px; ' +
        'text-align: center; opacity: 0.5;">50%</div>' +
      '<div style="padding: 14px; background: #336699; color: white; border-radius: 6px; ' +
        'text-align: center; opacity: 0.25;">25%</div>' +
      '<div style="padding: 14px; background: #336699; color: white; border-radius: 6px; ' +
        'text-align: center; opacity: 0.1;">10%</div>' +
    '</div>' +
    '<div style="position: relative; height: 80px; margin-bottom: 12px;">' +
      '<div style="position: absolute; top: 0; left: 0; width: 200px; height: 60px; ' +
        'background: #cc3333; border-radius: 6px; padding: 8px; color: white;">Red layer (below)</div>' +
      '<div style="position: absolute; top: 20px; left: 80px; width: 200px; height: 60px; ' +
        'background: #3366cc; border-radius: 6px; padding: 8px; color: white; opacity: 0.6;">' +
        'Blue layer (slightly shy)</div>' +
    '</div>' +

    // ---- Interactive: hover buttons, links ----
    '<h2 style="color: #994422;">Interactive</h2>' +
    '<p>These buttons test the <b>DOM Mutation API</b> &mdash; click them:</p>' +
    '<div style="margin-bottom: 8px;">' +
      '<span id="btn-blue" class="btn btn-blue">Add Card</span>' +
      '<span id="btn-green" class="btn btn-green">Shuffle Colours</span>' +
      '<span id="btn-red" class="btn btn-red">Remove Last</span>' +
    '</div>' +
    '<p style="font-size: 12px; color: #777; margin-bottom: 8px;">' +
      '<b>Add Card</b> &mdash; CreateElement + SetInnerHtml + AppendChild &bull; ' +
      '<b>Shuffle Colours</b> &mdash; QuerySelectorAll + SetAttr &bull; ' +
      '<b>Remove Last</b> &mdash; RemoveElement' +
    '</p>' +
    '<div id="playground"></div>' +
    '<p>Links &mdash; hover to change colour, click to open:</p>' +
    '<p>' +
      '<a href="https://www.softperfect.com">SoftPerfect Website</a> &bull; ' +
      '<a href="https://www.freepascal.org">Free Pascal</a> &bull; ' +
      '<a href="https://wiki.lazarus.freepascal.org">Lazarus Wiki</a>' +
    '</p>' +
    '<p>Hover list items:</p>' +
    '<div style="max-width: 300px;">' +
      '<div id="item-1" class="hover-row">Hover me gently</div>' +
      '<div id="item-2" class="hover-row">I change colour on hover</div>' +
      '<div id="item-3" class="hover-row">Me too, it''s a CSS thing</div>' +
    '</div>' +

    // ---- Form controls ----
    '<h2 style="color: #994422;">Button Styles</h2>' +

    '<div style="margin-bottom: 16px;">' +
      '<button>Do Nothing</button> ' +
      '<button>Also Nothing</button> ' +
      '<button disabled>Nope</button>' +
    '</div>' +

    '<div style="margin-bottom: 16px;">' +
      '<button style="padding: 6px 20px;">Extra Comfy</button> ' +
      '<button style="font-size: 16px; padding: 8px 24px;">Can''t Miss Me</button>' +
    '</div>' +

    '<div style="margin-bottom: 16px;">' +
      '<button style="background-color: #2ecc71; border: 2px solid #27ae60; color: #fff; ' +
        'border-radius: 8px; padding: 6px 20px;">Green</button> ' +
      '<button style="background-color: #e74c3c; border: 2px solid #c0392b; color: #fff; ' +
        'border-radius: 8px; padding: 6px 20px;">Red</button> ' +
      '<button style="background-color: #f39c12; border: 2px solid #e67e22; color: #fff; ' +
        'border-radius: 20px; padding: 6px 24px;">Pill Shape</button> ' +
      '<button style="background-color: #fff; border: 1px solid #bbb; color: #333; ' +
        'border-radius: 3px; padding: 6px 20px;">Outline</button> ' +
      '<button style="background-color: #34495e; border: none; color: #ecf0f1; ' +
        'border-radius: 0; padding: 8px 20px; font-size: 13px;">Square Dark</button>' +
    '</div>' +

    '<h2 style="color: #994422;">Alongside Checkboxes and Radios</h2>' +

    '<div style="margin-bottom: 16px;">' +
      '<label><input type="checkbox"> I have read the terms (nobody does)</label> ' +
      '<button>Submit</button>' +
    '</div>' +

    '<div style="margin-bottom: 16px;">' +
      '<label><input type="radio" name="opt" checked> Tabs</label> ' +
      '<label><input type="radio" name="opt"> Spaces</label> ' +
      '<button>Start Flame War</button>' +
    '</div>' +

    // ---- Text Inputs (in a table for label alignment + in-table test) ----
    '<h2 style="color: #994422;">Text Inputs</h2>' +

    '<table style="border-collapse: collapse; margin-bottom: 16px;">' +
      '<tr><td style="padding: 4px 8px 4px 0;">Text:</td>' +
        '<td style="padding: 4px 0;"><input type="text" value="Hello, world!" placeholder="Type here..." size="30"></td></tr>' +
      '<tr><td style="padding: 4px 8px 4px 0;">Password:</td>' +
        '<td style="padding: 4px 0;"><input type="password" value="secret" size="30"></td></tr>' +
      '<tr><td style="padding: 4px 8px 4px 0;">Placeholder:</td>' +
        '<td style="padding: 4px 0;"><input type="text" placeholder="Enter your name..." size="30"></td></tr>' +
      '<tr><td style="padding: 4px 8px 4px 0;">Read-only:</td>' +
        '<td style="padding: 4px 0;"><input type="text" value="Cannot edit this" readonly size="30"></td></tr>' +
      '<tr><td style="padding: 4px 8px 4px 0;">Disabled:</td>' +
        '<td style="padding: 4px 0;"><input type="text" value="Disabled field" disabled size="30"></td></tr>' +
      '<tr><td style="padding: 4px 8px 4px 0;">Max length (5):</td>' +
        '<td style="padding: 4px 0;"><input type="text" maxlength="5" size="30" placeholder="5 chars max"></td></tr>' +
      '<tr><td style="padding: 4px 8px 4px 0;">Large font:</td>' +
        '<td style="padding: 4px 0;"><input type="text" size="30" value="Bigger text" ' +
          'style="font-size: 18px; padding: 6px 8px;"></td></tr>' +
      '<tr><td style="padding: 4px 8px 4px 0;">Styled font:</td>' +
        '<td style="padding: 4px 0;"><input type="text" size="30" value="Blue monospace" ' +
          'style="font-family: Consolas, monospace; color: #06c; padding: 4px 8px;"></td></tr>' +
      '<tr><td style="padding: 4px 8px 4px 0;">Green border:</td>' +
        '<td style="padding: 4px 0;"><input type="text" size="30" value="Nature theme" ' +
          'style="border: 2px solid #2ecc71; border-radius: 8px; padding: 4px 8px;"></td></tr>' +
      '<tr><td style="padding: 4px 8px 4px 0;">Dark theme:</td>' +
        '<td style="padding: 4px 0;"><input type="text" size="30" value="Dark input" ' +
          'style="background-color: #2c3e50; border: 1px solid #4a6278; color: #ecf0f1; ' +
          'border-radius: 4px; padding: 5px 8px;"></td></tr>' +
      '<tr><td style="padding: 4px 8px 4px 0;">No radius:</td>' +
        '<td style="padding: 4px 0;"><input type="text" size="30" value="Sharp corners" ' +
          'style="border: 2px solid #e74c3c; border-radius: 0; padding: 4px 8px;"></td></tr>' +
      '<tr><td style="padding: 4px 8px 4px 0;">:focus CSS:</td>' +
        '<td style="padding: 4px 0;"><input type="text" class="focus-input" size="30" ' +
          'value="Click me - border turns purple" placeholder="Focus to change style"></td></tr>' +
    '</table>' +

    '<h2 style="color: #994422;">Textarea</h2>' +

    '<table style="border-collapse: collapse; margin-bottom: 16px;">' +
      '<tr style="vertical-align: top;">' +
        '<td style="padding: 0 16px 0 0;">' +
          '<div style="margin-bottom: 4px; font-weight: bold; font-size: 13px; color: #555;">Editable</div>' +
          '<textarea rows="4" cols="35">Dear diary,' + #10 +
          'Today I rendered HTML without a browser.' + #10 +
          'It was glorious.</textarea>' +
        '</td>' +
        '<td style="padding: 0 16px 0 0;">' +
          '<div style="margin-bottom: 4px; font-weight: bold; font-size: 13px; color: #555;">With placeholder</div>' +
          '<textarea rows="4" cols="35" placeholder="Write a comment..."></textarea>' +
        '</td>' +
      '</tr>' +
    '</table>' +

    // ---- Footer ----
    '<hr style="border: none; border-top: 1px solid #ccc; margin: 16px 0;">' +
    '<p style="color: #999; font-size: 12px; text-align: center;">' +
      'Pixie HTML Engine &copy; 2025 &mdash; No Electron was harmed in the making of this demo &#x1F308;</p>' +

    '</body></html>',
    ImgPath);
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
  PixieHtmlView.LoadHtml(HtmlText, ActualUrl);
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
        try
          Pdf.SaveToFile(PixieHtmlView.Html.Text, Dlg.FileName);
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
  HtmlText: string;
  F: TStringList;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Filter := 'HTML files (*.html;*.htm)|*.html;*.htm|All files (*.*)|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if Dlg.Execute then
    begin
      F := TStringList.Create;
      try
        F.LoadFromFile(Dlg.FileName);
        HtmlText := F.Text;
      finally
        F.Free;
      end;
      UrlEdit.Text := '';
      PixieHtmlView.LoadHtml(HtmlText, ExtractFilePath(Dlg.FileName));
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
      'You are about to navigate to:' + LineEnding + LineEnding +
      UrlEdit.Text + LineEnding + LineEnding +
      'Please note that Pixie is a lightweight HTML/CSS rendering ' +
      'engine designed for rich content display, not a full web browser. ' +
      'Complex web pages may render incorrectly or incompletely.' + LineEnding + LineEnding +
      'Continue?',
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
        'You are about to navigate to:' + LineEnding + LineEnding +
        FullUrl + LineEnding + LineEnding +
        'Please note that Pixie is a lightweight HTML/CSS rendering ' +
        'engine designed for rich content display, not a full web browser. ' +
        'Complex web pages may render incorrectly or incompletely.' + LineEnding + LineEnding +
        'Continue?',
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
const
  CardColors: array[0..5] of string = (
    '#e8f4fd', '#fde8e8', '#e8fde8', '#fff3e0', '#f3e5f5', '#e0f7fa');
  CardBorders: array[0..5] of string = (
    '#90caf9', '#ef9a9a', '#a5d6a7', '#ffcc80', '#ce93d8', '#80deea');
  BtnColors: array[0..7] of string = (
    '#336699', '#993366', '#339944', '#cc6633',
    '#664499', '#cc3333', '#337799', '#996633');
var
  PixEl: TPixieElement;
  ElId: string;
  Doc: TPixieDocument;
  Playground, NewEl, LastChild: TPixieElement;
  Items: TPixieElementList;
  I, Idx: Integer;
begin
  Result := False;
  if not (El is TPixieElement) then
    Exit;

  PixEl := TPixieElement(El);
  ElId := PixEl.GetAttr('id');
  Doc := PixieHtmlView.Document;

  if (Doc <> nil) and (ElId = 'btn-blue') then
  begin
    // Add Card: CreateElement + SetInnerHtml + AppendChild
    Playground := Doc.GetElementById('playground');
    if Playground <> nil then
    begin
      Inc(FCardCount);
      Idx := (FCardCount - 1) mod Length(CardColors);
      NewEl := Doc.CreateElement('div', nil);
      NewEl.SetAttr('class', 'card');
      NewEl.SetAttr('style',
        'padding: 10px; margin-top: 6px; border-radius: 6px; ' +
        'border: 1px solid ' + CardBorders[Idx] + '; ' +
        'background: ' + CardColors[Idx] + ';');
      Doc.BeginUpdate;
      try
        Doc.SetInnerHtml(NewEl,
          '<b>Card #' + IntToStr(FCardCount) + '</b> &mdash; ' +
          'added via CreateElement + SetInnerHtml + AppendChild');
        Playground.AppendChild(NewEl);
      finally
        Doc.EndUpdate;
      end;
    end;
    Result := True;
  end
  else if (Doc <> nil) and (ElId = 'btn-green') then
  begin
    // Shuffle Colours: QuerySelectorAll + SetAttr
    Items := Doc.QuerySelectorAll('#playground > .card');
    try
      for I := 0 to Items.Count - 1 do
      begin
        Idx := Random(Length(CardColors));
        Items[I].SetAttr('style',
          'padding: 10px; margin-top: 6px; border-radius: 6px; ' +
          'border: 1px solid ' + CardBorders[Idx] + '; ' +
          'background: ' + CardColors[Idx] + ';');
      end;
      // Also randomise the three button colours
      for I := 0 to 2 do
      begin
        case I of
          0: NewEl := Doc.GetElementById('btn-blue');
          1: NewEl := Doc.GetElementById('btn-green');
          2: NewEl := Doc.GetElementById('btn-red');
        end;
        if NewEl <> nil then
        begin
          Idx := Random(Length(BtnColors));
          NewEl.SetAttr('style', 'background: ' + BtnColors[Idx] + ';');
        end;
      end;
    finally
      Items.Free;
    end;
    Doc.Changed;
    Result := True;
  end
  else if (Doc <> nil) and (ElId = 'btn-red') then
  begin
    // Remove Last: RemoveElement
    Playground := Doc.GetElementById('playground');
    if (Playground <> nil) and (Playground.Children.Count > 0) then
    begin
      LastChild := Playground.Children[Playground.Children.Count - 1];
      Doc.RemoveElement(LastChild);
    end;
    Result := True;
  end
  else if ElId <> '' then
  begin
    ShowMessage('Clicked: ' + ElId);
    Result := True;
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

end.
