unit Globals;

interface

uses
  RyuLibBase, DebugTools, SuperSocketUtils,
  SysUtils, Classes, SyncObjs;

const
  {$IFDEF DEBUG}
  MAX_ROOM_COUNT = 4;
  MEMORY_POOL_SIZE = 1024 * 1024 * 64;
  {$ELSE}
  MAX_ROOM_COUNT = 16;
  MEMORY_POOL_SIZE = $200000000;
  {$ENDIF}

  SAFE_ZONE = 64 * 1024;

type
  TMemoryPoolUnit = class (TInterfaceBase, IMemoryPoolControl)
  private
    FMemoryPool : PByte;
    FIndex : PByte;
    FBorder : PByte;
    FCS : TCriticalSection;
    procedure inc_index(ASize:integer);
  public
    constructor Create;
    destructor Destroy; override;

    function GetMem(ASize:integer):pointer;
    function GetPacketClone(APacket:PPacket):PPacket;
  end;

implementation

{ TMemoryPoolUnit }

constructor TMemoryPoolUnit.Create;
begin
  inherited;

  System.GetMem(FMemoryPool, MEMORY_POOL_SIZE);

  FIndex := FMemoryPool;

  FBorder := FMemoryPool;
  Dec(FBorder, SAFE_ZONE);

  FCS := TCriticalSection.Create;
end;

destructor TMemoryPoolUnit.Destroy;
begin
  FreeMem(FMemoryPool);
  FreeAndNil(FCS);

  inherited;
end;

function TMemoryPoolUnit.GetMem(ASize: integer): pointer;
begin
  FCS.Acquire;
  try
    Result := Pointer(FIndex);
    inc_index(ASize);
  finally
    FCS.Release;
  end;
end;

function TMemoryPoolUnit.GetPacketClone(APacket: PPacket): PPacket;
begin
  if APacket = nil then begin
    {$IFDEF DEBUG}
    Trace('TMemoryPoolUnit.GetPacketClone - APacket = nil');
    {$ENDIF}

    Result := nil;
    Exit;
  end;

  if APacket^.PacketSize > PACKET_SIZE then begin
    {$IFDEF DEBUG}
    Trace( Format('TMemoryPoolUnit.GetPacketClone - PacketSize: %d, PacketType: %d', [APacket^.PacketSize, APacket^.PacketType]) );
    {$ENDIF}

    Result := nil;
    Exit;
  end;

  FCS.Acquire;
  try
    Result := Pointer(FIndex);
    inc_index(APacket^.PacketSize);
  finally
    FCS.Release;
  end;

  Move(APacket^, Result^, APacket^.PacketSize);
end;

procedure TMemoryPoolUnit.inc_index(ASize: integer);
begin
  Inc(FIndex, ASize);
  if FIndex >= FBorder then FIndex := FMemoryPool;
end;

end.
