object fmMain: TfmMain
  Left = 0
  Top = 0
  ActiveControl = edMsg
  Caption = 'Simple Chat Client'
  ClientHeight = 327
  ClientWidth = 301
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 13
  object moMsg: TMemo
    Left = 8
    Top = 35
    Width = 285
    Height = 258
    ImeName = 'Microsoft Office IME 2007'
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 0
  end
  object edMsg: TEdit
    Left = 8
    Top = 299
    Width = 285
    Height = 21
    ImeName = 'Microsoft Office IME 2007'
    TabOrder = 1
    OnKeyPress = edMsgKeyPress
  end
  object btConnect: TButton
    Left = 8
    Top = 4
    Width = 75
    Height = 25
    Caption = 'btConnect'
    TabOrder = 2
    OnClick = btConnectClick
  end
  object btDisconnect: TButton
    Left = 89
    Top = 4
    Width = 75
    Height = 25
    Caption = 'btDisconnect'
    TabOrder = 3
    OnClick = btDisconnectClick
  end
end
