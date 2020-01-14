unit _fmMain;

interface

uses
  DebugTools, IdGlobal,
  SuperSocketUtils, SuperSocketClient, SuperSocketServer, MemoryPool,
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TfmMain = class(TForm)
    btStart: TButton;
    btStop: TButton;
    Panel1: TPanel;
    moMsg: TMemo;
    Timer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure btStartClick(Sender: TObject);
    procedure btStopClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure TimerTimer(Sender: TObject);
  private
    FOldTick, FTerm : cardinal;
  private
    FServerPacketCount : integer;
    FMemoryPool : TMemoryPool;
    FSocketServer : TSuperSocketServer;
    procedure on_server_Connected(AConnection:TConnection);
    procedure on_server_Disconnected(AConnection:TConnection);
    procedure on_server_Received(AConnection:TConnection; APacket:PPacket);
  private
    FClientPacketCount : integer;
    FSocketClient : TSuperSocketClient;
    procedure on_client_Connected(Sender:TObject);
    procedure on_client_Disconnected(Sender:TObject);
    procedure on_client_Received(Sender:TObject; APacket:PPacket);

    procedure do_send;
  public
  end;

var
  fmMain: TfmMain;

implementation

function GetPacketClone(AMemoryPool:TMemoryPool; APacket: PPacket): PPacket;
begin
  AMemoryPool.GetMem(Pointer(Result), APacket^.PacketSize);
  APacket^.Clone(Result);
end;

{$R *.dfm}

procedure TfmMain.btStartClick(Sender: TObject);
begin
  FOldTick := GetTickCount;

  FServerPacketCount := 0;
  FClientPacketCount := 0;
  FSocketClient.Connect('127.0.0.1', 1000);
end;

procedure TfmMain.btStopClick(Sender: TObject);
begin
  FSocketClient.Disconnect;
end;

procedure TfmMain.do_send;
var
  i: Integer;
  packet : PPacket;
begin
  packet := TPacket.GetPacket(0, 'Socket test - 012345678901234567890123456789012345678901234567890123456789');
  try
    for i := 1 to 16 do FSocketClient.Send(packet);
  finally
    FreeMem(packet);
  end;

  packet := TPacket.GetPacket(1, 'Socket test - 012345678901234567890123456789012345678901234567890123456789');
  try
    FSocketClient.Send(packet);
  finally
    FreeMem(packet);
  end;
end;

procedure TfmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FSocketClient.Terminate;
end;

procedure TfmMain.FormCreate(Sender: TObject);
begin
  FMemoryPool := TMemoryPool32.Create(1024 * 1024);

  FSocketServer := TSuperSocketServer.Create(false);
  FSocketServer.UseNagel := false;
  FSocketServer.Port := 1000;
  FSocketServer.OnConnected := on_server_Connected;
  FSocketServer.OnDisconnected := on_server_Disconnected;
  FSocketServer.OnReceived := on_server_Received;
  FSocketServer.Start;

  FSocketClient := TSuperSocketClient.Create(false);
  FSocketClient.UseNagel := false;
  FSocketClient.OnConnected := on_client_Connected;
  FSocketClient.OnDisconnected := on_client_Disconnected;
  FSocketClient.OnReceived := on_client_Received;
end;

procedure TfmMain.on_client_Connected(Sender: TObject);
begin
  moMsg.Lines.Add('on_client_Connected');
  do_send;
end;

procedure TfmMain.on_client_Disconnected(Sender: TObject);
begin
  moMsg.Lines.Add('on_client_Disconnected');
end;

procedure TfmMain.on_client_Received(Sender: TObject; APacket: PPacket);
var
  tick : cardinal;
begin
  tick := GetTickCount;
  FTerm := tick - FOldTick;
  FOldTick := tick;

  FClientPacketCount := FClientPacketCount + 1;
  if APacket^.PacketType = 1 then do_send;
end;

procedure TfmMain.on_server_Connected(AConnection: TConnection);
begin
  moMsg.Lines.Add('on_server_Connected - ' + AConnection.Text);
  AConnection.IsLogined := true;
end;

procedure TfmMain.on_server_Disconnected(AConnection: TConnection);
begin
  moMsg.Lines.Add('on_server_Disconnected - ' + AConnection.Text);
end;

procedure TfmMain.on_server_Received(AConnection: TConnection;
  APacket: PPacket);
var
  Packet: PPacket;
begin
  FServerPacketCount := FServerPacketCount + 1;
  Packet := GetPacketClone(FMemoryPool, APacket);
  FSocketServer.SendToAll(Packet);
end;

procedure TfmMain.TimerTimer(Sender: TObject);
begin
  Caption := Format('Term: %d, Server: %d, Client: %d', [FTerm, FServerPacketCount, FClientPacketCount]);
end;

end.
