{.used.}

import
  std/sequtils,
  testutils/unittests,
  ../../waku/v2/protocol/waku_store/waku_store_types

procSuite "Sorted store queue":

  # Helper functions
  proc genIndexedWakuMessage(i: int8): IndexedWakuMessage =
    ## Use i to generate an IndexedWakuMessage
    var data {.noinit.}: array[32, byte]
    for x in data.mitems: x = i.byte
    return IndexedWakuMessage(msg: WakuMessage(payload: @[byte i], timestamp: float64(i)),
                              index: Index(receiverTime: float64(i), senderTime: float64(i), digest: MDigest[256](data: data)))

  # Test variables  
  let
    capacity = 5
    unsortedSet = [5,1,3,2,4]
  
  var testStoreQueue = StoreQueueRef.new(capacity)
  for i in unsortedSet:
    discard testStoreQueue.add(genIndexedWakuMessage(i.int8))
  
  test "Store queue can be created with limited capacity":
    var stQ = StoreQueueRef.new(capacity)
    check:
      stQ.len == 0 # Empty when initialised
    
    for i in 1..capacity: # Fill up the queue
      check:
        stQ.add(genIndexedWakuMessage(i.int8)).isOk()
    
    check:
      stQ.len == capacity
    
    # Add one more. Capacity should not be exceeded.
    check:
      stQ.add(genIndexedWakuMessage(capacity.int8 + 1)).isOk()
    
    check:
      stQ.len == capacity
  
  test "Store queue sort-on-insert works":    
    # Walk forward through the set and verify ascending order
    var prevSmaller = genIndexedWakuMessage(min(unsortedSet).int8 - 1).index
    for i in testStoreQueue.fwdIterator:
      let (index, indexedWakuMessage) = i
      check cmp(index, prevSmaller) > 0
      prevSmaller = index
    
    # Walk backward through the set and verify descending order
    var prevLarger = genIndexedWakuMessage(max(unsortedSet).int8 + 1).index
    for i in testStoreQueue.bwdIterator:
      let (index, indexedWakuMessage) = i
      check cmp(index, prevLarger) < 0
      prevLarger = index
  
  test "Can access first item from store queue":
    let first = testStoreQueue.first()
    check:
      first.isOk()
      first.get().msg.timestamp == 1.0
    
    # Error condition
    let emptyQ = StoreQueueRef.new(capacity)
    check:
      emptyQ.first().isErr()
  
  test "Can access last item from store queue":
    let last = testStoreQueue.last()
    check:
      last.isOk()
      last.get().msg.timestamp == 5.0
    
    # Error condition
    let emptyQ = StoreQueueRef.new(capacity)
    check:
      emptyQ.last().isErr()
  
  test "Store queue forward pagination works":
    proc predicate(i: IndexedWakuMessage): bool = true # no filtering

    var (res, pInfo, err) = testStoreQueue.getPage(predicate,
                                                   PagingInfo(pageSize: 3,
                                                              direction: PagingDirection.FORWARD))
    
    check:
      # First page
      pInfo.pageSize == 3
      pInfo.direction == PagingDirection.FORWARD
      pInfo.cursor.senderTime == 3.0
      err == HistoryResponseError.NONE
      res.mapIt(it.timestamp.int) == @[1,2,3]


    (res, pInfo, err) = testStoreQueue.getPage(predicate,
                                               pInfo)
    
    check:
      # Second page
      pInfo.pageSize == 2
      pInfo.direction == PagingDirection.FORWARD
      pInfo.cursor.senderTime == 5.0
      err == HistoryResponseError.NONE
      res.mapIt(it.timestamp.int) == @[4,5]
    
    (res, pInfo, err) = testStoreQueue.getPage(predicate,
                                               pInfo)

    check:
      # Empty last page
      pInfo.pageSize == 0
      pInfo.direction == PagingDirection.FORWARD
      pInfo.cursor.senderTime == 5.0
      err == HistoryResponseError.NONE
      res.len == 0
  
  test "Store queue backward pagination works":   
    proc predicate(i: IndexedWakuMessage): bool = true # no filtering

    var (res, pInfo, err) = testStoreQueue.getPage(predicate,
                                                   PagingInfo(pageSize: 3,
                                                              direction: PagingDirection.BACKWARD))
    
    check:
      # First page
      pInfo.pageSize == 3
      pInfo.direction == PagingDirection.BACKWARD
      pInfo.cursor.senderTime == 3.0
      err == HistoryResponseError.NONE
      res.mapIt(it.timestamp.int) == @[3,4,5]


    (res, pInfo, err) = testStoreQueue.getPage(predicate,
                                               pInfo)
    
    check:
      # Second page
      pInfo.pageSize == 2
      pInfo.direction == PagingDirection.BACKWARD
      pInfo.cursor.senderTime == 1.0
      err == HistoryResponseError.NONE
      res.mapIt(it.timestamp.int) == @[1,2]
    
    (res, pInfo, err) = testStoreQueue.getPage(predicate,
                                               pInfo)

    check:
      # Empty last page
      pInfo.pageSize == 0
      pInfo.direction == PagingDirection.BACKWARD
      pInfo.cursor.senderTime == 1.0
      err == HistoryResponseError.NONE
      res.len == 0
  
  test "Store queue pagination works with predicate":
    proc onlyEvenTimes(i: IndexedWakuMessage): bool = i.msg.timestamp.int64 mod 2 == 0
    proc onlyOddTimes(i: IndexedWakuMessage): bool = i.msg.timestamp.int64 mod 2 != 0

    ## Forward pagination: only even timestamped messages
    
    var (res, pInfo, err) = testStoreQueue.getPage(onlyEvenTimes,
                                                   PagingInfo(pageSize: 2,
                                                              direction: PagingDirection.FORWARD))
    
    check:
      # First page
      pInfo.pageSize == 2
      pInfo.direction == PagingDirection.FORWARD
      pInfo.cursor.senderTime == 4.0
      err == HistoryResponseError.NONE
      res.mapIt(it.timestamp.int) == @[2,4]
    
    (res, pInfo, err) = testStoreQueue.getPage(onlyEvenTimes,
                                               pInfo)

    check:
      # Empty next page
      pInfo.pageSize == 0
      pInfo.direction == PagingDirection.FORWARD
      pInfo.cursor.senderTime == 4.0
      err == HistoryResponseError.NONE
      res.len == 0

    ## Backward pagination: only odd timestamped messages
    
    (res, pInfo, err) = testStoreQueue.getPage(onlyOddTimes,
                                               PagingInfo(pageSize: 2,
                                               direction: PagingDirection.BACKWARD))
    
    check:
      # First page
      pInfo.pageSize == 2
      pInfo.direction == PagingDirection.BACKWARD
      pInfo.cursor.senderTime == 3.0
      err == HistoryResponseError.NONE
      res.mapIt(it.timestamp.int) == @[3,5]
    
    (res, pInfo, err) = testStoreQueue.getPage(onlyOddTimes,
                                               pInfo)

    check:
      # Next page
      pInfo.pageSize == 1
      pInfo.direction == PagingDirection.BACKWARD
      pInfo.cursor.senderTime == 1.0
      err == HistoryResponseError.NONE
      res.mapIt(it.timestamp.int) == @[1]

    (res, pInfo, err) = testStoreQueue.getPage(onlyOddTimes,
                                               pInfo)

    check:
      # Empty last page
      pInfo.pageSize == 0
      pInfo.direction == PagingDirection.BACKWARD
      pInfo.cursor.senderTime == 1.0
      err == HistoryResponseError.NONE
      res.len == 0

  test "Store queue pagination handles invalid cursor":   
    proc predicate(i: IndexedWakuMessage): bool = true # no filtering

    # Invalid cursor in backwards direction

    var (res, pInfo, err) = testStoreQueue.getPage(predicate,
                                                   PagingInfo(pageSize: 3,
                                                              cursor: Index(receiverTime: float64(3), senderTime: float64(3), digest: MDigest[256]()),
                                                              direction: PagingDirection.BACKWARD))
    
    check:
      # Empty response with error
      pInfo.pageSize == 0
      pInfo.direction == PagingDirection.BACKWARD
      pInfo.cursor.senderTime == 3.0
      err == HistoryResponseError.INVALID_CURSOR
      res.len == 0
    
    # Same test, but forward direction

    (res, pInfo, err) = testStoreQueue.getPage(predicate,
                                               PagingInfo(pageSize: 3,
                                                          cursor: Index(receiverTime: float64(3), senderTime: float64(3), digest: MDigest[256]()),
                                                          direction: PagingDirection.FORWARD))
    
    check:
      # Empty response with error
      pInfo.pageSize == 0
      pInfo.direction == PagingDirection.FORWARD
      pInfo.cursor.senderTime == 3.0
      err == HistoryResponseError.INVALID_CURSOR
      res.len == 0
  
  test "Store queue pagination works on empty list":
    var stQ = StoreQueueRef.new(capacity)
    check:
      stQ.len == 0 # Empty when initialised
    
    proc predicate(i: IndexedWakuMessage): bool = true # no filtering

    # Get page from empty queue in bwd dir

    var (res, pInfo, err) = stQ.getPage(predicate,
                                        PagingInfo(pageSize: 3,
                                                   direction: PagingDirection.BACKWARD))
    
    check:
      # Empty response
      pInfo.pageSize == 0
      pInfo.direction == PagingDirection.BACKWARD
      pInfo.cursor.senderTime == 0.0
      err == HistoryResponseError.NONE
      res.len == 0
    
    # Get page from empty queue in fwd dir
    
    (res, pInfo, err) = stQ.getPage(predicate,
                                    PagingInfo(pageSize: 3,
                                               direction: PagingDirection.FORWARD))

    check:
      # Empty response
      pInfo.pageSize == 0
      pInfo.direction == PagingDirection.FORWARD
      pInfo.cursor.senderTime == 0.0
      err == HistoryResponseError.NONE
      res.len == 0

  test "Can verify if store queue contains an index":
    let
      existingIndex = genIndexedWakuMessage(4).index
      nonExistingIndex = genIndexedWakuMessage(99).index
    check:
      testStoreQueue.contains(existingIndex) == true
      testStoreQueue.contains(nonExistingIndex) == false
