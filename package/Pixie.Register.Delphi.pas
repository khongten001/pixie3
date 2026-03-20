unit Pixie.Register.Delphi;

interface

procedure Register;

implementation

uses
  Classes, Pixie.HtmlView.VCL;

procedure Register;
begin
  RegisterComponents('Misc', [TPixieHtmlView]);
end;

end.
