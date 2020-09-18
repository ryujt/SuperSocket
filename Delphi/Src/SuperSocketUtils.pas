unit SuperSocketUtils;

interface

uses
  RyuLibBase, DebugTools,
  Generics.Collections,
  SysUtils, Classes, WinSock2;

const
  /// Packet size limitation including header.
  PACKET_SIZE = 1024 * 32;

  /// Concurrent connection limitation
  CONNECTION_POOL_SIZE = 4096;

  /// Buffer size of TPacketReader (+ safe zone)
  PACKETREADER_BUFFER_SIZE = PACKET_SIZE * 2 + 1024;

  MAX_IDLE_MS = 20000;

  ERROR_CONNECT = -1;

type
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

  TPacketList = TList<PPacket>;

  TPacketReader = class
  strict private
    FBuffer : pbyte;
    FDataSize : integer;
    FPacketList : TPacketList;
    function can_add(AOffset:pbyte): boolean;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    procedure Write(AData:pointer; ASize:integer);
    function GetPacket:PPacket;
  end;

  IMemoryPoolControl = interface
    ['{B763D3F8-CABD-4CBA-82A4-A7B5804232AB}']
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

procedure TPacketReader.Clear;
var
  i: Integer;
begin
  for i := 0 to FPacketList.Count - 1 do FreeMem(FPacketList[0]);
  FPacketList.Clear;
  FDataSize := 0;
end;

constructor TPacketReader.Create;
begin
  inherited;

  FDataSize := 0;

  GetMem(FBuffer, PACKETREADER_BUFFER_SIZE);
  FPacketList := TPacketList.Create;
end;

destructor TPacketReader.Destroy;
begin
  Clear;

  FreeMem(FBuffer);

  inherited;
end;

function TPacketReader.GetPacket: PPacket;
begin
  Result := nil;

  if FPacketList.Count = 0 then Exit;

  Result := FPacketList[0];
  FPacketList.Delete(0);
end;

function TPacketReader.can_add(AOffset:pbyte): boolean;
var
  PacketPtr : PPacket absolute AOffset;
begin
  if FDataSize < SizeOf(PacketPtr^.PacketSize) then begin
    Result := false;
    Exit;
  end;

  Result := FDataSize >= PacketPtr^.PacketSize;
end;

procedure TPacketReader.Write(AData: pointer; ASize: integer);
var
  offset : pbyte;
  PacketPtr : PPacket;
begin
  offset := FBuffer + FDataSize;

  Move(AData^, offset^, ASize);
  FDataSize := FDataSize + ASize;

  while can_add(offset) do begin
    PacketPtr := Pointer(offset);
    FPacketList.Add( PacketPtr^.Clone );

    {$IFDEF DEBUG}
    if PacketPtr^.PacketSize > PACKET_SIZE then Trace('TPacketReader.Write - PacketPtr^.PacketSize > PACKET_SIZE');
    {$ENDIF}

    offset := offset + PacketPtr^.PacketSize;
    FDataSize := FDataSize - PacketPtr^.PacketSize;

    {$IFDEF DEBUG}
    if FDataSize < 0 then Trace('TPacketReader.Write - FDataSize < 0');
    {$ENDIF}
  end;

  if FDataSize > 0 then Move(offset^, FBuffer^, FDataSize);  
end;

initialization
  NilPacket.PacketSize := 3;
  NilPacket.PacketType := 255;

  if WSAStartup(WINSOCK_VERSION, WSAData) <> 0 then
    raise Exception.Create(SysErrorMessage(GetLastError));
finalization
  WSACleanup;
end.
