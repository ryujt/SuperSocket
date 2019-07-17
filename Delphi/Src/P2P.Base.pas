unit P2P.Base;

interface

uses
  Classes, SysUtils;

const
  TCP_PORT = 8899;
  UDP_PORT = 9988;

type
  TPacketType = (
    ptLogin, ptErLogin, ptOkLogin,
    ptIDinUse, ptUserLimit,
    ptUserList, ptUserIn, ptUserOut,

    ptTextTCP, ptDataTCP
  );

  TUDP_PacketType = (
    ptPing, ptPong,

    // 연결이 가능한 지 확인 메시지를 보내고 답장을 받는다.
    ptHello, ptHi,

    ptTextUDP, ptDataUDP,

    // Text, Data 패킷을 받았는 지 확인,
    // 보낸 개수와 받은 개수의 차이만 처리하여 응답이 부족하면 접속을 끊어 버린다. (홀을 닫는다)
    ptASK
  );

  TPacketToID = packed record
    ConnectionID : integer;
    Data : packed array [0..4096] of byte;
  end;
  PPacketToID = ^TPacketToID;

var
  {$IFDEF CPUX86}
  SERVER_MEMORYPOOL_SIZE : int64 =  256 * 1024 * 1024;
  {$ENDIF}

  {$IFDEF CPUX64}
  SERVER_MEMORYPOOL_SIZE : int64 = 4 * 1024 * 1024 * 1024;
  {$ENDIF}

implementation

end.
