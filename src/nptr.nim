## Module nptr implements smart pointers. They are safe to use across threads.

import
  options

when compileOption("threads"):
  import locks

export
  options

when compileOption("threads"):
  type
    UniquePtrInternal[T] = tuple [
      item: T,
      id: uint8,
      lock: Lock,
      count: uint8,
    ]
    SharedPtrInternal[T] = tuple [
      item: T,
      count: uint8,
      weakCount: uint8,
      readers: uint8,
      countLock: Lock,
      resourceLock: Lock,
      readersLock: Lock,
      serviceLock: Lock,
    ]
else:
  # lock is not needed in a non-concurrent situation.
  type
    UniquePtrInternal[T] = tuple [
      item: T,
      id: uint8,
      count: uint8,
    ]
    SharedPtrInternal[T] = tuple [
      item: T,
      count: uint8,
      weakCount: uint8,
    ]

type
  UniquePtr*[T] = object
    ## UniquePtr manages the lifetime of an object. It retains a single ownership of the object and cannot be copied. It can be passed across threads.
    id: uint8
    item: ptr UniquePtrInternal[T]
    destroy: proc(t: var T)
  SharedPtr*[T] = object
    ## SharedPtr manages the lifetime of an object. It allows multiple ownership of the object. It can be copied and passed across threads. In a multi-threading environment, it also performs as a read-write mutex to the underlying data where it allows multiple readers and a single writer at any given time.
    content: ptr SharedPtrInternal[T]
    destroy: proc(t: var T)
  WeakPtr*[T] = object
    ## WeakPtr is a non-owning reference to the object pointed to by SharedPtr. WeakPtr can be passed across threads. It is obtained from SharedPtr, and must be converted back into SharedPtr in order to access the object.
    content: ptr SharedPtrInternal[T]
    destroy: proc(t: var T)

proc initUniquePtr*[T](destructor: proc(t: var T)): UniquePtr[T] =
  ## create a unique ptr with the given destructor.
  when compileOption("threads"):
    result.item = cast[ptr UniquePtrInternal[T]](allocShared0(sizeof(UniquePtrInternal[T])))
    result.item[].count = 1
    initLock(result.item[].lock)
  else:
    result.item = cast[ptr UniquePtrInternal[T]](alloc0(sizeof(UniquePtrInternal[T])))
    result.item[].count = 1
  result.destroy = destructor

proc initUniquePtr*[T](): UniquePtr[T] =
  ## create a unique ptr.
  initUniquePtr(proc(t: var T) = discard)

proc `=destroy`[T](p: var UniquePtr[T]) =
  if p.item == nil:
    return

  var canDestroy, canDealloc: bool
  when compileOption("threads"):
    withLock p.item[].lock:
      p.item[].count -= 1
      canDestroy = p.item[].id == p.id
      canDealloc = p.item[].count == 0
  else:
    p.item[].count -= 1
    canDestroy = p.item[].id == p.id
    canDealloc = p.item[].count == 0

  if canDestroy:
    p.destroy(p.item[].item)
  if canDealloc:
    when compileOption("threads"):
      deinitLock(p.item[].lock)
      deallocShared(p.item)
    else:
      dealloc(p.item)

proc `=copy`[T](dest: var UniquePtr[T], src: UniquePtr[T]) =
  if dest.item == src.item:
    return
  `=destroy`(dest)
  wasMoved(dest)
  if src.item == nil:
    return
  when compileOption("threads"):
    withLock src.item[].lock:
      if src.item[].id != src.id:
        return
      src.item[].id += 1
      src.item[].count += 1
  else:
    if src.item[].id != src.id:
      return
    src.item[].id += 1
    src.item[].count += 1
  dest.id = src.item[].id
  dest.item = src.item
  dest.destroy = src.destroy

proc read*[T](p: UniquePtr[T], fn: proc(i: T)) {.gcsafe.} =
  if p.item == nil:
    raise newException(AccessViolationDefect, "unique ptr is no longer available")
  when compileOption("threads"):
    withLock p.item[].lock:
      if p.item[].id != p.id:
        raise newException(AccessViolationDefect, "unique ptr is no longer available")
  else:
    if p.item[].id != p.id:
      raise newException(AccessViolationDefect, "unique ptr is no longer available")
  fn(p.item[].item)

proc write*[T](p: UniquePtr[T], fn: proc(i: var T)) {.gcsafe.} =
  if p.item == nil:
    raise newException(AccessViolationDefect, "unique ptr is no longer available")
  when compileOption("threads"):
    withLock p.item[].lock:
      if p.item[].id != p.id:
        raise newException(AccessViolationDefect, "unique ptr is no longer available")
  else:
    if p.item[].id != p.id:
      raise newException(AccessViolationDefect, "unique ptr is no longer available")
  fn(p.item[].item)

proc initSharedPtr*[T](destructor: proc(t: var T)): SharedPtr[T] =
  ## initialize the shared ptr. Upon clean up, the object will be destroyed using the given destructor.
  when compileOption("threads"):
    result.content = cast[typeof(result.content)](allocShared0(sizeof(SharedPtrInternal[T])))
  else:
    result.content = cast[typeof(result.content)](alloc0(sizeof(SharedPtrInternal[T])))
  result.content[].count = 1
  result.destroy = destructor
  when compileOption("threads"):
    initLock(result.content[].countLock)
    initLock(result.content[].resourceLock)
    initLock(result.content[].readersLock)
    initLock(result.content[].serviceLock)

proc initSharedPtr*[T](): SharedPtr[T] =
  ## initialize the shared ptr.
  initSharedPtr[T](proc(t: var T) = discard)

proc `=destroy`[T](p: var SharedPtr[T]) =
  if p.content == nil:
    return

  var canDestroy, canDealloc: bool
  when compileOption("threads"):
    withLock p.content[].countLock:
      p.content[].count -= 1
      canDestroy = p.content[].count == 0
      canDealloc = p.content[].weakCount == 0 and canDestroy
  else:
    p.content[].count -= 1
    canDestroy = p.content[].count == 0
    canDealloc = p.content[].weakCount == 0 and canDestroy

  if canDestroy:
    p.destroy(p.content[].item)
  if canDealloc:
    when compileOption("threads"):
      deinitLock(p.content[].countLock)
      deinitLock(p.content[].resourceLock)
      deinitLock(p.content[].readersLock)
      deinitLock(p.content[].serviceLock)
      deallocShared(p.content)
    else:
      dealloc(p.content)

proc `=copy`[T](dest: var SharedPtr[T], src: SharedPtr[T]) =
  if dest.content == src.content:
    return
  `=destroy`(dest)
  wasMoved(dest)
  if src.content == nil:
    return
  when compileOption("threads"):
    withLock src.content[].countLock:
      src.content[].count += 1
      dest.content = src.content
      dest.destroy = src.destroy
  else:
    src.content[].count += 1
    dest.content = src.content
    dest.destroy = src.destroy

proc write*[T](p: SharedPtr[T], writer: proc(i: var T)) {.gcsafe.} =
  ## get write access to the underlying object
  when compileOption("threads"):
    withLock p.content[].serviceLock:
      p.content[].resourceLock.acquire()
    try:
      writer(p.content[].item)
    finally:
      p.content[].resourceLock.release()
  else:
    writer(p.content[].item)

proc read*[T](p: SharedPtr[T], reader: proc(i: T)) {.gcsafe.} =
  ## get read access to the underlying object.
  when compileOption("threads"):
    withLock p.content[].serviceLock:
      withLock p.content[].readersLock:
        p.content[].readers += 1
        if p.content[].readers == 1:
          p.content[].resourceLock.acquire()

  reader(p.content[].item)

  when compileOption("threads"):
    withLock p.content[].readersLock:
      p.content[].readers -= 1
      if p.content[].readers == 0:
        p.content[].resourceLock.release()

proc weak*[T](p: SharedPtr[T]): WeakPtr[T] =
  ## get the weak ptr
  when compileOption("threads"):
    withLock p.content[].countLock:
      p.content[].weakCount += 1
  else:
    p.content[].weakCount += 1
  result.content = p.content
  result.destroy = p.destroy

proc `=destroy`[T](p: var WeakPtr[T]) =
  if p.content == nil:
    return
  var canDealloc: bool
  when compileOption("threads"):
    withLock p.content[].countLock:
      p.content[].weakCount -= 1
      canDealloc = p.content[].weakCount == 0 and p.content[].count == 0
  else:
    p.content[].weakCount -= 1
    canDealloc = p.content[].weakCount == 0 and p.content[].count == 0
  if canDealloc:
    when compileOption("threads"):
      deinitLock(p.content[].countLock)
      deinitLock(p.content[].resourceLock)
      deinitLock(p.content[].readersLock)
      deinitLock(p.content[].serviceLock)
      deallocShared(p.content)
    else:
      dealloc(p.content)

proc `=copy`[T](dest: var WeakPtr[T], src: WeakPtr[T]) =
  if dest.content == src.content:
    return
  `=destroy`(dest)
  wasMoved(dest)
  if src.content == nil:
    return
  when compileOption("threads"):
    withLock src.content[].countLock:
      src.content[].weakCount += 1
  else:
    src.content[].weakCount += 1
  dest.content = src.content
  dest.destroy = src.destroy

proc promote*[T](p: WeakPtr[T]): Option[SharedPtr[T]] =
  ## attempt to promote the weak ptr into shared ptr.
  if p.content == nil:
    return none[SharedPtr[T]]()
  var temp: SharedPtr[T]
  when compileOption("threads"):
    withLock p.content[].countLock:
      if p.content[].count == 0:
        return none[SharedPtr[T]]()
      p.content[].count += 1
  else:
    if p.content[].count == 0:
      return none[SharedPtr[T]]()
    p.content[].count += 1
  temp.content = p.content
  temp.destroy = p.destroy
  return some(temp)
