unit _fmMain;

interface

uses
  P2P.Base,
  DebugTools, MemoryPool, ControlServer,
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.AppEvnts;

type
  TfmMain = class(TForm)
    ApplicationEvents: TApplicationEvents;
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormDestroy(Sender: TObject);
    procedure ApplicationEventsException(Sender: TObject; E: Exception);
  private
    FControlServer : TControlServer;
  public
  end;

var
  fmMain: TfmMain;

implementation

{$R *.dfm}

procedure TfmMain.ApplicationEventsException(Sender: TObject; E: Exception);
begin
  Trace('P2P Server - ' + E.Message);
end;

procedure TfmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FControlServer.Stop;
end;

procedure TfmMain.FormCreate(Sender: TObject);
begin
  CreateMemoryPool(SERVER_MEMORYPOOL_SIZE);

  FControlServer := TControlServer.Create;
  FControlServer.Start;
end;

procedure TfmMain.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FControlServer);
end;

end.
