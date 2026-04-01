unit Pixie.Register.Lazarus;

{$MODE DELPHI}

{$R Pixie.IDE.Icons.res}

interface

procedure Register;

implementation

uses
  Classes, Pixie.HtmlView, Pixie.SvgView;

procedure Register;
begin
  RegisterComponents('Pixie', [TPixieHtmlView, TPixieSvgView]);
end;

end.
