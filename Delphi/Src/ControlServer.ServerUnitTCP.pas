unit ControlServer.ServerUnitTCP;

interface

uses
  P2P.Base,
  SuperSocket, SuperSocket.RoomList, Database,
  DebugTools, ValueList, MemoryPool, SimpleThread,
  Windows, SysUtils, Classes, TypInfo;

type
  TServerUnitTCP = class
  private
    FRoomList : TRoomList;
    procedure on_FRoomList_UserIn(ARoomUnit:TRoomUnit; AConnection:TConnection);
    procedure on_FRoomList_UserOut(ARoomUnit:TRoomUnit; AConnection:TConnection);
    procedure on_FRoomList_IDinUse(ARoomUnit:TRoomUnit; AConnection:TConnection);
    procedure on_FRoomList_Received(ARoomUnit:TRoomUnit; AConnection:TConnection; APacket:PPacket);
  private
    procedure rp_Chat(ARoomUnit:TRoomUnit; AConnection:TConnection; APacket:PPacket);
    procedure rp_Whisper(ARoomUnit:TRoomUnit; AConnection:TConnection; APacket:PPacket);
  private
    FSocket : TSuperSocketServer;
    procedure on_FSocket_Connected(AConnection:TConnection);
    procedure on_FSocket_Disconnected(AConnection:TConnection);
    procedure on_FSocket_Received(AConnection:TConnection; APacket:PPacket);
  private
    procedure rp_Login(AConnection:TConnection; APacket:PPacket);
    procedure rp_TextTCP(AConnection:TConnection; APacket:PPacket);
    procedure rp_DataTCP(AConnection:TConnection; APacket:PPacket);
  private
    FDatabase : TDatabase;
    procedure on_Database_LoginResult(AConnection:TConnection; APacket:PPacket; AResult:TValueList);
  private
    procedure sp_OkLogin(ARoomUnit:TRoomUnit; AConnection:TConnection);
    procedure sp_ErLogin(ARoomUnit:TRoomUnit; AConnection:TConnection; const AErrorMsg:string);
    procedure sp_UserLimit(ARoomUnit:TRoomUnit; AConnection:TConnection);
    procedure sp_IDinUse(ARoomUnit:TRoomUnit; AConnection:TConnection);
    procedure sp_UserList(ARoomUnit:TRoomUnit; AConnection:TConnection);
    procedure sp_UserIn(ARoomUnit:TRoomUnit; AConnection:TConnection);
    procedure sp_UserOut(ARoomUnit:TRoomUnit; AConnection:TConnection);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Start(APort:integer);
    procedure Stop;

    procedure SendText(AConnection:TConnection; APacketType:TPacketType; const AText:string);
  end;

implementation

{ TServerUnitTCP }

constructor TServerUnitTCP.Create;
begin
  inherited;

  FDatabase := TDatabase.Create;
  FDatabase.OnLoginResult := on_Database_LoginResult;

  FRoomList := TRoomList.Create;
  FRoomList.OnUserIn := on_FRoomList_UserIn;
  FRoomList.OnUserOut := on_FRoomList_UserOut;
  FRoomList.OnIDinUse := on_FRoomList_IDinUse;
  FRoomList.OnReceived := on_FRoomList_Received;

  FSocket := TSuperSocketServer.Create(nil);
  FSocket.OnConnected := on_FSocket_Connected;
  FSocket.OnDisconnected := on_FSocket_Disconnected;
  FSocket.OnReceived := on_FSocket_Received;
end;

destructor TServerUnitTCP.Destroy;
begin
  Stop;

  FreeAndNil(FSocket);
  FreeAndNil(FRoomList);
  FreeAndNil(FDatabase);

  inherited;
end;

procedure TServerUnitTCP.on_Database_LoginResult(AConnection: TConnection;
  APacket: PPacket; AResult: TValueList);
var
  RoomUnit : TRoomUnit;
begin
  if AResult.Booleans['result'] = false then begin
    sp_ErLogin(nil, AConnection, '아이디 및 암호를 확인하여 주시기 바랍니다.');
    Exit;
  end;

  if AConnection.UserLevel = 0 then begin
    RoomUnit := FRoomList.FindRoomUnit(AConnection.RoomID);
    if (RoomUnit <> nil) and (AResult.Integers['user_limit'] > 0) then begin
      if RoomUnit.Connections.Count >= AResult.Integers['user_limit'] then begin
        sp_UserLimit(nil, AConnection);
        Exit;
      end;
    end;
  end;

  FRoomList.UserIn(AConnection);
end;

procedure TServerUnitTCP.on_FRoomList_IDinUse(ARoomUnit: TRoomUnit;
  AConnection: TConnection);
begin
  sp_IDinUse(ARoomUnit, AConnection);
  sp_UserOut(ARoomUnit, AConnection);
  AConnection.Disconnect;
end;

procedure TServerUnitTCP.on_FRoomList_Received(ARoomUnit: TRoomUnit;
  AConnection: TConnection; APacket: PPacket);
begin
//  case TPacketType(APacket^.PacketType) of
//    ptChat: rp_Chat(ARoomUnit, AConnection, APacket);
//    ptWhisper: rp_Whisper(ARoomUnit, AConnection, APacket);
//  end;
end;

procedure TServerUnitTCP.on_FRoomList_UserIn(ARoomUnit: TRoomUnit;
  AConnection: TConnection);
begin
  sp_UserList(ARoomUnit, AConnection);
  sp_OkLogin(ARoomUnit, AConnection);
  sp_UserIn(ARoomUnit, AConnection);
end;

procedure TServerUnitTCP.on_FRoomList_UserOut(ARoomUnit: TRoomUnit;
  AConnection: TConnection);
begin
  sp_UserOut(ARoomUnit, AConnection);
end;

procedure TServerUnitTCP.on_FSocket_Connected(AConnection: TConnection);
begin
  //
end;

procedure TServerUnitTCP.on_FSocket_Disconnected(AConnection: TConnection);
begin
  try
    FRoomList.UserOut(AConnection);
  except
    on E : Exception do Trace('TServerUnitTCP.on_FSocket_Disconnected - ' + E.Message);
  end;
end;

procedure TServerUnitTCP.on_FSocket_Received(AConnection: TConnection;
  APacket: PPacket);
var
  Packet : PPacket;
begin
  {$IFDEF DEBUG}
//  Trace( Format('TServerUnitTCP.on_FRoomList_Received - %S, %s, %s', [AConnection.RoomID, GetEnumName(TypeInfo(TPacketType), APacket^.PacketType), APacket^.Text]) );
  {$ENDIF}

  InterlockedExchange(AConnection.IdleCount, 0);

  try
    Packet := CloneMemory(APacket, APacket^.Size);

    case TPacketType(APacket^.PacketType) of
      ptLogin: rp_Login(AConnection, Packet);
      ptTextTCP: rp_TextTCP(AConnection, Packet);
      ptDataTCP: rp_DataTCP(AConnection, Packet);
      else FRoomList.Received(AConnection, Packet);
    end;
  except
    on E : Exception do Trace('TServerUnitTCP.on_FSocket_Received - ' + E.Message);
  end;
end;

procedure TServerUnitTCP.rp_Chat(ARoomUnit: TRoomUnit; AConnection: TConnection;
  APacket: PPacket);
begin
  ARoomUnit.SendToAll(APacket);
end;

procedure TServerUnitTCP.rp_DataTCP(AConnection: TConnection; APacket: PPacket);
var
  ConnectionID : integer;
begin
  Move(APacket^.DataStart, ConnectionID, SizeOf(ConnectionID));
  FSocket.SendToID(ConnectionID, APacket);

  {$IFDEF DEBUG}
//  Trace( Format('TServerUnitTCP.rp_DataTCP - ConnectionID: %d', [ConnectionID]) );
  {$ENDIF}
end;

procedure TServerUnitTCP.rp_Login(AConnection: TConnection; APacket: PPacket);
begin
  FDatabase.Login(AConnection, APacket);
end;

procedure TServerUnitTCP.rp_TextTCP(AConnection: TConnection; APacket: PPacket);
var
  ConnectionID : integer;
begin
  Move(APacket^.DataStart, ConnectionID, SizeOf(ConnectionID));
  FSocket.SendToID(ConnectionID, APacket);

  {$IFDEF DEBUG}
//  Trace( Format('TServerUnitTCP.rp_TextTCP - ConnectionID: %d', [ConnectionID]) );
  {$ENDIF}
end;

procedure TServerUnitTCP.rp_Whisper(ARoomUnit: TRoomUnit;
  AConnection: TConnection; APacket: PPacket);
var
  Loop: Integer;
  ValueList : TValueList;
  sUserIDs : string;
  Connection : TConnection;
begin
  ValueList := TValueList.Create;
  try
    ValueList.Text := APacket^.Text;

    sUserIDs := ValueList.Values['UserIDs'];

    for Loop := 0 to ARoomUnit.Connections.Count-1 do begin
      Connection := ARoomUnit.Connections.Items[Loop];
      if Pos(Connection.UserID, sUserIDs) > 0 then Connection.Send(APacket);
    end;
  finally
    ValueList.Free;
  end;
end;

procedure TServerUnitTCP.SendText(AConnection: TConnection; APacketType:TPacketType;
  const AText: string);
var
  Packet : PPacket;
begin
  Packet := TPacket.GetPacket(pdNone, Integer(APacketType), AText);
  try
    AConnection.Send( CloneMemory(Packet, Packet^.Size) );
  finally
    FreeMem(Packet);
  end;
end;

procedure TServerUnitTCP.sp_ErLogin(ARoomUnit:TRoomUnit; AConnection: TConnection;
  const AErrorMsg: string);
begin
  SendText(AConnection, ptErLogin, AErrorMsg);
end;

procedure TServerUnitTCP.sp_IDinUse(ARoomUnit:TRoomUnit; AConnection: TConnection);
var
  Packet : PPacket;
begin
  Packet := TPacket.GetPacket(pdNone, Integer(ptIDinUse), nil, 0);
  try
    AConnection.Send( CloneMemory(Packet, Packet^.Size) );
  finally
    FreeMem(Packet);
  end;
end;

procedure TServerUnitTCP.sp_OkLogin(ARoomUnit:TRoomUnit; AConnection: TConnection);
begin
  SendText(AConnection, ptOkLogin, AConnection.Text);
end;

procedure TServerUnitTCP.sp_UserIn(ARoomUnit:TRoomUnit; AConnection: TConnection);
var
  Packet : PPacket;
begin
  Packet := TPacket.GetPacket(pdNone, Integer(ptUserIn), AConnection.Text);
  try
    ARoomUnit.SendToOther(AConnection, CloneMemory(Packet, Packet^.Size));
  finally
    FreeMem(Packet);
  end;
end;

procedure TServerUnitTCP.sp_UserLimit(ARoomUnit:TRoomUnit; AConnection: TConnection);
var
  Packet : PPacket;
begin
  Packet := TPacket.GetPacket(pdNone, Integer(ptUserLimit), nil, 0);
  try
    AConnection.Send( CloneMemory(Packet, Packet^.Size) );
  finally
    FreeMem(Packet);
  end;
end;

procedure TServerUnitTCP.sp_UserList(ARoomUnit: TRoomUnit; AConnection: TConnection);
var
  Loop: Integer;
  Connection : TConnection;
//  sUserInfo : string;
//  stUserList : string;
begin
  for Loop := 0 to ARoomUnit.Connections.Count-1 do begin
    Connection := ARoomUnit.Connections.Items[Loop];

    if Connection.IsLogined = false then Continue;
    if Connection = AConnection then Continue;
    if Connection.UserID = '' then Continue;

    SendText(AConnection, ptUserIn, Connection.Text);
  end;

  // 사용자가 많은 경우에는 묶어서 보내야 패킷 수를 줄여서 효율적이다.
  // 하지만, P2P에서 한 방에 많은 사용자가 있을 수가 없어서 개별 전송하는 것으로 변경하였다.
  // 추후 다른 프로젝트에서 참고하도록 기존 소스를 남겨 둔다.
//  stUserList := '';
//
//  for Loop := 0 to ARoomUnit.Connections.Count-1 do begin
//    Connection := ARoomUnit.Connections.Items[Loop];
//
//    if Connection.IsLogined = false then Continue;
//    if Connection = AConnection then Continue;
//    if Connection.UserID = '' then Continue;
//
//    sUserInfo := Connection.Text;
//
//    if (ByteLength(stUserList) + ByteLength(sUserInfo)) >= 1400 then begin
//      SendText(AConnection, ptUserList, stUserList);
//      stUserList := '';
//    end;
//
//    stUserList := stUserList + sUserInfo + '<rYu>end.<rYu>';
//  end;
//
//  if stUserList <> '' then SendText(AConnection, ptUserList, stUserList);
end;

procedure TServerUnitTCP.sp_UserOut(ARoomUnit:TRoomUnit; AConnection: TConnection);
var
  Packet : PPacket;
begin
  Packet := TPacket.GetPacket(pdNone, Integer(ptUserOut), AConnection.Text);
  try
    ARoomUnit.SendToOther(AConnection, CloneMemory(Packet, Packet^.Size));
  finally
    FreeMem(Packet);
  end;
end;

procedure TServerUnitTCP.Start(APort: integer);
begin
  FSocket.Port := APort;
  FSocket.Start;
end;

procedure TServerUnitTCP.Stop;
begin
  FSocket.Stop;
end;

end.
