unit TextProtocol;

interface

type
  TPacketType = (
    ptNone,

    ptLogin, ptSenderLogin, ptInvisibleLogin,
    ptLogout,

    ptOkLogin, ptErLogin, ptIDinUse,

    ptAskUserList,
    ptUserIn, ptUserOut, ptUserListStart, ptUserListEnd,

    ptUserStatus,

    ptChat, ptWhisper,

    ptCallSender,

    ptKickOut, ptUserLevel, ptMute, ptNotice,

    ptOnAir, ptOffAir,
    ptAskChatHistory, ptChatHistoryStart, ptChatHistoryEnd
  );

implementation

end.
