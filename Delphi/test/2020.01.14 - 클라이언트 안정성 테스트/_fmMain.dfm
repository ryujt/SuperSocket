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
    object btStart: TButton
      Left = 12
      Top = 9
      Width = 75
      Height = 25
      Caption = 'Start'
      TabOrder = 0
      OnClick = btStartClick
    end
    object btStop: TButton
      Left = 93
      Top = 9
      Width = 75
      Height = 25
      Caption = 'btStop'
      TabOrder = 1
      OnClick = btStopClick
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
  object Timer: TTimer
    Interval = 200
    OnTimer = TimerTimer
    Left = 404
    Top = 332
  end
  object IdTCPServer: TIdTCPServer
    Bindings = <>
    DefaultPort = 1000
    OnConnect = IdTCPServerConnect
    OnExecute = IdTCPServerExecute
    Left = 196
    Top = 100
  end
end
