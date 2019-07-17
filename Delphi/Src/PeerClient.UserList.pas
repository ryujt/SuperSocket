unit PeerClient.UserList;

interface

uses
  DebugTools, ValueList,
  Generics.Collections,
  SysUtils, Classes;

type
  TUserInfo = class
  private
    FCountSent : integer;
    FCountASK : integer;
  public
    ConnectionID : integer;
    UserID : string;
    PeerIP : string;
    PeerPort : integer;

    constructor Create;

    /// 패킷을 주고 받은 개수를 파악하여 응답이 너무 없으면 Peer 정보를 삭제한다.
    procedure IncSent;
    procedure IncASK;
  end;

  TUserList = class
  private
    FList : TList<TUserInfo>;
  private
    function GetCount: integer;
    function GetItems(AIndex: integer): TUserInfo;
  public
    constructor Create;
    destructor Destroy; override;

    procedure UserIn(const AUserID:string; AValueList:TValueList);
    procedure UserOut(const AUserID:string);

    function FindUserInfo(const AUserID:string):TUserInfo;

    procedure IncASK(const APeerIP: string; APeerPort: integer);
  public
    property Count : integer read GetCount;
    property Items[AIndex:integer] : TUserInfo read GetItems;
  end;

implementation

{ TUserInfo }

constructor TUserInfo.Create;
begin
  inherited;

  FCountSent := 0;
  FCountASK := 0;
end;

procedure TUserInfo.IncASK;
begin
  Inc(FCountASK);
end;

procedure TUserInfo.IncSent;
begin
  Inc(FCountSent);
  if FCountSent < 1000 then Exit;

  {$IFDEF DEBUG}
  Trace( Format('TUserInfo.IncASK - UserID: %s, FCountSent: %d, FCountASK: %d', [UserID, FCountSent, FCountASK]) );
  {$ENDIF}

  FCountSent := 0;

  if FCountASK > 0 then begin
    FCountASK := 0;
    Exit;
  end;

  Trace('TUserInfo.IncASK - FCountASK = 0');

  PeerIP := '';
  PeerPort:= 0;
end;

{ TUserList }

constructor TUserList.Create;
begin
  inherited;

  FList := TList<TUserInfo>.Create;
end;

procedure TUserList.IncASK(const APeerIP: string; APeerPort: integer);
var
  Loop: Integer;
  UserInfo : TUserInfo;
begin
  for Loop := 0 to FList.Count-1 do begin
    UserInfo := FList[Loop];
    if (UserInfo.PeerIP = APeerIP) and (UserInfo.PeerPort = APeerPort) then UserInfo.IncASK;
  end;
end;

destructor TUserList.Destroy;
var
  Loop: Integer;
begin
  for Loop := 0 to FList.Count-1 do FList[Loop].Free;

  FreeAndNil(FList);

  inherited;
end;

function TUserList.FindUserInfo(const AUserID: string): TUserInfo;
var
  Loop: Integer;
begin
  Result := nil;

  for Loop := 0 to FList.Count-1 do
    if FList[Loop].UserID = AUserID then begin
      Result := FList[Loop];
      Break;
    end;
end;

function TUserList.GetCount: integer;
begin
  Result := FList.Count;
end;

function TUserList.GetItems(AIndex: integer): TUserInfo;
begin
  Result := FList[AIndex];
end;

procedure TUserList.UserIn(const AUserID: string; AValueList: TValueList);
var
  UserInfo : TUserInfo;
begin
  UserOut(AUserID);

  UserInfo := TUserInfo.Create;
  UserInfo.ConnectionID := AValueList.Integers['ID'];
  UserInfo.UserID := AUserID;

  FList.Add(UserInfo)
end;

procedure TUserList.UserOut(const AUserID: string);
var
  Loop: Integer;
begin
  for Loop := FList.Count-1 downto 0 do
    if FList[Loop].UserID = AUserID then begin
      FList[Loop].Free;
      FList.Delete(Loop);
      Break;
    end;
end;

end.
