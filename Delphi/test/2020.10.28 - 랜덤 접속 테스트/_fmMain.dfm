object fmMain: TfmMain
  Left = 0
  Top = 0
  Caption = 'fmMain'
  ClientHeight = 349
  ClientWidth = 677
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
  object Panel1: TPanel
    Left = 0
    Top = 0
    Width = 677
    Height = 41
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object btStart: TButton
      Left = 12
      Top = 10
      Width = 75
      Height = 25
      Caption = 'btStart'
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
    Width = 677
    Height = 308
    Align = alClient
    ScrollBars = ssBoth
    TabOrder = 1
  end
  object ApplicationEvents: TApplicationEvents
    OnException = ApplicationEventsException
    Left = 332
    Top = 180
  end
  object Timer: TTimer
    Enabled = False
    Interval = 500
    OnTimer = TimerTimer
    Left = 60
    Top = 120
  end
end
