unit SuperSocketUtils;

interface

uses
  DebugTools, DynamicQueue,
  SysUtils, Classes, WinSock2;

const
  /// Packet size limitation including header.
  PACKET_SIZE = 1024 * 32;

  /// Concurrent connection limitation
  CONNECTION_POOL_SIZE = 4096;

  /// Buffer size of TPacketReader
  PACKETREADER_PAGE_SIZE = PACKET_SIZE * 16;

  MAX_IDLE_MS = 20000;

  ERROR_CONNECT = -1;

type
  {*
    메모리를 사용후 해제하지 않고 큐에 넣어서 재사용한다.
    PACKET_SIZE의 같은 크기의 메모리를 재사용하기 위해 사용.
  }
  TMemoryRecylce = class
  strict private
    FQueue : TDynamicQueue;
  public
    constructor Create;
    destructor Destroy; override;

    function Get:pointer;
    procedure Release(AData:pointer);
  end;

  PPacket = ^TPacket;

  {*
    [Packet] = [PacketSize:word] [PacketType: byte] [Data]
  }
  TPacket = packed record
  strict private
    function GetData: pointer;
    function GetDataSize: word;
    procedure SetDataSize(const Value: word);
    function GetText: string;
  public
    PacketSize : word;
    PacketType : byte;
    DataStart : byte;

    class function GetPacket(APacketType:byte; AData:pointer; ASize:integer):PPacket; overload; static;
    class function GetPacket(APacketType:byte; const AText:string):PPacket; overload; static;

    procedure Clear;
    procedure Clone(APacket:PPacket); overload;
    function Clone:PPacket; overload;
  public
    property Data : pointer read GetData;

    /// Size of [Data]
    property DataSize : word read GetDataSize write SetDataSize;

    /// Convert [Data] to string
    property Text : string read GetText;
  end;

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
    procedure Write(AData:pointer; ASize:integer);
    function Read:PPacket;
    function canRead:boolean;
    function canReadSize:boolean;

    {*
      Check where packet is broken.
      If it is, VerifyPacket will clear all packet inside.
    }
    function VerifyPacket:boolean;
  public
    property BufferSize : integer read FBufferSize;
  end;

  IMemoryPoolObserver = interface
    ['{8E41C992-E8F5-480E-94F1-D30E738506DB}']
    procedure MemoryRefresh;
  end;

  IMemoryPoolControl = interface
    ['{B763D3F8-CABD-4CBA-82A4-A7B5804232AB}']
    procedure AddObserver(AObserver:IMemoryPoolObserver);
    function GetPacketClone(APacket:PPacket):PPacket;
  end;

var
  WSAData : TWSAData;
  NilPacket : TPacket;

function GetIP(const AHost:AnsiString):AnsiString;
procedure SetSocketDelayOption(ASocket:integer; ADelay:boolean);
procedure SetSocketLingerOption(ASocket,ALinger:integer);

implementation

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

{ TMemoryRecylce }

constructor TMemoryRecylce.Create;
begin
  FQueue := TDynamicQueue.Create(false);
end;

destructor TMemoryRecylce.Destroy;
begin
  FreeAndNil(FQueue);

  inherited;
end;

function TMemoryRecylce.Get: pointer;
const
   // 돌려 받은 메모리를 바로 다시 할당하지 않도록 버퍼 공간을 둔다.
   // 혹시라도 아주 짧은 순간에 돌려받은 메모리가 다른 프로세스에서 사용되거나 영향 줄까봐 노파심에
   // 메모리를 조금 더 사용할 뿐 부정적 영향은 없을 거 같아서 추가된 코드 무시해도 된다.
   SPARE_SPACE = 1024;
begin
  if (FQueue.Count < SPARE_SPACE) or (not FQueue.Pop(Result)) then GetMem(Result, PACKET_SIZE);
end;

procedure TMemoryRecylce.Release(AData: pointer);
begin
  FQueue.Push(AData);
end;

{ TPacket }

procedure TPacket.Clear;
begin
  PacketSize := 0;
  PacketType := 0;
end;

function TPacket.Clone: PPacket;
begin
  GetMem(Result, PacketSize);
  Move(Self, Result^, PacketSize);
end;

procedure TPacket.Clone(APacket: PPacket);
begin
  Move(Self, APacket^, PacketSize);
end;

function TPacket.GetData: pointer;
begin
  Result := @DataStart;
end;

class function TPacket.GetPacket(APacketType: byte; const AText: string): PPacket;
var
  utf8 : UTF8String;
begin
  if AText = '' then begin
    Result := TPacket.GetPacket(APacketType, nil, 0);
    Exit;
  end;

  utf8 := AText;
  Result := TPacket.GetPacket(APacketType, @utf8[1], Length(utf8));
end;

class function TPacket.GetPacket(APacketType:byte; AData:pointer; ASize:integer): PPacket;
begin
  GetMem(Result, ASize + SizeOf(Word) + SizeOf(Byte));
  Result^.PacketType := APacketType;
  Result^.DataSize := ASize;

  if ASize > 0 then Move(AData^, Result^.Data^, ASize);
end;

function TPacket.GetText: string;
var
  utf8 : UTF8String;
begin
  SetLength(utf8, GetDataSize);
  Move(DataStart, utf8[1], GetDataSize);
  Result := utf8;
end;

function TPacket.GetDataSize: word;
begin
  Result := PacketSize - SizeOf(Word) - SizeOf(Byte);
end;

procedure TPacket.SetDataSize(const Value: word);
begin
  PacketSize := Value + SizeOf(Word) + SizeOf(Byte);
end;

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
  Result := (FBufferSize > 0) and (FBufferSize >= PacketPtr^.PacketSize);
end;

function TPacketReader.canReadSize: boolean;
var
  PacketPtr : PPacket;
begin
  if FOffsetPtr = nil then begin
    Result := false;
    Exit;
  end;

  PacketPtr := Pointer(FOffsetPtr);
  Result := FBufferSize >= SizeOf(Word);
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

  FBufferSize := FBufferSize - Result^.PacketSize;
  FOffset := FOffset + Result^.PacketSize;
  FOffsetPtr := FOffsetPtr + Result^.PacketSize;
end;

function TPacketReader.VerifyPacket:boolean;
var
  PacketPtr : PPacket;
begin
  Result := true;

  if not canReadSize then Exit;

  PacketPtr := Pointer(FOffsetPtr);
  Result := PacketPtr^.PacketSize <= PACKET_SIZE;

  {$IFDEF DEBUG}
  if Result = false then begin
    Trace( Format('TPacketReader.VerifyPacket - Size: %d', [PacketPtr^.PacketSize]) );
  end;
  {$ENDIF}
end;

procedure TPacketReader.Write(AData: pointer; ASize: integer);
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
end;

initialization
  NilPacket.PacketSize := 3;
  NilPacket.PacketType := 255;

  if WSAStartup(WINSOCK_VERSION, WSAData) <> 0 then
    raise Exception.Create(SysErrorMessage(GetLastError));
finalization
  WSACleanup;
end.
