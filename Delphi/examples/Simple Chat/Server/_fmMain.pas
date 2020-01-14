unit _fmMain;

interface

uses
  DebugTools, SuperSocket,
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Buttons;

type
  TfmMain = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
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
  FSuperSocketServer := TSuperSocketServer.Create(Self);
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
begin
  Trace( Format('TfmMain.on_FSuperSocketServer_Received - APacket^.Size: %d', [APacket^.Size]) );
  FSuperSocketServer.SendToAll(APacket);
end;

end.
