unit Pixie.Register.Delphi.VCL;

{$R Pixie.Icons.dcr}

interface

procedure Register;

implementation

uses
  Classes, Pixie.HtmlView.VCL;

procedure Register;
begin
  RegisterComponents('Additional', [TPixieHtmlView]);
end;

end.
