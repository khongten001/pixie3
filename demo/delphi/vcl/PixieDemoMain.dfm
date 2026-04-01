object MainForm: TMainForm
  Left = 300
  Top = 100
  Caption = 'Pixie Demo (Delphi VCL)'
  ClientHeight = 600
  ClientWidth = 800
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 15
  object StatusBar: TStatusBar
    Left = 0
    Top = 577
    Width = 800
    Height = 23
    Panels = <
      item
        Text = 'Parse: '#8212
        Width = 200
      end
      item
        Text = 'Paint: '#8212
        Width = 200
      end>
  end
end
