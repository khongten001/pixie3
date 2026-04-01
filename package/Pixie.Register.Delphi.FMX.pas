unit Pixie.Register.Delphi.FMX;

{$R Pixie.Icons.dcr}

interface

procedure Register;

implementation

uses
  Classes, Pixie.HtmlView.FMX, Pixie.SvgView.FMX;

procedure Register;
begin
  RegisterComponents('Pixie', [TPixieHtmlView, TPixieSvgView]);
end;

end.
