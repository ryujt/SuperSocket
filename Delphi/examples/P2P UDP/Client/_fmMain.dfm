object fmMain: TfmMain
  Left = 0
  Top = 0
  Caption = 'P2P UDP Client'
  ClientHeight = 561
  ClientWidth = 784
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnClose = FormClose
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 13
  object Panel1: TPanel
    Left = 0
    Top = 0
    Width = 784
    Height = 77
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object edIP: TEdit
      Left = 8
      Top = 11
      Width = 121
      Height = 21
      TabOrder = 0
      Text = '127.0.0.1'
    end
    object edRoomID: TEdit
      Left = 148
      Top = 11
      Width = 121
      Height = 21
      TabOrder = 1
      Text = 'Rooom-01'
    end
    object edUserID: TEdit
      Left = 284
      Top = 11
      Width = 121
      Height = 21
      TabOrder = 2
      Text = 'User-A'
    end
    object btConnect: TButton
      Left = 444
      Top = 9
      Width = 75
      Height = 25
      Caption = 'Connect'
      TabOrder = 3
      OnClick = btConnectClick
    end
    object btDisconnect: TButton
      Left = 525
      Top = 9
      Width = 75
      Height = 25
      Caption = 'Disconnect'
      TabOrder = 4
      OnClick = btDisconnectClick
    end
    object edMsg: TEdit
      Left = 8
      Top = 44
      Width = 397
      Height = 21
      TabOrder = 5
      OnKeyPress = edMsgKeyPress
    end
    object btLogin: TButton
      Left = 606
      Top = 9
      Width = 75
      Height = 25
      Caption = 'Login'
      TabOrder = 6
      OnClick = btLoginClick
    end
  end
  object moMsg: TMemo
    Left = 0
    Top = 77
    Width = 784
    Height = 484
    Align = alClient
    ReadOnly = True
    ScrollBars = ssBoth
    TabOrder = 1
  end
end
