unit _fmMain;

interface

uses
  DebugTools, MemoryPool, LazyRelease,
  SuperSocketUtils, SuperSocketServer, SuperSocketClient,
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TForm1 = class(TForm)
    Button1: TButton;
    Timer: TTimer;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure TimerTimer(Sender: TObject);
  private
    FMemoryPool : TMemoryPool;
    FLazyRelease : TLazyRelease;
    function GetPacketClone(APacket:PPacket):PPacket;
    function make_packet:PPacket;
    procedure check_packet(const ATag:string; APacket:PPacket);
  private
    FServer : TSuperSocketServer;
    procedure on_server_connected(AConnection:TConnection);
    procedure on_server_received(AConnection:TConnection; APacket:PPacket);
  private
    FClient1 : TSuperSocketClient;
    procedure on_FClient1_received(ASender:TObject; APacket:PPacket);
  private
    FClient2 : TSuperSocketClient;
    procedure on_FClient2_received(ASender:TObject; APacket:PPacket);
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

procedure TForm1.Button1Click(Sender: TObject);
begin
  Timer.Enabled := not Timer.Enabled;
  if Timer.Enabled then Button1.Caption := 'Started'
  else Button1.Caption := 'Stoped';
end;

procedure TForm1.check_packet(const ATag: string; APacket: PPacket);
var
  i: Integer;
  check : pbyte;
  check_sum : byte;
begin
  if APacket^.DataSize = 0 then Exit;

  check_sum := APacket^.PacketSize mod 256;

  if check_sum <> APacket^.PacketType then begin
    Trace(ATag + ' - check_sum <> APacket^.PacketType');
  end;

  check := @APacket^.DataStart;
  for i := 1 to APacket^.DataSize do begin
    if check_sum <> check^ then begin
      Trace(ATag + ' - check_sum <> check^');
    end;
    Inc(check);
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  FMemoryPool := TMemoryPool32.Create(1024 * 1024 * 64);
  FLazyRelease := TLazyRelease.Create('', 1024 * 32);

  FServer := TSuperSocketServer.Create(true);
  FServer.OnConnected := on_server_connected;
  FServer.OnReceived := on_server_received;

  FClient1 := TSuperSocketClient.Create(true);
  FClient1.OnReceived := on_FClient1_received;

  FClient2 := TSuperSocketClient.Create(true);
  FClient2.OnReceived := on_FClient2_received;

  FServer.Port := 1234;
  FServer.Start;

  FClient1.Connect('127.0.0.1', 1234);
  FClient2.Connect('127.0.0.1', 1234);
end;

function TForm1.GetPacketClone(APacket: PPacket): PPacket;
begin
//  Result := FMemoryPool.GetMem(APacket^.PacketSize);
  GetMem(Result, APacket^.PacketSize);
  FLazyRelease.Release(Result);

  Move(APacket^, Result^, APacket^.PacketSize);
end;

function TForm1.make_packet: PPacket;
var
  check_sum : byte;
  size : integer;
begin
  size := Random(1024 * 32 - 3) + 3;
  check_sum := size mod 256;

//  Result := FMemoryPool.GetMem(size);
  GetMem(Result, size);
  FLazyRelease.Release(Result);

  Result^.PacketSize := size;
  Result^.PacketType := check_sum;
  FillChar(Result^.DataStart, size - 3, check_sum);

  check_packet('make_packet', Result);
end;

procedure TForm1.on_FClient1_received(ASender: TObject; APacket: PPacket);
begin
  check_packet('on_FClient1_received', APacket);
end;

procedure TForm1.on_FClient2_received(ASender: TObject; APacket: PPacket);
begin
  check_packet('on_FClient2_received', APacket);
end;

procedure TForm1.on_server_connected(AConnection: TConnection);
begin
  Trace( Format('on_server_connected - ID: %d', [AConnection.ID]) );
end;

procedure TForm1.on_server_received(AConnection: TConnection; APacket: PPacket);
var
  packet : PPacket;
begin
  check_packet('on_server_received', APacket);

  packet := GetPacketClone(APacket);
  if packet <> nil then FServer.SendToOther(AConnection, packet);  
end;

procedure TForm1.TimerTimer(Sender: TObject);
var
  i: Integer;
begin
  Timer.OnTimer := nil;
  try
    for i := 1 to 32 do FClient1.Send(make_packet);
  finally
    Timer.OnTimer := TimerTimer;
  end;
end;

end.
