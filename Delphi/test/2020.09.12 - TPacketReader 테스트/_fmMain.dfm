object fmMain: TfmMain
  Left = 0
  Top = 0
  ClientHeight = 411
  ClientWidth = 852
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 13
  object moResult: TMemo
    Left = 0
    Top = 41
    Width = 852
    Height = 370
    Align = alClient
    TabOrder = 0
  end
  object Panel1: TPanel
    Left = 0
    Top = 0
    Width = 852
    Height = 41
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 1
    object btStart: TButton
      Left = 8
      Top = 9
      Width = 75
      Height = 25
      Caption = 'Start 1'
      TabOrder = 0
      OnClick = btStartClick
    end
    object Button1: TButton
      Left = 89
      Top = 9
      Width = 75
      Height = 25
      Caption = 'Start 2'
      TabOrder = 1
    end
  end
end
