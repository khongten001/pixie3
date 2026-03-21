unit Pixie.Register.Lazarus;

{$MODE DELPHI}

{$R Pixie.IDE.Icons.res}

interface

procedure Register;

implementation

uses
  Classes, Pixie.HtmlView;

procedure Register;
begin
  RegisterComponents('Additional', [TPixieHtmlView]);
end;

end.
