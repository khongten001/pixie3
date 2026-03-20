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
  RegisterComponents('Misc', [TPixieHtmlView]);
end;

end.
