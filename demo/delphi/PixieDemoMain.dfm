object MainForm: TMainForm
  Left = 300
  Top = 100
  Caption = 'Pixie Demo (Delphi)'
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
  object UrlPanel: TPanel
    Left = 0
    Top = 0
    Width = 800
    Height = 36
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object BtnOpen: TButton
      AlignWithMargins = True
      Left = 4
      Top = 6
      Width = 130
      Height = 24
      Margins.Left = 4
      Margins.Top = 6
      Margins.Right = 0
      Margins.Bottom = 6
      Align = alLeft
      Caption = 'Load HTML from file'
      TabOrder = 0
      OnClick = BtnOpenClick
    end
    object BtnGo: TButton
      AlignWithMargins = True
      Left = 746
      Top = 6
      Width = 50
      Height = 24
      Margins.Left = 0
      Margins.Top = 6
      Margins.Right = 4
      Margins.Bottom = 6
      Align = alRight
      Caption = 'Go'
      TabOrder = 2
      OnClick = BtnGoClick
    end
    object UrlEdit: TEdit
      AlignWithMargins = True
      Left = 142
      Top = 6
      Width = 604
      Height = 24
      Margins.Left = 8
      Margins.Top = 6
      Margins.Right = 8
      Margins.Bottom = 6
      Align = alClient
      TabOrder = 1
      TextHint = '...or try a simple web-site here'
      OnKeyPress = UrlEditKeyPress
    end
  end
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
