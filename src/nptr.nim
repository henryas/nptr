## Module nptr implements smart pointers. They are safe to use across threads.

import
  locks,
  asyncdispatch,
  options,
  os

when isMainModule:
  import threadpool # for testing

export
  options

type
  UniquePtr*[T] = object
    ## UniquePtr manages the lifetime of an object. It retains a single ownership of the object and cannot be copied. It can be passed across threads.
    item: ptr T
    destroy: proc(t: var T)
  SharedPtr*[T] = object
    ## SharedPtr manages the lifetime of an object. It allows multiple ownership of the object. It can be copied and passed across threads. It acts as a read-write mutex to the underlying data and therefore carries a higher cost than UniquePtr.
    content: ptr tuple[
      item: T,
      count: uint8,
      lock: Lock,
      readers: uint8,
      writerQueue: uint8,
    ]
    destroy: proc(t: var T)
  WeakPtr*[T] = object
    ## WeakPtr is a non-owning reference to the object pointed to by SharedPtr. WeakPtr can be passed across threads. It is obtained from SharedPtr, and must be converted back into SharedPtr in order to access the object it points to.
    content: ptr ptr tuple[
      item: T,
      count: uint8,
      lock: Lock,
      readers: uint8,
      writerQueue: uint8,
    ]
    destroy: proc(t: var T)

proc initUniquePtr*[T](destructor: proc(t: var T)): UniquePtr[T] =
  ## create a unique ptr with the given destructor.
  result.item = cast[ptr T](allocShared(sizeof(T)))
  result.item[] = default(T)
  result.destroy = destructor

proc initUniquePtr*[T](): UniquePtr[T] =
  ## create a unique ptr.
  initUniquePtr(proc(t: var T) = discard)

proc `=destroy`[T](p: var UniquePtr[T]) =
  if p.item == nil:
    return
  var old = p.item
  p.destroy(p.item[])
  if p.item == nil:
    p.item = old
  deallocShared(p.item)
  p.item = nil
  p.destroy = nil

proc `=copy`[T](dest: var UniquePtr[T], src: UniquePtr[T]) =
  if dest.item == src.item:
    return
  raise newException(ObjectAssignmentDefect, "unique ptr must not be copied")

proc read*[T](p: UniquePtr[T], fn: proc(i: T)) {.gcsafe.} =
  if p.item == nil:
    raise newException(AccessViolationDefect, "unique ptr is no longer available")
  fn(p.item[])

proc write*[T](p: UniquePtr[T], fn: proc(i: var T)) {.gcsafe.} =
  if p.item == nil:
    raise newException(AccessViolationDefect, "unique ptr is no longer available")
  fn(p.item[])

proc move*[T](src: var UniquePtr[T]): UniquePtr[T] =
  if src.item == nil:
    return
  result.item = src.item
  result.destroy = src.destroy
  src.item = nil
  src.destroy = nil

proc initSharedPtr*[T](destructor: proc(t: var T)): SharedPtr[T] =
  ## initialize the shared ptr. Upon clean up, the object will be destroyed using the given destructor function.
  result.content = cast[typeof(result.content)](allocShared(sizeof(result.content)))
  result.content[].item = default(T)
  result.content[].count = 1
  result.content[].writerQueue = 0
  result.content[].readers = 0
  result.destroy = destructor
  initLock(result.content[].lock)

proc initSharedPtr*[T](): SharedPtr[T] =
  ## initialize the shared ptr.
  initSharedPtr[T](proc(t: var T) = discard)

proc `=destroy`[T](p: var SharedPtr[T]) =
  if p.content == nil:
    return
  var lastCopy: bool
  withLock p.content[].lock:
    p.content[].count -= 1
    lastCopy = p.content[].count == 0
  if lastCopy:
    p.destroy(p.content[].item)
    deallocShared(p.content)
    p.content = nil
    p.destroy = nil

proc `=copy`[T](dest: var SharedPtr[T], src: SharedPtr[T]) =
  if dest.content == src.content:
    return
  `=destroy`(dest)
  wasMoved(dest)
  if src.content == nil:
    return
  withLock src.content[].lock:
    src.content[].count += 1
    dest.content = src.content

proc write*[T](p: SharedPtr[T], writer: proc(i: var T)) {.gcsafe.} =
  ## get write access to the underlying object
  var done: bool
  var first = true

  while not done:
    withLock p.content[].lock:
      if p.content[].readers == 0:
        writer(p.content[].item)
        if not first:
          p.content[].writerQueue -= 1
        done = true
      else:
        if first:
          p.content[].writerQueue += 1
          first = false
    if not done:
      sleep(250)

proc read*[T](p: SharedPtr[T], reader: proc(i: T)) {.gcsafe.} =
  ## get read access to the underlying object.
  var done: bool
  var canRead: bool
  while not done:
    withLock p.content[].lock:
      if p.content[].writerQueue == 0:
        p.content[].readers += 1
        canRead = true
    if canRead:
      reader(p.content[].item)
      withLock p.content[].lock:
        p.content[].readers -= 1
      done = true
    if not done:
      sleep(250)

proc weak*[T](p: SharedPtr[T]): WeakPtr[T] =
  ## get the weak ptr
  result.content = unsafeAddr p.content
  result.destroy = p.destroy

proc `=destroy`[T](p: var WeakPtr[T]) =
  p.content = nil
  p.destroy = nil

proc promote*[T](p: var WeakPtr[T]): Option[SharedPtr[T]] =
  ## attempt to promote the weak ptr into shared ptr.
  if p.content == nil or p.content == p.content[]:
    return none[SharedPtr[T]]()
  var temp: SharedPtr[T]
  withLock p.content[].lock:
    p.content[].count += 1
    temp.content = p.content[]
    temp.destroy = p.destroy
  return some(temp)

when isMainModule:
  template expectError(body: untyped): untyped =
    var hasError: bool
    try:
      body
    except:
      hasError = true
    doAssert hasError

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

  block uniquePtrAccessViolationTest:
    var pt = initUniquePtr[int]()
    proc work(p: UniquePtr[int]) = discard
    work(move pt)
    expectError:
      pt.read(proc(i: int) = discard)

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

  block sharedPtrTest3:
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

  block weakPtr:
    var p1 = initSharedPtr[int]()
    p1.write(proc(i: var int) = i=8)

    var wp = p1.weak() # obtain WeakPtr
    var promotion = wp.promote() # in order to access the value, promote WeakPtr to SharedPtr
    if promotion.isNone: # check for error
      doAssert(false, "failed to promote")
    promotion.get().read(proc(i: int) = doAssert i == 8)

  block weakPtr2:
    # ensure that weak does not destroy sharedptr.
    var p = initSharedPtr[int]()
    p.write(proc(i: var int) = i=10)
    block:
      discard p.weak()
    p.read(proc(i: int) = doAssert i==10)

  block weakPtr3:
    # ensure promotion fails when sharedptr is destroyed
    var wp: WeakPtr[int]
    block:
      var p = initSharedPtr[int]()
      p.write(proc(i: var int) = i=10)
      wp = p.weak()
    doAssert wp.promote().isNone()

  block destructorTest:
    var isDestructorCalled:bool
    block:
      proc work(p: UniquePtr[int]) = discard
      var p = initUniquePtr[int](proc(i: var int) = isDestructorCalled = true)
      spawn work(move p)
      sync()
    doAssert isDestructorCalled