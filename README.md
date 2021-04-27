# nptr

## Installation

Use _nimble_ to install:
```
nimble install nptr
```

## Overview

Module nptr implements smart pointers for the Nim language. They allow a
convenient management of an object's lifetime, particularly when the object
requires a custom destructor (eg. in a non-GC environment, IO resources, etc.),
and the pointers are thread-safe. The default destructor calls the object's
`=destroy` hook.

There are three types of smart pointers: _UniquePtr_, _SharedPtr_, and
_WeakPtr_. They are unimaginatively named after the C++'s smart pointers:
_unique_ptr_, _shared_ptr_, and _weak_ptr_. The `nptr` pointers share
similarities to their C++ counterparts but are not quite the same as explained
below.

## UniquePtr

UniquePtr implies a sole ownership of the object. The pointer can be moved
around, but not copied. The pointer is the only one that accesses the object at
any given time. When the pointer is no longer used, it calls the destructor and
cleans up the object. Any attempt to copy the pointer will raise exception.

### Example:
```Nim
import threadpool

var pt = initUniquePtr[string]()
pt[] = "Hello" # assignment

proc work(cp: UniquePtr[string]) =
  cp[].add(" World")
  doAssert cp[] == "Hello World"

spawn work(move pt) # explicit move may be required when the compiler is unable to determine whether the variable has been moved.
# pt has been moved. any attempt to access pt will raise exception.
sync()
```

### API Overview
```Nim
# initialize the pointer
proc initUniquePtr[T]();

# initialize the pointer with a custom destructor
proc initUniquePtr[T](destructor: proc(var T));

# access the object
proc `[]`[T](pt: UniquePtr[T]): var T;

# object assignment
proc `[]=`[T](pt: UniquePtr[T], item: T);
```

## SharedPtr

SharedPtr implies multiple ownership of the object. The pointer can be copied
and moved around. When the last pointer to the object goes out of scope, the
destructor is called and object is destroyed.

In a concurrent environment, SharedPtr acts as a read-write mutex. It allows
multiple readers or a single writer at any given time. In a single-threaded
environment, SharedPtr is a plain reference counter pointer. The interface for
both concurrent and single-threaded environment remains the same. SharedPtr in a
single-threaded environment still requires obtaining the lock although there is
no locking involved.

To access the object in SharedPtr, obtain either a read lock or a write lock and
it returns _Readable_ or _Writeable_ object pointer respectively. _Readable_
pointer allows a read-only access to the object. _Writeable_ object allows a
write access to the object. The locks are automatically released when the object
pointer (_Readable_ and _Writeable_) goes out of scope. _Readable_ and _Writeable_
can not be copied.

### Example:
```Nim
import threadpool

var pt = initSharedPtr[int]()

proc increment(cp: SharedPtr[int]) =
  cp.writeLock i:
    i[] += 1

for _ in 0..4:
  spawn increment(pt)
sync()

pt.readLock i:
  doAssert i == 5 # note: unlike writeLock, there is no [] required for i.
```

The _readLock_ and the _writeLock_ follow the following syntax pattern:
```
<pt>.[readLock|writeLock] <object pointer name>:
  # do work
```

There is an alternate way of working with the locks as follows:

### Example:
```Nim
import threadpool

var pt = initSharedPtr[int]()

proc increment(cp: SharedPtr[int]) =
  let i = cp.writeLock()
  i[] += 1

for _ in 0..4:
  spawn increment(pt)
sync()

doAssert pt.readLock()[] == 5
```

### API Overview
```Nim
# initialize the pointer
proc initSharedPtr[T]();

# initialize the pointer with a custom destructor
proc initSharedPtr[T](destructor: proc(var T));

# obtain a read lock. The read lock is released when Readable[T] goes out of scope.
proc readLock[T](pt: SharedPtr[T]): Readable[T];

# convenient syntax for readLock.
template readLock(p: typed, v, statements: untyped);

# obtain a write lock. The write lock is released when Writeable[T] goes out of scope.
proc writeLock[T](pt: SharedPtr[T]): Writeable[T];

# convenient syntax for writeLock.
template writeLock(p: typed, v, statements: untyped);

# obtain the weak pointer.
proc weak[T](src: SharedPtr[T]): WeakPtr[T];
```

## WeakPtr

WeakPtr maintains a weak reference to the object held by SharedPtr. WeakPtr does
not claim ownership of the object and the object may be deleted by SharedPtr at
any time. In order to access the object, WeakPtr must be promoted to SharedPtr.
If the object no longer exists, the promotion will fail.

### Example:
```Nim
var p1 = initSharedPtr[int]()
p1.writeLock i:
  i = 8

var wp = p1.weak() # obtain WeakPtr
var promotion = wp.promote() # in order to access the value, promote WeakPtr to SharedPtr
if promotion.isNone: # check for error
  echo "promotion fails"
doAssert promotion.get().readLock()[] == 8
```

### API Overview
```Nim
# obtain a weak ptr from a shared ptr.
proc weak(pt: SharedPtr[T]): WeakPtr[T];

# attempt to promote a weak ptr into a shared ptr.
proc promote[T](pt: WeakPtr[T]): Option[SharedPtr[T]];
```

## Destructor

Custom destructor can be specified during the construction of UniquePtr and
SharedPtr. The default destructor calls the object's `=destroy` hook.

### Example:
```Nim
var unique = initUniquePtr[int](proc(i: var int) =
  # custom destructor here
)
var shared = initSharedPtr[int](proc(i: var int) =
  # custom destructor here
)
```
