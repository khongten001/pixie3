unit Pixie.Register.Lazarus;

{$MODE DELPHI}

{$R Pixie.IDE.Icons.res}

interface

procedure Register;

implementation

uses
  Classes, Pixie.HtmlView, Pixie.TagBar, Pixie.PaintBox, Pixie.SvgView;

procedure Register;
begin
  RegisterComponents('Pixie',
    [TPixieHtmlView, TPixieTagBar, TPixiePaintBox, TPixieSvgView]);
end;

end.
