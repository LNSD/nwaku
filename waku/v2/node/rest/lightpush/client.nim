{.push raises: [Defect].}

import
  stew/results,
  chronicles,
  presto/[common, client]
import
  ../serdes,
  ../utils,
  ./types,
  ./types_serdes


logScope: topics = "rest_client_lightpush"


proc encodeBytes*(value: seq[PubSubTopicString],
                  contentType: string): RestResult[seq[byte]] =
  if MediaType.init(contentType) != MIMETYPE_JSON:
    error "Unsupported contentType value", contentType = contentType
    return err("Unsupported contentType")
  
  let encoded = ?encodeIntoJsonBytes(value)
  return ok(encoded)

proc decodeBytes*(t: typedesc[string], value: openarray[byte],
                  contentType: string): RestResult[string] =
  if MediaType.init(contentType) != MIMETYPE_TEXT:
    error "Unsupported contentType valaue", contentType = contentType
    return err("Unsupported contentType")
  
  var res: string
  if len(value) > 0:
    res = newString(len(value))
    copyMem(addr res[0], unsafeAddr value[0], len(value))
  return ok(res)

proc encodeBytes*(value: LightpushPostMessagesRequest,
                  contentType: string): RestResult[seq[byte]] =
  if MediaType.init(contentType) != MIMETYPE_JSON:
    error "Unsupported contentType value", contentType = contentType
    return err("Unsupported contentType")
  
  let encoded = ?encodeIntoJsonBytes(value)
  return ok(encoded)

# TODO: Check how we can use a constant to set the method endpoint (improve "rest" pragma under nim-presto)
proc lightpushPostMessagesV1*(body: LightpushPostMessagesRequest): RestResponse[string] {.rest, endpoint: "/lightpush/v1/messages", meth: HttpMethod.MethodPost.}