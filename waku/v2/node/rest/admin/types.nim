when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}

import
  std/[sets, strformat],
  chronicles,
  json_serialization,
  json_serialization/std/options,
  presto/[route, client, common]
import
  ../serdes

#### Types

type AdminPeer* = object
    multiaddr: string
    protocol: string
    connected: bool

type
  AdminGetPeersResponse* = seq[AdminPeer]
  AdminPostPeersRequest* = seq[string]


#### Type conversion

# TODO: Add type oonversion methods
# proc toRelayWakuMessage*(msg: WakuMessage): RelayWakuMessage =
#   RelayWakuMessage(
#     payload: base64.encode(Base64String, msg.payload),
#     contentTopic: some(msg.contentTopic),
#     version: some(Natural(msg.version)),
#     timestamp: some(msg.timestamp)
#   )

# proc toWakuMessage*(msg: RelayWakuMessage, version = 0): Result[WakuMessage, cstring] =
#   let
#     payload = ?msg.payload.decode()
#     contentTopic = msg.contentTopic.get(DefaultContentTopic)
#     version = uint32(msg.version.get(version))
#     timestamp = msg.timestamp.get(0)

#   ok(WakuMessage(payload: payload, contentTopic: contentTopic, version: version, timestamp: timestamp))


#### Serialization and deserialization

proc writeValue*(writer: var JsonWriter[RestJson], value: AdminPeer)
  {.raises: [IOError, Defect].} =
  writer.beginRecord()
  writer.writeField("multiaddr", value.multiaddr)
  writer.writeField("protocol", value.protocol)
  writer.writeField("connected", value.connected)
  writer.endRecord()

proc readValue*(reader: var JsonReader[RestJson], value: var AdminPeer)
  {.raises: [SerializationError, IOError, Defect].} =
  var
    multiaddr = none(string)
    protocol = none(string)
    connected = none(bool)

  var keys = initHashSet[string]()
  for fieldName in readObjectFields(reader):
    # Check for reapeated keys
    if keys.containsOrIncl(fieldName):
      let err = try: fmt"Multiple `{fieldName}` fields found"
                except: "Multiple fields with the same name found"
      reader.raiseUnexpectedField(err, "RelayWakuMessage")

    case fieldName
    of "multiaddr":
      multiaddr = some(reader.readValue(string))
    of "protocol":
      protocol = some(reader.readValue(string))
    of "connected":
      connected = some(reader.readValue(bool))
    else:
      unrecognizedFieldWarning()

  if multiaddr.isNone():
    reader.raiseUnexpectedValue("Field `multiaddr` is missing")
  if protocol.isNone():
    reader.raiseUnexpectedValue("Field `protocol` is missing")
  if connected.isNone():
    reader.raiseUnexpectedValue("Field `connected` is missing")

  value = AdminPeer(
    multiaddr: multiaddr.get(),
    protocol: protocol.get(),
    connected: connected.get()
  )
