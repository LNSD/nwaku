{.push raises: [Defect].}

import
  std/options,
  stew/results
import 
  ../../../protocol/waku_message,
  ../base64


#### Types

type
  PubSubTopicString* = distinct string
  ContentTopicString* = distinct string

type FilterWakuMessage* = object
      payload*: Base64String
      contentTopic*: Option[ContentTopicString]
      version*: Option[Natural]
      timestamp*: Option[int64]

type 
  FilterSubscriptionsRequest* = object
    contentFilters: seq[ContentTopicString]
    pubsubTopic: Option[PubSubTopicString]

  FilterPostSubscriptionsRequest* = FilterSubscriptionsRequest
  FilterDeleteSubscriptionsRequest* = FilterSubscriptionsRequest

  FilterGetMessagesResponse* = seq[FilterWakuMessage]


#### Type conversion

proc toFilterWakuMessage*(msg: WakuMessage): FilterWakuMessage =
  FilterWakuMessage(
    payload: base64.encode(Base64String, msg.payload),
    contentTopic: some(ContentTopicString(msg.contentTopic)),
    version: some(Natural(msg.version)),
    timestamp: some(msg.timestamp)
  )

proc toWakuMessage*(msg: FilterWakuMessage, version = 0): Result[WakuMessage, cstring] =
  const defaultContentTopic = ContentTopicString("/waku/2/default-content/proto")
  let 
    payload = ?msg.payload.decode()
    contentTopic = ContentTopic(msg.contentTopic.get(defaultContentTopic))
    version = uint32(msg.version.get(version))
    timestamp = msg.timestamp.get(0)

  ok(WakuMessage(payload: payload, contentTopic: contentTopic, version: version, timestamp: timestamp))
