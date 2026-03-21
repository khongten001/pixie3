program PixieFmxDemo;

uses
  System.StartUpCopy,
  FMX.Forms,
  PixieFmxDemoMain in 'PixieFmxDemoMain.pas' {MainForm};

{$R *.res}
{$R ..\..\resources\images.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
