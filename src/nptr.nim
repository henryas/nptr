## Module nptr implements smart pointers. They are safe to use across threads.

import
  locks,
  asyncdispatch,
  options,
  macros

export
  options

type
  UniquePtr*[T] = object
    ## UniquePtr manages the lifetime of an object. It retains a single ownership of the object and cannot be copied. It can be passed across threads.
    item: ptr T
    destroy: proc(t: ptr T)
  SharedPtr*[T] = object
    ## SharedPtr manages the lifetime of an object. It allows multiple ownership of the object. It can be copied and passed across threads. It acts as a read-write mutex to the underlying data and therefore carries a higher cost than UniquePtr.
    item: ptr T
    count: ptr int
    lock: ptr Lock
    readers: ptr int
    writerQueue: ptr int
    destroy: proc(t: ptr T)
  WeakPtr*[T] = object
    ## WeakPtr is a non-owning reference to the object pointed to by SharedPtr. WeakPtr can be passed across threads. It is obtained from SharedPtr, and must be converted back into SharedPtr in order to access the object it points to.
    item: ptr T
    count: ptr int
    lock: ptr Lock
    readers: ptr int
    writerQueue: ptr int
    destroy: proc(t: ptr T)

proc initUniquePtr*[T](destructor: proc(t: ptr T)): UniquePtr[T] =
  ## create a unique ptr with the given destructor.
  result.item = cast[ptr T](alloc(sizeof(T)))
  result.item[] = default(T)
  result.destroy = destructor

proc initUniquePtr*[T](): UniquePtr[T] =
  ## create a unique ptr.
  initUniquePtr(proc(t: ptr T) = discard)

proc `=destroy`[T](p: var UniquePtr[T]) =
  if p.item == nil:
    return
  var old = p.item
  p.destroy(p.item)
  if p.item == nil:
    p.item = old
  dealloc(p.item)
  p.item = nil
  echo "destroyed"
  p.destroy = nil

proc `=copy`[T](dest: var UniquePtr[T], src: UniquePtr[T]) =
  if dest.item == src.item:
    return
  raise newException(ObjectAssignmentDefect, "unique ptr must not be copied")

proc read*[T](p: UniquePtr[T], fn: proc(i: T)) {.gcsafe.} =
  fn(p.item[])

proc write*[T](p: UniquePtr[T], fn: proc(i: var T)) {.gcsafe.} =
  fn(p.item[])

proc move*[T](src: var UniquePtr[T]): UniquePtr[T] =
  result = initUniquePtr[T]()
  result.item = src.item
  result.destroy = src.destroy
  src.item = nil
  src.destroy = nil

proc initSharedPtr*[T](destructor: proc(t: ptr T)): SharedPtr[T] =
  ## initialize the shared ptr. Upon clean up, the object will be destroyed using the given destructor function.
  result.item = cast[ptr T](alloc(sizeof(T)))
  result.count = cast[ptr int](alloc(sizeof(int)))
  result.lock = cast[ptr Lock](alloc(sizeof(Lock)))
  result.readers = cast[ptr int](alloc(sizeof(int)))
  result.writerQueue = cast[ptr int](alloc(sizeof(int)))
  result.item[] = default(T)
  result.count[] = 1
  result.destroy = destructor
  initLock(result.lock[])

proc initSharedPtr*[T](): SharedPtr[T] =
  ## initialize the shared ptr.
  initSharedPtr[T](proc(t: ptr T) = discard)

proc `=destroy`[T](p: var SharedPtr[T]) =
  if p.count == nil:
    return
  var lastCopy: bool
  withLock p.lock[]:
    p.count[] -= 1
    lastCopy = p.count[] == 0
  if lastCopy:
    var old = p.item
    p.destroy(p.item)
    if p.item == nil:
      p.item = old
    dealloc(p.item)
    dealloc(p.count)
    dealloc(p.lock)
    dealloc(p.readers)
    dealloc(p.writerQueue)
    p.item = nil
    p.count = nil
    p.lock = nil
    p.readers = nil
    p.writerQueue = nil
    p.destroy = nil
    echo "destroyed"

proc `=copy`[T](dest: var SharedPtr[T], src: SharedPtr[T]) =
  if dest.count == src.count:
    return
  `=destroy`(dest)
  wasMoved(dest)
  if src.count == nil:
    return
  withLock src.lock[]:
    src.count[] += 1
    dest.item = src.item
    dest.count = src.count
    dest.destroy = src.destroy
    dest.readers = src.readers
    dest.writerQueue = src.writerQueue
  dest.lock = src.lock

proc write*[T](p: SharedPtr[T], writer: proc(i: var T)) {.gcsafe.} =
  ## get write access to the underlying object
  var done: bool
  var first = true
  while not done:
    withLock p.lock[]:
      if p.readers[] == 0:
        writer(p.item[])
        if not first:
          p.writerQueue[] -= 1
        done = true
      else:
        if first:
          p.writerQueue[] += 1
          first = false
    if not done:
      poll()

proc read*[T](p: SharedPtr[T], reader: proc(i: T)) {.gcsafe.} =
  ## get read access to the underlying object.
  var done: bool
  var canRead: bool
  while not done:
    withLock p.lock[]:
      if p.writerQueue[] == 0:
        p.readers[] += 1
        canRead = true
    if canRead:
      reader(p.item[])
      withLock p.lock[]:
        p.readers[] -= 1
      done = true
    if not done:
      poll()

proc weak*[T](p: SharedPtr[T]): WeakPtr[T] =
  ## get the weak ptr
  result.item = p.item
  result.lock = p.lock
  result.count = p.count
  result.readers = p.readers
  result.writerQueue = p.writerQueue
  result.destroy = p.destroy

proc `=destroy`[T](p: var WeakPtr[T]) =
  p.item = nil
  p.lock = nil
  p.count = nil
  p.readers = nil
  p.writerQueue = nil
  p.destroy = nil

proc promote*[T](p: var WeakPtr[T]): Option[SharedPtr[T]] =
  ## attempt to promote the weak ptr into shared ptr.
  if p.lock == nil or p.count[] == 0:
    return none[SharedPtr[T]]()
  var temp: SharedPtr[T]
  withLock p.lock[]:
    p.count[] += 1
    temp.item = p.item
    temp.count = p.count
    temp.readers = p.readers
    temp.writerQueue = p.writerQueue
    temp.destroy = p.destroy
  temp.lock = p.lock
  return some(temp)

