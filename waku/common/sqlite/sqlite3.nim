when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}

import
  std/os,
  stew/results,
  chronicles,
  sqlite3_abi




type
  Sqlite3Connection* = ptr sqlite3

template dispose(conn: Sqlite3Connection) =
  discard sqlite3_close(conn)


# Raw statement

type Sqlite3Stmt* = ptr sqlite3_stmt


template dispose(statement: Sqlite3Stmt) =
  discard sqlite3_finalize(statement)




type RowHandler* = proc(s: Sqlite3Stmt) {.closure.}
