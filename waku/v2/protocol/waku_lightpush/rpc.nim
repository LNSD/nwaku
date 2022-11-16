when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}

import
  std/options
import
  ../waku_message/rpc

type
  PushRequest* = object
    pubSubTopic*: string
    message*: WakuMessageRPC

  PushResponse* = object
    isSuccess*: bool
    info*: Option[string]

  PushRPC* = object
    requestId*: string
    request*: Option[PushRequest]
    response*: Option[PushResponse]
