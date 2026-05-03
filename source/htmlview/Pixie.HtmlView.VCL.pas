unit Pixie.HtmlView.VCL;

// TPixieHtmlView — Delphi VCL visual component that renders HTML content
// using the Pixie engine with Direct2D/DirectWrite graphics.

interface

uses
  System.Classes, System.SysUtils,
  Pixie.HtmlView.VCL.Base;

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
