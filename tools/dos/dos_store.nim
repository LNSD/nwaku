{.push raises: [Defect].}

import
  std/[options, strutils],
  stew/results,
  stew/shims/net as stewNet,
  chronos,
  chronos/transports/common as chronosCommon,
  chronicles,
  confutils,
  libp2p/[switch,                   # manage transports, a single entry point for dialing and listening
          crypto/crypto,            # cryptographic functions
          stream/connection,        # create and close stream read / write connections
          multiaddress,             # encode different addressing schemes. For example, /ip4/7.7.7.7/tcp/6543 means it is using IPv4 protocol and TCP
          peerinfo,                 # manage the information of a peer, such as peer ID and public / private key
          peerid,                   # Implement how peers interact
          protobuf/minprotobuf,     # message serialisation/deserialisation from and to protobufs
          protocols/protocol,       # define the protocol base type
          protocols/secure/secio,   # define the protocol of secure input / output, allows encrypted communication that uses public keys to validate signed messages instead of a certificate authority like in TLS
          nameresolving/dnsresolver,# define DNS resolution
          muxers/muxer]             # define an interface for stream multiplexing, allowing peers to offer many protocols over a single connection
import   
  ../../waku/v2/protocol/waku_message,
  ../../waku/v2/protocol/waku_lightpush,
  ../../waku/v2/protocol/waku_filter, 
  ../../waku/v2/protocol/waku_store,
  ../../waku/v2/node/[wakunode2, waku_payload],
  ../../waku/v2/node/dnsdisc/waku_dnsdisc,
  ../../waku/v2/utils/[peers, time],
  ../../waku/common/utils/nat,
  ./common


logScope: topics = "dos.waku-store"

const ClientId* = "dos.waku-store"

const DefaultWakuStoreQueryTimeout* = 10_000.milliseconds


## Utils

proc getDnsResolver(): DosResult[DnsResolver] =
  try:
    let nameServers = @[
      initTAddress("1.1.1.1", 53),
      initTAddress("1.0.0.1", 53),
    ]
    ok(DnsResolver.new(nameServers))
  except:
    err(getCurrentExceptionMsg())


## Store client

type WakuStoreClient* = ref object
      node*: WakuNode

proc new*(T: type WakuStoreClient, key: crypto.PrivateKey): DosResult[T] =
  let resolver = ?getDnsResolver()

  let (extIp, extTcpPort, extUdpPort) = setupNat(
    "any",
    ClientId,
    Port(uint16(62_000)),
    Port(uint16(62_000))
  )

  var node: WakuNode 
  try:
    node = WakuNode.new(
      nodeKey=key, 
      bindIp=ValidIpAddress.init("0.0.0.0"),
      bindPort=Port(uint16(62_000)),
      extIp=extIp,
      extPort=extTcpPort,
      nameResolver=resolver
    )
  except:
    return err("failed to create a waku node" & getCurrentExceptionMsg())

  ok(WakuStoreClient(node: node))


proc setPeer*(c: WakuStoreClient, address: string): DosResult[void] =
  try:
    c.node.setStorePeer(address)
  except:
    return err("failed to set store peer: " & getCurrentExceptionMsg())

  ok()

proc sendQuery*(c: WakuStoreClient, q: HistoryQuery, timeout=DefaultWakuStoreQueryTimeout): Future[DosResult[HistoryResponse]] {.async.} =
  let req = c.node.query(q)
  
  if not (await req.withTimeout(timeout)):
    return err("history query timeout")
  
  let res = req.read()
  if res.isErr():
    return err(res.error())

  return ok(res.value)

proc start*(c: WakuStoreClient) {.async.} =
  await c.node.start()

  # await c.node.mountRelay(@["/waku/2/default-waku/proto"], relayMessages = false)
  
  # c.node.mountLibp2pPing()

  await c.node.mountStore()

proc getPeerInfo*(c: WakuStoreClient): RemotePeerInfo =
  c.node.switch.peerInfo.toRemotePeerInfo()

proc connectToNodes*[I: string|RemotePeerInfo](c: WakuStoreClient, nodes: I|seq[I]) {.async.} =
  when nodes is seq:
    await c.node.connectToNodes(nodes)
  else:
    await c.node.connectToNodes(@[nodes])


proc discoverNodes*(url: string): Future[DosResult[seq[RemotePeerInfo]]] {.async.} =
  var discoveredNodes: seq[RemotePeerInfo]

  var nameServers: seq[TransportAddress]
  try:
    for ip in @["1.1.1.1", "1.0.0.1"]:
      nameServers.add(initTAddress(ip, 53)) # Assume all servers use port 53
  except:
    return err(getCurrentExceptionMsg())

  let resDnsResolver = getDnsResolver()
  if resDnsResolver.isErr():
    return err(resDnsResolver.error())

  let dnsResolver = resDnsResolver.get()


  proc resolver(domain: string): Future[string] {.async, gcsafe.} =
    trace "resolving", domain=domain
    let resolved = await dnsResolver.resolveTxt(domain)
    return resolved[0] # Use only first answer
  
  var wakuDnsDiscovery = WakuDnsDiscovery.init(url, resolver)
  if wakuDnsDiscovery.isErr():
    return err("Failed to init Waku DNS discovery")

  let discoveredPeers = wakuDnsDiscovery.get().findPeers()
  if discoveredPeers.isOk():
    discoveredNodes = discoveredPeers.get()
    try:
      return ok(discoveredNodes)
    except:
      return err(getCurrentExceptionMsg())
