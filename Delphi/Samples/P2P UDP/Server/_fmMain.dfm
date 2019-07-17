object fmMain: TfmMain
  Left = 0
  Top = 0
  Caption = 'P2P UDP Server'
  ClientHeight = 76
  ClientWidth = 356
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
  object ApplicationEvents: TApplicationEvents
    OnException = ApplicationEventsException
    Left = 72
    Top = 28
  end
end
