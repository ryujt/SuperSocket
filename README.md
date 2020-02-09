# Delphi IOCP Socket Library

## Requirement
* RyuLib for Delphi: https://github.com/ryujt/ryulib-delphi

## 참고 사이트
* [http://10bun.tv/](http://10bun.tv/)

## Pakcet 구조
[Packet] = [PacketSize][PacketType][DataStart]
* SuperSocket은 패킷을 보낼 때 패킷 전체의 크기를 보내고, 이어서 PacketType과 실제 패킷을 보냅니다.

## 패킷 생성 방법
``` delphi
var
  packet : PPacket
begin
  packet := TPacket.GetPacket(0, data, size);
  
  // TPacket.GetPacket(APacketType:byte; AData:pointer; ASize:integer):PPacket; overload; static;  
  // TPacket.GetPacket(APacketType:byte; const AText:string):PPacket; overload; static;
```

## 메모리 풀의 사용
```
uses
  SuperSocketUtils, SuperSocketServer, MemoryPool ...;

function GetPacketClone(AMemoryPool: TMemoryPool; APacket: PPacket): PPacket;

implementation

function GetPacketClone(AMemoryPool: TMemoryPool; APacket: PPacket): PPacket;
begin
  if APacket^.PacketSize = 0 then begin
    Result := nil;
    Exit;
  end;

  AMemoryPool.GetMem(Pointer(Result), APacket^.PacketSize);
  APacket^.Clone(Result);
end;

procedure TServerUnit.on_FSocket_Received(AConnection: TConnection; APacket: PPacket);
var
  packet: PPacket;
begin
  Packet := GetPacketClone(FMemoryPool, APacket);
  if Packet = nil then Exit;

  case packet^.PacketType of
    0: ;
    1: ;
end;
```
* 받은 패킷을 다시 클라이언트에 보낼 일이 있다면 메모리 풀을 이용해야 합니다. 패킷은 비동기로 처리되기 때문에 Send..() 메소드를 사용하고 나서 바로 패킷을 삭제하면 안되기 때문입니다. 내부에서 자동으로 메모리를 삭제할 수는 있지만, 메모리 복사 등에 소비되는 CPU 소모를 피하기 위해서 메모리 풀과 함께 사용하도록 설계되어 있습니다.
* 클라이언트 소켓은 메모리 풀을 사용할 필요가 없습니다.
