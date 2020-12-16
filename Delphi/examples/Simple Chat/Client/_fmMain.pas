unit _fmMain;

interface

uses
  SuperSocketClient, SuperSocketUtils,
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls;

type
  TfmMain = class(TForm)
    moMsg: TMemo;
    edMsg: TEdit;
    btConnect: TButton;
    btDisconnect: TButton;
    procedure FormCreate(Sender: TObject);
    procedure edMsgKeyPress(Sender: TObject; var Key: Char);
    procedure btConnectClick(Sender: TObject);
    procedure btDisconnectClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FSocket : TSuperSocketClient;
    procedure on_Connected(Sender:TObject);
    procedure on_Disconnected(Sender:TObject);
    procedure on_Received(Sender:TObject; APacket:PPacket);
    procedure do_SendText(AText:string);
  public
  end;

var
  fmMain: TfmMain;

implementation

{$R *.dfm}

procedure TfmMain.btConnectClick(Sender: TObject);
begin
  FSocket.Connect('127.0.0.1', 1234);
end;

procedure TfmMain.btDisconnectClick(Sender: TObject);
begin
  FSocket.Disconnect;
  Caption := 'Disconnected..';
end;

procedure TfmMain.do_SendText(AText: string);
var
  PacketPtr : PPacket;
begin
  PacketPtr := TPacket.GetPacket(0, AText);
  try
    FSocket.Send(PacketPtr);
  finally
    FreeMem(PacketPtr);
  end;
end;

procedure TfmMain.edMsgKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then begin
    Key := #0;
    do_SendText('Msg=' + edMsg.Text);
    edMsg.Text := '';
  end;
end;

procedure TfmMain.FormCreate(Sender: TObject);
begin
  FSocket := TSuperSocketClient.Create;
  FSocket.OnConnected := on_Connected;
  FSocket.OnDisconnected := on_Disconnected;
  FSocket.OnReceived := on_Received;
end;

procedure TfmMain.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FSocket);
end;

procedure TfmMain.on_Connected(Sender: TObject);
begin
  Caption := 'Connected..';
end;

procedure TfmMain.on_Disconnected(Sender: TObject);
begin
  Caption := 'Disconnected..';
end;

procedure TfmMain.on_Received(Sender:TObject; APacket:PPacket);
begin
  moMsg.Lines.Add(APacket^.Text);
end;

end.
