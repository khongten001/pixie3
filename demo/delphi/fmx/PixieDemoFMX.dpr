program PixieDemoFMX;

uses
  System.StartUpCopy,
  FMX.Forms,
  PixieDemoMain in 'PixieDemoMain.pas' {MainForm};

{$R *.res}
{$R ..\..\resources\images.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
