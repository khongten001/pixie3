unit Pixie.Register.Delphi.VCL;

{$R Pixie.Icons.dcr}

interface

procedure Register;

implementation

uses
  Classes, Pixie.HtmlView.VCL, Pixie.SvgView.VCL;

procedure Register;
begin
  RegisterComponents('Pixie', [TPixieHtmlView, TPixieSvgView]);
end;

end.
