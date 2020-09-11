unit SuperSocketClient;

interface

uses
  SuperSocketUtils,
  RyuLibBase, DebugTools, SimpleThread, DynamicQueue,
  Windows, SysUtils, Classes, WinSock2;

type
  TSuperSocketClient = class;

  TIOStatus = (ioConnect, ioDisconnect, ioDisconnected, ioSend, ioRecv, ioIdleCountTimeout, ioTerminate);

  TIOData = record
    Overlapped : OVERLAPPED;
    wsaBuffer : TWSABUF;
    Status: TIOStatus;
    Socket : integer;
    Host : string;
    Port : integer;
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

  TCompletePort = class
  strict private
    FSocketClient : TSuperSocketClient;
    FSocket : TSocket;
    FPacketReader : TPacketReader;
    FCompletionPort : THandle;
    FIODataPool : TIODataPool;
    FMemoryPool : TMemoryPool;

    procedure start_Receive;

    procedure do_Connect(AData:PIOData);
    procedure do_Disconnect;
    procedure do_DisconnectWithEvent;
    procedure do_Receive(AData:pointer; ASize:integer);
    procedure do_Terminate;
  strict private
    FSimpleThread : TSimpleThread;
    procedure on_FSimpleThread_Execute(ASimpleThread:TSimpleThread);
  strict private
    FOldTick : DWORD;
    FUseNagel: boolean;
  public
    IdleCount : integer;

    constructor Create(ASocketClient:TSuperSocketClient); reintroduce;
    destructor Destroy; override;

    procedure Terminate;
    procedure TerminateNow;

    procedure Connect(const AHost:string; APort:integer);
    procedure Disconnect;
    procedure Send(APacket:PPacket);
    procedure IdleCountTimeout;
  private
    function GetConnected: boolean;
  public
    property UseNagel : boolean read FUseNagel write FUseNagel;
    property Connected : boolean read GetConnected;
  end;

  TSuperSocketClientErrorEvent = procedure (Sender:TObject; AErrorCode:integer; const AMsg:string) of object;
  TSuperSocketClientReceivedEvent = procedure (ASender:TObject; APacket:PPacket) of object;

  TSuperSocketClient = class
  private
    FCompletePort : TCompletePort;
    FIdleCountThread : TSimpleThread;
  private
    FOnError: TSuperSocketClientErrorEvent;
    FOnConnected: TNotifyEvent;
    FOnDisconnected: TNotifyEvent;
    FOnReceived: TSuperSocketClientReceivedEvent;
    function GetConnected: boolean;
    function GetUseNagle: boolean;
    procedure SetUseNagle(const Value: boolean);
  public
    constructor Create(AIdleCheck:boolean=false); reintroduce;
    destructor Destroy; override;

    /// Terminate all internal thread and functions.
    procedure Terminate;

    {* Connect to the server.
    @param AHost Host name of the server.
    @param APort Port number of the server.
    }
    procedure Connect(const AHost:string; APort:integer);

    /// Disconnect the current connection.
    procedure Disconnect;

    {* Send a packet to the current connection.
    @param APacket a message to send.
    }
    procedure Send(APacket:PPacket);
  public
    /// Indicates whether the connection is connected.
    property Connected : boolean read GetConnected;

    /// Specifies whether to use nagle algorithm.
    property UseNagel : boolean read GetUseNagle write SetUseNagle;
  public
    /// Use OnError to perform special processing when the error raised.
    property OnError : TSuperSocketClientErrorEvent read FOnError write FOnError;

    /// Use OnConnected to perform special processing when the connection created.
    property OnConnected : TNotifyEvent read FOnConnected write FOnConnected;

    /// Use OnDisconnected to perform special processing when the connection disconnected.
    property OnDisconnected : TNotifyEvent read FOnDisconnected write FOnDisconnected;

    /// Use OnDisconnected to perform special processing when the connection has new packet.
    property OnReceived : TSuperSocketClientReceivedEvent read FOnReceived write FOnReceived;
  end;

implementation

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

{ TCompletePort }

procedure TCompletePort.Connect(const AHost: string; APort: integer);
var
  pData : PIOData;
begin
  pData := FIODataPool.Get;
  pData^.Status := ioConnect;
  pData^.Host := AHost;
  pData^.Port := APort;

  if not PostQueuedCompletionStatus(FCompletionPort, SizeOf(pData), 0, POverlapped(pData)) then begin
    Trace('TSuperSocketClient.Connect - PostQueuedCompletionStatus Error');
    FIODataPool.Release(pData);
  end;
end;

constructor TCompletePort.Create(ASocketClient:TSuperSocketClient);
begin
  inherited Create;

  FSocketClient := ASocketClient;

  FSocket := INVALID_SOCKET;
  FUseNagel := false;
  FOldTick := 0;
  IdleCount := 0;

  FCompletionPort := CreateIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, 0);
  FPacketReader := TPacketReader.Create;
  FIODataPool := TIODataPool.Create;
  FMemoryPool := TMemoryPool.Create;
  FSimpleThread := TSimpleThread.Create('TSuperSocketClient.CompletePort', on_FSimpleThread_Execute);
end;

destructor TCompletePort.Destroy;
begin
  do_Terminate;

  inherited;
end;

procedure TCompletePort.Disconnect;
var
  pData : PIOData;
begin
  pData := FIODataPool.Get;
  pData^.Status := ioDisconnect;

  if not PostQueuedCompletionStatus(FCompletionPort, SizeOf(pData), 0, POverlapped(pData)) then begin
    Trace('TSuperSocketClient.Disconnect - PostQueuedCompletionStatus Error');
    FIODataPool.Release(pData);
  end;
end;

procedure TCompletePort.do_Connect(AData: PIOData);

var
  Addr : TSockAddrIn;
begin
  FSimpleThread.Name := Format('TCompletePort.CompletePort(%d)', [AData^.Port]);

  FPacketReader.Clear;

  IdleCount := 0;

  do_Disconnect;

  FSocket := WSASocket(AF_INET, SOCK_STREAM, 0, nil, 0, WSA_FLAG_OVERLAPPED);
  if FSocket = INVALID_SOCKET then
    raise Exception.Create(SysErrorMessage(WSAGetLastError));

  FillChar(Addr, SizeOf(TSockAddrIn), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := htons(AData^.Port);
  Addr.sin_addr.S_addr := INET_ADDR(PAnsiChar(GetIP(AnsiString(AData^.Host))));

  if WinSock2.connect(FSocket, TSockAddr(Addr), SizeOf(Addr)) = 0 then begin
    SetSocketDelayOption(FSocket, FUseNagel);

    if CreateIoCompletionPort(FSocket, FCompletionPort, 0, 0) = 0 then begin
      Trace('TSuperSocketClient.CreateIoCompletionPort Error');
      closesocket(FSocket);
      FSocket := INVALID_SOCKET;
      Exit;
    end;

    if Assigned(FSocketClient.FOnConnected) then FSocketClient.FOnConnected(FSocketClient);

    start_Receive;

  end else begin
    FSocket := INVALID_SOCKET;
    if Assigned(FSocketClient.FOnError) then FSocketClient.FOnError(FSocketClient, -1, 'Connection failed.');
  end;
end;

procedure TCompletePort.do_Disconnect;
begin
  if FSocket = INVALID_SOCKET then Exit;

  closesocket(FSocket);
  FSocket := INVALID_SOCKET;
end;

procedure TCompletePort.do_DisconnectWithEvent;
begin
  if FSocket = INVALID_SOCKET then Exit;

  {$IFDEF DEBUG}
  Trace('TCompletePort - do_DisconnectWithEvent');
  {$ENDIF}

  closesocket(FSocket);
  FSocket := INVALID_SOCKET;

  if Assigned(FSocketClient.FOnDisconnected) then FSocketClient.FOnDisconnected(FSocketClient);
end;

procedure TCompletePort.do_Receive(AData: pointer; ASize: integer);
var
  PacketPtr : PPacket;
begin
  IdleCount := 0;

  FPacketReader.Write(AData, ASize);

  if FPacketReader.VerifyPacket = false then begin
    Trace('TCompletePort.do_Receive - FPacketReader.VerifyPacket = false, ');
    Disconnect;
    Exit;
  end;

  while FPacketReader.canRead do begin
    PacketPtr := FPacketReader.Read;
    if Assigned(FSocketClient.FOnReceived) then FSocketClient.FOnReceived(FSocketClient, PacketPtr);

    if FPacketReader.VerifyPacket = false then begin
      Trace('TCompletePort.do_Receive - FPacketReader.VerifyPacket = false, ');
      Disconnect;
      Exit;
    end;
  end;
end;

procedure TCompletePort.do_Terminate;
begin
  if FSocket <> INVALID_SOCKET then closesocket(FSocket);
  FSocket := INVALID_SOCKET;

  if FSimpleThread <> nil then FSimpleThread.Terminate;
end;

function TCompletePort.GetConnected: boolean;
begin
  Result := FSocket <> INVALID_SOCKET;
end;

procedure TCompletePort.IdleCountTimeout;
var
  pData : PIOData;
begin
  pData := FIODataPool.Get;
  pData^.Status := ioIdleCountTimeout;

  if not PostQueuedCompletionStatus(FCompletionPort, SizeOf(pData), 0, POverlapped(pData)) then begin
    Trace('TSuperSocketClient.IdleCountTimeout - PostQueuedCompletionStatus Error');
    FIODataPool.Release(pData);
  end;
end;

procedure TCompletePort.on_FSimpleThread_Execute(ASimpleThread: TSimpleThread);
var
  pData : PIOData;
  Transferred : DWord;
  Key : NativeUInt;
  LastError : integer;
  isGetOk, isCondition : boolean;
begin
  while not ASimpleThread.Terminated do begin
    isGetOk := GetQueuedCompletionStatus(FCompletionPort, Transferred, Key, POverlapped(pData), INFINITE);

    isCondition :=
      (pData <> nil) and ((Transferred = 0) or (not isGetOk));
    if isCondition then begin
      if not isGetOk then begin
        LastError := WSAGetLastError;
        Trace(Format('TSuperSocketClient.on_FSimpleThread_Execute - %s', [SysErrorMessage(LastError)]));
      end;

      do_DisconnectWithEvent;
      if pData <> nil then FIODataPool.Release(pData);

      Continue;
    end;

    if pData = nil then Continue;

    case pData^.Status of
      ioConnect: do_Connect(pData);
      ioDisconnect: do_Disconnect;

      ioSend:FreeMem(pData^.wsaBuffer.buf);

      ioRecv: begin
        start_Receive;
        do_Receive(pData^.wsaBuffer.buf, Transferred);
        FMemoryPool.Release(pData.wsaBuffer.buf);
      end;

      ioTerminate: do_Terminate;
      ioIdleCountTimeout: do_DisconnectWithEvent;
    end;

    FIODataPool.Release(pData);
  end;

  do_Disconnect;

  FreeAndNil(FPacketReader);
  FreeAndNil(FIODataPool);
  FreeAndNil(FMemoryPool);
  CloseHandle(FCompletionPort);
end;

procedure TCompletePort.start_Receive;
var
  pData : PIOData;
  byteRecv, dwFlags: DWord;
  recv_ret, LastError: Integer;
begin
  if FSocket = INVALID_SOCKET then Exit;

  pData := FIODataPool.Get;
  PData^.wsaBuffer.buf := FMemoryPool.Get;
  pData^.wsaBuffer.len := PACKET_SIZE;
  pData^.Status := ioRecv;

  dwFlags := 0;
  recv_ret := WSARecv(FSocket, LPWSABUF(@pData^.wsaBuffer), 1, byteRecv, dwFlags, LPWSAOVERLAPPED(pData), nil);

  if recv_ret = SOCKET_ERROR then begin
    LastError := WSAGetLastError;
    if LastError <> ERROR_IO_PENDING then begin
      Trace(Format('TSuperSocketClient.start_Receive - %s', [SysErrorMessage(LastError)]));

      do_DisconnectWithEvent;
      FIODataPool.Release(pData);
    end;
  end;
end;

procedure TCompletePort.Terminate;
var
  pData : PIOData;
begin
  pData := FIODataPool.Get;
  pData^.Status := ioTerminate;

  if not PostQueuedCompletionStatus(FCompletionPort, SizeOf(pData), 0, POverlapped(pData)) then begin
    Trace('TSuperSocketClient.Terminate - PostQueuedCompletionStatus Error');
    FIODataPool.Release(pData);
  end;
end;

procedure TCompletePort.TerminateNow;
begin
  FSimpleThread.TerminateNow;
end;

procedure TCompletePort.Send(APacket: PPacket);
var
  packet : PPacket;
  pData : PIOData;
  BytesSent, Flags: DWORD;
  ErrorCode, LastError : integer;
begin
  if FSocket = INVALID_SOCKET then Exit;

  packet := APacket.Clone;

  pData := FIODataPool.Get;
  PData^.wsaBuffer.buf := Pointer(packet);
  pData^.wsaBuffer.len := packet^.PacketSize;
  pData^.Status := ioSend;

  Flags := 0;
  ErrorCode := WSASend(FSocket, @(PData^.wsaBuffer), 1, BytesSent, Flags, Pointer(pData), nil);

  if ErrorCode = SOCKET_ERROR then begin
    LastError := WSAGetLastError;
    if LastError <> ERROR_IO_PENDING then begin
      Trace(Format('TSuperSocketClient.Send - %s', [SysErrorMessage(LastError)]));

      do_DisconnectWithEvent;
      FreeMem(packet);
      FIODataPool.Release(pData);
    end;
  end;
end;

{ TSuperSocketClient }

procedure TSuperSocketClient.Connect(const AHost: string; APort: integer);
begin
  FCompletePort.Connect(AHost, APort);
end;

constructor TSuperSocketClient.Create(AIdleCheck:boolean);
begin
  inherited Create;

  FCompletePort := TCompletePort.Create(Self);

  if not AIdleCheck then begin
    FIdleCountThread := nil;
    Exit;
  end;

  FIdleCountThread := TSimpleThread.Create(
    'TSuperSocketClient.IdleCount',
    procedure (ASimpleThread:TSimpleThread)
    begin
      while ASimpleThread.Terminated = false do begin
        if FCompletePort.Connected and (InterlockedIncrement(FCompletePort.IdleCount) > 5) then begin
          FCompletePort.IdleCountTimeout;

          {$IFDEF DEBUG}
          Trace( Format('TSuperSocketClient - Disconnected for IdleCount (%d)', [FCompletePort.IdleCount]) );
          {$ENDIF}
        end;

        Send(@NilPacket);

        ASimpleThread.Sleep(MAX_IDLE_MS div 5);
      end;
    end
  );
end;

destructor TSuperSocketClient.Destroy;
begin
  Terminate;

  inherited;
end;

procedure TSuperSocketClient.Disconnect;
begin
  FCompletePort.Disconnect;
end;

function TSuperSocketClient.GetConnected: boolean;
begin
  Result := FCompletePort.Connected;
end;

function TSuperSocketClient.GetUseNagle: boolean;
begin
  Result := FCompletePort.UseNagel;
end;

procedure TSuperSocketClient.Send(APacket: PPacket);
begin
  FCompletePort.Send(APacket);
end;

procedure TSuperSocketClient.SetUseNagle(const Value: boolean);
begin
  FCompletePort.UseNagel := Value;
end;

procedure TSuperSocketClient.Terminate;
begin
  if FIdleCountThread <> nil then FIdleCountThread.TerminateNow;
  FCompletePort.TerminateNow;
end;

end.
