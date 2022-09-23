{.push raises: [Defect].}

import
  std/[sequtils, strutils, times],
  chronos,
  chronicles,
  libp2p/multiaddress,
  libp2p/crypto/crypto
import
  ../../waku/v2/utils/peers,
  ../../waku/v2/utils/pagination,
  ../../waku/v2/utils/time,
  ../../waku/v2/protocol/waku_store,
  ./common,
  ./dos_store

logScope: topics = "dos"

# ./build/wakunode2 --nodekey=c5b00947dce061e55bb2061fd17d8c1012a7dc0499cc8883c38cb2234fbc1d93 --ports-shift=10 --metrics-logging=false --rpc=false --store=true --sqlite-store=true --db-path="$(pwd)/build" --persist-messages=true
const StorePeer = "/ip4/127.0.0.1/tcp/60010/p2p/16Uiu2HAm9EVQf54eCk651fhRyzUUcC1MkxMmU1Naax3F5QSRs6d6"

## wakuv2.test
# const StorePeer = "/dns4/node-01.do-ams3.wakuv2.test.statusim.net/tcp/30303/p2p/16Uiu2HAmPLe7Mzm8TsYUubgCAW1aJoeFScxrLj8ppHFivPo97bUZ"
# const DnsDiscoveryUrl = "enrtree://AOFTICU2XWDULNLZGRMQS4RIZPAZEHYMV4FYHAPW563HNRAOERP7C@test.waku.nodes.status.im"


# ## status.test
# const StorePeer = "/dns4/node-01.do-ams3.status.test.statusim.net/tcp/30303/p2p/16Uiu2HAkukebeXjTQ9QDBeNDWuGfbaSg79wkkhK4vPocLgR6QFDf"

proc sendRequest(client: WakuStoreClient) {.async.} =
  ## Query -->  SELECT receiverTimestamp, contentTopic, payload, pubsubTopic, version, senderTimestamp FROM Message WHERE (contentTopic = (?)) AND pubsubTopic = (?) AND (senderTimestamp >= (?) AND senderTimestamp <= (?)) ORDER BY senderTimestamp DESC, id DESC, pubsubTopic DESC, receiverTimestamp DESC LIMIT 50;

  # # Chat2
  # let rpc = HistoryQuery(contentFilters: @[ HistoryContentFilter(contentTopic: "/toy-chat/2/huilong/proto") ])
  
  ## status-web
  let rpc = HistoryQuery(
    contentFilters: @[
      HistoryContentFilter(contentTopic: "/waku/1/0x35cd47c5/rfc26"),
    ],
    pubSubTopic: "/waku/2/default-waku/proto",
    startTime: Timestamp(1661155200500 * 1_000_000),
    endTime: Timestamp(1662124449000 * 1_000_000),
    pagingInfo: PagingInfo(pageSize: 300)
  )
  
  let startTime = getTime()

  let res = await client.sendQuery(rpc, timeout=chronos.seconds(2))
  if res.isErr():
    error "query failed", error=res.error()
    return

  let response = res.get()

  let messages = response.messages
  let elapsedTime = getTime() - startTime
  warn "request response received",  message_count=messages.len, time_ms=elapsedTime.inMilliseconds


proc main() {.async.} =
  let key = randomPrivateKey()

  let client = WakuStoreClient.new(key).tryGet()
  
  let info = client.getPeerInfo()
  echo "\nListening on: " & $info.addrs[0] & "/p2p/" & $info

  echo "\nClient start\n"
  await client.start()

  # let discoveredNodes = await discoverNodes(DnsDiscoveryUrl)
  # for node in discoveredNodes.get().filter(proc(x: RemotePeerInfo): bool = StorePeer.contains($x)):
  #   echo "\nConnecting to discovered peer: " & $node & "\n"
  #   await client.connectToNodes(node)

  let node = StorePeer
  # echo "\nConnecting to: " & $node & "\n"
  # await client.connectToNodes(node)

  echo "\nSetting store peer: " & StorePeer
  let resSetPeer = client.setPeer(StorePeer)
  if resSetPeer.isErr():
    error "failed to set store peer", error=resSetPeer.error()
    return

  for batch in 1..10:
    await sleepAsync(chronos.millis(500))
    echo "\nBatch number: " & $batch

    var requests: seq[Future[void]] = @[]
    for i in 1..10:
      requests.add(sendRequest(client))
    
    await allFutures(requests)

  # waitFor sendRequest(client)


when isMainModule:
  waitFor main()
