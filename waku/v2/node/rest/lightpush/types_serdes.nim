{.push raises: [Defect].}

import
  std/[sets, strformat],
  chronicles,
  json_serialization,
  json_serialization/std/options
import 
  ../serdes,
  ../base64,
  ./types


#### Serialization and deserialization

proc writeValue*(writer: var JsonWriter[RestJson], value: Base64String)
  {.raises: [IOError, Defect].} =
  writer.writeValue(string(value))

proc writeValue*(writer: var JsonWriter[RestJson], value: PubSubTopicString)
  {.raises: [IOError, Defect].} =
  writer.writeValue(string(value))
  
proc writeValue*(writer: var JsonWriter[RestJson], value: ContentTopicString)
  {.raises: [IOError, Defect].} =
  writer.writeValue(string(value))

proc writeValue*(writer: var JsonWriter[RestJson], value: LightpushWakuMessage)
  {.raises: [IOError, Defect].} =
  writer.beginRecord()
  writer.writeField("payload", value.payload)
  if value.contentTopic.isSome:
    writer.writeField("contentTopic", value.contentTopic)
  if value.version.isSome:
    writer.writeField("version", value.version)
  if value.timestamp.isSome:
    writer.writeField("timestamp", value.timestamp)
  writer.endRecord()

proc writeValue*(writer: var JsonWriter[RestJson], value: LightpushPostMessagesRequest)
  {.raises: [IOError, Defect].} =
  writer.beginRecord()
  if value.pubsubTopic.isSome():
    writer.writeField("pubsubTopic", value.pubsubTopic.get())
  writer.writeField("message", value.message)
  writer.endRecord()

proc readValue*(reader: var JsonReader[RestJson], value: var Base64String)
  {.raises: [SerializationError, IOError, Defect].} =
  value = Base64String(reader.readValue(string))

proc readValue*(reader: var JsonReader[RestJson], value: var PubSubTopicString)
  {.raises: [SerializationError, IOError, Defect].} =
  value = PubSubTopicString(reader.readValue(string))

proc readValue*(reader: var JsonReader[RestJson], value: var ContentTopicString)
  {.raises: [SerializationError, IOError, Defect].} =
  value = ContentTopicString(reader.readValue(string))

proc readValue*(reader: var JsonReader[RestJson], value: var LightpushWakuMessage)
  {.raises: [SerializationError, IOError, Defect].} =
  var
    payload = none(Base64String)
    contentTopic = none(ContentTopicString)
    version = none(Natural)
    timestamp = none(int64)

  var keys = initHashSet[string]()
  for fieldName in readObjectFields(reader):
    # Check for reapeated keys
    if keys.containsOrIncl(fieldName):
      let err = try: fmt"Multiple `{fieldName}` fields found"
                except: "Multiple fields with the same name found"
      reader.raiseUnexpectedField(err, "LightpushWakuMessage")

    case fieldName
    of "payload":
      payload = some(reader.readValue(Base64String))
    of "contentTopic":
      contentTopic = some(reader.readValue(ContentTopicString))
    of "version":
      version = some(reader.readValue(Natural))
    of "timestamp":
      timestamp = some(reader.readValue(int64))
    else:
      unrecognizedFieldWarning()

  if payload.isNone():
    reader.raiseUnexpectedValue("Field `payload` is missing")

  value = LightpushWakuMessage(
    payload: payload.get(),
    contentTopic: contentTopic,
    version: version,
    timestamp: timestamp 
  )

proc readValue*(reader: var JsonReader[RestJson], value: var LightpushPostMessagesRequest)
  {.raises: [SerializationError, IOError, Defect].} =
  var
    message = none(LightpushWakuMessage)
    pubsubTopic = none(PubSubTopicString)

  var keys = initHashSet[string]()
  for fieldName in readObjectFields(reader):
    # Check for reapeated keys
    if keys.containsOrIncl(fieldName):
      let err = try: fmt"Multiple `{fieldName}` fields found"
                except: "Multiple fields with the same name found"
      reader.raiseUnexpectedField(err, "LightpushWakuMessage")

    case fieldName
    of "message":
      message = some(reader.readValue(LightpushWakuMessage))
    of "pubsubTopic":
      pubsubTopic = some(reader.readValue(PubSubTopicString))
    else:
      unrecognizedFieldWarning()

  if message.isNone():
    reader.raiseUnexpectedValue("Field `message` is missing")

  value = LightpushPostMessagesRequest(
    message: message.get(),
    pubsubTopic: pubsubTopic,
  )

