unit ControlServer;

interface

uses
  P2P.Base,
  ControlServer.ServerUnitTCP,
  ControlServer.ServerUnitUDP,
  SysUtils, Classes;

type
  TControlServer = class
  private
     FServerUnitTCP : TServerUnitTCP;
     FServerUnitUDP : TServerUnitUDP;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Start;
    procedure Stop;
  end;

implementation

{ TControlServer }

constructor TControlServer.Create;
begin
  inherited;

   FServerUnitTCP := TServerUnitTCP.Create;
   FServerUnitUDP := TServerUnitUDP.Create;
end;

destructor TControlServer.Destroy;
begin
  Stop;

//  FreeAndNil(FServerUnitTCP);
//  FreeAndNil(FServerUnitUDP);

  inherited;
end;

procedure TControlServer.Start;
begin
  FServerUnitTCP.Start(TCP_PORT);
  FServerUnitUDP.Start(UDP_PORT);
end;

procedure TControlServer.Stop;
begin
  FServerUnitTCP.Stop;
  FServerUnitUDP.Stop;
end;

end.
