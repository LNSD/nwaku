when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}

import
  std/options,
  stew/results,
  chronicles,
  chronos,
  libp2p/crypto/crypto,
  presto,
  json_rpc/rpcserver,
  metrics,
  metrics/chronos_httpserver
import
  ../../waku/v2/node/message_cache,
  ../../waku/v2/node/rest/server,
  ../../waku/v2/node/rest/debug/handlers as rest_debug_api,
  ../../waku/v2/node/rest/relay/handlers as rest_relay_api,
  ../../waku/v2/node/rest/relay/topic_cache,
  ../../waku/v2/node/rest/store/handlers as rest_store_api,
  ../../waku/v2/node/jsonrpc/admin/handlers as rpc_admin_api,
  ../../waku/v2/node/jsonrpc/debug/handlers as rpc_debug_api,
  ../../waku/v2/node/jsonrpc/filter/handlers as rpc_filter_api,
  ../../waku/v2/node/jsonrpc/relay/handlers as rpc_relay_api,
  ../../waku/v2/node/jsonrpc/store/handlers as rpc_store_api
import
  ../../app,
  ../../config

logScope:
  topics = "wakunode"


type
  Wakunode2* = ref object
    conf: WakuNodeConf
    app: App

    rpcServer: Option[RpcHttpServer]
    restServer: Option[RestServerRef]
    metricsServer: Option[MetricsHttpServerRef]

  Wakunode2Result*[T] = Result[T, string]


proc new*(T: type Wakunode2, rng: ref HmacDrbgContext, conf: WakuNodeConf): T =
  let app = App.init(rng, conf)
  Wakunode2(app: app)


## Monitoring and external interfaces

proc startRestServer(wakunode2: Wakunode2, address: ValidIpAddress, port: Port, conf: WakuNodeConf): AppResult[RestServerRef] =
  let server = ? newRestHttpServer(address, port)

  ## Debug REST API
  installDebugApiHandlers(server.router, wakunode2.app.node)

  ## Relay REST API
  if conf.relay:
    let relayCache = TopicCache.init(capacity=conf.restRelayCacheCapacity)
    installRelayApiHandlers(server.router, wakunode2.app.node, relayCache)

  ## Store REST API
  installStoreApiHandlers(server.router, wakunode2.app.node)

  server.start()
  info "Starting REST HTTP server", url = "http://" & $address & ":" & $port & "/"

  ok(server)

proc startRpcServer(app: Wakunode2, address: ValidIpAddress, port: Port, conf: WakuNodeConf): AppResult[RpcHttpServer] =
  let ta = initTAddress(address, port)

  var server: RpcHttpServer
  try:
    server = newRpcHttpServer([ta])
  except CatchableError:
    return err("failed to init JSON-RPC server: " & getCurrentExceptionMsg())

  installDebugApiHandlers(wakunode2.app.node, server)

  if conf.relay:
    let relayMessageCache = rpc_relay_api.MessageCache.init(capacity=30)
    installRelayApiHandlers(wakunode2.app.node, server, relayMessageCache)
    if conf.rpcPrivate:
      installRelayPrivateApiHandlers(wakunode2.app.node, server, relayMessageCache)

  if conf.filternode != "":
    let filterMessageCache = rpc_filter_api.MessageCache.init(capacity=30)
    installFilterApiHandlers(wakunode2.app.node, server, filterMessageCache)

  installStoreApiHandlers(wakunode2.app.node, server)

  if conf.rpcAdmin:
    installAdminApiHandlers(wakunode2.app.node, server)

  server.start()
  info "RPC Server started", address=ta

  ok(server)

proc startMetricsServer(serverIp: ValidIpAddress, serverPort: Port): AppResult[MetricsHttpServerRef] =
  info "Starting metrics HTTP server", serverIp= $serverIp, serverPort= $serverPort

  let metricsServerRes = MetricsHttpServerRef.new($serverIp, serverPort)
  if metricsServerRes.isErr():
    return err("metrics HTTP server start failed: " & $metricsServerRes.error)

  let server = metricsServerRes.value
  try:
    waitFor server.start()
  except CatchableError:
    return err("metrics HTTP server start failed: " & getCurrentExceptionMsg())

  info "Metrics HTTP server started", serverIp= $serverIp, serverPort= $serverPort
  ok(server)

proc startMetricsLogging(): AppResult[void] =
  startMetricsLog()
  ok()

proc setupMonitoringAndExternalInterfaces*(wakunode2: var Wakunode2): AppResult[void] =
  if wakunode2.conf.rpc:
    let startRpcServerRes = startRpcServer(wakunode2, wakunode2.conf.rpcAddress, Port(wakunode2.conf.rpcPort + wakunode2.conf.portsShift), wakunode2.conf)
    if startRpcServerRes.isErr():
      error "6/7 Starting JSON-RPC server failed. Continuing in current state.", error=startRpcServerRes.error
    else:
      wakunode2.rpcServer = some(startRpcServerRes.value)

  if wakunode2.conf.rest:
    let startRestServerRes = startRestServer(wakunode2, wakunode2.conf.restAddress, Port(wakunode2.conf.restPort + wakunode2.conf.portsShift), wakunode2.conf)
    if startRestServerRes.isErr():
      error "6/7 Starting REST server failed. Continuing in current state.", error=startRestServerRes.error
    else:
      wakunode2.restServer = some(startRestServerRes.value)


  if wakunode2.conf.metricsServer:
    let startMetricsServerRes = startMetricsServer(wakunode2.conf.metricsServerAddress, Port(wakunode2.conf.metricsServerPort + wakunode2.conf.portsShift))
    if startMetricsServerRes.isErr():
      error "6/7 Starting metrics server failed. Continuing in current state.", error=startMetricsServerRes.error
    else:
      wakunode2.metricsServer = some(startMetricsServerRes.value)

  if wakunode2.conf.metricsLogging:
    let startMetricsLoggingRes = startMetricsLogging()
    if startMetricsLoggingRes.isErr():
      error "6/7 Starting metrics console logging failed. Continuing in current state.", error=startMetricsLoggingRes.error

  ok()

