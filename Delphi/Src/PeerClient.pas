unit PeerClient;

interface

uses
  P2P.Base,
  PeerClient.ClientUnitTCP,
  PeerClient.ClientUnitUDP,
  PeerClient.UserList,
  RyuLibBase, ValueList, SuperSocket,
  SysUtils, Classes;

type
  TPeerClient = class
  private
    FUserList : TUserList;
  private
    FClientUnitUDP : TClientUnitUDP;
    procedure on_FClientUnitUDP_HoleCreated(ASender:TObject; const AUserID,APeerIP:string; APeerPort:integer; APacket:PPacket);
    procedure on_FClientUnitUDP_Received(ASender:TObject; const APeerIP:string; APeerPort:integer; APacketType:TUDP_PacketType; APacket:PPacket);
  private
    procedure rp_ASK(const APeerIP:string; APeerPort:integer; APacket:PPacket);
  private
    FClientUnitTCP : TClientUnitTCP;
    procedure on_FClientUnitTCP_Received(ASender:TObject; APacketType:TPacketType; APacket:PPacket; AValueList:TValueList);
    procedure on_FClientUnitTCP_Data(Sender:TObject; AData:pointer; ASize:integer);
    procedure on_FClientUnitTCP_Text(Sender:TObject; const AText:string);
  private
    procedure rp_UserIn(APacket:PPacket; AValueList:TValueList);
    procedure rp_UserOut(APacket:PPacket; AValueList:TValueList);
  private
    FUserID: string;
    FOnText: TStringEvent;
    FOnData: TDataEvent;
    FOnControlData: TValueListEvent;
    function GetOnConnected: TNotifyEvent;
    function GetOnDisconnected: TNotifyEvent;
    procedure SetOnConnected(const Value: TNotifyEvent);
    procedure SetOnDisconnected(const Value: TNotifyEvent);
    function GetConnected: boolean;
  public
    constructor Create;
    destructor Destroy; override;

    function Connect(const AHost:string):boolean;
    procedure Disconnect;

    procedure sp_Login(const ARoomID,AUserID:string);

    procedure SendToUserID(const AUserID,AText:string); overload;
    procedure SendToUserID(const AUserID:string; AData:pointer; ASize:integer); overload;

    procedure SendToConnectionID(AConnectionID:integer; const AText:string); overload;
    procedure SendToConnectionID(AConnectionID:integer; AData:pointer; ASize:integer); overload;

    procedure SendToAll(const AText:string); overload;
    procedure SendToAll(AData:pointer; ASize:integer); overload;

    procedure SendToOther(const AText:string); overload;
    procedure SendToOther(AData:pointer; ASize:integer); overload;
  public
    property Connected : boolean read GetConnected;
    property UserID : string read FUserID;
  public
    property OnConnected : TNotifyEvent read GetOnConnected write SetOnConnected;
    property OnDisconnected : TNotifyEvent read GetOnDisconnected write SetOnDisconnected;
    property OnText : TStringEvent read FOnText write FOnText;
    property OnData : TDataEvent read FOnData write FOnData;
    property OnControlData : TValueListEvent read FOnControlData write FOnControlData;
  end;

implementation

{ TPeerClient }

function TPeerClient.Connect(const AHost: string): boolean;
begin
  FUserID := '';
  FClientUnitUDP.Connect(AHost, UDP_PORT);
  Result := FClientUnitTCP.Connect(AHost, TCP_PORT);
end;

constructor TPeerClient.Create;
begin
  inherited;

  FUserID := '';

  FUserList := TUserList.Create;

  FClientUnitUDP := TClientUnitUDP.Create;
  FClientUnitUDP.OnHoleCreated := on_FClientUnitUDP_HoleCreated;
  FClientUnitUDP.OnReceived := on_FClientUnitUDP_Received;

  FClientUnitTCP := TClientUnitTCP.Create;
  FClientUnitTCP.OnReceived := on_FClientUnitTCP_Received;
  FClientUnitTCP.OnText := on_FClientUnitTCP_Text;
  FClientUnitTCP.OnData := on_FClientUnitTCP_Data;
end;

destructor TPeerClient.Destroy;
begin
  Disconnect;

  FreeAndNil(FUserList);
  FreeAndNil(FClientUnitTCP);
  FreeAndNil(FClientUnitUDP);

  inherited;
end;

procedure TPeerClient.Disconnect;
begin
  FClientUnitUDP.Disconnect;
  FClientUnitTCP.Disconnect;
end;

function TPeerClient.GetConnected: boolean;
begin
  Result := FClientUnitTCP.Connected;
end;

function TPeerClient.GetOnConnected: TNotifyEvent;
begin
  Result := FClientUnitTCP.OnConnected;
end;

function TPeerClient.GetOnDisconnected: TNotifyEvent;
begin
  Result := FClientUnitTCP.OnDisconnected;
end;

procedure TPeerClient.on_FClientUnitTCP_Data(Sender: TObject; AData: pointer;
  ASize: integer);
begin
  if Assigned(FOnData) then FOnData(Self, AData, ASize);
end;

procedure TPeerClient.on_FClientUnitTCP_Received(ASender: TObject;
  APacketType: TPacketType; APacket:PPacket; AValueList: TValueList);
begin
  if Assigned(FOnControlData) then FOnControlData(Self, AValueList);

  case APacketType of
    ptUserIn: rp_UserIn(APacket, AValueList);
    ptUserOut: rp_UserOut(APacket, AValueList);
  end;
end;

procedure TPeerClient.on_FClientUnitTCP_Text(Sender: TObject;
  const AText: string);
begin
  if Assigned(FOnText) then FOnText(Self, AText);
end;

procedure TPeerClient.on_FClientUnitUDP_HoleCreated(ASender: TObject;
  const AUserID, APeerIP: string; APeerPort: integer; APacket: PPacket);
var
  UserInfo : TUserInfo;
begin
  UserInfo := FUserList.FindUserInfo(AUserID);

  if UserInfo = nil then Exit;

  UserInfo.PeerIP := APeerIP;
  UserInfo.PeerPort := APeerPort;
end;

procedure TPeerClient.on_FClientUnitUDP_Received(ASender: TObject;
  const APeerIP: string; APeerPort: integer; APacketType: TUDP_PacketType;
  APacket: PPacket);
begin
  if FClientUnitTCP.Connected = false then Exit;

  case APacketType of
    ptTextUDP: if Assigned(FOnText) then FOnText(Self, APacket^.Text);
    ptDataUDP: if Assigned(FOnData) then FOnData(Self, @APacket^.DataStart, APacket^.DataSize);
    ptASK: rp_ASK(APeerIP, APeerPort, APacket);
  end;
end;

procedure TPeerClient.rp_ASK(const APeerIP: string; APeerPort: integer; APacket: PPacket);
begin
  FUserList.IncASK(APeerIP, APeerPort);
end;

procedure TPeerClient.rp_UserIn(APacket: PPacket; AValueList: TValueList);
var
  IPs : TStringList;
  Loop: Integer;
begin
  FUserList.UserIn(AValueList.Values['UserID'], AValueList);

  FClientUnitUDP.sp_Hello(AValueList.Values['RemoteIP'], AValueList.Integers['RemotePort'], AValueList.Values['UserID']);

  IPs := TStringList.Create;
  try
    IPs.Delimiter := ';';
    IPs.DelimitedText := AValueList.Values['LocalIP'];

    for Loop := 0 to IPs.Count-1 do FClientUnitUDP.sp_Hello(IPs[Loop], AValueList.Integers['LocalPort'], AValueList.Values['UserID']);
  finally
    IPs.Free;
  end;
end;

procedure TPeerClient.rp_UserOut(APacket: PPacket; AValueList: TValueList);
begin
  FUserList.UserOut(AValueList.Values['UserID']);
end;

procedure TPeerClient.SendToOther(const AText: string);
var
  Loop: Integer;
  UserInfo : TUserInfo;
begin
  if FClientUnitTCP.Connected = false then Exit;

  for Loop := 0 to FUserList.Count-1 do begin
    UserInfo := FUserList.Items[Loop];

    if UserInfo.PeerIP = '' then begin
      FClientUnitTCP.Send(UserInfo.ConnectionID, AText);
    end else begin
      FClientUnitUDP.Send(UserInfo.PeerIP, UserInfo.PeerPort, AText);
      UserInfo.IncSent;
    end;
  end;
end;

procedure TPeerClient.SendToAll(const AText: string);
var
  Loop: Integer;
  UserInfo : TUserInfo;
begin
  if FClientUnitTCP.Connected = false then Exit;

  for Loop := 0 to FUserList.Count-1 do begin
    UserInfo := FUserList.Items[Loop];

    if UserInfo.PeerIP = '' then begin
      FClientUnitTCP.Send(UserInfo.ConnectionID, AText);
    end else begin
      FClientUnitUDP.Send(UserInfo.PeerIP, UserInfo.PeerPort, AText);
      UserInfo.IncSent;
    end;
  end;

  if Assigned(FOnText) then FOnText(Self, AText);
end;

procedure TPeerClient.SendToAll(AData: pointer; ASize: integer);
var
  Loop: Integer;
  UserInfo : TUserInfo;
begin
  if FClientUnitTCP.Connected = false then Exit;

  for Loop := 0 to FUserList.Count-1 do begin
    UserInfo := FUserList.Items[Loop];

    if UserInfo.PeerIP = '' then begin
      FClientUnitTCP.Send(UserInfo.ConnectionID, AData, ASize);
    end else begin
      FClientUnitUDP.Send(UserInfo.PeerIP, UserInfo.PeerPort, AData, ASize);
      UserInfo.IncSent;
    end;
  end;

  if Assigned(FOnText) then FOnData(Self, AData, ASize);
end;

procedure TPeerClient.SendToConnectionID(AConnectionID: integer; AData: pointer;
  ASize: integer);
var
  Loop: Integer;
  UserInfo : TUserInfo;
begin
  if FClientUnitTCP.Connected = false then Exit;

  for Loop := 0 to FUserList.Count-1 do begin
    UserInfo := FUserList.Items[Loop];

    if AConnectionID <> UserInfo.ConnectionID then Continue;

    if UserInfo.PeerIP = '' then begin
      FClientUnitTCP.Send(UserInfo.ConnectionID, AData, ASize);
    end else begin
      FClientUnitUDP.Send(UserInfo.PeerIP, UserInfo.PeerPort, AData, ASize);
      UserInfo.IncSent;
    end;
  end;
end;

procedure TPeerClient.SendToConnectionID(AConnectionID: integer;
  const AText: string);
var
  Loop: Integer;
  UserInfo : TUserInfo;
begin
  if FClientUnitTCP.Connected = false then Exit;

  for Loop := 0 to FUserList.Count-1 do begin
    UserInfo := FUserList.Items[Loop];

    if AConnectionID <> UserInfo.ConnectionID then Continue;

    if UserInfo.PeerIP = '' then begin
      FClientUnitTCP.Send(UserInfo.ConnectionID, AText);
    end else begin
      FClientUnitUDP.Send(UserInfo.PeerIP, UserInfo.PeerPort, AText);
      UserInfo.IncSent;
    end;
  end;
end;

procedure TPeerClient.SendToOther(AData: pointer; ASize: integer);
var
  Loop: Integer;
  UserInfo : TUserInfo;
begin
  if FClientUnitTCP.Connected = false then Exit;

  for Loop := 0 to FUserList.Count-1 do begin
    UserInfo := FUserList.Items[Loop];

    if UserInfo.PeerIP = '' then begin
      FClientUnitTCP.Send(UserInfo.ConnectionID, AData, ASize);
    end else begin
      FClientUnitUDP.Send(UserInfo.PeerIP, UserInfo.PeerPort, AData, ASize);
      UserInfo.IncSent;
    end;
  end;
end;

procedure TPeerClient.SendToUserID(const AUserID: string; AData: pointer;
  ASize: integer);
var
  Loop: Integer;
  UserInfo : TUserInfo;
begin
  if FClientUnitTCP.Connected = false then Exit;

  for Loop := 0 to FUserList.Count-1 do begin
    UserInfo := FUserList.Items[Loop];

    if AUserID <> UserInfo.UserID then Continue;

    if UserInfo.PeerIP = '' then begin
      FClientUnitTCP.Send(UserInfo.ConnectionID, AData, ASize);
    end else begin
      FClientUnitUDP.Send(UserInfo.PeerIP, UserInfo.PeerPort, AData, ASize);
      UserInfo.IncSent;
    end;
  end;
end;

procedure TPeerClient.SetOnConnected(const Value: TNotifyEvent);
begin
  FClientUnitTCP.OnConnected := Value;
end;

procedure TPeerClient.SetOnDisconnected(const Value: TNotifyEvent);
begin
  FClientUnitTCP.OnDisconnected := Value;
end;

procedure TPeerClient.SendToUserID(const AUserID, AText: string);
var
  Loop: Integer;
  UserInfo : TUserInfo;
begin
  if FClientUnitTCP.Connected = false then Exit;

  for Loop := 0 to FUserList.Count-1 do begin
    UserInfo := FUserList.Items[Loop];

    if AUserID <> UserInfo.UserID then Continue;

    if UserInfo.PeerIP = '' then begin
      FClientUnitTCP.Send(UserInfo.ConnectionID, AText);
    end else begin
      FClientUnitUDP.Send(UserInfo.PeerIP, UserInfo.PeerPort, AText);
      UserInfo.IncSent;
    end;
  end;
end;

procedure TPeerClient.sp_Login(const ARoomID, AUserID: string);
begin
  if FClientUnitTCP.Connected = false then Exit;

  FUserID := AUserID;
  FClientUnitUDP.UserID := AUserID;
  FClientUnitTCP.UserID := AUserID;

  FClientUnitTCP.sp_Login(ARoomID, AUserID, FClientUnitUDP.Port, FClientUnitUDP.RemotePort);
end;

end.
