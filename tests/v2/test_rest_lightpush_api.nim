{.used.}

import
  stew/byteutils,
  stew/shims/net,
  testutils/unittests,
  chronicles,
  presto,
  libp2p/crypto/crypto
import
  ../../waku/v2/utils/peers,
  ../../waku/v2/node/peer_manager/peer_manager,
  ../../waku/v2/node/wakunode2,
  ../../waku/v2/node/rest/[server, client, utils],
  ../../waku/v2/node/rest/lightpush


const 
  DefaultPubsubTopic = "/waku/2/default-waku/proto"
  DefaultContentTopic = ContentTopic("/waku/2/default-content/proto")


proc testWakuNode(port=9000): WakuNode = 
  let 
    rng = crypto.newRng()
    privkey = crypto.PrivateKey.random(Secp256k1, rng[]).tryGet()
    bindIp = ValidIpAddress.init("0.0.0.0")
    extIp = ValidIpAddress.init("127.0.0.1")
    port = Port(port)

  WakuNode.new(privkey, bindIp, port, some(extIp), some(port))

proc fakeWakuMessage(payload = toBytes("TEST"), contentTopic = DefaultContentTopic): WakuMessage = 
  WakuMessage(
    payload: payload,
    contentTopic: contentTopic,
    version: 1,
    timestamp: 2022
  )


suite "REST API - Lightpush":
  asyncTest "Push a message to lightpush peer node - POST /lightpush/v1/messages": 
    ## "Lightpush API: push a message": 
    ## Given
    let lightpushPeer = testWakuNode(port=9001)
    await lightpushPeer.start()
    lightpushPeer.mountRelay(@[DefaultPubsubTopic]) 
    lightpushPeer.mountLightPush()

    let node = testWakuNode(port=9002)
    await node.start()
    node.mountRelay(relayMessages=false) 
    node.mountLightpush()
    node.setLightpushPeer(lightpushPeer.switch.peerInfo.toRemotePeerInfo())


    # Rest server setup
    let restPort = Port(8546)
    let restAddress = ValidIpAddress.init("0.0.0.0")
    let restServer = RestServerRef.init(restAddress, restPort).tryGet()

    installLightpushApiHandlers(restServer.router, node)
    restServer.start()

    let client = newRestHttpClient(initTAddress(restAddress, restPort))
    
    ## When
    let reqBody = LightpushPostMessagesRequest(
      pubsubTopic: some(PubsubTopicString(DefaultPubsubTopic)),
      message: fakeWakuMessage().toLightpushWakuMessage()
    )

    let response = await client.lightpushPostMessagesV1(reqBody)

    ## Then
    check:
      response.status == 200
      response.contentType == $MIMETYPE_TEXT
      response.data == "OK"

    # TODO: Check for the message to be published to the topic

    ## Cleanup
    await restServer.stop()
    await restServer.closeWait()
    await allFutures(lightpushPeer.stop(), node.stop())
