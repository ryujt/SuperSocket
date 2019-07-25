object fmMain: TfmMain
  Left = 0
  Top = 0
  Caption = 'fmMain'
  ClientHeight = 652
  ClientWidth = 822
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnClose = FormClose
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 13
  object Panel1: TPanel
    Left = 0
    Top = 0
    Width = 822
    Height = 41
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    ExplicitLeft = 148
    ExplicitTop = 132
    ExplicitWidth = 185
    object btConnect: TButton
      Left = 12
      Top = 9
      Width = 75
      Height = 25
      Caption = 'btConnect'
      TabOrder = 0
      OnClick = btConnectClick
    end
    object btDisconnect: TButton
      Left = 93
      Top = 9
      Width = 75
      Height = 25
      Caption = 'btDisconnect'
      TabOrder = 1
      OnClick = btDisconnectClick
    end
    object Button3: TButton
      Left = 174
      Top = 9
      Width = 75
      Height = 25
      Caption = 'btSend'
      TabOrder = 2
      OnClick = Button3Click
    end
    object Button4: TButton
      Left = 255
      Top = 9
      Width = 75
      Height = 25
      Caption = 'Button4'
      TabOrder = 3
    end
  end
  object moMsg: TMemo
    Left = 0
    Top = 41
    Width = 822
    Height = 611
    Align = alClient
    ScrollBars = ssBoth
    TabOrder = 1
  end
end
