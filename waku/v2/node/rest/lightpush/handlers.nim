{.push raises: [Defect].}

import
  stew/byteutils,
  chronicles,
  json_serialization,
  json_serialization/std/options,
  presto/[route, client, common]
import
  ../../wakunode2,
  ../serdes,
  ../utils,
  ./types,
  ./types_serdes 

logScope: topics = "rest_api_lightpush"


const DefaultPubsubTopic = PubsubTopicString("/waku/2/default-waku/proto")

const PushRequestTimeout = 5.seconds # Max time to wait for futures


##### Handlers

const ROUTE_RELAY_MESSAGESV1* = "/lightpush/v1/messages"

proc installLightpushPostMessagesV1Handler*(router: var RestRouter, node: WakuNode) =
  router.api(MethodPost, ROUTE_RELAY_MESSAGESV1) do (contentBody: Option[ContentBody]) -> RestApiResponse: 
    # Check the request body
    if contentBody.isNone():
      return RestApiResponse.badRequest()
    
    let reqBodyContentType = MediaType.init(contentBody.get().contentType)
    if reqBodyContentType != MIMETYPE_JSON:
      return RestApiResponse.badRequest()

    let reqBodyData = contentBody.get().data
    let reqResult = decodeFromJsonBytes(LightpushPostMessagesRequest, reqBodyData)
    if reqResult.isErr():
      return RestApiResponse.badRequest()
    

    let pubSubTopic = reqResult.value.pubsubTopic.get(DefaultPubsubTopic)
    let resMessage = reqResult.value.message.toWakuMessage(version = 0)
    if resMessage.isErr():
      return RestApiResponse.badRequest()


    let pushRequest = node.lightpush(pubSubTopic.string, resMessage.value)
    if not (waitFor pushRequest.withTimeout(PushRequestTimeout)):
      error "Failed to push message to lightpush node", error="request timeout"
      return RestApiResponse.internalServerError()
    
    let resPush = pushRequest.read()
    if resPush.isErr():
      error "Failed to push message to lightpush node", error=resPush.error()
      return RestApiResponse.internalServerError()

    return RestApiResponse.ok()


proc installLightpushApiHandlers*(router: var RestRouter, node: WakuNode) =
  installLightpushPostMessagesV1Handler(router, node)