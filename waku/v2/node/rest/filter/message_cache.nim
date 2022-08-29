when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}


import
  chronicles
import
  ../../../protocol/waku_message,
  ../../../protocol/waku_filter/client,
  ../../message_cache

logScope: 
  topics = "rest_api_filter.messagecache"

export message_cache


##### MessageCache

type PubSubTopic = string 

type FilterMessageCache* = MessageCache[(PubSubTopic, ContentTopic)]


##### Message handler

type FilterMessageCacheMessageHandler* = FilterPushHandler

proc messageHandler*(cache: FilterMessageCache): FilterMessageCacheMessageHandler =
  let handler = proc(pubsubTopic: PubSubTopic, msg: WakuMessage) {.gcsafe, closure.} =
    trace "Message handler triggered", pubsubTopic=pubsubTopic, contentTopic=msg.contentTopic
    cache.addMessage((pubsubTopic, msg.contentTopic), msg)
  
  handler