unit Pixie.Register.Delphi.FMX;

{$R Pixie.Icons.dcr}

interface

procedure Register;

implementation

uses
  Classes, Pixie.HtmlView.FMX, Pixie.PaintBox.FMX, Pixie.SvgView.FMX, Pixie.TagBar.FMX;

procedure Register;
begin
  RegisterComponents('Pixie',
    [TPixieHtmlView, TPixiePaintBox, TPixieSvgView, TPixieTagBar]);
end;

end.
