## Waku RFC 14/WAKU2-MESSAGE: https://rfc.vac.dev/spec/14/
## Wire format protobuf definition: https://github.com/vacp2p/waku/blob/main/waku/message/v1/message.proto

when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}

import
  std/options
import
  ../../../common/protobuf,
  ../../utils/time,
  ./message


const MaxWakuMessageSize* = 1024 * 1024 # In bytes. Corresponds to PubSub default



## Protocol wire format

type WakuMessageRPC* = object
    payload*: seq[byte]
    contentTopic*: ContentTopic
    version*: Option[uint32]
    timestamp*: Option[int64]
    # Experimental: This is part of https://rfc.vac.dev/spec/17/ spec and not yet part of 14/WAKU2-MESSAGE spec
    when defined(rln):
      proof*: Option[seq[byte]]
    ephemeral*: Option[bool]


##  Wire format codec

proc encode*(message: WakuMessageRPC): ProtoBuffer =
  var buf = initProtoBuffer()

  # Required attributes
  buf.write3(1, message.payload)
  buf.write3(2, message.contentTopic)
  
  # Optional attributes
  if message.version.isSome():
    buf.write3(3, message.version.get())
    
  if message.timestamp.isSome():
    buf.write3(10, zint64(message.timestamp.get()))
  
  when defined(rln):
    if message.proof.isSome():
      buf.write3(21, message.proof.get())

  if message.ephemeral.isSome():
    buf.write3(31, uint64(message.ephemeral.get()))

  buf.finish3()

  buf

proc decode*(T: type WakuMessageRPC, buffer: seq[byte]): ProtoResult[T] =
  var msg = WakuMessageRPC()
  let pb = initProtoBuffer(buffer)

  if not ?pb.getField(1, msg.payload):
    return err(ProtoError.RequiredFieldMissing)

  if not ?pb.getField(2, msg.contentTopic):
    return err(ProtoError.RequiredFieldMissing)

  var version: uint32
  if ?pb.getField(3, version):
    msg.version = some(version)
  else:
    msg.version = none(uint32)


  var timestamp: zint64
  if ?pb.getField(10, timestamp):
    msg.timestamp = some(int64(timestamp))
  else:
    msg.timestamp = none(int64)

  # Experimental, this is part of https://rfc.vac.dev/spec/17/ spec
  when defined(rln):
    var proofBytes: seq[byte]
    if ?pb.getField(21, proofBytes):
      msg.proof = some(proofBytes)
    else:
      msg.proof = none(seq[byte])

  var ephemeral: uint
  if ?pb.getField(31, ephemeral):
    msg.ephemeral = some(bool(ephemeral))
  else:
    msg.ephemeral = none(bool)

  ok(msg)


## Wire protocol type mappings

proc toRPC*(message: WakuMessage): WakuMessageRPC =
  var rpc = WakuMessageRPC(
    payload: message.payload,
    contentTopic: message.contentTopic,
  )

  if message.version != default(type message.version):
    rpc.version =  some(uint32(message.version))

  if message.timestamp != default(type message.timestamp): 
    rpc.timestamp = some(int64(message.timestamp))

  when defined(rln):
    if message.proof.len > 0:
      rpc.proof = some(message.proof)
  
  if message.ephemeral:
    rpc.ephemeral = some(message.ephemeral)

  rpc

proc toAPI*(rpc: WakuMessageRPC): WakuMessage =
  var msg = WakuMessage(
    payload: rpc.payload,
    contentTopic: rpc.contentTopic
  )

  if rpc.version.isSome():
    msg.version = uint32(rpc.version.get())
  
  if rpc.timestamp.isSome():
    msg.timestamp = Timestamp(rpc.timestamp.get())

  when defined(rln):
    if rpc.proof.isSome():
      msg.proof = rpc.proof.get()

  if rpc.ephemeral.isSome():
    msg.ephemeral = bool(rpc.ephemeral.get())
  
  msg