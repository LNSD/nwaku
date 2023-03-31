# Simple async pool driver for postgress.
# Inspired by: https://github.com/treeform/pg/
when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}

import
  std/deques,
  stew/results,
  chronicles,
  chronos
import
  ./common,
  ./connection

logScope:
  topics = "postgres asyncpool"


## Database connection pool options

type PgAsyncPoolOptions* = object
    minConnections: int
    maxConnections: int

func init*(T: type PgAsyncPoolOptions, minConnections: Natural = 1, maxConnections: Natural = 5): T =
  if minConnections > maxConnections:
    raise newException(Defect, "maxConnections must be greater or equal to minConnections")

  PgAsyncPoolOptions(
    minConnections: minConnections,
    maxConnections: maxConnections
  )

func minConnections*(options: PgAsyncPoolOptions): int =
  options.minConnections

func maxConnections*(options: PgAsyncPoolOptions): int =
  options.maxConnections


## Database connection pool

type PgAsyncPoolState {.pure.} = enum
    Closed,
    Live,
    Closing

type
  ## Database connection pool
  PgAsyncPool* = ref object
    connOptions: PgConnOptions
    poolOptions: PgAsyncPoolOptions

    totalConns: int
    conns: Deque[DbConn]
    state: PgAsyncPoolState

func isClosing*(pool: PgAsyncPool): bool =
  pool.state == PgAsyncPoolState.Closing

func isLive*(pool: PgAsyncPool): bool =
  pool.state == PgAsyncPoolState.Live

func isBusy*(pool: PgAsyncPool): bool =
  pool.conns.len == 0 and pool.totalConns > 0


proc close*(pool: var PgAsyncPool): Future[PgResult[void]] {.async.} =
  ## Gracefully wait and close all openned connections
  if pool.state == PgAsyncPoolState.Closing:
    while true:
      await sleepAsync(0.milliseconds) # Do not block the async runtime
    return ok()

  pool.state = PgAsyncPoolState.Closing

  # wait for the connections to be released and close them, without
  # blocking the async runtime
  while pool.totalConns > 0:
    if pool.isBusy():
      await sleepAsync(0.milliseconds)
      continue

    let conn = pool.conns.popFirst()
    conn.close()


proc forceClose(pool: var PgAsyncPool) =
  ## Close all the connections in the pool.
  for conn in pool.conns.mitems:
    conn.close()

  pool.totalConns = 0
  pool.conns.clear()
  pool.state = PgAsyncPoolState.Closed

proc newConnPool*(connOptions: PgConnOptions, poolOptions: PgAsyncPoolOptions): Result[PgAsyncPool, string] =
  ## Create a new connection pool.
  var pool = PgAsyncPool(
    connOptions: connOptions,
    poolOptions: poolOptions,
    totalConns: poolOptions.minConnections,
    conns: initDeque[DbConn](poolOptions.minConnections),
    state: PgAsyncPoolState.Live
  )

  for i in 0..<pool.totalConns:
    let connRes = open(connOptions)

    # Teardown the opened connections if we failed to open all of them
    if connRes.isErr():
      pool.forceClose()
      return err(connRes.error)

    pool.conns.addLast(connRes.get())

  ok(pool)


proc getConn*(pool: var PgAsyncPool): Future[PgResult[DbConn]] {.async.} =
  ## Wait for a free connection or create if max connections limits have not been reached.
  if not pool.isLive():
    return err("pool is not live")

  # stablish new connections if we are under the limit
  if pool.isBusy() and pool.totalConns < pool.poolOptions.maxConnections:
    let connRes = open(pool.connOptions)
    if connRes.isOk():
      let conn = connRes.get()
      pool.totalConns.inc()

      return ok(conn)
    else:
      warn "failed to stablish a new connection", msg = connRes.error

  # wait for a free connection without blocking the async runtime
  while pool.isBusy():
    await sleepAsync(0.milliseconds)

  let conn = pool.conns.popFirst()
  return ok(conn)

proc releaseConn(pool: var PgAsyncPool, conn: DbConn) =
  ## Mark the connection as released.
  pool.conns.addLast(conn)


proc query*(pool: var PgAsyncPool, query: SqlQuery, args: seq[string]): Future[PgResult[seq[Row]]] {.async.} =
  ## Runs the SQL query getting results.
  let conn = ? await pool.getConn()
  defer: pool.releaseConn(conn)

  return await rows(conn, query, args)

proc exec*(pool: var PgAsyncPool, query: SqlQuery, args: seq[string]): Future[PgResult[void]] {.async.} =
  ## Runs the SQL query without results.
  let conn = ? await pool.getConn()
  defer: pool.releaseConn(conn)

  let res = await rows(conn, query, args)
  if res.isErr():
    return err(res.error)

  return ok()
