unit Pixie.HtmlView.FMX;

// TPixieHtmlView — Delphi FMX visual component that renders HTML content
// using the Pixie engine with FireMonkey graphics. Enables cross-platform
// HTML rendering on Windows, macOS, iOS, and Android.

interface

uses
  System.Classes, System.SysUtils,
  Pixie.HtmlView.FMX.Base;

type
  { TPixieHtmlView }

  TPixieHtmlView = class(TPixieHtmlViewBase)
  public
    procedure LoadFromString(const AHtml: string;
      const ABaseUrl: string = '');
    procedure LoadFromFile(const AFileName: string;
      const ABaseUrl: string = '');
    procedure LoadFromStream(AStream: TStream;
      const ABaseUrl: string = '');
  published
    property Lines: TStrings read GetLines write SetLines;
  end;

implementation

procedure TPixieHtmlView.LoadFromString(const AHtml: string;
  const ABaseUrl: string);
begin
  CoreLoadFromString(AHtml, ABaseUrl);
end;

procedure TPixieHtmlView.LoadFromFile(const AFileName: string;
  const ABaseUrl: string);
begin
  CoreLoadFromFile(AFileName, ABaseUrl);
end;

procedure TPixieHtmlView.LoadFromStream(AStream: TStream;
  const ABaseUrl: string);
begin
  CoreLoadFromStream(AStream, ABaseUrl);
end;

end.
