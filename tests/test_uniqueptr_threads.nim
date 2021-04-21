discard """
  matrix: "--threads:on"
"""
import
  nptr,
  threadpool

block uniquePtrTest1:
  var pt = initUniquePtr[string]()
  pt.write(proc(s: var string) = s="Hello") # assignment

  proc work(cp: UniquePtr[string]) =
    cp.write(proc(s: var string) =
      s.add(" World")
      doAssert s == "Hello World"
    )
  spawn work(move pt) # explicit move is required when passing across threads
  sync()

block uniquePtrTest2:
  var pt = initUniquePtr[int]()
  pt.write(proc(s: var int) = s=8) # assignment

  proc work(cp: UniquePtr[int]) =
    cp.write(proc(s: var int) =
      s = 10
      doAssert s == 10
    )
  spawn work(move pt) # explicit move is required when passing across threads
  sync()

block uniquePtrTest3:
  # ensure using shared heap
  var pt: UniquePtr[int]

  proc work(o: ptr UniquePtr[int]) {.thread.} =
    var localPt = initUniquePtr[int]()
    localPt.write(proc(i: var int) = i=8)
    o[] = move localPt

  var t: Thread[ptr UniquePtr[int]]
  createThread[ptr UniquePtr[int]](t, work, addr pt)
  joinThread(t)

  pt.read(proc(i: int) = doAssert i == 8)

block destructorUniquePtrTest:
  var isDestructorCalled:bool
  block:
    proc work(p: UniquePtr[int]) = discard
    var p = initUniquePtr[int](proc(i: var int) = isDestructorCalled = true)
    spawn work(move p)
    sync()
  doAssert isDestructorCalled