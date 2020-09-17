unit _fmMain;

interface

uses
  DebugTools, SuperSocketUtils,
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TfmMain = class(TForm)
    moResult: TMemo;
    Panel1: TPanel;
    btStart: TButton;
    Button1: TButton;
    procedure btStartClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure Button1Click(Sender: TObject);
  private
    FBuffer : pointer;
    FPacketReader : TPacketReader;
  public
  end;

var
  fmMain: TfmMain;

implementation

{$R *.dfm}

procedure TfmMain.btStartClick(Sender: TObject);
var
  packet, result : PPacket;
  index : PByte;
  i, size: Integer;
begin
  try
    while true do begin
      size := Random(2048);

      index := FBuffer;
      packet := Pointer(index);
      packet.PacketSize := size;
      index := index + size;
      packet := Pointer(index);
      packet.PacketSize := size;

      for i := 1 to 1024 do FPacketReader.Write(FBuffer, size * 2);

      while FPacketReader.canRead do begin
        result := FPacketReader.Read;
        Assert(result^.PacketSize = size);
      end;
    end;
  except
    on E : Exception do Caption := Format('size: %d, result^.PacketSize: %d', [size, result^.PacketSize, E.Message]);
  end;
end;

procedure TfmMain.Button1Click(Sender: TObject);
var
  packet : TPacket;
  result_packet : PPacket;
  i, count_write, write_bytes, write_size : integer;
begin
  Packet.PacketType := 0;

  Randomize;

  while true do begin
    count_write := Random(10);

    for i := 1 to count_write do begin
      packet.PacketSize := Random(PACKET_SIZE div 2) + 1;
      if packet.PacketSize > PACKET_SIZE then begin
        Trace('packet.PacketSize > PACKET_SIZE');
      end;

      FPacketReader.Write(@packet, 3);

      write_bytes := 0;
      while write_bytes < packet.PacketSize do begin
        write_size := Random(packet.PacketSize) + 1;
        if (write_bytes + write_size) > packet.PacketSize then write_size := packet.PacketSize - write_bytes;
        FPacketReader.Write(FBuffer, write_size);
        FPacketReader.VerifyPacket;
        write_bytes := write_bytes + write_size;
      end;
    end;

    while FPacketReader.BufferSize > PACKET_SIZE do begin
      if FPacketReader.canRead then begin
        result_packet := FPacketReader.Read;
        if result_packet^.PacketSize > PACKET_SIZE then begin
          Trace('result_packet^.PacketSize > PACKET_SIZE');
        end;
      end;
    end;

  end;
end;

procedure TfmMain.FormCreate(Sender: TObject);
begin
  GetMem(FBuffer, PACKET_SIZE * 2);
  FPacketReader := TPacketReader.Create;
end;

end.
