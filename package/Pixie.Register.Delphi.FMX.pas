unit Pixie.Register.Delphi.FMX;

{$R Pixie.Icons.dcr}

interface

procedure Register;

implementation

uses
  Classes, Pixie.HtmlView.FMX;

procedure Register;
begin
  RegisterComponents('Additional', [TPixieHtmlView]);
end;

end.
