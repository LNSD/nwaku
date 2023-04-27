when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}

import
  std/[sequtils, strutils, options],
  stew/results,
  stew/shims/net,
  chronos,
  chronicles,
  metrics,
  libp2p/multiaddress,
  eth/keys as eth_keys,
  eth/p2p/discoveryv5/node,
  eth/p2p/discoveryv5/protocol
import
  ./waku_core,
  ./waku_enr

export protocol, waku_enr


declarePublicGauge waku_discv5_discovered, "number of nodes discovered"
declarePublicGauge waku_discv5_errors, "number of waku discv5 errors", ["type"]

logScope:
  topics = "waku discv5"


## Config

type WakuDiscoveryV5Config* = object
    discv5Config*: Option[DiscoveryConfig]
    address*: ValidIpAddress
    port*: Port
    privateKey*: eth_keys.PrivateKey
    bootstrapRecords*: seq[waku_enr.Record]
    autoupdateRecord*: bool


## Protocol

type WakuDiscv5Predicate* = proc(record: waku_enr.Record): bool {.closure, gcsafe.}

type WakuDiscoveryV5* = ref object
    conf: WakuDiscoveryV5Config
    protocol*: protocol.Protocol
    listening*: bool

proc new*(T: type WakuDiscoveryV5, rng: ref HmacDrbgContext, conf: WakuDiscoveryV5Config, record: Option[waku_enr.Record]): T =
  let protocol = newProtocol(
    rng = rng,
    config = conf.discv5Config.get(protocol.defaultDiscoveryConfig),
    bindPort = conf.port,
    bindIp = conf.address,
    privKey = conf.privateKey,
    bootstrapRecords = conf.bootstrapRecords,
    enrAutoUpdate = conf.autoupdateRecord,
    previousRecord = record,
    enrIp = none(ValidIpAddress),
    enrTcpPort = none(Port),
    enrUdpPort = none(Port),
  )

  WakuDiscoveryV5(conf: conf, protocol: protocol, listening: false)

proc new*(T: type WakuDiscoveryV5,
          extIp: Option[ValidIpAddress],
          extTcpPort: Option[Port],
          extUdpPort: Option[Port],
          bindIP: ValidIpAddress,
          discv5UdpPort: Port,
          bootstrapEnrs = newSeq[enr.Record](),
          enrAutoUpdate = false,
          privateKey: eth_keys.PrivateKey,
          flags: CapabilitiesBitfield,
          multiaddrs = newSeq[MultiAddress](),
          rng: ref HmacDrbgContext,
          discv5Config: protocol.DiscoveryConfig = protocol.defaultDiscoveryConfig): T {.
  deprecated: "use the config and record proc variant instead".}=

  let record = block:
        var builder = EnrBuilder.init(privateKey)
        builder.withIpAddressAndPorts(
            ipAddr = extIp,
            tcpPort = extTcpPort,
            udpPort = extUdpPort,
        )
        builder.withWakuCapabilities(flags)
        builder.withMultiaddrs(multiaddrs)
        builder.build().expect("Record within size limits")

  let conf = WakuDiscoveryV5Config(
    discv5Config: some(discv5Config),
    address: bindIP,
    port: discv5UdpPort,
    privateKey: privateKey,
    bootstrapRecords: bootstrapEnrs,
    autoupdateRecord: enrAutoUpdate,
  )

  WakuDiscoveryV5.new(rng, conf, some(record))


proc start*(wd: WakuDiscoveryV5): Result[void, string] =
  if wd.listening:
    return err("already listening")

  # Start listening on configured port
  debug "start listening on udp port", address = $wd.conf.address, port = $wd.conf.port
  try:
    wd.protocol.open()
  except CatchableError:
    return err("failed to open udp port: " & getCurrentExceptionMsg())

  wd.listening = true

  # Start Discovery v5
  trace "start discv5 service"
  wd.protocol.start()

  ok()

proc closeWait*(wd: WakuDiscoveryV5) {.async.} =
  debug "closing Waku discovery v5 node"
  if not wd.listening:
    return

  wd.listening = false
  await wd.protocol.closeWait()

proc findRandomPeers*(wd: WakuDiscoveryV5, pred: WakuDiscv5Predicate = nil): Future[seq[waku_enr.Record]] {.async.} =
  ## Find random peers to connect to using Discovery v5
  let discoveredNodes = await wd.protocol.queryRandom()

  var discoveredRecords = discoveredNodes.mapIt(it.record)

  # Filter out nodes that do not match the predicate
  if not pred.isNil():
    discoveredRecords = discoveredRecords.filter(pred)

  return discoveredRecords


## Helper functions

proc parseBootstrapAddress(address: string): Result[enr.Record, cstring] =
  logScope:
    address = address

  if address[0] == '/':
    return err("MultiAddress bootstrap addresses are not supported")

  let lowerCaseAddress = toLowerAscii(address)
  if lowerCaseAddress.startsWith("enr:"):
    var enrRec: enr.Record
    if not enrRec.fromURI(address):
      return err("Invalid ENR bootstrap record")

    return ok(enrRec)

  elif lowerCaseAddress.startsWith("enode:"):
    return err("ENode bootstrap addresses are not supported")

  else:
    return err("Ignoring unrecognized bootstrap address type")

proc addBootstrapNode*(bootstrapAddr: string,
                       bootstrapEnrs: var seq[enr.Record]) =
  # Ignore empty lines or lines starting with #
  if bootstrapAddr.len == 0 or bootstrapAddr[0] == '#':
    return

  let enrRes = parseBootstrapAddress(bootstrapAddr)
  if enrRes.isErr():
    debug "ignoring invalid bootstrap address", reason = enrRes.error
    return

  bootstrapEnrs.add(enrRes.value)
