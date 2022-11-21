
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



##  Sqlite vacuum

# TODO: Cache this value in the SqliteDatabase object.
#       Page size should not change during the node execution time
proc getPageSize*(db: SqliteDatabase): SqliteResult[int64] =
  ## Query or set the page size of the database. The page size must be a power of
  ## two between 512 and 65536 inclusive.
  var size: int64
  proc handler(s: RawStmtPtr) =
    size = sqlite3_column_int64(s, 0)

  let res = db.query("PRAGMA page_size;", handler)
  if res.isErr():
      return err("failed to get page_size")

  ok(size)


proc getFreelistCount*(db: SqliteDatabase): SqliteResult[int64] =
  ## Return the number of unused pages in the database file.
  var count: int64
  proc handler(s: RawStmtPtr) =
    count = sqlite3_column_int64(s, 0)

  let res = db.query("PRAGMA freelist_count;", handler)
  if res.isErr():
      return err("failed to get freelist_count")

  ok(count)


proc getPageCount*(db: SqliteDatabase): SqliteResult[int64] =
  ## Return the total number of pages in the database file.
  var count: int64
  proc handler(s: RawStmtPtr) =
    count = sqlite3_column_int64(s, 0)

  let res = db.query("PRAGMA page_count;", handler)
  if res.isErr():
      return err("failed to get page_count")

  ok(count)


proc vacuum*(db: SqliteDatabase): SqliteResult[void] =
  ## The VACUUM command rebuilds the database file, repacking it into a minimal amount of disk space.
  let res = db.query("VACUUM;", NoopRowHandler)
  if res.isErr():
      return err("vacuum failed")

  ok()
