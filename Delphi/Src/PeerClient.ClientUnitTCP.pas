unit PeerClient.ClientUnitTCP;

interface

uses
  P2P.Base,
  DebugTools, RyuLibBase, ValueList, SimpleThread,
  SuperSocket, Sys,
  Windows, SysUtils, Classes, TypInfo;

type
  TClientUnitTCPEvent = procedure (ASender:TObject; APacketType:TPacketType; APacket:PPacket; AValueList:TValueList) of object;

  TClientUnitTCP = class
  private
    FSocket : TSuperSocketClient;
    procedure on_FSocket_Received(ASender:TObject; APacket:PPacket);
  private
    procedure rp_TextTCP(APacket:PPacket);
    procedure rp_DataTCP(APacket:PPacket);
    procedure rp_Default(APacket:PPacket);
  private
    FOnReceived: TClientUnitTCPEvent;
    FUserID: string;
    FOnText: TStringEvent;
    FOnData: TDataEvent;
    function GetOnConnected: TNotifyEvent;
    function GetOnDisconnected: TNotifyEvent;
    procedure SetOnConnected(const Value: TNotifyEvent);
    procedure SetOnDisconnected(const Value: TNotifyEvent);
    function GetConnected: boolean;
  public
    constructor Create;
    destructor Destroy; override;

    function Connect(const AHost:string; APort:integer):boolean;
    procedure Disconnect;

    procedure sp_Login(const ARoomID,AUserID:string; ALocalPort,ARemotePort: integer);

    procedure Send(AConnectionID:integer; const AText:string); overload;
    procedure Send(AConnectionID:integer; AData:pointer; ASize:integer); overload;
  public
    property Connected : boolean read GetConnected;
    property UserID : string read FUserID write FUserID;
  public
    property OnConnected : TNotifyEvent read GetOnConnected write SetOnConnected;
    property OnDisconnected : TNotifyEvent read GetOnDisconnected write SetOnDisconnected;
    property OnReceived : TClientUnitTCPEvent read FOnReceived write FOnReceived;
    property OnText : TStringEvent read FOnText write FOnText;
    property OnData : TDataEvent read FOnData write FOnData;
  end;

implementation

{ TClientUnitTCP }

function TClientUnitTCP.Connect(const AHost: string; APort: integer): boolean;
begin
  FUserID := '';
  Result := FSocket.Connect(AHost, APort);
end;

constructor TClientUnitTCP.Create;
begin
  inherited;

  FUserID := '';

  FSocket := TSuperSocketClient.Create(nil);
  FSocket.OnReceived := on_FSocket_Received;
end;

destructor TClientUnitTCP.Destroy;
begin
  Disconnect;

  FreeAndNil(FSocket);

  inherited;
end;

procedure TClientUnitTCP.Disconnect;
begin
  FSocket.Disconnect;
end;

function TClientUnitTCP.GetConnected: boolean;
begin
  Result := FSocket.Connected;
end;

function TClientUnitTCP.GetOnConnected: TNotifyEvent;
begin
  Result := FSocket.OnConnected;
end;

function TClientUnitTCP.GetOnDisconnected: TNotifyEvent;
begin
  Result := FSocket.OnDisconnected;
end;

procedure TClientUnitTCP.sp_Login(const ARoomID, AUserID: string; ALocalPort,ARemotePort: integer);
var
  Packet : PPacket;
begin
  Packet := TPacket.GetPacket(pdNone, Integer(ptLogin),
    'RoomID=' + ARoomID + '<rYu>' +
    'UserID=' + AUserID + '<rYu>' +
    'LocalIP=' + LocalIPs + '<rYu>' +
    'LocalPort=' + IntToStr(ALocalPort) + '<rYu>' +
    'RemotePort=' + IntToStr(ARemotePort) + '<rYu>'
  );
  try
    FSocket.Send(Packet);
  finally
    FreeMem(Packet);
  end;
end;

procedure TClientUnitTCP.on_FSocket_Received(ASender: TObject;
  APacket: PPacket);
begin
  case TPacketType(APacket^.PacketType) of
    ptTextTCP: rp_TextTCP(APacket);
    ptDataTCP: rp_DataTCP(APacket);
    else rp_Default(APacket);
  end;
end;

procedure TClientUnitTCP.rp_DataTCP(APacket: PPacket);
var
  Buffer : TPacketToID;
begin
  {$IFDEF DEBUG}
//  Trace( Format('TClientUnitTCP.rp_DataTCP - FUserID: %s, %d', [FUserID, APacket^.Size]) );
  {$ENDIF}

  Move(APacket^.DataStart, Buffer, APacket^.DataSize);
  if Assigned(FOnData) then FOnData(Self, @Buffer.Data, APacket^.DataSize - SizeOf(Integer));
end;

procedure TClientUnitTCP.rp_Default(APacket: PPacket);
var
  sCode : string;
  ValueList : TValueList;
begin
  sCode := GetEnumName(TypeInfo(TPacketType), APacket^.PacketType);
  Delete(sCode, 1, 2);

  {$IFDEF DEBUG}
  Trace( Format('TClientUnitTCP.on_FSocket_Received - %s, %s', [sCode, APacket^.Text]) );
  {$ENDIF}

  if not Assigned(FOnReceived) then Exit;

  ValueList := TValueList.Create;
  try
    ValueList.Text := 'Code=' + sCode + '<rYu>' + APacket^.Text;
    FOnReceived(Self, TPacketType(APacket^.PacketType), APacket, ValueList);
  finally
    ValueList.Free;
  end;
end;

procedure TClientUnitTCP.rp_TextTCP(APacket: PPacket);
var
  Buffer : TPacketToID;
  ssData : TStringStream;
begin
  {$IFDEF DEBUG}
//  Trace( Format('TClientUnitTCP.rp_TextTCP - FUserID: %s, %d', [FUserID, APacket^.Size]) );
  {$ENDIF}

  Move(APacket^.DataStart, Buffer, APacket^.DataSize);

  ssData := TStringStream.Create;
  try
    ssData.Write(Buffer.Data, APacket^.DataSize - SizeOf(Integer));
    ssData.Position := 0;

    if Assigned(FOnText) then FOnText(Self, ssData.DataString);
  finally
    ssData.Free;
  end;
end;

procedure TClientUnitTCP.Send(AConnectionID:integer; const AText: string);
var
  Packet : PPacket;
  Buffer : TPacketToID;
  Size : integer;
  ssData : TStringStream;
begin
  Buffer.ConnectionID := AConnectionID;

  ssData := TStringStream.Create(AText);
  try
    Size := ssData.Size;
    Move(ssData.Memory^, Buffer.Data, Size);
  finally
    ssData.Free;
  end;

  Packet := TPacket.GetPacket(pdNone, Byte(ptTextTCP), @Buffer, Size + SizeOf(Integer));
  try
    FSocket.Send(Packet);
  finally
    FreeMem(Packet);
  end;
end;

procedure TClientUnitTCP.Send(AConnectionID:integer; AData: pointer; ASize: integer);
var
  Packet : PPacket;
  Buffer : TPacketToID;
begin
  Buffer.ConnectionID := AConnectionID;
  Move(AData^, Buffer.Data, ASize);

  Packet := TPacket.GetPacket(pdNone, Byte(ptDataTCP), @Buffer, ASize + SizeOf(Integer));
  try
    FSocket.Send(Packet);
  finally
    FreeMem(Packet);
  end;
end;

procedure TClientUnitTCP.SetOnConnected(const Value: TNotifyEvent);
begin
  FSocket.OnConnected := Value;
end;

procedure TClientUnitTCP.SetOnDisconnected(const Value: TNotifyEvent);
begin
  FSocket.OnDisconnected := Value;
end;

end.
