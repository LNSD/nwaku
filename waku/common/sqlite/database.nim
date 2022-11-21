# The code in this file is an adaptation of the Sqlite KV Store found in nim-eth.
# https://github.com/status-im/nim-eth/blob/master/eth/db/kvstore_sqlite3.nim
#
# Most of it is a direct copy, the only unique functions being `get` and `put`.
when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}

import
  std/os,
  stew/results,
  chronicles,
  sqlite3_abi
import
  ./common,
  ./statement


logScope:
  topics = "sqlite"


type Sqlite = ptr sqlite3

template dispose(db: Sqlite) =
  discard sqlite3_close(db)

proc release[T](x: var AutoDisposed[T]): T =
  result = x.val
  x.val = nil

proc disposeIfUnreleased[T](x: var AutoDisposed[T]) =
  mixin dispose
  if x.val != nil:
    dispose(x.release)

template checkErr*(op, cleanup: untyped) =
  if (let rc = (op); rc != SQLITE_OK):
    cleanup
    return err($sqlite3_errstr(v))

template checkErr*(op) =
  checkErr(op): discard

template prepare*(env: Sqlite, q: string, cleanup: untyped): RawStmt =
  var s: ptr sqlite3_stmt
  checkErr sqlite3_prepare_v2(env, q, q.len.cint, addr s, nil):
    cleanup
  s


## Sqlite database object

type SqliteDatabase* = ref object
    env*: Sqlite



proc new*(T: type SqliteDatabase, path: string, readOnly=false): SqliteResult[T] =
  var env: AutoDisposed[ptr sqlite3]
  defer: disposeIfUnreleased(env)

  let flags = if readOnly: SQLITE_OPEN_READONLY
              else: SQLITE_OPEN_READWRITE or SQLITE_OPEN_CREATE

  if path != ":memory:":
    try:
      createDir(parentDir(path))
    except OSError, IOError:
      return err("sqlite: cannot create database directory")

  checkErr sqlite3_open_v2(path, addr env.val, flags.cint, nil)

  template prepare(q: string, cleanup: untyped): ptr sqlite3_stmt =
    var s: ptr sqlite3_stmt
    checkErr sqlite3_prepare_v2(env.val, q, q.len.cint, addr s, nil):
      cleanup
    s

  template checkExec(s: ptr sqlite3_stmt) =
    if (let x = sqlite3_step(s); x != SQLITE_DONE):
      discard sqlite3_finalize(s)
      return err($sqlite3_errstr(x))

    if (let x = sqlite3_finalize(s); x != SQLITE_OK):
      return err($sqlite3_errstr(x))

  template checkExec(q: string) =
    let s = prepare(q): discard
    checkExec(s)

  template checkWalPragmaResult(journalModePragma: ptr sqlite3_stmt) =
    if (let x = sqlite3_step(journalModePragma); x != SQLITE_ROW):
      discard sqlite3_finalize(journalModePragma)
      return err($sqlite3_errstr(x))

    if (let x = sqlite3_column_type(journalModePragma, 0); x != SQLITE3_TEXT):
      discard sqlite3_finalize(journalModePragma)
      return err($sqlite3_errstr(x))

    if (let x = sqlite3_column_text(journalModePragma, 0);
        x != "memory" and x != "wal"):
      discard sqlite3_finalize(journalModePragma)
      return err("Invalid pragma result: " & $x)


  let journalModePragma = prepare("PRAGMA journal_mode = WAL;"): discard
  checkWalPragmaResult(journalModePragma)
  checkExec(journalModePragma)

  ok(SqliteDatabase(env: env.release))




proc query*(db: SqliteDatabase, query: string, onData: DataProc): SqliteResult[bool] =
  var s = prepare(db.env, query): discard

  try:
    var gotResults = false
    while true:
      let v = sqlite3_step(s)
      case v
      of SQLITE_ROW:
        onData(s)
        gotResults = true
      of SQLITE_DONE:
        break
      else:
        return err($sqlite3_errstr(v))
    return ok gotResults
  finally:
    # release implicit transaction
    discard sqlite3_reset(s) # same return information as step
    discard sqlite3_clear_bindings(s) # no errors possible
    discard sqlite3_finalize(s) # NB: dispose of the prepared query statement and free associated memory

proc prepareStmt*(
  db: SqliteDatabase,
  stmt: string,
  Params: type,
  Res: type
): SqliteResult[SqliteStmt[Params, Res]] =
  var s: RawStmt
  checkErr sqlite3_prepare_v2(db.env, stmt, stmt.len.cint, addr s, nil)
  ok(SqliteStmt[Params, Res](s))

proc close*(db: SqliteDatabase) =
  discard sqlite3_close(db.env)

  db[] = SqliteDatabase()[]

