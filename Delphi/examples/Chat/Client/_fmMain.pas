unit _fmMain;

interface

uses
  SuperSocketClient, SuperSocketUtils, ObserverList, JsonData, AudioZip,
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, TypInfo;

type
  TChatPacketType = (
    ptLogin,
    ptUserIn, ptUserOut,
    ptChat,
    ptAudio
  );

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
  private
    FObserverList : TObserverList;
  public
  published
    procedure rp_UserIn(AJsonData:TJsonData);
    procedure rp_Chat(AJsonData:TJsonData);
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
  PacketPtr := TPacket.GetPacket(Integer(ptChat) , Format('{"msg": "%s"}', [AText]) );
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
    do_SendText(edMsg.Text);
    edMsg.Text := '';
  end;
end;

procedure TfmMain.FormCreate(Sender: TObject);
begin
  FObserverList := TObserverList.Create(nil);
  FObserverList.Add(Self);

  FSocket := TSuperSocketClient.Create;
  FSocket.OnConnected := on_Connected;
  FSocket.OnDisconnected := on_Disconnected;
  FSocket.OnReceived := on_Received;
end;

procedure TfmMain.FormDestroy(Sender: TObject);
begin
  FObserverList.Remove(Self);

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
var
  code : string;
  JsonData : TJsonData;
begin
  case TChatPacketType(APacket^.PacketType) of
    ptAudio: begin
    end;

    else begin
      code := GetEnumName(TypeInfo(TChatPacketType), APacket^.PacketType);
      Delete(code, 1, 2);

      JsonData := TJsonData.Create;
      try
        JsonData.Text := APacket^.Text;
        JsonData.Values['code'] := code;

        FObserverList.AsyncBroadcast(JsonData);
      finally
        JsonData.Free;
      end;
    end;
  end;
end;

procedure TfmMain.rp_Chat(AJsonData: TJsonData);
begin
  moMsg.Lines.Add(AJsonData.Values['msg']);
end;

procedure TfmMain.rp_UserIn(AJsonData: TJsonData);
begin
  moMsg.Lines.Add(AJsonData.Values['name'] + '¥‘¿Ã ¿‘¿Â«œºÃΩ¿¥œ¥Ÿ.');
end;

end.
