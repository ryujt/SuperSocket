unit SuperSocket.RoomList;

interface

uses
  DebugTools, SuperSocket, BinarySearch, TaskQueue, LazyRelease,
  SysUtils, Classes, SyncObjs;

type
  TRoomList = class;
  TRoomUnit = class;

  TReceivedData = class
  private
    Connection : TConnection;
    Packet : PPacket;
    constructor Create(AConnection:TConnection; APacket:PPacket); reintroduce;
  end;

  TRoomUnitTask = (ruUserIn, ruUserOut, ruReceived);

  TRoomUnit = class
  private
    FIsTerminated : boolean;
    FRoomList : TRoomList;
    FRoomID : string;
    FConnections : TBinarySearch;

    procedure UserIn(AConnection:TConnection);
    procedure UserOut(AConnection:TConnection);
    procedure Received(AConnection:TConnection; APacket:PPacket);
  private
    FTaskQueue : TTaskQueue<TRoomUnitTask, TReceivedData>;
    procedure on_FTaskQueue_Task(ASender:Tobject; ATaskType:TRoomUnitTask; AReceivedData:TReceivedData);

    procedure do_UserIn(AConnection:TConnection);
    procedure do_UserOut(AConnection:TConnection);
    procedure do_Received(AConnection:TConnection; APacket:PPacket);
  private
    function GetConnections: TBinarySearchInterface;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Terminate;

    procedure SendToAll(APacket:PPacket);
    procedure SendToOther(AConnection:TConnection; APacket:PPacket);
  public
    UserData : TObject;
    property Connections : TBinarySearchInterface read GetConnections;
  end;

  TRoomListTask = (rlUserIn, rlUserOut, rlRemove);

  TRoomListEvent = procedure (ARoomUnit:TRoomUnit; AConnection:TConnection) of object;
  TRoomPacketEvent = procedure (ARoomUnit:TRoomUnit; AConnection:TConnection; APacket:PPacket) of object;

  TRoomList = class
  private
    FCS : TCriticalSection;
    FLazyDestroy : TLazyDestroy;
    FBinarySearch : TBinarySearch;

    procedure Remove(ARoomUnit:TRoomUnit);
  private
    FTaskQueue : TTaskQueue<TRoomListTask, Pointer>;
    procedure on_FTaskQueue_Task(ASender:Tobject; ATaskType:TRoomListTask; AData:Pointer);

    function do_UserIn(AConnection:TConnection):TRoomUnit;
    procedure do_UserOut(AConnection:TConnection);
    procedure do_Remove(ARoomUnit:TRoomUnit);
  private
    FOnUserOut: TRoomListEvent;
    FOnUserIn: TRoomListEvent;
    FOnIDinUse: TRoomListEvent;
    FOnReceived: TRoomPacketEvent;
  public
    constructor Create;
    destructor Destroy; override;

    function FindRoomUnit(const ARoomID:string):TRoomUnit;

    procedure UserIn(AConnection:TConnection);
    procedure UserOut(AConnection:TConnection);

    procedure Received(AConnection:TConnection; APacket:PPacket);
  public
    property OnUserIn : TRoomListEvent read FOnUserIn write FOnUserIn;
    property OnUserOut : TRoomListEvent read FOnUserOut write FOnUserOut;
    property OnIDinUse : TRoomListEvent read FOnIDinUse write FOnIDinUse;
    property OnReceived : TRoomPacketEvent read FOnReceived write FOnReceived;
  end;

implementation

{ TReceivedData }

constructor TReceivedData.Create(AConnection: TConnection; APacket: PPacket);
begin
  Connection := AConnection;
  Packet := APacket;
end;

{ TRoomUnit }

procedure TRoomUnit.do_Received(AConnection: TConnection; APacket: PPacket);
begin
  if AConnection.IsLogined and Assigned(FRoomList.FOnReceived) then FRoomList.FOnReceived(Self, AConnection, APacket);
end;

procedure TRoomUnit.do_UserIn(AConnection: TConnection);
var
  iIndex : integer;
  Connection : TConnection;
begin
  iIndex := FConnections.Find(AConnection);
  if (iIndex <> -1) then begin
    Connection := Pointer(FConnections.Items[iIndex]);

    FConnections.Remove(Connection);

    if Connection.IsLogined then begin
      Connection.IsLogined := false;
      Connection.Room := nil;
      if Assigned(FRoomList.FOnIDinUse) then FRoomList.FOnIDinUse(Self, Connection);
    end;
  end;

  AConnection.IsLogined := true;
  AConnection.Room := Self;

  FConnections.Insert(AConnection);

  if Assigned(FRoomList.FOnUserIn) then FRoomList.FOnUserIn(Self, AConnection);
end;

constructor TRoomUnit.Create;
begin
  inherited;

  FIsTerminated := false;

  UserData := nil;

  FConnections := TBinarySearch.Create;
  FConnections.SetCompareFunction(
    function (A,B:pointer):integer
    var
      pA : TConnection absolute A;
      pB : TConnection absolute B;
    begin
      if pA.UserID > pB.UserID then Result := 1
      else if pA.UserID < pB.UserID then Result := -1
      else Result := 0;
    end
  );

  FTaskQueue := TTaskQueue<TRoomUnitTask, TReceivedData>.Create;
  FTaskQueue.OnTask := on_FTaskQueue_Task;
end;

destructor TRoomUnit.Destroy;
begin
  {$IFDEF DEBUG}
  Trace( Format('TRoomUnit.Destroy - RoomID: %s, %d', [FRoomID, Integer(Self)]) );
  {$ENDIF}

  if UserData <> nil then FreeAndNil(UserData);

  FreeAndNil(FConnections);
  FreeAndNil(FTaskQueue);

  inherited;
end;

procedure TRoomUnit.Received(AConnection: TConnection; APacket: PPacket);
begin
  if FIsTerminated = false then
    FTaskQueue.Add(ruReceived, TReceivedData.Create(AConnection, APacket));
end;

procedure TRoomUnit.SendToAll(APacket: PPacket);
var
  Loop: Integer;
  Connection : TConnection;
begin
  for Loop := 0 to FConnections.Count-1 do begin
    Connection := Pointer(FConnections.Items[Loop]);
    if Connection.IsLogined then Connection.Send(APacket);
  end;
end;

procedure TRoomUnit.SendToOther(AConnection: TConnection; APacket: PPacket);
var
  Loop: Integer;
  Connection : TConnection;
begin
  for Loop := 0 to FConnections.Count-1 do begin
    Connection := Pointer(FConnections.Items[Loop]);
    if (Connection <> AConnection) and Connection.IsLogined then Connection.Send(APacket);
  end;
end;

procedure TRoomUnit.Terminate;
begin
  FIsTerminated := true;
end;

procedure TRoomUnit.UserIn(AConnection: TConnection);
begin
  if FIsTerminated = false then
    FTaskQueue.Add(ruUserIn, TReceivedData.Create(AConnection, nil));
end;

procedure TRoomUnit.UserOut(AConnection: TConnection);
begin
  if FIsTerminated = false then
    FTaskQueue.Add(ruUserOut, TReceivedData.Create(AConnection, nil));
end;

function TRoomUnit.GetConnections: TBinarySearchInterface;
begin
  Result := FConnections;
end;

procedure TRoomUnit.on_FTaskQueue_Task(ASender: Tobject;
  ATaskType: TRoomUnitTask; AReceivedData: TReceivedData);
begin
  try
    if FIsTerminated then Exit;

    try
      case ATaskType of
        ruUserIn: do_UserIn(AReceivedData.Connection);
        ruUserOut:do_UserOut(AReceivedData.Connection);
        ruReceived: do_Received(AReceivedData.Connection, AReceivedData.Packet);
      end;
    except
      on E : Exception do
        Trace( Format('TRoomUnit.on_FTaskQueue_Task - %s', [E.Message]) );
    end;
  finally
    AReceivedData.Free;
  end;
end;

procedure TRoomUnit.do_UserOut(AConnection: TConnection);
begin
  if AConnection.Room = nil then Exit;

  AConnection.Room := nil;

  FConnections.Remove(AConnection);

  if FConnections.Count = 0 then begin
    FRoomList.Remove(Self);
  end;

  if Assigned(FRoomList.FOnUserOut) then FRoomList.FOnUserOut(Self, AConnection);
end;

{ TRoomList }

procedure TRoomList.on_FTaskQueue_Task(ASender: Tobject;
  ATaskType: TRoomListTask; AData: Pointer);
begin
  case ATaskType of
    rlUserIn: do_UserIn(AData);
    rlUserOut: do_UserOut(AData);
    rlRemove: do_Remove(AData);
  end;
end;

procedure TRoomList.Received(AConnection: TConnection; APacket: PPacket);
var
  RoomUnit : TRoomUnit;
begin
  RoomUnit := Pointer(AConnection.Room);
  if RoomUnit <> nil then RoomUnit.Received(AConnection, APacket);
end;

procedure TRoomList.Remove(ARoomUnit: TRoomUnit);
begin
  FTaskQueue.Add(rlRemove, ARoomUnit);
end;

procedure TRoomList.UserIn(AConnection: TConnection);
begin
  FTaskQueue.Add(rlUserIn, AConnection);
end;

procedure TRoomList.UserOut(AConnection: TConnection);
begin
  FTaskQueue.Add(rlUserOut, AConnection);
end;

procedure TRoomList.do_Remove(ARoomUnit: TRoomUnit);
begin
  FCS.Acquire;
  try
    FBinarySearch.Remove(ARoomUnit);
  finally
    FCS.Release;
  end;

  ARoomUnit.Terminate;
  FLazyDestroy.Release(ARoomUnit);
end;

function TRoomList.do_UserIn(AConnection: TConnection): TRoomUnit;
var
  iIndex : integer;
begin
  FCS.Acquire;
  try
    iIndex := FBinarySearch.Find(
      @AConnection.RoomID,
      function (A,B:pointer):integer
      var
        pA : PString absolute A;
        pB : TRoomUnit absolute B;
      begin
        if pA^ > pB.FRoomID then Result := 1
        else if pA^ < pB.FRoomID then Result := -1
        else Result := 0;
      end
    );
    if iIndex = -1 then begin
      Result := TRoomUnit.Create;
      Result.FRoomList := Self;
      Result.FRoomID := AConnection.RoomID;
      FBinarySearch.Insert(Result);
    end else begin
      Result := FBinarySearch.Items[iIndex];
    end;
  finally
    FCS.Release;
  end;

  Result.UserIn(AConnection);
end;

procedure TRoomList.do_UserOut(AConnection: TConnection);
var
  RoomUnit : TRoomUnit;
begin
  RoomUnit := Pointer(AConnection.Room);
  if RoomUnit <> nil then RoomUnit.UserOut(AConnection);
end;

function TRoomList.FindRoomUnit(const ARoomID: string): TRoomUnit;
var
  iIndex : integer;
begin
  Result := nil;

  FCS.Acquire;
  try
    iIndex := FBinarySearch.Find(
      @ARoomID,
      function (A,B:pointer):integer
      var
        pA : PString absolute A;
        pB : TRoomUnit absolute B;
      begin
        if pA^ > pB.FRoomID then Result := 1
        else if pA^ < pB.FRoomID then Result := -1
        else Result := 0;
      end
    );
    if iIndex <> -1 then Result := FBinarySearch.Items[iIndex];
  finally
    FCS.Release;
  end;
end;

constructor TRoomList.Create;
const
  LAZYDESTROY_RING_SIZE = 3;
begin
  inherited;

  FCS := TCriticalSection.Create;

  FLazyDestroy := TLazyDestroy.Create(LAZYDESTROY_RING_SIZE);

  FBinarySearch := TBinarySearch.Create;
  FBinarySearch.SetCompareFunction(
    function (A,B:pointer):integer
    var
      pA : TRoomUnit absolute A;
      pB : TRoomUnit absolute B;
    begin
      if pA.FRoomID > pB.FRoomID then Result := 1
      else if pA.FRoomID < pB.FRoomID then Result := -1
      else Result := 0;
    end
  );

  FTaskQueue := TTaskQueue<TRoomListTask, Pointer>.Create;
  FTaskQueue.OnTask := on_FTaskQueue_Task;
end;

destructor TRoomList.Destroy;
begin
//  FreeAndNil(FCS);
//  FreeAndNil(FLazyDestroy);
//  FreeAndNil(FBinarySearch);
//  FreeAndNil(FTaskQueue);

  inherited;
end;

end.
