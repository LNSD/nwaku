when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}

import
  stew/results,
  sqlite3_abi
import
  ../common,
  ../statement,
  ../database


## Database scheme versioning

proc getUserVersion*(database: SqliteDatabase): SqliteResult[int64] =
  ## Get the value of the user-version integer.
  ##
  ## The user-version is an integer that is available to applications to use however they want.
  ## SQLite makes no use of the user-version itself. This integer is stored at offset 60 in
  ## the database header.
  ##
  ## For more info check: https://www.sqlite.org/pragma.html#pragma_user_version
  var version: int64
  proc handler(s: ptr sqlite3_stmt) =
    version = sqlite3_column_int64(s, 0)

  let res = database.query("PRAGMA user_version;", handler)
  if res.isErr():
      return err("failed to get user_version")

  ok(version)

proc setUserVersion*(database: SqliteDatabase, version: int64): SqliteResult[void] =
  ## Set the value of the user-version integer.
  ##
  ## The user-version is an integer that is available to applications to use however they want.
  ## SQLite makes no use of the user-version itself. This integer is stored at offset 60 in
  ## the database header.
  ##
  ## For more info check: https://www.sqlite.org/pragma.html#pragma_user_version
  let query = "PRAGMA user_version=" & $version & ";"
  let res = database.query(query, NoopRowHandler)
  if res.isErr():
      return err("failed to set user_version")

  ok()
