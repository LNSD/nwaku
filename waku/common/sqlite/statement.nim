when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}

import
  std/options,
  stew/results,
  chronicles,
  sqlite3_abi
import
  ./common

logScope:
  topics = "sqlite"


## Query

type SqlQuery* = distinct string

template sql*(query: string): SqlQuery =
  ## Constructs a SqlQuery from the string query.
  ## This is supposed to be used as a raw-string-literal modifier: `sql"SELECT * FROM table"`
  SqlQuery(query)


## Sqlite

proc disposeIfUnreleased[T](x: var AutoDisposed[T]) =
  mixin dispose
  if x.val != nil:
    dispose(x.release)


# Raw statement

type
  RawStmt* = ptr sqlite3_stmt

  RowHandler* = proc(s: RawStmt) {.closure.} # the nim-eth definition is different; one more indirection


template dispose(rawStmt: RawStmt) =
  discard sqlite3_finalize(rawStmt)


proc bindParam*(s: RawStmt, n: int, val: auto): cint =
  when val is openarray[byte]|seq[byte]:
    if val.len > 0:
      sqlite3_bind_blob(s, n.cint, unsafeAddr val[0], val.len.cint, nil)
    else:
      sqlite3_bind_blob(s, n.cint, nil, 0.cint, nil)
  elif val is int32:
    sqlite3_bind_int(s, n.cint, val)
  elif val is uint32:
    sqlite3_bind_int64(s, n.cint, val)
  elif val is int64:
    sqlite3_bind_int64(s, n.cint, val)
  elif val is float64:
    sqlite3_bind_double(s, n.cint, val)
  # Note: bind_text not yet supported in sqlite3_abi wrapper
  # elif val is string:
  #   sqlite3_bind_text(s, n.cint, val.cstring, -1, nil)  # `-1` implies string length is the number of bytes up to the first null-terminator
  else:
    {.fatal: "Please add support for the '" & $typeof(val) & "' type".}

template bindParams(s: RawStmt, params: auto) =
  when params is tuple:
    var i = 1
    for param in fields(params):
      checkErr bindParam(s, i, param)
      inc i
  else:
    checkErr bindParam(s, 1, params)

template readResult(s: RawStmt, column: cint, T: type): auto =
  when T is Option:
    if sqlite3_column_type(s, column) == SQLITE_NULL:
      none(typeof(default(T).get()))
    else:
      some(readSimpleResult(s, column, typeof(default(T).get())))
  else:
    readSimpleResult(s, column, T)

template readResult(s: RawStmt, T: type): auto =
  when T is tuple:
    var res: T
    var i = cint 0
    for field in fields(res):
      field = readResult(s, i, typeof(field))
      inc i
    res
  else:
    readResult(s, 0.cint, T)




# Statement

const NoopRowHandler*: RowHandler = proc(s: RawStmt) {.closure.} = discard

type
  NoParams* = tuple

  SqliteStmt*[Params; SqliteResult] = distinct RawStmt

template dispose*(sqliteStmt: SqliteStmt) =
  discard sqlite3_finalize(RawStmt(sqliteStmt))




proc exec*[Params, Res](s: SqliteStmt[Params, Res],
                        params: Params,
                        handler: RowHandler): SqliteResult[void] =
  let s = RawStmt(s)
  bindParams(s, params)

  try:
    while true:
      let v = sqlite3_step(s)
      case v
      of SQLITE_ROW:
        handler(s)
      of SQLITE_DONE:
        break
      else:
        return err($sqlite3_errstr(v))
    return ok()
  finally:
    # Release implicit transaction
    discard sqlite3_reset(s) # same return information as step
    discard sqlite3_clear_bindings(s) # no errors possible

proc exec*[P](s: SqliteStmt[P, void], params: P): SqliteResult[void] =
  ## Void result variant of exec to be used with non-query statements like
  ## pragmas.
  let s = RawStmt(s)
  bindParams(s, params)

  try:
    if (let rc = sqlite3_step(s); rc != SQLITE_DONE):
      return err($sqlite3_errstr(v))
    else:
      return ok()
  finally:
    # Release implict transaction
    discard sqlite3_reset(s) # same return information as step
    discard sqlite3_clear_bindings(s) # no errors possible
