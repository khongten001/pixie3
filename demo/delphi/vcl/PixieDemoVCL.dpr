program PixieDemoVCL;

uses
  Vcl.Forms,
  PixieDemoMain in 'PixieDemoMain.pas' {MainForm};

{$R *.res}
{$R ..\..\resources\images.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
