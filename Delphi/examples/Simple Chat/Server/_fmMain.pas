unit _fmMain;

interface

uses
  DebugTools, SuperSocketServer, SuperSocketUtils, MemoryPool,
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Buttons;

type
  TfmMain = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FMemoryPool : TMemoryPool;
    FSuperSocketServer : TSuperSocketServer;
    procedure on_FSuperSocketServer_Connected(AConnection:TConnection);
    procedure on_FSuperSocketServer_Disconnected(AConnection:TConnection);
    procedure on_FSuperSocketServer_Received(AConnection:TConnection; APacket:PPacket);
  public
  end;

var
  fmMain: TfmMain;

implementation

{$R *.dfm}

procedure TfmMain.FormCreate(Sender: TObject);
begin
  FMemoryPool := TMemoryPool32.Create(1024 * 1024 * 64);

  FSuperSocketServer := TSuperSocketServer.Create;
  FSuperSocketServer.OnConnected := on_FSuperSocketServer_Connected;
  FSuperSocketServer.OnDisconnected := on_FSuperSocketServer_Disconnected;
  FSuperSocketServer.OnReceived := on_FSuperSocketServer_Received;
  FSuperSocketServer.Port := 1234;
  FSuperSocketServer.Start;
end;

procedure TfmMain.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FSuperSocketServer);
end;

procedure TfmMain.on_FSuperSocketServer_Connected(AConnection: TConnection);
begin
  Trace('TfmMain.on_FSuperSocketServer_Connected');
end;

procedure TfmMain.on_FSuperSocketServer_Disconnected(AConnection: TConnection);
begin
  Trace('TfmMain.on_FSuperSocketServer_Disconnected');
end;

procedure TfmMain.on_FSuperSocketServer_Received(AConnection: TConnection; APacket: PPacket);
var
  packet : PPacket;
begin
  packet := FMemoryPool.GetClone(APacket, APacket^.PacketSize);
  FSuperSocketServer.SendToAll(packet);
end;

end.
