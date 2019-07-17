unit PeerClient.ClientUnitUDP;

interface

uses
  P2P.Base,
  DebugTools,
  UDPSocket, SuperSocket, ValueList,
  SysUtils, Classes, TypInfo;

const
  ASK_INTERVAL = 20;

type
  THoleCreatedEvent = procedure (ASender:TObject; const AUserID,APeerIP:string; APeerPort:integer; APacket:PPacket) of object;
  TReceivedEvent = procedure (ASender:TObject; const APeerIP:string; APeerPort:integer; APacketType:TUDP_PacketType; APacket:PPacket) of object;

  TClientUnitUDP = class
  private
    FCountASK : integer;
    FSocket : TUDPSocket;
    procedure on_FSocket_Received(const APeerIP:string; APeerPort:integer; AData:pointer; ASize:integer);
  private
    procedure sp_Ping(const AHost:string; APort:integer);
    procedure sp_Hi(const AHost:string; APort:integer; APacket:PPacket);
    procedure sp_ASK(const AHost:string; APort:integer);
  private
    procedure rp_Pong(const APeerIP:string; APeerPort:integer; APacket:PPacket);
    procedure rp_Hello(const APeerIP:string; APeerPort:integer; APacket:PPacket);
    procedure rp_Hi(const APeerIP:string; APeerPort:integer; APacket:PPacket);
  private
    FRemotePort: integer;
    FUserID: string;
    FOnHoleCreated: THoleCreatedEvent;
    FOnReceived: TReceivedEvent;
    function GetPort: integer;
  public
    constructor Create;
    destructor Destroy; override;

    function Connect(const AHost:string; APort:integer):boolean;
    procedure Disconnect;

    procedure sp_Hello(const AHost:string; APort:integer; const AUserID: string);

    procedure Send(const AHost:string; APort:integer; const AText:string); overload;
    procedure Send(const AHost:string; APort:integer; AData:pointer; ASize:integer); overload;
  public
    property UserID : string read FUserID write FUserID;
    property Port : integer read GetPort;
    property RemotePort : integer read FRemotePort;

    /// 상대방에게 전송한 메시지에 대한 답변을 받은 경우, UDP로 P2P 홀 생성이 성공한 것이다.
    property OnHoleCreated : THoleCreatedEvent read FOnHoleCreated write FOnHoleCreated;

    property OnReceived : TReceivedEvent read FOnReceived write FOnReceived;
  end;

implementation

{ TClientUnitUDP }

function TClientUnitUDP.Connect(const AHost: string; APort: integer): boolean;
begin
  FUserID := '';
  FRemotePort := 0;
  FCountASK := 0;

  try
    FSocket.Start(True);
    sp_Ping(AHost, APort);
    Result := true;
  except
    Result := false;
  end;
end;

constructor TClientUnitUDP.Create;
begin
  inherited;

  FUserID := '';
  FRemotePort := 0;
  FCountASK := 0;

  FSocket := TUDPSocket.Create(nil);
  FSocket.OnReceived := on_FSocket_Received;
end;

destructor TClientUnitUDP.Destroy;
begin
  Disconnect;

  FreeAndNil(FSocket);

  inherited;
end;

procedure TClientUnitUDP.Disconnect;
begin
  FSocket.Stop;
end;

function TClientUnitUDP.GetPort: integer;
begin
  Result := FSocket.Port;
end;

procedure TClientUnitUDP.on_FSocket_Received(const APeerIP: string;
  APeerPort: integer; AData: pointer; ASize: integer);
var
  Packet : PPacket absolute AData;
begin
  {$IFDEF DEBUG}
//  Trace( Format('TClientUnitUDP.on_FSocket_Received - APeerIP: %s, APeerPort: %d, %s, %s', [APeerIP, APeerPort, GetEnumName(TypeInfo(TUDP_PacketType), Packet^.PacketType), Packet^.Text]) );
  {$ENDIF}

  case TUDP_PacketType(Packet^.PacketType) of
    ptPong: rp_Pong(APeerIP, APeerPort, Packet);
    ptHello: rp_Hello(APeerIP, APeerPort, Packet);
    ptHi: rp_Hi(APeerIP, APeerPort, Packet);
    ptTextUDP, ptDataUDP: sp_ASK(APeerIP, APeerPort);
  end;

  if Assigned(FOnReceived) then FOnReceived(Self, APeerIP, APeerPort, TUDP_PacketType(Packet^.PacketType), Packet);
end;

procedure TClientUnitUDP.rp_Hello(const APeerIP: string; APeerPort: integer;
  APacket: PPacket);
begin
  sp_Hi(APeerIP, APeerPort, APacket);
end;

procedure TClientUnitUDP.rp_Hi(const APeerIP: string; APeerPort: integer;
  APacket: PPacket);
var
  ValueList : TValueList;
begin
  ValueList := TValueList.Create;
  try
    ValueList.Text := APacket^.Text;

    if ValueList.Values['From'] <> FUserID then Exit;

    {$IFDEF DEBUG}
    Trace('TClientUnitUDP.rp_Hi  - ' + ValueList.Text);
    {$ENDIF}

    if Assigned(FOnHoleCreated) then FOnHoleCreated(Self, ValueList.Values['UserID'], APeerIP, APeerPort, APacket);    
  finally
    ValueList.Free;
  end;
end;

procedure TClientUnitUDP.rp_Pong(const APeerIP: string; APeerPort: integer; APacket: PPacket);
var
  ValueList : TValueList;
begin
  ValueList := TValueList.Create;
  try
    ValueList.Text := APacket^.Text;
    FRemotePort := ValueList.Integers['RemotePort'];
  finally
    ValueList.Free;
  end;
end;

procedure TClientUnitUDP.Send(const AHost: string; APort: integer;
  const AText: string);
var
  Packet : PPacket;
begin
  Packet := TPacket.GetPacket(pdNone, Byte(ptTextUDP), AText);
  try
    FSocket.SendTo(AHost, APort, Packet, Packet^.Size);
  finally
    FreeMem(Packet);
  end;
end;

procedure TClientUnitUDP.Send(const AHost: string; APort: integer;
  AData: pointer; ASize: integer);
var
  Packet : PPacket;
begin
  Packet := TPacket.GetPacket(pdNone, Byte(ptDataUDP), AData, ASize);
  try
    FSocket.SendTo(AHost, APort, Packet, Packet^.Size);
  finally
    FreeMem(Packet);
  end;
end;

procedure TClientUnitUDP.sp_ASK(const AHost: string; APort: integer);
var
  Packet : PPacket;
begin
  Inc(FCountASK);
  if FCountASK < ASK_INTERVAL then Exit;
  FCountASK := 0;

  Packet := TPacket.GetPacket(pdNone, Byte(ptASK), nil, 0);
  try
    FSocket.SendTo(AHost, APort, Packet, Packet^.Size);
  finally
    FreeMem(Packet);
  end;
end;

procedure TClientUnitUDP.sp_Hello(const AHost: string; APort: integer; const AUserID: string);
var
  Packet : PPacket;
begin
  Packet := TPacket.GetPacket( pdNone, Byte(ptHello), Format('From=%s<rYu>Host=%s<rYu>Port=%d<rYu>UserID=%s', [FUserID, AHost, APort, AUserID]) );
  try
    FSocket.SendTo(AHost, APort, Packet, Packet^.Size);
  finally
    FreeMem(Packet);
  end;
end;

procedure TClientUnitUDP.sp_Hi(const AHost:string; APort:integer; APacket:PPacket);
var
  Packet : PPacket;
begin
  Packet := APacket.Clone;
  try
    Packet^.PacketType := Byte(ptHi);
    FSocket.SendTo(AHost, APort, Packet, Packet^.Size);
  finally
    FreeMem(Packet);
  end;
end;

procedure TClientUnitUDP.sp_Ping(const AHost:string; APort:integer);
var
  Packet : PPacket;
begin
  Packet := TPacket.GetPacket(pdNone, Byte(ptPing), nil, 0);
  try
    FSocket.SendTo(AHost, APort, Packet, Packet^.Size);
  finally
    FreeMem(Packet);
  end;
end;

end.
