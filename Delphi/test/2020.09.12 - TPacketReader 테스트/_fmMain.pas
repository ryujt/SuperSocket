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
      size := Random(2048) + 3;

      index := FBuffer;
      packet := Pointer(index);
      packet.PacketSize := size;
      index := index + size;
      packet := Pointer(index);
      packet.PacketSize := size;

      for i := 1 to 1024 do FPacketReader.Write(FBuffer, size * 2);

      while true do begin
        result := FPacketReader.GetPacket;
        if result = nil then Break;
        
        Assert(result^.PacketSize = size);

        FreeMem(result);
      end;
    end;
  except
    on E : Exception do Caption := Format('size: %d, result^.PacketSize: %d', [size, result^.PacketSize, E.Message]);
  end;
end;

procedure TfmMain.FormCreate(Sender: TObject);
begin
  GetMem(FBuffer, PACKET_SIZE * 2);
  FPacketReader := TPacketReader.Create;
end;

end.
