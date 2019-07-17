unit Database;

interface

uses
  SuperSocket, SimpleThread, SuspensionQueue, ValueList,
  SysUtils, Classes;

const
  THREAD_COUNT = 8;

type
  TDatabase = class;

  TDatabaseRequestBase = class
  private
    Database : TDatabase;
    Connection : TConnection;
    Packet : PPacket;
  public
    constructor Create(ADatabase:TDatabase; AConnection:TConnection; APacket:PPacket); reintroduce;
    procedure Execute; virtual; abstract;
  end;

  TDatabaseRequestLogin = class (TDatabaseRequestBase)
  private
  public
    procedure Execute; override;
  end;

  TDatabaseEvent = procedure (AConnection:TConnection; APacket:PPacket; AResult:TValueList) of object;

  TDatabase = class
  private
    FQueue : TSuspensionQueue<TDatabaseRequestBase>;
  private
    FThreadList : array [0..THREAD_COUNT-1] of TSimpleThread;
    procedure on_Thread_Execute(ASimpleThread:TSimpleThread);
  private
    FOnLoginResult: TDatabaseEvent;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Login(AConnection:TConnection; APacket:PPacket);
  public
    property OnLoginResult : TDatabaseEvent read FOnLoginResult write FOnLoginResult;
  end;

implementation

{ TDatabaseRequest }

constructor TDatabaseRequestBase.Create(ADatabase: TDatabase;
  AConnection: TConnection; APacket: PPacket);
begin
  Database := ADatabase;
  Connection := AConnection;
  Packet := APacket;
end;

{ TDatabaseRequestLogin }

procedure TDatabaseRequestLogin.Execute;
var
  Result : TValueList;
begin
  Result := TValueList.Create;
  try
    Result.Text := Packet^.Text;

    Connection.RoomID     := Result.Values['RoomID'];
    Connection.UserID     := Result.Values['UserID'];
    Connection.LocalIP    := Result.Values['LocalIP'];
    Connection.LocalPort  := Result.Integers['LocalPort'];
    Connection.RemotePort := Result.Integers['RemotePort'];

    Result.Booleans['Result'] := true;

    if Assigned(Database.FOnLoginResult) then Database.FOnLoginResult(Connection, Packet, Result);    
  finally
    Result.Free;
  end;
end;

{ TDatabase }

procedure TDatabase.on_Thread_Execute(ASimpleThread: TSimpleThread);
var
  DatabaseRequest : TDatabaseRequestBase;
begin
  while ASimpleThread.Terminated = false do begin
    DatabaseRequest := FQueue.Pop;
    try
      DatabaseRequest.Execute;
    finally
      DatabaseRequest.Free;
    end;
  end;

  FreeAndNil(FQueue);
end;

constructor TDatabase.Create;
var
  Loop: Integer;
begin
  inherited;

  FQueue := TSuspensionQueue<TDatabaseRequestBase>.Create;

  for Loop := 0 to THREAD_COUNT-1 do begin
    FThreadList[Loop] := TSimpleThread.Create('TDatabase', on_Thread_Execute);
  end;
end;

destructor TDatabase.Destroy;
var
  Loop: Integer;
begin
  for Loop := 0 to THREAD_COUNT-1 do FThreadList[Loop].TerminateNow;

  inherited;
end;

procedure TDatabase.Login(AConnection: TConnection; APacket: PPacket);
begin
  FQueue.Push( TDatabaseRequestLogin.Create(Self, AConnection, APacket) );
end;

end.
