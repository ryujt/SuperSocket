unit ControlServer.ServerUnitUDP;

interface

uses
  P2P.Base,
  DebugTools,
  UDPSocket, SuperSocket,
  SysUtils, Classes, TypInfo;

type
  TServerUnitUDP = class
  private
    FSocket : TUDPSocket;
    procedure on_FSocket_Received(const APeerIP:string; APeerPort:integer; AData:pointer; ASize:integer);
  private
    procedure sp_Pong(const ARemoteIP:string; ARemotePort:integer);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Start(APort:integer);
    procedure Stop;
  end;

implementation

{ TServerUnitUDP }

constructor TServerUnitUDP.Create;
begin
  inherited;

  FSocket := TUDPSocket.Create(nil);
  FSocket.OnReceived := on_FSocket_Received;
end;

destructor TServerUnitUDP.Destroy;
begin
  Stop;

  FreeAndNil(FSocket);

  inherited;
end;

procedure TServerUnitUDP.on_FSocket_Received(const APeerIP: string;
  APeerPort: integer; AData: pointer; ASize: integer);
var
  Packet : PPacket absolute AData;
begin
  {$IFDEF DEBUG}
  Trace( Format('TServerUnitUDP.on_FSocket_Received - PeerIP: %s, %s', [APeerIP, GetEnumName(TypeInfo(TUDP_PacketType), Packet^.PacketType)]) );
  {$ENDIF}

  case TUDP_PacketType(Packet^.PacketType) of
    ptPing: sp_Pong(APeerIP, APeerPort);
  end;
end;

procedure TServerUnitUDP.sp_Pong(const ARemoteIP: string; ARemotePort: integer);
var
  Packet : PPacket;
begin
  Packet := TPacket.GetPacket( pdNone, Byte(ptPong), Format('RemoteIP=%s<rYu>RemotePort=%d', [ARemoteIP, ARemotePort]) );
  try
    FSocket.SendTo(ARemoteIP, ARemotePort, Packet, Packet^.Size);
  finally
    FreeMem(Packet);
  end;
end;

procedure TServerUnitUDP.Start(APort: integer);
begin
  FSocket.Port := APort;
  FSocket.Start(True);
end;

procedure TServerUnitUDP.Stop;
begin
  FSocket.Stop;
end;

end.
