unit SuperSocketServer;

interface

uses
  RyuLibBase, DebugTools, SuperSocketUtils, SimpleThread, DynamicQueue,
  Windows, SysUtils, Classes, WinSock2, AnsiStrings;

type
  TIOStatus = (ioStart, ioStop, ioAccepted, ioSend, ioRecv, ioDisconnect);

  TSuperSocketServer = class;

  TConnection = class
  private
    FPacketReader : TPacketReader;
    procedure do_Init;
    procedure do_PacketIn(AData:pointer; ASize:integer);
  private
    FSuperSocketServer : TSuperSocketServer;
    FID : integer;
    FSocket : TSocket;
    FRemoteIP : string;
    function GetIsConnected: boolean;
    function GetText: string;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Disconnect;

    {*
      Send [Packet]
      @param APacket See the TPacket class
      @param APacketSize SizeOf([Header][PacketType[Data])
    }
    procedure Send(APacket:PPacket);
  public
    /// Dummy property as like TComponent.Tag.
    Tag : integer;

    /// Dummy property as like TComponent.Tag.
    UserData : pointer;

    IdleCount : integer;

    IsLogined : boolean;
    RoomID : string;
    Room : TObject;
    UserID : string;
    UserPW : string;
    UserName : string;
    UserLevel : integer;

    property IsConnected : boolean read GetIsConnected;

    /// Information of TConnection object.
    property ID : integer read FID;
    property Text : string read GetText;
  end;

  TIOData = record
    Overlapped : OVERLAPPED;
    wsaBuffer : TWSABUF;
    Status: TIOStatus;
    Socket : integer;
    RemoteIP : string;
    Connection : TConnection;
  end;
  PIOData = ^TIOData;

  TIODataPool = class
  strict private
    FQueue : TDynamicQueue;
  public
    constructor Create;
    destructor Destroy; override;

    function Get:PIOData;
    procedure Release(AIOData:PIOData);
  end;

  TListenerEvent = procedure (ASocket:integer; const ARemoteIP:string) of object;

  TListener = class
  strict private
    FSocket : TSocket;
  strict private
    FSimpleThread : TSimpleThread;
    procedure on_FSimpleThread_Execute(ASimpleThread:TSimpleThread);
  strict private
    FPort: integer;
    FUseNagel: boolean;
    FOnAccepted: TListenerEvent;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Start;
    procedure Stop;
  public
    property Port : integer read FPort write FPort;
    property UseNagel : boolean read FUseNagel write FUseNagel;
    property OnAccepted : TListenerEvent read FOnAccepted write FOnAccepted;
  end;

  TCompletePortEvent = procedure (ATransferred:DWord; AIOData:PIOData) of object;

  TCompletePort = class
  strict private
    FCompletionPort : THandle;
    FIODataPool : TIODataPool;
    FMemoryPool : TMemoryPool;
    procedure do_FireDisconnectEvent(AIOData:PIOData);
  strict private
    FSimpleThread : TSimpleThread;
    procedure on_FSimpleThread_Execute(ASimpleThread:TSimpleThread);
  strict private
    FOnAccepted: TCompletePortEvent;
    FOnDisconnect: TCompletePortEvent;
    FOnStop: TCompletePortEvent;
    FOnReceived: TCompletePortEvent;
    FOnStart: TCompletePortEvent;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Start;
    procedure Stop;
    procedure Accepted(ASocket:integer; const ARemoteIP:string);
    procedure Receive(AConnection:TConnection);
    procedure Send(AConnection:TConnection; AData:pointer; ASize:word);
    procedure Disconnect(AConnection:TConnection);
  public
    property OnStart : TCompletePortEvent read FOnStart write FOnStart;
    property OnStop : TCompletePortEvent read FOnStop write FOnStop;
    property OnAccepted : TCompletePortEvent read FOnAccepted write FOnAccepted;
    property OnReceived : TCompletePortEvent read FOnReceived write FOnReceived;
    property OnDisconnect : TCompletePortEvent read FOnDisconnect write FOnDisconnect;
  end;

  TConnectionList = class
  strict private
    FID : integer;
    FCount : integer;
    FConnections : array [0..CONNECTION_POOL_SIZE-1] of TConnection;
    function GetConnection(AIndex:integer):TConnection;
  public
    constructor Create(ASuperSocketServer:TSuperSocketServer); reintroduce;
    destructor Destroy; override;

    procedure TerminateAll;

    function Add(ASocket:integer; const ARemoteIP:string):TConnection;
    procedure Remove(AConnection:TConnection);

    function FindByUserID(const AUserID:string):TConnection;
  public
    property Count : integer read FCount;
    property Items[AIndex:integer] : TConnection read GetConnection;
  end;

  TSuperSocketServerEvent = procedure (AConnection:TConnection) of object;
  TSuperSocketServerReceivedEvent = procedure (AConnection:TConnection; APacket:PPacket) of object;

  TSuperSocketServer = class
  private
    FIdleCountThread : TSimpleThread;
    FConnectionList : TConnectionList;
  private
    FListener : TListener;
    procedure on_FListener_Accepted(ASocket:integer; const ARemoteIP:string);
  private
    FCompletePort : TCompletePort;
    procedure on_FCompletePort_Start(ATransferred:DWord; AIOData:PIOData);
    procedure on_FCompletePort_Stop(ATransferred:DWord; AIOData:PIOData);
    procedure on_FCompletePort_Accepted(ATransferred:DWord; AIOData:PIOData);
    procedure on_FCompletePort_Received(ATransferred:DWord; AIOData:PIOData);
    procedure on_FCompletePort_Disconnect(ATransferred:DWord; AIOData:PIOData);
  private
    FOnConnected: TSuperSocketServerEvent;
    FOnDisconnected: TSuperSocketServerEvent;
    FOnReceived: TSuperSocketServerReceivedEvent;
    procedure SetPort(const Value: integer);
    function GetUseNagel: boolean;
    procedure SetUseNagel(const Value: boolean);
    function GetPort: integer;
  public
    constructor Create(AIdleCheck:boolean=true); reintroduce;
    destructor Destroy; override;

    procedure Start;
    procedure Stop;

    procedure SendTo(AConnection:TConnection; APacket:PPacket);
    procedure SendToID(AID:integer; APacket:PPacket);
    procedure SendToAll(APacket:PPacket);
    procedure SendToOther(AConnection:TConnection; APacket:PPacket);
  public
    property Port : integer read GetPort write SetPort;
    property UseNagel : boolean read GetUseNagel write SetUseNagel;
    property ConnectionList : TConnectionList read FConnectionList;
  published
    property OnConnected : TSuperSocketServerEvent read FOnConnected write FOnConnected;
    property OnDisconnected : TSuperSocketServerEvent read FOnDisconnected write FOnDisconnected;
    property OnReceived : TSuperSocketServerReceivedEvent read FOnReceived write FOnReceived;
  end;

implementation

procedure SetSocketDelayOption(ASocket:integer; ADelay:boolean);
var
  iValue : integer;
begin
  if ADelay then iValue := 0
  else iValue := 1;

  setsockopt( ASocket, IPPROTO_TCP, TCP_NODELAY, @iValue, SizeOf(iValue) );
end;

procedure SetSocketLingerOption(ASocket,ALinger:integer);
type
  TLinger = packed record
    OnOff : integer;
    Linger : integer;
  end;
var
  Linger : TLinger;
begin
  Linger.OnOff := 1;
  Linger.Linger := ALinger;
  setsockopt( ASocket, SOL_SOCKET, SO_LINGER, @Linger, SizeOf(Linger) );
end;

{ TConnection }

constructor TConnection.Create;
begin
  inherited;

  FSocket := 0;

  FPacketReader := TPacketReader.Create;

  do_Init;
end;

destructor TConnection.Destroy;
begin
  FreeAndNil(FPacketReader);

  inherited;
end;

procedure TConnection.Disconnect;
begin
  FSuperSocketServer.FCompletePort.Disconnect(Self);
end;

procedure TConnection.do_Init;
begin
  FID := 0;
  FRemoteIP := '';
  RoomID := '';
  Room := nil;
  UserData := nil;
  UserID:= '';
  UserName := '';
  UserPW := '';
  UserLevel := 0;
  IsLogined := false;

  IdleCount := 0;

  if FSocket <> INVALID_SOCKET then closesocket(FSocket);
  FSocket := INVALID_SOCKET;

  FPacketReader.Clear;
end;

procedure TConnection.do_PacketIn(AData: pointer; ASize: integer);
var
  PacketPtr : PPacket;
begin
  IdleCount := 0;

  FPacketReader.Write(UserName, AData, ASize);
  while FPacketReader.canRead do begin
    PacketPtr := FPacketReader.Read;
    if PacketPtr^.PacketType = 255 then Send(@NilPacket)
    else if Assigned(FSuperSocketServer.FOnReceived) then FSuperSocketServer.FOnReceived(Self, PacketPtr);
  end;
end;

function TConnection.GetIsConnected: boolean;
begin
  Result := FSocket <> INVALID_SOCKET;
end;

function TConnection.GetText: string;
const
  fmt = '{"id": %d, "user_id": "%s", "user_name": "%s", "user_level": %d}';
begin
  Result := Format(fmt, [FID, UserID, UserName, UserLevel]);
end;

procedure TConnection.Send(APacket: PPacket);
begin
  if (FSocket <> INVALID_SOCKET) and (APacket <> nil) then
    FSuperSocketServer.FCompletePort.Send(Self, APacket, APacket^.PacketSize);
end;

{ TIODataPool }

constructor TIODataPool.Create;
begin
  FQueue := TDynamicQueue.Create(true);
end;

destructor TIODataPool.Destroy;
begin
  FreeAndNil(FQueue);

  inherited;
end;

function TIODataPool.Get: PIOData;
begin
  if not FQueue.Pop( Pointer(Result) ) then New(Result);
  FillChar(Result^.Overlapped, SizeOf(Overlapped), 0);
end;

procedure TIODataPool.Release(AIOData: PIOData);
begin
  FQueue.Push(AIOData);
end;

{ TListener }

constructor TListener.Create;
begin
  inherited;

  FPort := 0;
  FSimpleThread := nil;
  FSocket := INVALID_SOCKET;
  FUseNagel := false;
end;

destructor TListener.Destroy;
begin
  Stop;

  if FSimpleThread <> nil then FreeAndNil(FSimpleThread);

  inherited;
end;

procedure TListener.on_FSimpleThread_Execute(ASimpleThread: TSimpleThread);
var
  NewSocket : TSocket;
  Addr : TSockAddrIn;
  AddrLen : Integer;
  LastError : integer;
begin
  FSocket := WSASocket(AF_INET, SOCK_STREAM, 0, nil, 0, WSA_FLAG_OVERLAPPED);
  if FSocket = INVALID_SOCKET then
    raise Exception.Create(SysErrorMessage(WSAGetLastError));

  FillChar(Addr, SizeOf(TSockAddrIn), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := htons(FPort);
  Addr.sin_addr.S_addr := INADDR_ANY;

  if bind(FSocket, TSockAddr(Addr), SizeOf(Addr)) <> 0 then
    raise Exception.Create(Format('Port: %d - ', [FPort]) + SysErrorMessage(WSAGetLastError));

  if listen(FSocket, SOMAXCONN) <> 0 then
    raise Exception.Create(Format('Port: %d - ', [FPort]) + SysErrorMessage(WSAGetLastError));

  SetSocketDelayOption(FSocket, FUseNagel);
  SetSocketLingerOption(FSocket, 0);

  while not ASimpleThread.Terminated do begin
    if FSocket = INVALID_SOCKET then Break;

    AddrLen := SizeOf(Addr);
    NewSocket := WSAAccept(FSocket, PSockAddr(@Addr), @AddrLen, nil, 0);

    if ASimpleThread.Terminated then Break;

    if NewSocket = INVALID_SOCKET then begin
      LastError := WSAGetLastError;
      Trace(Format('TListener.on_FSimpleThread_Execute - %s', [SysErrorMessage(LastError)]));
      Continue;
    end;

    SetSocketDelayOption(NewSocket, FUseNagel);
    SetSocketLingerOption(NewSocket, 0);

    if Assigned(FOnAccepted) then FOnAccepted(NewSocket, String(AnsiStrings.StrPas(inet_ntoa(sockaddr_in(Addr).sin_addr))));
  end;
end;

procedure TListener.Start;
begin
  Stop;
  FSimpleThread := TSimpleThread.Create('TListener', on_FSimpleThread_Execute);
end;

procedure TListener.Stop;
begin
  if FSimpleThread = nil then Exit;

  FSimpleThread.TerminateNow;
  FSimpleThread := nil;

  if FSocket <> INVALID_SOCKET then begin
    FSocket := INVALID_SOCKET;
    closesocket(FSocket);
  end;
end;

{ TCompletePort }

procedure TCompletePort.Accepted(ASocket: integer; const ARemoteIP: string);
var
  pData : PIOData;
begin
  if CreateIoCompletionPort(ASocket, FCompletionPort, 0, 0) = 0 then begin
    Trace('TCompletePort.CreateIoCompletionPort Error');

    closesocket(ASocket);
    Exit;
  end;

  pData := FIODataPool.Get;
  pData^.Status := ioAccepted;
  pData^.Socket := ASocket;
  pData^.RemoteIP := ARemoteIP;

  if not PostQueuedCompletionStatus(FCompletionPort, SizeOf(pData), 0, POverlapped(pData)) then begin
    Trace('TCompletePort.Accepted - PostQueuedCompletionStatus Error');

    closesocket(ASocket);
    FIODataPool.Release(pData);
  end;
end;

constructor TCompletePort.Create;
begin
  FCompletionPort := CreateIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, 0);

  FIODataPool := TIODataPool.Create;
  FMemoryPool := TMemoryPool.Create;
  FSimpleThread := TSimpleThread.Create('TCompletePort.Create', on_FSimpleThread_Execute);
end;

destructor TCompletePort.Destroy;
begin
  FSimpleThread.TerminateNow;

  FreeAndNil(FIODataPool);
  FreeAndNil(FMemoryPool);
  CloseHandle(FCompletionPort);

  inherited;
end;

procedure TCompletePort.Disconnect(AConnection: TConnection);
var
  pData : PIOData;
begin
  pData := FIODataPool.Get;
  pData^.Status := ioDisconnect;
  pData^.Connection := AConnection;

  if not PostQueuedCompletionStatus(FCompletionPort, SizeOf(pData), 0, POverlapped(pData)) then begin
    Trace('TCompletePort.Disconnect - PostQueuedCompletionStatus Error');

    FIODataPool.Release(pData);
  end;
end;

procedure TCompletePort.do_FireDisconnectEvent(AIOData: PIOData);
begin
  if AIOData.Connection = nil then Exit;
  if AIOData.Connection.FSocket = INVALID_SOCKET then Exit;

  closesocket(AIOData.Connection.FSocket);
  AIOData.Connection.FSocket := INVALID_SOCKET;

  if Assigned(FOnDisconnect) then FOnDisconnect(0, AIOData);
end;

procedure TCompletePort.on_FSimpleThread_Execute(ASimpleThread: TSimpleThread);
var
  pData : PIOData;
  Transferred : DWord;
  Key : NativeUInt;
  isGetOk, isCondition : boolean;
  LastError : integer;
begin
  while not ASimpleThread.Terminated do begin
    isGetOk := GetQueuedCompletionStatus(FCompletionPort, Transferred, Key, POverlapped(pData), INFINITE);

    isCondition :=
      (pData <> nil) and ((Transferred = 0) or (not isGetOk));
    if isCondition then begin
      if not isGetOk then begin
        LastError := WSAGetLastError;
        Trace(Format('TCompletePort.on_FSimpleThread_Execute - %s', [SysErrorMessage(LastError)]));
      end;

      do_FireDisconnectEvent(pData);

      FIODataPool.Release(pData);

      Continue;
    end;

    if pData = nil then Continue;

    case pData^.Status of
      ioStart: if Assigned(FOnStart) then FOnStart(Transferred, pData);
      ioStop: if Assigned(FOnStop) then FOnStop(Transferred, pData);

      ioAccepted: begin
        if Assigned(FOnAccepted) then FOnAccepted(Transferred, pData);
        if pData^.Connection <> nil then Receive(pData^.Connection);
      end;

      ioSend: ;

      ioRecv: begin
        Receive(pData^.Connection);
        if Assigned(FOnReceived) then FOnReceived(Transferred, pData);
        FMemoryPool.Release(pData.wsaBuffer.buf);
      end;

      ioDisconnect: do_FireDisconnectEvent(pData);
    end;

    FIODataPool.Release(pData);
  end;
end;

procedure TCompletePort.Receive(AConnection: TConnection);
var
  pData : PIOData;
  byteRecv, dwFlags: DWord;
  recv_ret, LastError: Integer;
begin
  if AConnection.FSocket = INVALID_SOCKET then Exit;

  pData := FIODataPool.Get;
  PData^.wsaBuffer.buf := FMemoryPool.Get;
  pData^.wsaBuffer.len := PACKET_SIZE;
  pData^.Status := ioRecv;
  pData^.Connection := AConnection;

  dwFlags := 0;
  recv_ret := WSARecv(AConnection.FSocket, LPWSABUF(@pData^.wsaBuffer), 1, byteRecv, dwFlags, LPWSAOVERLAPPED(pData), nil);

  if recv_ret = SOCKET_ERROR then begin
    LastError := WSAGetLastError;
    if LastError <> ERROR_IO_PENDING then begin
      Trace(Format('TCompletePort.Receive - %s', [SysErrorMessage(LastError)]));

      do_FireDisconnectEvent(pData);
      FIODataPool.Release(pData);
    end;
  end;
end;

procedure TCompletePort.Send(AConnection: TConnection; AData: pointer;
  ASize: word);
var
  pData : PIOData;
  BytesSent, Flags: DWORD;
  ErrorCode, LastError : integer;
begin
  if AConnection.FSocket = INVALID_SOCKET then Exit;

  pData := FIODataPool.Get;
  PData^.wsaBuffer.buf := AData;
  pData^.wsaBuffer.len := ASize;
  pData^.Status := ioSend;
  pData^.Connection := AConnection;

  Flags := 0;
  ErrorCode := WSASend(AConnection.FSocket, @(PData^.wsaBuffer), 1, BytesSent, Flags, Pointer(pData), nil);

  if ErrorCode = SOCKET_ERROR then begin
    LastError := WSAGetLastError;
    if LastError <> ERROR_IO_PENDING then begin
      Trace(Format('TCompletePort.Send - %s', [SysErrorMessage(LastError)]));

      do_FireDisconnectEvent(pData);
      FIODataPool.Release(pData);
    end;
  end;
end;

procedure TCompletePort.Start;
var
  pData : PIOData;
begin
  pData := FIODataPool.Get;
  pData^.Status := ioStart;

  if not PostQueuedCompletionStatus(FCompletionPort, SizeOf(pData), 0, POverlapped(pData)) then begin
    Trace('TCompletePort.Start - PostQueuedCompletionStatus Error');

    FIODataPool.Release(pData);
  end;
end;

procedure TCompletePort.Stop;
var
  pData : PIOData;
begin
  pData := FIODataPool.Get;
  pData^.Status := ioStop;

  if not PostQueuedCompletionStatus(FCompletionPort, SizeOf(pData), 0, POverlapped(pData)) then begin
    Trace('TCompletePort.Stop - PostQueuedCompletionStatus Error');

    FIODataPool.Release(pData);
  end;
end;

{ TConnectionList }

function TConnectionList.Add(ASocket:integer; const ARemoteIP:string): TConnection;
var
  iCount : integer;
begin
  Result := nil;

  iCount := 0;
  while true do begin
    iCount := iCount + 1;
    if iCount > CONNECTION_POOL_SIZE then Break;

    Inc(FID);

    // "FConnectionID = 0" means that Connection is not assigned.
    if FID = 0 then Continue;

    if FConnections[DWord(FID) mod CONNECTION_POOL_SIZE].FID = 0 then begin
      Inc(FCount);
      Result := FConnections[DWord(FID) mod CONNECTION_POOL_SIZE];
      Result.FID := FID;
      Result.FSocket := ASocket;
      Result.FRemoteIP := ARemoteIP;
      Result.RoomID := '';
      Result.Room := nil;
      Break;
    end;
  end;
end;

constructor TConnectionList.Create(ASuperSocketServer:TSuperSocketServer);
var
  Loop: Integer;
begin
  inherited Create;

  FID := 0;
  FCount := 0;

  for Loop := 0 to CONNECTION_POOL_SIZE-1 do begin
    FConnections[Loop] := TConnection.Create;
    FConnections[Loop].FSuperSocketServer := ASuperSocketServer;
  end;
end;

destructor TConnectionList.Destroy;
var
  Loop: Integer;
begin
  for Loop := 0 to CONNECTION_POOL_SIZE-1 do FConnections[Loop].Free;

  inherited;
end;

function TConnectionList.FindByUserID(const AUserID: string): TConnection;
var
  Loop: Integer;
  Connection : TConnection;
begin
  Result := nil;

  for Loop := 0 to CONNECTION_POOL_SIZE-1 do begin
    Connection := FConnections[Loop];
    if Connection.FID = 0 then Continue;
    if Connection.IsLogined = false then Continue;
    if Connection.FSocket = INVALID_SOCKET then Continue;

    if Connection.UserID = AUserID then begin
      Result := Connection;
      Break;
    end;
  end;
end;

function TConnectionList.GetConnection(AIndex: integer): TConnection;
begin
  Result := nil;

  if AIndex <> 0 then begin
    Result := FConnections[DWord(AIndex) mod CONNECTION_POOL_SIZE];
  end;
end;

procedure TConnectionList.Remove(AConnection: TConnection);
begin
  if AConnection.FID <> 0 then Dec(FCount);
  AConnection.FID := 0;
end;

procedure TConnectionList.TerminateAll;
var
  Loop: Integer;
begin
  for Loop := 0 to CONNECTION_POOL_SIZE-1 do FConnections[Loop].do_Init;
end;

{ TSuperSocketServer }

constructor TSuperSocketServer.Create(AIdleCheck:boolean);
begin
  inherited Create;

  FConnectionList := TConnectionList.Create(Self);

  FListener := TListener.Create;
  FListener.OnAccepted := on_FListener_Accepted;

  FCompletePort := TCompletePort.Create;
  FCompletePort.OnStart      := on_FCompletePort_Start;
  FCompletePort.OnStop       := on_FCompletePort_Stop;
  FCompletePort.OnAccepted   := on_FCompletePort_Accepted;
  FCompletePort.OnReceived   := on_FCompletePort_Received;
  FCompletePort.OnDisconnect := on_FCompletePort_Disconnect;

  if not AIdleCheck then begin
    FIdleCountThread := nil;
    Exit;
  end;

  FIdleCountThread := TSimpleThread.Create(
    'TSuperSocketServer.FIdleCountThread',
    procedure (ASimpleThread:TSimpleThread)
    var
      Loop: Integer;
      Connection : TConnection;
    begin
      while ASimpleThread.Terminated = false do begin
        for Loop := 0 to CONNECTION_POOL_SIZE-1 do begin
          Connection := ConnectionList.Items[Loop];

          if Connection = nil then Continue;
          if Connection.FSocket = INVALID_SOCKET then Continue;
          if Connection.IsLogined = false then Continue;

          {$IFDEF DEBUG}
          //Trace( Format('TConnection - IdleCount (%d, %d)', [Connection.ID, Connection.IdleCount]) );
          {$ENDIF}

          if InterlockedIncrement(Connection.IdleCount) > 4 then begin
            {$IFDEF DEBUG}
            Trace( Format('TSuperSocketServer - Disconnected for IdleCount (%s, %d)', [Connection.UserID, Connection.IdleCount]) );
            {$ENDIF}

            Connection.Disconnect;
          end;
        end;

        Sleep(MAX_IDLE_MS div 4);
      end;
    end
  );
end;

destructor TSuperSocketServer.Destroy;
begin
  FListener.Stop;

  if FIdleCountThread <> nil then begin
    FIdleCountThread.TerminateNow;
    FreeAndNil(FIdleCountThread);
  end;

  FreeAndNil(FConnectionList);
  FreeAndNil(FListener);
  FreeAndNil(FCompletePort);

  inherited;
end;

function TSuperSocketServer.GetPort: integer;
begin
  Result := FListener.Port;
end;

function TSuperSocketServer.GetUseNagel: boolean;
begin
  Result := FListener.UseNagel;
end;

procedure TSuperSocketServer.on_FCompletePort_Accepted(ATransferred: DWord;
  AIOData: PIOData);
var
  Connection : TConnection;
begin
  Connection := FConnectionList.Add(AIOData^.Socket, AIOData^.RemoteIP);

  if Connection = nil then begin
    Trace('TSuperSocketServer.on_FCompletePort_Accepted - Connection = nil');
    closesocket(AIOData^.Socket);
    Exit;
  end;

  AIOData^.Connection := Connection;

  if Assigned(FOnConnected) then FOnConnected(Connection);  
end;

procedure TSuperSocketServer.on_FCompletePort_Disconnect(ATransferred: DWord;
  AIOData: PIOData);
begin
  FConnectionList.Remove(AIOData^.Connection);
  if Assigned(FOnDisconnected) then FOnDisconnected(AIOData^.Connection);
end;

procedure TSuperSocketServer.on_FCompletePort_Received(ATransferred: DWord;
  AIOData: PIOData);
begin
  AIOData^.Connection.do_PacketIn(AIOData^.wsaBuffer.buf, ATransferred);
end;

procedure TSuperSocketServer.on_FCompletePort_Start(ATransferred: DWord;
  AIOData: PIOData);
begin
  FListener.Start;
end;

procedure TSuperSocketServer.on_FCompletePort_Stop(ATransferred: DWord;
  AIOData: PIOData);
begin
  FConnectionList.TerminateAll;
  FListener.Stop;
end;

procedure TSuperSocketServer.on_FListener_Accepted(ASocket: integer;
  const ARemoteIP: string);
begin
  FCompletePort.Accepted(ASocket, ARemoteIP);
end;

procedure TSuperSocketServer.SendTo(AConnection: TConnection; APacket: PPacket);
begin
  if AConnection <> nil then AConnection.Send(APacket);
end;

procedure TSuperSocketServer.SendToAll(APacket: PPacket);
var
  Loop: Integer;
begin
  for Loop := 0 to CONNECTION_POOL_SIZE-1 do SendTo(FConnectionList.Items[Loop], APacket);
end;

procedure TSuperSocketServer.SendToID(AID: integer; APacket: PPacket);
var
  Connection : TConnection;
begin
  Connection := FConnectionList.Items[AID];
  if Connection <> nil then Connection.Send(APacket);
end;

procedure TSuperSocketServer.SendToOther(AConnection: TConnection;
  APacket: PPacket);
var
  Loop: Integer;
begin
  for Loop := 0 to CONNECTION_POOL_SIZE-1 do begin
    if FConnectionList.Items[Loop] <> AConnection then SendTo(FConnectionList.Items[Loop], APacket);
  end;
end;

procedure TSuperSocketServer.SetPort(const Value: integer);
begin
  FListener.Port := Value;
end;

procedure TSuperSocketServer.SetUseNagel(const Value: boolean);
begin
  FListener.UseNagel := Value;
end;

procedure TSuperSocketServer.Start;
begin
  FCompletePort.Start;
end;

procedure TSuperSocketServer.Stop;
begin
  FCompletePort.Stop;
end;

end.
