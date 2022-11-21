when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}

import
  stew/results,
  sqlite3_abi

type
  SqliteError* = object
    code: int
    cause: string
    extendedCode: int
    extendedCause: string

type SqliteResult*[T] = Result[T, SqliteError]


## Auto-dispose

type
  AutoDisposed*[T: ptr|ref] = object
    val: T


## Helper methods

template checkErr*(op, cleanup: untyped) =
  if (let rc = (op); rc != SQLITE_OK):
    cleanup

    let
      code = int(rc)
      cause = string(sqlite3_errstr(rc))
    return err(SqliteError(code: int(rc), cause: cause))

template checkErr*(op) =
  checkErr(op): discard

