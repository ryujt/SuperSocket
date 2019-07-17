unit SuperSocket;

interface

uses
  DebugTools, SimpleThread, DynamicQueue, SuspensionQueue,
  Windows, SysUtils, Classes, WinSock2, AnsiStrings;

const
  /// Packet size limitation including header.
  PACKET_SIZE = 4096;

  /// Concurrent connection limitation
  CONNECTION_POOL_SIZE = 4096;

  /// Buffer size of TPacketReader
  PACKETREADER_PAGE_SIZE = PACKET_SIZE * 16;

type
  TPacketDirection = (pdNone, pdAll, pdOther);
  TIOStatus = (ioStart, ioStop, ioAccepted, ioSend, ioRecv, ioDisconnect);

  PPacket = ^TPacket;

  {*
    [Packet] = [Header] [PacketType: byte] [Data]
    [Header] = [Direction: 4bits] [Size: 12bits]
  }
  TPacket = packed record
  strict private
    function GetData: pointer;
    function GetDirection: TPacketDirection;
    function GetDataSize: word;
    procedure SetDirection(const Value: TPacketDirection);
    procedure SetDataSize(const Value: word);
    function GetSize: word;
    function GetText: string;
  public
    Header : word;
    PacketType : byte;
    DataStart : byte;

    class function GetPacket(ADirection:TPacketDirection; APacketType:byte; AData:pointer; ASize:integer):PPacket; overload; static;
    class function GetPacket(ADirection:TPacketDirection; APacketType:byte; const AText:string):PPacket; overload; static;

    procedure Clear;
    function Clone:PPacket;
  public
    property Direction : TPacketDirection read GetDirection write SetDirection;

    property Data : pointer read GetData;

    /// Size of [Data]
    property DataSize : word read GetDataSize write SetDataSize;

    /// Size of [Packet]
    property Size : word read GetSize;

    /// Convert [Data] to string
    property Text : string read GetText;
  end;

  TMemoryPool = class
  strict private
    FQueue : TDynamicQueue;
  public
    constructor Create;
    destructor Destroy; override;

    function Get:pointer;
    procedure Release(AData:pointer);
  end;

  TSuperSocketServer = class;

  TPacketReader = class
  strict private
    FBuffer : pointer;
    FBufferSize : integer;
    FOffset : integer;
    FCapacity : integer;
    FOffsetPtr : PByte;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    procedure Write(const AID:string; AData:pointer; ASize:integer);
    function Read:PPacket;
    function canRead:boolean;

    {*
      Check where packet is broken.
      If it is, VerifyPacket will clear all packet inside.
      @param AID Identification of Connection for debug foot-print.
    }
    procedure VerifyPacket(const AID:string);
  end;

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
    UserName : string;
    UserLevel : integer;

    /// Local IP address that TSuperSocketClient send after connected.
    LocalIP : string;

    /// for P2P hole punching
    LocalPort : integer;
    RemotePort : integer;

    property ID : integer read FID;

    /// IP address of remote host.
    property RemoteIP : string read FRemoteIP;

    property IsConnected : boolean read GetIsConnected;

    /// Information of TConnection object.
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
  private
    FSocket : TSocket;
  private
    FSimpleThread : TSimpleThread;
    procedure on_FSimpleThread_Execute(ASimpleThread:TSimpleThread);
  private
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
  private
    FSimpleThread : TSimpleThread;
    procedure on_FSimpleThread_Execute(ASimpleThread:TSimpleThread);
  private
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
  private
    FID : integer;
    FCount : integer;
    FConnections : array [0..CONNECTION_POOL_SIZE-1] of TConnection;
    function GetCount:integer;
    function GetConnection(AIndex:integer):TConnection;
  private
    procedure TerminateAll;

    /// 사용 가능한 Connection 객체를 리턴한다.
    function Add(ASocket:integer; const ARemoteIP:string):TConnection;
    procedure Remove(AConnection:TConnection);
  public
    constructor Create(ASuperSocketServer:TSuperSocketServer); reintroduce;
    destructor Destroy; override;
  public
    property Count : integer read GetCount;
    property Items[AIndex:integer] : TConnection read GetConnection;
  end;

  TSuperSocketServerEvent = procedure (AConnection:TConnection) of object;

  TSuperSocketServerReceivedEvent = procedure (AConnection:TConnection; APacket:PPacket) of object;

  TSuperSocketServer = class (TComponent)
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
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Start;
    procedure Stop;

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

  TSuperSocketClientReceivedEvent = procedure (ASender:TObject; APacket:PPacket) of object;

  TClientSocketUnit = class
  private
    FIdleCount : integer;
    FIdleCountThread : TSimpleThread;
  private
    FSocket : TSocket;
    FPacketReader : TPacketReader;
    procedure do_FireDisconnectedEvent;
  strict private
    FSimpleThread : TSimpleThread;
    procedure on_FSimpleThread_Execute(ASimpleThread:TSimpleThread);
  private
    FOnDisconnected: TNotifyEvent;
    FOnReceived: TSuperSocketClientReceivedEvent;
    FUseNagel: boolean;
  public
    constructor Create;
    destructor Destroy; override;

    function Connect(const AHost:string; APort:integer):boolean;
    procedure Disconnect;

    function Receive:PPacket;
    procedure Send(APacket:PPacket);
  public
    property UseNagel : boolean read FUseNagel write FUseNagel;
  public
    property OnDisconnected : TNotifyEvent read FOnDisconnected write FOnDisconnected;
    property OnReceived : TSuperSocketClientReceivedEvent read FOnReceived write FOnReceived;
  end;

  TScheduleType = (stNone, stConnected, stDisconnect, stSend, stDisconnected, stTerminate);

  TSchedule = class
  private
  public
    ScheduleType : TScheduleType;
    ClientSocketUnit : TClientSocketUnit;
    PacketPtr : PPacket;
  end;

  TClientSchedulerOnConnectedEvent = procedure (AClientSocketUnit:TClientSocketUnit) of object;

  TClientScheduler = class
  strict private
    FQueue : TSuspensionQueue<TSchedule>;
    procedure do_Send(APacket:PPacket);
  private
    FClientSocketUnit : TClientSocketUnit;
    procedure on_FClientSocketUnit_Disconnected(Sender:TObject);
  strict private
    FSimpleThread : TSimpleThread;
    procedure on_FSimpleThread_Execute(ASimpleThread:TSimpleThread);
  private
    FOnTaskConnected: TClientSchedulerOnConnectedEvent;
    FOnTaskDisconnect: TNotifyEvent;
    FOnTaskDisconnected: TNotifyEvent;
  public
    constructor Create;
    destructor Destroy; override;

    procedure TaskConnected(AClientSocketUnit:TClientSocketUnit);
    procedure TaskDisconnect;
    procedure TaskDisconnected;
    procedure TaskSend(APacket:PPacket);
    procedure TaskTerminate;
  public
    procedure SetSocketUnit(AClientSocketUnit:TClientSocketUnit);
    procedure ReleaseSocketUnit;
  public
    property OnTaskConnected : TClientSchedulerOnConnectedEvent read FOnTaskConnected write FOnTaskConnected;
    property OnTaskDisconnect : TNotifyEvent read FOnTaskDisconnect write FOnTaskDisconnect;
    property OnTaskDisconnected : TNotifyEvent read FOnTaskDisconnected write FOnTaskDisconnected;
  end;

  TSuperSocketClient = class (TComponent)
  private
    FClientScheduler : TClientScheduler;
    procedure on_FClientScheduler_TaskConnected(AClientSocketUnit:TClientSocketUnit);
    procedure on_FClientScheduler_TaskDisconnect(Sender:TObject);
    procedure on_FClientScheduler_Disconnected(Sender:TObject);
  private
    FUseNagle: boolean;
    FOnConnected: TNotifyEvent;
    FOnDisconnected: TNotifyEvent;
    FOnReceived: TSuperSocketClientReceivedEvent;
    function GetConnected: boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function Connect(const AHost:string; APort:integer):boolean;
    procedure Disconnect;

    procedure Send(APacket:PPacket);
  published
    property Connected : boolean read GetConnected;
    property UseNagel : boolean read FUseNagle write FUseNagle;
  published
    property OnConnected : TNotifyEvent read FOnConnected write FOnConnected;
    property OnDisconnected : TNotifyEvent read FOnDisconnected write FOnDisconnected;
    property OnReceived : TSuperSocketClientReceivedEvent read FOnReceived write FOnReceived;
  end;

implementation

var
  NilPacket : PPacket;

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

{ TPacket }

procedure TPacket.Clear;
begin
  Header := 0;
  PacketType := 0;
end;

function TPacket.Clone: PPacket;
begin
  GetMem(Result, Size);
  Move(Self, Result^, Size);
end;

function TPacket.GetData: pointer;
begin
  Result := @DataStart;
end;

function TPacket.GetDirection: TPacketDirection;
begin
  Result := TPacketDirection( (Header and $F000) shr 12 );
end;

class function TPacket.GetPacket(ADirection: TPacketDirection;
  APacketType: byte; const AText: string): PPacket;
var
  ssData : TStringStream;
begin
  if AText = '' then begin
    Result := TPacket.GetPacket(ADirection, APacketType, nil, 0);
    Exit;
  end;

  ssData := TStringStream.Create(AText);
  try
    Result := TPacket.GetPacket(ADirection, APacketType, ssData.Memory, ssData.Size);
  finally
    ssData.Free;
  end;
end;

class function TPacket.GetPacket(ADirection:TPacketDirection; APacketType:byte; AData:pointer; ASize:integer): PPacket;
begin
  GetMem(Result, ASize + SizeOf(Word) + SizeOf(Byte));
  Result^.Direction := ADirection;
  Result^.PacketType := APacketType;
  Result^.DataSize := ASize;

  if ASize > 0 then Move(AData^, Result^.Data^, ASize);
end;

function TPacket.GetSize: word;
begin
  Result := GetDataSize + SizeOf(Header) + SizeOf(PacketType);
end;

function TPacket.GetText: string;
var
  ssData : TStringStream;
begin
  ssData := TStringStream.Create;
  try
    ssData.Write(DataStart, GetDataSize);
    ssData.Position := 0;

    Result := Result + ssData.DataString;
  finally
    ssData.Free
  end;
end;

function TPacket.GetDataSize: word;
begin
  Result := Header and $0FFF;
end;

procedure TPacket.SetDirection(const Value: TPacketDirection);
begin
  Header := ((Byte(Value) and $0F) shl 12) or (Header and $0FFF);
end;

procedure TPacket.SetDataSize(const Value: word);
begin
  if Value > (PACKET_SIZE - SizeOf(Header) - SizeOf(PacketType)) then
    raise Exception.Create('TPacket.SetSize - Message');

  Header := (Header and $F000) or (Value and $0FFF);
end;

{ TMemoryPool }

constructor TMemoryPool.Create;
begin
  FQueue := TDynamicQueue.Create(false);
end;

destructor TMemoryPool.Destroy;
begin
  FreeAndNil(FQueue);

  inherited;
end;

function TMemoryPool.Get: pointer;
begin
  if not FQueue.Pop(Result) then GetMem(Result, PACKET_SIZE);
end;

procedure TMemoryPool.Release(AData: pointer);
begin
  FQueue.Push(AData);
end;

{ TConnection }

constructor TConnection.Create;
begin
  inherited;

  FSocket := 0;
  RoomID := '';
  Room := nil;

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

  IdleCount := 0;

  if FSocket <> INVALID_SOCKET then closesocket(FSocket);
  FSocket := INVALID_SOCKET;

  IsLogined := false;

  LocalIP := '';
  FRemoteIP := '';

  LocalPort := 0;
  RemotePort := 0;

  UserData := nil;
  UserName := '';
  UserLevel := 0;

  FPacketReader.Clear;
end;

procedure TConnection.do_PacketIn(AData: pointer; ASize: integer);
var
  PacketPtr : PPacket;
begin
  FPacketReader.Write(UserName, AData, ASize);
  if FPacketReader.canRead then begin
    PacketPtr := FPacketReader.Read;

    if PacketPtr^.DataSize = 0 then Send(NilPacket)
    else if Assigned(FSuperSocketServer.FOnReceived) then FSuperSocketServer.FOnReceived(Self, PacketPtr);
  end;
end;

function TConnection.GetIsConnected: boolean;
begin
  Result := FSocket <> INVALID_SOCKET;
end;

function TConnection.GetText: string;
begin
  Result := 'ID=' + IntToStr(FID);

  if LocalIP <> '' then Result := Result + '<rYu>LocalIP=' + LocalIP;
  if LocalPort <> 0 then Result := Result + '<rYu>LocalPort=' + IntToStr(LocalPort);

  if RemoteIP <> '' then Result := Result + '<rYu>RemoteIP=' + FRemoteIP;
  if RemotePort <> 0 then Result := Result + '<rYu>RemotePort=' + IntToStr(RemotePort);

  if UserID <> '' then Result := Result + '<rYu>UserID=' + UserID;
  if UserName <> '' then Result := Result + '<rYu>UserName=' + UserName;

  if UserLevel <> 0 then Result := Result + '<rYu>UserLevel=' + IntToStr(UserLevel);
end;

procedure TConnection.Send(APacket: PPacket);
begin
  if FSocket <> INVALID_SOCKET then
    FSuperSocketServer.FCompletePort.Send(Self, APacket, APacket^.Size);
end;

{ TIODataPool }

constructor TIODataPool.Create;
begin
  FQueue := TDynamicQueue.Create(false);
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
    raise Exception.Create(SysErrorMessage(WSAGetLastError));

  if listen(FSocket, SOMAXCONN) <> 0 then
    raise Exception.Create(SysErrorMessage(WSAGetLastError));

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
  FSimpleThread := TSimpleThread.Create('TListener.Start', on_FSimpleThread_Execute);
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

function TConnectionList.GetCount: integer;
begin
  Result := FCount;
end;

function TConnectionList.GetConnection(AIndex: integer): TConnection;
begin
  Result := nil;

  if AIndex <> 0 then begin
    Result := FConnections[DWord(AIndex) mod CONNECTION_POOL_SIZE];
    if (Result <> nil) and (Result.FID <> AIndex) then Result := nil;
  end;
end;

procedure TConnectionList.Remove(AConnection: TConnection);
begin
  if AConnection.FID <> 0 then Dec(FCount);
  AConnection.do_Init;
end;

procedure TConnectionList.TerminateAll;
var
  Loop: Integer;
begin
  for Loop := 0 to CONNECTION_POOL_SIZE-1 do FConnections[Loop].do_Init;
end;

{ TSuperSocketServer }

constructor TSuperSocketServer.Create(AOwner: TComponent);
begin
  inherited;

  FConnectionList := TConnectionList.Create(Self);

  FListener := TListener.Create;
  FListener.OnAccepted := on_FListener_Accepted;

  FCompletePort := TCompletePort.Create;
  FCompletePort.OnStart      := on_FCompletePort_Start;
  FCompletePort.OnStop       := on_FCompletePort_Stop;
  FCompletePort.OnAccepted   := on_FCompletePort_Accepted;
  FCompletePort.OnReceived   := on_FCompletePort_Received;
  FCompletePort.OnDisconnect := on_FCompletePort_Disconnect;

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
          if Connection.IsLogined = false then Continue;

          if InterlockedIncrement(Connection.IdleCount) > 2 then begin
            {$IFDEF DEBUG}
            Trace( Format('Connection is in the idle status - UserID: %s', [Connection.UserID]) );
            {$ENDIF}

            Connection.Disconnect;
          end;
        end;

        ASimpleThread.Sleep(10000);
      end;
    end
  );
end;

destructor TSuperSocketServer.Destroy;
begin
  FListener.Stop;

  FIdleCountThread.TerminateNow;

  FreeAndNil(FIdleCountThread);
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

procedure TSuperSocketServer.SendToAll(APacket: PPacket);
var
  Loop: Integer;
begin
  for Loop := 0 to CONNECTION_POOL_SIZE-1 do FConnectionList.FConnections[Loop].Send(APacket);
end;

procedure TSuperSocketServer.SendToID(AID: integer; APacket: PPacket);
var
  Connection : TConnection;
begin
  Connection := FConnectionList.GetConnection(AID);
  if Connection <> nil then Connection.Send(APacket);
end;

procedure TSuperSocketServer.SendToOther(AConnection: TConnection;
  APacket: PPacket);
var
  Loop: Integer;
begin
  for Loop := 0 to CONNECTION_POOL_SIZE-1 do begin
    if FConnectionList.FConnections[Loop] <> AConnection then FConnectionList.FConnections[Loop].Send(APacket);
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

var
  WSAData : TWSAData;

{$IFDEF DEBUG}
  Packet : TPacket;
{$ENDIF}

{ TPacketReader }

function TPacketReader.canRead: boolean;
var
  PacketPtr : PPacket;
begin
  if FOffsetPtr = nil then begin
    Result := false;
    Exit;
  end;

  PacketPtr := Pointer(FOffsetPtr);
  Result := FBufferSize >= PacketPtr^.Size;
end;

procedure TPacketReader.Clear;
begin
  FBufferSize := 0;
  FOffset := 0;
  FCapacity := 0;

  if FBuffer <> nil then FreeMem(FBuffer);
  FBuffer := nil;

  FOffsetPtr := nil;
end;

constructor TPacketReader.Create;
begin
  inherited;

  FBuffer := nil;
  FBufferSize := 0;
  FOffset := 0;
  FCapacity := 0;
  FOffsetPtr := nil;
end;

destructor TPacketReader.Destroy;
begin
  Clear;

  inherited;
end;

function TPacketReader.Read: PPacket;
begin
  Result := nil;

  if not canRead then Exit;

  Result := Pointer(FOffsetPtr);

  FBufferSize := FBufferSize - Result^.Size;
  FOffset := FOffset + Result^.Size;
  FOffsetPtr := FOffsetPtr + Result^.Size;
end;

procedure TPacketReader.VerifyPacket(const AID:string);
var
  PacketPtr : PPacket;
begin
  if not canRead then Exit;

  PacketPtr := Pointer(FOffsetPtr);

  if PacketPtr.Size > PACKET_SIZE then begin
    Trace( Format('TPacketReader.VerifyPacket (%s) - PacketPtr.Size(%d) > PACKET_SIZE', [AID, PacketPtr.Size]) );
    Clear;
  end;
end;

procedure TPacketReader.Write(const AID: string; AData: pointer; ASize: integer);
var
  iNewSize : integer;
  pNewData : pointer;
  pTempIndex : pbyte;
  pOldData : pointer;
begin
  if ASize <= 0 then Exit;

  iNewSize := FBufferSize + ASize;

  if (iNewSize + FOffset) > FCapacity then begin
    FCapacity := ((iNewSize div PACKETREADER_PAGE_SIZE) + 1) * PACKETREADER_PAGE_SIZE;

    GetMem(pNewData, FCapacity);
    pTempIndex := pNewData;

    if FBufferSize > 0 then begin
      Move(FOffsetPtr^, pTempIndex^, FBufferSize);
      pTempIndex := pTempIndex + FBufferSize;
    end;

    Move(AData^, pTempIndex^, ASize);

    FOffset := 0;

    pOldData := FBuffer;
    FBuffer := pNewData;

    if pOldData <> nil then FreeMem(pOldData);

    FOffsetPtr := FBuffer;
  end else begin
    pTempIndex := FOffsetPtr + FBufferSize;
    Move(AData^, pTempIndex^, ASize);
  end;

  FBufferSize := iNewSize;

  VerifyPacket(AID);
end;

{ TClientSocketUnit }

function GetIP(const AHost:AnsiString):AnsiString;
type
  TaPInAddr = array[0..10] of PInAddr;
  PaPInAddr = ^TaPInAddr;
var
  phe: PHostEnt;
  pptr: PaPInAddr;
  i: Integer;
begin
  Result := '';
  phe := GetHostByName(PAnsiChar(AHost));
  if phe = nil then Exit;
  pPtr := PaPInAddr(phe^.h_addr_list);
  i := 0;
  while pPtr^[i] <> nil do begin
    Result := inet_ntoa(pptr^[i]^);
    Inc(i);
  end;
end;

function TClientSocketUnit.Connect(const AHost: string; APort: integer): boolean;
var
  Addr : TSockAddrIn;
begin
  FSocket := Socket(AF_INET, SOCK_STREAM, 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := htons(APort);
  Addr.sin_addr.S_addr := INET_ADDR(PAnsiChar(GetIP(AnsiString(AHost))));

  Result := WinSock2.connect(FSocket, TSockAddr(Addr), SizeOf(Addr)) = 0;

  if Result then begin
    SetSocketDelayOption(FSocket, FUseNagel);
    FSimpleThread := TSimpleThread.Create('TClientSocketUnit.Connect', on_FSimpleThread_Execute);
  end else begin
    FSocket := INVALID_SOCKET;
  end;
end;

constructor TClientSocketUnit.Create;
begin
  inherited;

  FUseNagel := false;
  FSocket := INVALID_SOCKET;

  FPacketReader := TPacketReader.Create;

  FIdleCount := 0;

  FIdleCountThread := TSimpleThread.Create(
    'TClientSocketUnit.FIdleCountThread',
    procedure (ASimpleThread:TSimpleThread)
    begin
      while ASimpleThread.Terminated = false do begin
        if FSocket <> INVALID_SOCKET then begin
          Send(nil);

          // 서버로부터 최소 10초 이상 응답이 없었다면 접속을 끝는다.
          if InterlockedIncrement(FIdleCount) > 1 then begin
            Disconnect;
            if Assigned(FOnDisconnected) then FOnDisconnected(Self);
          end;
        end;

        ASimpleThread.Sleep(10000);
      end;
    end
  );
end;

destructor TClientSocketUnit.Destroy;
begin
  if FSimpleThread <> nil then FSimpleThread.TerminateNow;

  closesocket(FSocket);

  FIdleCountThread.TerminateNow;

  FreeAndNil(FIdleCountThread);
  FreeAndNil(FPacketReader);

  inherited;
end;

procedure TClientSocketUnit.Disconnect;
begin
  if FSocket <> INVALID_SOCKET then closesocket(FSocket);
  FSocket := INVALID_SOCKET;
end;

procedure TClientSocketUnit.do_FireDisconnectedEvent;
begin
  if FSocket = INVALID_SOCKET then Exit;

  closesocket(FSocket);
  FSocket := INVALID_SOCKET;

  if Assigned(FOnDisconnected) then FOnDisconnected(Self);
end;

procedure TClientSocketUnit.on_FSimpleThread_Execute(
  ASimpleThread: TSimpleThread);
var
  PacketPtr : PPacket;
begin
  while not ASimpleThread.Terminated do begin
    PacketPtr := Receive;

    if PacketPtr = nil then begin
      Sleep(1);
      Continue;
    end;

    InterlockedExchange(FIdleCount, 0);

    if Assigned(FOnReceived) and (PacketPtr^.DataSize > 0) then FOnReceived(Self, PacketPtr);
  end;
end;

function TClientSocketUnit.Receive: PPacket;
var
  iRecv : integer;
  Buffer : array [0..PACKETREADER_PAGE_SIZE] of byte;
begin
  Result := nil;

  if FSocket = INVALID_SOCKET then Exit;

  iRecv := recv(FSocket, Buffer, SizeOf(Buffer), 0);

  if iRecv = SOCKET_ERROR then begin
    do_FireDisconnectedEvent;
    Exit;
  end;

  FPacketReader.Write('TClientSocketUnit', @Buffer, iRecv);

  Result := FPacketReader.Read;
end;

procedure TClientSocketUnit.Send(APacket: PPacket);
begin
  if APacket = nil then APacket := NilPacket;  
  if WinSock2.send(FSocket, APacket^, APacket^.Size, 0) = SOCKET_ERROR then do_FireDisconnectedEvent;
end;

{ TClientScheduler }

procedure TClientScheduler.TaskConnected(AClientSocketUnit: TClientSocketUnit);
var
  Schedule : TSchedule;
begin
  AClientSocketUnit.OnDisconnected := on_FClientSocketUnit_Disconnected;

  Schedule := TSchedule.Create;
  Schedule.ScheduleType := stConnected;
  Schedule.ClientSocketUnit := AClientSocketUnit;
  FQueue.Push(Schedule);
end;

constructor TClientScheduler.Create;
begin
  inherited;

  FClientSocketUnit := nil;

  FQueue := TSuspensionQueue<TSchedule>.Create;

  FSimpleThread := TSimpleThread.Create('TClientScheduler.Create', on_FSimpleThread_Execute);
end;

destructor TClientScheduler.Destroy;
begin
  FSimpleThread.TerminateNow;

  ReleaseSocketUnit;
  if FQueue <> nil then FreeAndNil(FQueue);

  inherited;
end;

procedure TClientScheduler.TaskDisconnect;
var
  Schedule : TSchedule;
begin
  Schedule := TSchedule.Create;
  Schedule.ScheduleType := stDisconnect;
  FQueue.Push(Schedule);
end;

procedure TClientScheduler.TaskDisconnected;
var
  Schedule : TSchedule;
begin
  Schedule := TSchedule.Create;
  Schedule.ScheduleType := stDisconnected;
  FQueue.Push(Schedule);
end;

procedure TClientScheduler.do_Send(APacket: PPacket);
begin
  try
    if FClientSocketUnit <> nil then FClientSocketUnit.Send(APacket);
  finally
    FreeMem(APacket);
  end;
end;

procedure TClientScheduler.on_FClientSocketUnit_Disconnected(Sender: TObject);
begin
  TaskDisconnected;
end;

procedure TClientScheduler.on_FSimpleThread_Execute(
  ASimpleThread: TSimpleThread);
var
  Schedule : TSchedule;
begin
  while not ASimpleThread.Terminated do begin
    Schedule := FQueue.Pop;
    try
      case Schedule.ScheduleType of
        stNone: ;
        stConnected: if Assigned(FOnTaskConnected) then FOnTaskConnected(Schedule.ClientSocketUnit);
        stDisconnect: if Assigned(FOnTaskDisconnect) then FOnTaskDisconnect(FClientSocketUnit);
        stDisconnected: if Assigned(FOnTaskDisconnected) then FOnTaskDisconnected(FClientSocketUnit);
        stSend: do_Send(Schedule.PacketPtr);
        stTerminate: Break;
      end;
    finally
      Schedule.Free;
    end;
  end;

  ReleaseSocketUnit;
  if FQueue <> nil then FreeAndNil(FQueue);
end;

procedure TClientScheduler.ReleaseSocketUnit;
begin
  if FClientSocketUnit <> nil then begin
    FClientSocketUnit.OnDisconnected := nil;
    FClientSocketUnit.OnReceived := nil;
    FreeAndNil(FClientSocketUnit);
  end;
end;

procedure TClientScheduler.TaskSend(APacket: PPacket);
var
  Schedule : TSchedule;
begin
  Schedule := TSchedule.Create;
  Schedule.ScheduleType := stSend;
  Schedule.PacketPtr := APacket;
  FQueue.Push(Schedule);
end;

procedure TClientScheduler.TaskTerminate;
var
  Schedule : TSchedule;
begin
  Schedule := TSchedule.Create;
  Schedule.ScheduleType := stTerminate;
  FQueue.Push(Schedule);
end;

procedure TClientScheduler.SetSocketUnit(
  AClientSocketUnit: TClientSocketUnit);
begin
  if FClientSocketUnit <> nil then FClientSocketUnit.Free;
  FClientSocketUnit := AClientSocketUnit;
end;

{ TSuperSocketClient }

function TSuperSocketClient.Connect(const AHost: string; APort: integer): boolean;
var
  ClientSocketUnit : TClientSocketUnit;
begin
  ClientSocketUnit := TClientSocketUnit.Create;
  ClientSocketUnit.UseNagel := FUseNagle;

  if not ClientSocketUnit.Connect(AHost, APort) then begin
    ClientSocketUnit.Free;
    Result := false;
    Exit;
  end;

  ClientSocketUnit.OnReceived := FOnReceived;
  FClientScheduler.TaskConnected(ClientSocketUnit);

  Result := true;
end;

constructor TSuperSocketClient.Create(AOwner: TComponent);
begin
  inherited;

  FUseNagle := false;

  FClientScheduler := TClientScheduler.Create;
  FClientScheduler.OnTaskConnected := on_FClientScheduler_TaskConnected;
  FClientScheduler.OnTaskDisconnect := on_FClientScheduler_TaskDisconnect;
  FClientScheduler.OnTaskDisconnected := on_FClientScheduler_Disconnected;
end;

destructor TSuperSocketClient.Destroy;
begin
  FClientScheduler.TaskTerminate;

  inherited;
end;

procedure TSuperSocketClient.Disconnect;
begin
  FClientScheduler.TaskDisconnect;
end;

function TSuperSocketClient.GetConnected: boolean;
begin
  Result := (FClientScheduler.FClientSocketUnit <> nil) and (FClientScheduler.FClientSocketUnit.FSocket <> INVALID_SOCKET);
end;

procedure TSuperSocketClient.on_FClientScheduler_TaskConnected(AClientSocketUnit:TClientSocketUnit);
begin
  FClientScheduler.SetSocketUnit(AClientSocketUnit);
  if Assigned(FOnConnected) then FOnConnected(Self);  
end;

procedure TSuperSocketClient.on_FClientScheduler_TaskDisconnect(Sender: TObject);
begin
  FClientScheduler.ReleaseSocketUnit;
end;

procedure TSuperSocketClient.on_FClientScheduler_Disconnected(Sender: TObject);
begin
  if Assigned(FOnDisconnected) then FOnDisconnected(Self);  
end;

procedure TSuperSocketClient.Send(APacket: PPacket);
begin
  FClientScheduler.TaskSend(APacket^.Clone);
end;

initialization
  NilPacket := TPacket.GetPacket(pdNone, 0, nil, 0);

  if WSAStartup(WINSOCK_VERSION, WSAData) <> 0 then
    raise Exception.Create(SysErrorMessage(GetLastError));

{$IFDEF DEBUG}
  Packet.Clear;

  Packet.Direction := pdNone;  Assert(Packet.Direction = pdNone, 'Packet.Direction <> pdNone');
  Packet.Direction := pdAll;  Assert(Packet.Direction = pdAll, 'Packet.Direction <> pdAll');
  Packet.Direction := pdOther;  Assert(Packet.Direction = pdOther, 'Packet.Direction <> pdOther');

  Packet.DataSize := 0;  Assert(Packet.DataSize = 0, 'Packet.Direction <> 0');
  Packet.DataSize := 10;  Assert(Packet.DataSize = 10, 'Packet.Direction <> 10');
  Packet.DataSize := 1000;  Assert(Packet.DataSize = 1000, 'Packet.Direction <> 1000');
  Packet.DataSize := 2000;  Assert(Packet.DataSize = 2000, 'Packet.Direction <> 2000');
//  Packet.DataSize := 4096-8;  Assert(Packet.DataSize = 4096-8, 'Packet.Direction <> 4096-8');
{$ENDIF}

finalization
  WSACleanup;
end.
