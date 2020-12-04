unit _fmMain;

interface

uses
  DebugTools, Disk, MemoryPool,
  SuperSocketUtils, SuperSocketServer, SuperSocketClient,
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.AppEvnts, Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TfmMain = class(TForm)
    Panel1: TPanel;
    moMsg: TMemo;
    btStart: TButton;
    btStop: TButton;
    ApplicationEvents: TApplicationEvents;
    Timer: TTimer;
    procedure ApplicationEventsException(Sender: TObject; E: Exception);
    procedure TimerTimer(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btStartClick(Sender: TObject);
    procedure btStopClick(Sender: TObject);
  private
    FMemoryPool : TMemoryPool;
  private
    FServer : TSuperSocketServer;
    procedure on_server_connected(AConnection:TConnection);
    procedure on_server_received(AConnection:TConnection; APacket:PPacket);
  private
    FClient : TSuperSocketClient;
    procedure on_FClient_connected(ASender:TObject);
    procedure on_FClient_disconnected(ASender:TObject);
    procedure on_FClient_received(ASender:TObject; APacket:PPacket);
  public
  end;

var
  fmMain: TfmMain;

implementation

{$R *.dfm}

procedure TfmMain.ApplicationEventsException(Sender: TObject; E: Exception);
begin
  moMsg.Lines.Add(E.Message);
end;

procedure TfmMain.btStartClick(Sender: TObject);
begin
  Timer.Enabled := true;
end;

procedure TfmMain.btStopClick(Sender: TObject);
begin
  Timer.Enabled := false;
end;

procedure TfmMain.FormCreate(Sender: TObject);
begin
  FMemoryPool := TMemoryPool32.Create(1024 * 1024 * 64);

  FServer := TSuperSocketServer.Create(true);
  FServer.OnConnected := on_server_connected;
  FServer.OnReceived := on_server_received;

  FClient := TSuperSocketClient.Create(true);
  FClient.OnConnected := on_FClient_connected;
  FClient.OnDisconnected := on_FClient_disconnected;
  FClient.OnReceived := on_FClient_received;

  FServer.Port := 1234;
  FServer.Start;
end;

procedure TfmMain.on_FClient_connected(ASender: TObject);
begin
  moMsg.Lines.Add('Connected!');
end;

procedure TfmMain.on_FClient_disconnected(ASender: TObject);
begin
  moMsg.Lines.Add('Disconnected!');
end;

procedure TfmMain.on_FClient_received(ASender: TObject; APacket: PPacket);
begin

end;

procedure TfmMain.on_server_connected(AConnection: TConnection);
begin

end;

procedure TfmMain.on_server_received(AConnection: TConnection; APacket: PPacket);
begin

end;

procedure TfmMain.TimerTimer(Sender: TObject);
begin
  if FClient.Connected then FClient.Disconnect
  else FClient.Connect('127.0.0.1', 1234);
end;

end.
