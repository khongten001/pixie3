unit Pixie.Register.Delphi.VCL;

{$R Pixie.Icons.dcr}

interface

procedure Register;

implementation

uses
  Classes, Pixie.HtmlView.VCL, Pixie.PaintBox.VCL, Pixie.SvgView.VCL, Pixie.TagBar.VCL;

procedure Register;
begin
  RegisterComponents('Pixie',
    [TPixieHtmlView, TPixiePaintBox, TPixieSvgView, TPixieTagBar]);
end;

end.
