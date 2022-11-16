when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}


import
  ../../utils/time

type
  PubsubTopic* = string
  ContentTopic* = string

const 
  DefaultPubsubTopic*: PubsubTopic = PubsubTopic("/waku/2/default-waku/proto")
  DefaultContentTopic*: ContentTopic = ContentTopic("/waku/2/default-content/proto")


type WakuMessage* = object
    payload*: seq[byte]
    contentTopic*: ContentTopic
    version*: uint32
    timestamp*: Timestamp  # Sender generated timestamp
    # Experimental: This is part of https://rfc.vac.dev/spec/17/ spec and not yet part of 14/WAKU2-MESSAGE spec
    when defined(rln):
      proof*: seq[byte] ## The proof field indicates that the message is not a spam
    ephemeral*: bool  ## The ephemeral field indicates if the message should be stored. 