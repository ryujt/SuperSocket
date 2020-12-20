unit SuperSocketServer;

interface

uses
  RyuLibBase, DebugTools, SuperSocketUtils, SimpleThread, DynamicQueue, JsonData,
  Windows, SysUtils, Classes, WinSock2, AnsiStrings, TypInfo;

type
  TIOStatus = (ioStart, ioStop, ioAccepted, ioSend, ioRecv, ioDisconnect, ioUserEvent);

  TSuperSocketServer = class;

  /// Contains information and methods of connection.
  TConnection = class
  private
    FPacketReader : TPacketReader;
    procedure do_Init;
    procedure do_Close;
    procedure do_PacketIn(AData:pointer; ASize:integer);
  private
    FSuperSocketServer : TSuperSocketServer;
    FID : integer;
    FSocket : TSocket;
    function GetIsConnected: boolean;
    function GetText: string;
    function GetIsMuted: boolean;
    function GetUserID: string;
    function GetUserLevel: integer;
    function GetUserName: string;
    procedure SetIsMuted(const Value: boolean);
    procedure SetUserID(const Value: string);
    procedure SetUserLevel(const Value: integer);
    procedure SetUserName(const Value: string);
    function GetRemoteIP: string;
    procedure SetRemoteIP(const Value: string);
    function GetIsAvailable: boolean;
  public
    constructor Create;
    destructor Destroy; override;

    /// Disconnect the current connection.
    procedure Disconnect;

    {* Send a packet to the current connection.
    @param APacket a message to send.
    }
    procedure Send(APacket:PPacket);
  public
    /// Dummy property as like TComponent.Tag.
    Tag : integer;
    TagStr : string;
    TagObject : TObject;

    /// Extra user information
    UserData : TJsonData;

    IdleCount : integer;

    /// Predeclare frequently used variables
    IsLogined : boolean;
    RoomID : string;
    Room : TObject;
    UserPW : string;
  public
    /// Indicates whether the current connection is connected.
    property IsConnected : boolean read GetIsConnected;

    /// Indicates whether the current connection is Logined and connected.
    property IsAvailable : boolean read GetIsAvailable;

    /// The unique ID of the current connection assigned in TConnectionList.
    property ID : integer read FID;

    property RemoteIP : string read GetRemoteIP write SetRemoteIP;

    /// frequently used properties
    property IsMuted : boolean read GetIsMuted write SetIsMuted;
    property UserID : string read GetUserID write SetUserID;
    property UserName : string read GetUserName write SetUserName;
    property UserLevel : integer read GetUserLevel write SetUserLevel;

    /// Information of TConnection object in json format.
    property Text : string read GetText;
  end;

  TIOData = record
    Overlapped : OVERLAPPED;
    wsaBuffer : TWSABUF;
    Status: TIOStatus;
    Socket : integer;
    RemoteIP : string;
    Connection : TConnection;
    EventCode : integer;
    EventData : pointer;
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
    FPort : integer;
    FCompletionPort : THandle;
    FIODataPool : TIODataPool;
    FMemoryRecylce : TMemoryRecylce;
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

    procedure Start(APort:integer);
    procedure Stop;
    procedure Accepted(ASocket:integer; const ARemoteIP:string);
    procedure Receive(AConnection:TConnection);
    procedure Send(AConnection:TConnection; AData:pointer; ASize:word);
    procedure Disconnect(AConnection:TConnection);
    procedure UserEvent(AConnection:TConnection; AEventCode:integer; AEventData:pointer);
  private
    FOnUserEvent: TCompletePortEvent;
  public
    property OnStart : TCompletePortEvent read FOnStart write FOnStart;
    property OnStop : TCompletePortEvent read FOnStop write FOnStop;
    property OnAccepted : TCompletePortEvent read FOnAccepted write FOnAccepted;
    property OnReceived : TCompletePortEvent read FOnReceived write FOnReceived;
    property OnDisconnect : TCompletePortEvent read FOnDisconnect write FOnDisconnect;
    property OnUserEvent : TCompletePortEvent read FOnUserEvent write FOnUserEvent;
  end;

  TConnectionList = class
  strict private
    FID : integer;
    FCount : integer;
    FNullConnection : TConnection;
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
  TSuperSocketServerUserEvent = procedure (AConnection:TConnection; AEventCode:integer; AEventData:pointer) of object;

  /// TCP socket server using IOCP.
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
    procedure on_FCompletePort_UserEvent(ATransferred:DWord; AIOData:PIOData);
  private
    FOnConnected: TSuperSocketServerEvent;
    FOnDisconnected: TSuperSocketServerEvent;
    FOnReceived: TSuperSocketServerReceivedEvent;
    FOnUserEvent: TSuperSocketServerUserEvent;
    procedure SetPort(const Value: integer);
    function GetUseNagel: boolean;
    procedure SetUseNagel(const Value: boolean);
    function GetPort: integer;
  public
    constructor Create(AIdleCheck:boolean=true); reintroduce;
    destructor Destroy; override;

    procedure Start; /// Start TSuperSocketServer.
    procedure Stop;  /// Stop TSuperSocketServer.

    {* Send a message to the specified connection.
    @param AConnection the connection to receive the packet(APacket).
    @param APacket a message to send.
    }
    procedure SendTo(AConnection:TConnection; APacket:PPacket);

    {* Send a message to the specified connection ID.
    @param AID the connection ID to receive the packet(APacket).
    @param APacket a message to send.
    }
    procedure SendToID(AID:integer; APacket:PPacket);

    {* Deliver packets to all connected clients.
    @param APacket a message to send.
    }
    procedure SendToAll(APacket:PPacket);

    {* Deliver the packet to all connected clients except current connection.
    @param AConnection the connection to exclude.
    @param APacket a message to send.
    }
    procedure SendToOther(AConnection:TConnection; APacket:PPacket);

    {* Make user defined event. You can synchronize external thread messages with this procedure.
      @param AConnection the connection to exclude.
      @param AEventCode Code to categorize event messages
      @param AEventData User data for passing detail information of the event
    }
    procedure UserEvent(AConnection:TConnection; AEventCode:integer; AEventData:pointer=nil);
  public
    /// Port number for the server to use.
    property Port : integer read GetPort write SetPort;

    /// Specifies whether to use nagle algorithm.
    property UseNagel : boolean read GetUseNagel write SetUseNagel;

    /// A list of connections in TSuperSocketServer.
    property ConnectionList : TConnectionList read FConnectionList;
  public
    /// Use OnConnected to perform special processing when the new connection created.
    property OnConnected : TSuperSocketServerEvent read FOnConnected write FOnConnected;

    /// Use OnDisconnected to perform special processing when a connection disconnected.
    property OnDisconnected : TSuperSocketServerEvent read FOnDisconnected write FOnDisconnected;

    /// Use OnDisconnected to perform special processing when a connection has new packet.
    property OnReceived : TSuperSocketServerReceivedEvent read FOnReceived write FOnReceived;

    /// Use OnUserEvent to synchronize external thread messages.
    property OnUserEvent : TSuperSocketServerUserEvent read FOnUserEvent write FOnUserEvent;
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

procedure TConnection.do_Close;
begin
  if FSocket <> INVALID_SOCKET then closesocket(FSocket);
  FSocket := INVALID_SOCKET;
end;

constructor TConnection.Create;
begin
  inherited;

  FSocket := 0;

  UserData := TJsonData.Create;
  FPacketReader := TPacketReader.Create;

  do_Init;
end;

destructor TConnection.Destroy;
begin
  FreeAndNil(UserData);
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
  RoomID := '';
  Room := nil;
  UserPW := '';
  IsLogined := false;
  UserData.Text := '';

  InterlockedExchange(IdleCount, 0);

  FPacketReader.Clear;

  do_Close;
end;

procedure TConnection.do_PacketIn(AData: pointer; ASize: integer);
var
  PacketPtr : PPacket;
begin
  InterlockedExchange(IdleCount, 0);

  if FPacketReader.Write(AData, ASize) = false then begin
    Disconnect;
    Exit;
  end;

  while true do begin
    PacketPtr := FPacketReader.GetPacket;
    if PacketPtr = nil then Break;

    try
      if PacketPtr^.PacketType = 255 then Send(@NilPacket)
      else if Assigned(FSuperSocketServer.FOnReceived) then FSuperSocketServer.FOnReceived(Self, PacketPtr);
    finally
      FreeMem(PacketPtr);
    end;
  end;
end;

function TConnection.GetIsConnected: boolean;
begin
  Result := FSocket <> INVALID_SOCKET;
end;

function TConnection.GetIsAvailable: boolean;
begin
  Result := IsLogined and (FSocket <> INVALID_SOCKET);
end;

function TConnection.GetIsMuted: boolean;
begin
  Result := UserData.Booleans['is_muted'];
end;

function TConnection.GetRemoteIP: string;
begin
  Result := UserData.Values['remote_ip'];
end;

function TConnection.GetText: string;
begin
  UserData.Integers['id'] := FID;
  Result := UserData.Text;
end;

function TConnection.GetUserID: string;
begin
  Result := UserData.Values['user_id'];
end;

function TConnection.GetUserLevel: integer;
begin
  Result := UserData.Integers['user_level'];
end;

function TConnection.GetUserName: string;
begin
  Result := UserData.Values['user_name'];
end;

procedure TConnection.Send(APacket: PPacket);
begin
  if (FSocket <> INVALID_SOCKET) and (APacket <> nil) then
    FSuperSocketServer.FCompletePort.Send(Self, APacket, APacket^.PacketSize);
end;

procedure TConnection.SetIsMuted(const Value: boolean);
begin
  UserData.Booleans['is_muted'] := Value;
end;

procedure TConnection.SetRemoteIP(const Value: string);
begin
  UserData.Values['remote_ip'] := Value;
end;

procedure TConnection.SetUserID(const Value: string);
begin
  UserData.Values['user_id'] := Value;
end;

procedure TConnection.SetUserLevel(const Value: integer);
begin
  UserData.Integers['user_level'] := Value;
end;

procedure TConnection.SetUserName(const Value: string);
begin
  UserData.Values['user_name'] := Value;
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

    try
      AddrLen := SizeOf(Addr);
      NewSocket := WSAAccept(FSocket, PSockAddr(@Addr), @AddrLen, nil, 0);

      if ASimpleThread.Terminated then Break;

      if NewSocket = INVALID_SOCKET then begin
        {$IFDEF DEBUG}
        LastError := WSAGetLastError;
        Trace(Format('TListener.on_FSimpleThread_Execute - %s', [SysErrorMessage(LastError)]));
        {$ENDIF}

        Continue;
      end;

      SetSocketDelayOption(NewSocket, FUseNagel);
      SetSocketLingerOption(NewSocket, 0);

      if Assigned(FOnAccepted) then FOnAccepted(NewSocket, String(AnsiStrings.StrPas(inet_ntoa(sockaddr_in(Addr).sin_addr))));
    except
      on E : Exception do Trace('TListener.on_FSimpleThread_Execute - ' + E.Message);
    end;
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
    {$IFDEF DEBUG}
    Trace('TSuperSocketServer.CreateIoCompletionPort Error');
    {$ENDIF}

    closesocket(ASocket);
    Exit;
  end;

  pData := FIODataPool.Get;
  pData^.Status := ioAccepted;
  pData^.Socket := ASocket;
  pData^.RemoteIP := ARemoteIP;

  if not PostQueuedCompletionStatus(FCompletionPort, SizeOf(pData), 0, POverlapped(pData)) then begin
    {$IFDEF DEBUG}
    Trace('TSuperSocketServer.Accepted - PostQueuedCompletionStatus Error');
    {$ENDIF}

    closesocket(ASocket);
    FIODataPool.Release(pData);
  end;
end;

constructor TCompletePort.Create;
begin
  FCompletionPort := CreateIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, 0);

  FIODataPool := TIODataPool.Create;
  FMemoryRecylce := TMemoryRecylce.Create(CONNECTION_POOL_SIZE);
  FSimpleThread := TSimpleThread.Create('TSuperSocketServer.CompletePort', on_FSimpleThread_Execute);
end;

destructor TCompletePort.Destroy;
begin
  FSimpleThread.TerminateNow;

  FreeAndNil(FIODataPool);
  FreeAndNil(FMemoryRecylce);
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
    {$IFDEF DEBUG}
    Trace('TSuperSocketServer.Disconnect - PostQueuedCompletionStatus Error');
    {$ENDIF}

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
    try
      isGetOk := GetQueuedCompletionStatus(FCompletionPort, Transferred, Key, POverlapped(pData), INFINITE);

      if pData = nil then Continue;

      isCondition := ((Transferred = 0) or (not isGetOk));
      if isCondition then begin
        {$IFDEF DEBUG}
        if not isGetOk then begin
          LastError := WSAGetLastError;
          Trace(Format('TSuperSocketServer.on_FSimpleThread_Execute (Port: %d) - %s', [FPort, SysErrorMessage(LastError)]));
        end;
        {$ENDIF}

        do_FireDisconnectEvent(pData);
        FIODataPool.Release(pData);

        Continue;
      end;

      case pData^.Status of
        ioStart: begin
          ASimpleThread.Name := Format('TCompletePort.CompletePort (Port: %d)', [FPort]);
          if Assigned(FOnStart) then FOnStart(Transferred, pData);
        end;

        ioStop: if Assigned(FOnStop) then FOnStop(Transferred, pData);

        ioAccepted: begin
          if Assigned(FOnAccepted) then FOnAccepted(Transferred, pData);
          if pData^.Connection <> nil then Receive(pData^.Connection);
        end;

        ioSend: ;

        ioRecv: begin
          if Assigned(FOnReceived) then FOnReceived(Transferred, pData);
          FMemoryRecylce.Release(pData.wsaBuffer.buf);
          Receive(pData^.Connection);
        end;

        ioDisconnect: do_FireDisconnectEvent(pData);

        ioUserEvent: if Assigned(FOnUserEvent) then FOnUserEvent(Transferred, pData);
      end;

      FIODataPool.Release(pData);
    except
      on E : Exception do Trace( Format('TCompletePort.on_FSimpleThread_Execute (Port: %d) - %s', [FPort, E.Message]) );
    end;
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
  PData^.wsaBuffer.buf := FMemoryRecylce.Get(PACKET_SIZE);
  pData^.wsaBuffer.len := PACKET_SIZE;
  pData^.Status := ioRecv;
  pData^.Connection := AConnection;

  dwFlags := 0;
  recv_ret := WSARecv(AConnection.FSocket, LPWSABUF(@pData^.wsaBuffer), 1, byteRecv, dwFlags, LPWSAOVERLAPPED(pData), nil);

  if recv_ret = SOCKET_ERROR then begin
    LastError := WSAGetLastError;
    if LastError <> ERROR_IO_PENDING then begin
      {$IFDEF DEBUG}
      Trace( Format('TCompletePort.Receive - %s', [SysErrorMessage(LastError)]) );
      {$ENDIF}

      FIODataPool.Release(pData);

      AConnection.Disconnect;
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

  if ASize > PACKET_SIZE then begin
    Trace( Format('TCompletePort.Send - Size(%s) > PACKET_SIZE', [ASize]) );
    Exit;
  end;

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
      {$IFDEF DEBUG}
      Trace( Format('TCompletePort.Send - %s', [SysErrorMessage(LastError)]) );
      {$ENDIF}

      FIODataPool.Release(pData);

      // TODO:
      // 접속 처리 도중에 정상적인 경우인데도 에러가 발생할 수 있음
      // 소켓 초기화가 완전히 종료된 이후부터 Disconnect 처리되도록 수정해야 함
      // AConnection.Disconnect;
    end;
  end;
end;

procedure TCompletePort.Start(APort:integer);
var
  pData : PIOData;
begin
  FPort := APort;

  pData := FIODataPool.Get;
  pData^.Status := ioStart;

  if not PostQueuedCompletionStatus(FCompletionPort, SizeOf(pData), 0, POverlapped(pData)) then begin
    {$IFDEF DEBUG}
    Trace('TCompletePort.Start - PostQueuedCompletionStatus Error');
    {$ENDIF}

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
    {$IFDEF DEBUG}
    Trace('TCompletePort.Stop - PostQueuedCompletionStatus Error');
    {$ENDIF}

    FIODataPool.Release(pData);
  end;
end;

procedure TCompletePort.UserEvent(AConnection: TConnection;
  AEventCode: integer; AEventData:pointer);
var
  pData : PIOData;
begin
  pData := FIODataPool.Get;
  pData^.Status := ioUserEvent;
  pData^.Connection := AConnection;
  pData^.EventCode := AEventCode;
  pData^.EventData := AEventData;

  if not PostQueuedCompletionStatus(FCompletionPort, SizeOf(pData), 0, POverlapped(pData)) then begin
    {$IFDEF DEBUG}
    Trace('TCompletePort.Stop - PostQueuedCompletionStatus Error');
    {$ENDIF}

    FIODataPool.Release(pData);
  end;
end;

{ TConnectionList }

function TConnectionList.Add(ASocket:integer; const ARemoteIP:string): TConnection;
var
  iCount : integer;
begin
  Result := FNullConnection;

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

      // 복잡해 보이도록 "Random($4096) * CONNECTION_POOL_SIZE"를 더한다.
      // 실제 사용에서는 CONNECTION_POOL_SIZE로 나눠서 나머지만 취급하기 때문에 더하나 안하나 마찬가지
      // 하지만 ID를 랜덤으로 맞춰서 들어올 수 있는 확률을 낮출 수 있다.
      Randomize;
      Result.FID := Random($4096) * CONNECTION_POOL_SIZE + FID;

      Result.FSocket := ASocket;
      Result.RemoteIP := ARemoteIP;
      Result.RoomID := '';
      Result.Room := nil;
      Break;
    end;
  end;

  FID := FID mod CONNECTION_POOL_SIZE;
end;

constructor TConnectionList.Create(ASuperSocketServer:TSuperSocketServer);
var
  Loop: Integer;
begin
  inherited Create;

  FID := 0;
  FCount := 0;

  FNullConnection := TConnection.Create;
  FNullConnection.do_Init;

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

  FreeAndNil(FNullConnection);

  inherited;
end;

function TConnectionList.FindByUserID(const AUserID: string): TConnection;
var
  Loop: Integer;
  Connection : TConnection;
begin
  Result := FNullConnection;

  for Loop := 0 to CONNECTION_POOL_SIZE-1 do begin
    Connection := FConnections[Loop];
    if Connection.FID = 0 then Continue;
    if Connection.IsAvailable = false then Continue;
    if Connection.FSocket = INVALID_SOCKET then Continue;

    if Connection.UserID = AUserID then begin
      Result := Connection;
      Break;
    end;
  end;
end;

function TConnectionList.GetConnection(AIndex: integer): TConnection;
begin
  Result := FNullConnection;

  if AIndex > 0 then begin
    Result := FConnections[DWord(AIndex) mod CONNECTION_POOL_SIZE];
    if Result.ID = 0 then Result := FNullConnection;
  end;
end;

procedure TConnectionList.Remove(AConnection: TConnection);
begin
  if AConnection.FID <> 0 then Dec(FCount);
  AConnection.do_Close;
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
  FCompletePort.OnUserEvent  := on_FCompletePort_UserEvent;

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
          if Connection.IsAvailable = false then Continue;

          {$IFDEF DEBUG}
          //Trace( Format('TConnection - IdleCount (%d, %d)', [Connection.ID, Connection.IdleCount]) );
          {$ENDIF}

          if InterlockedIncrement(Connection.IdleCount) > (MAX_IDLE_MS div 1000) then begin
            {$IFDEF DEBUG}
            Trace( Format('TSuperSocketServer - Disconnected for IdleCount (%s, %d)', [Connection.UserID, Connection.IdleCount]) );
            {$ENDIF}

            Connection.Disconnect;
          end;
        end;

        Sleep(1000);
      end;
    end
  );
end;

destructor TSuperSocketServer.Destroy;
begin
  FListener.Stop;

  if FIdleCountThread <> nil then FIdleCountThread.TerminateNow;

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
    {$IFDEF DEBUG}
    Trace('TSuperSocketServer.on_FCompletePort_Accepted - Connection = nil');
    {$ENDIF}

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
  AIOData^.Connection.do_Init;
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

procedure TSuperSocketServer.on_FCompletePort_UserEvent(ATransferred: DWord;
  AIOData: PIOData);
begin
  if Assigned(FOnUserEvent) then FOnUserEvent(AIOData^.Connection, AIOData^.EventCode, AIOData^.EventData);
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
  FCompletePort.Start(FListener.Port);
end;

procedure TSuperSocketServer.Stop;
begin
  FCompletePort.Stop;
end;

procedure TSuperSocketServer.UserEvent(AConnection: TConnection;
  AEventCode: integer; AEventData:pointer);
begin
  FCompletePort.UserEvent(AConnection, AEventCode, AEventData);
end;

end.
