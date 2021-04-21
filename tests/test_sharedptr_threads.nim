discard """
  matrix: "--threads:on"
"""

import
  nptr,
  threadpool

block sharedPtr1:
  var pt = initSharedPtr[int]()
  proc work(cp: SharedPtr[int]) =
    cp.write(proc(i: var int) =
      i+=1
    )
  for _ in 0..4:
    spawn(work(pt))
  sync()

  pt.read(proc(i: int) = doAssert i==5)

block sharedPtr2:
  var pt = initSharedPtr[string]()
  proc work(cp: SharedPtr[string]) =
    cp.write(proc(i: var string) =
      i.add("a")
    )
  for _ in 0..4:
    spawn(work(pt))
  sync()

  pt.read(proc(i: string) = doAssert i=="aaaaa")

block sharedPtr3:
  # ensure using shared heap
  var pt: SharedPtr[int]

  proc work(o: ptr SharedPtr[int]) {.thread.} =
    var localPt = initSharedPtr[int]()
    localPt.write(proc(i: var int) = i=8)
    o[] = move localPt

  var t: Thread[ptr SharedPtr[int]]
  createThread[ptr SharedPtr[int]](t, work, addr pt)
  joinThread(t)

  pt.read(proc(i: int) = doAssert i == 8)

block destructorSharedPtrTest:
  var isDestructorCalled:bool
  block:
    proc work(p: SharedPtr[int]) = discard
    var p = initSharedPtr[int](proc(i: var int) = isDestructorCalled = true)
    spawn work(move p)
    sync()
  doAssert isDestructorCalled

