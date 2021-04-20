# nptr

Module nptr implements smart pointers for the Nim language. They allow sharing
of mutable variables across threads in a more convenient manner, and an easy
management of an object's lifetime when the object requires a custom destructor
(eg. in a non-GC environment).

The smart pointers have the following characteristics:
  * The smart pointers are safe to share across threads.
  * The smart pointers support optional custom destructor.

There are three types of smart pointers: _UniquePtr_, _SharedPtr_, and
_WeakPtr_. They are unimaginatively named after the C++'s smart pointers:
_unique_ptr_, _shared_ptr_, and _weak_ptr_. Their functions and use are
explained below.

## UniquePtr
UniquePtr implies a sole ownership of the object. The pointer can be moved
around, but not copied. The pointer is the only one that accesses the object at
any given time. When the pointer is no longer used, it calls the custom
destructor (if there is any) and cleans up the object. Any attempt to copy the
pointer will raise ObjectAssignmentDefect exception.

### Example:
```Nim
import threadpool

var pt = initUniquePtr[string]()
pt.write(proc(s: var string) = s="Hello") # assignment

proc work(cp: UniquePtr[string]) =
  cp.write(proc(s: var string) =
    s.add(" World")
    doAssert s == "Hello World"
  )

spawn work(move pt) # explicit move is required when passing across threads
# pt has been moved. any attempt to access pt will raise AccessViolationDefect exception.
sync()
```

## SharedPtr
SharedPtr implies multiple ownership of the object. The pointer can be copied
and moved around. When the last pointer to the object goes out of scope, the
object is destroyed. If there is any custom destructor, the destructor will be
called. In a concurrent environment, SharedPtr also acts as a read-write mutex.
It allows multiple readers or a single writer at any given time.

### Example:
```Nim
import threadpool

var pt = initSharedPtr[int]()

proc increment(cp: SharedPtr[int]) =
  cp.write(proc(i: var int) =
    i+=1
  )

for _ in 0..4:
  spawn increment(pt)
sync()

pt.read(proc(i: int) = doAssert i==5)
```

## WeakPtr
WeakPtr maintains a weak reference to the object held by SharedPtr. WeakPtr does
not claim ownership of the object and the object may be deleted by SharedPtr at
any time. In order to access the object, WeakPtr must be promoted to SharedPtr.
If the object no longer exists, the promotion will fail.

### Example:
```Nim
var p1 = initSharedPtr[int]()
p1.write(proc(i: var int) = i=8)

var wp = p1.weak() # obtain WeakPtr
var promotion = wp.promote() # in order to access the value, promote WeakPtr to SharedPtr
if promotion.isNone: # check for error
  echo "promotion fails"
promotion.get().read(proc(i: int) = doAssert i == 8)
```

## Destructor
Optional custom destructor can be specified during the construction of UniquePtr
and SharedPtr.

### Example:
```Nim
var p = initSharedPtr[int](proc(i: var int) =
  # custom destructor here
)
```

## Closure
When the object contains a closure, explicit memory allocation and deallocation
are required. The module provides _autoAlloc_ and _autoDealloc_ for convenience,
but the user can use any memory allocation and deallocation functions. The
following code will fail to compile:
```Nim
type MyObject = object
  fn: proc()

let pt = initUniquePtr[MyObject]()
pt.write(proc(o: var MyObject) =
  o.fn = proc() = echo "Hello World!" # this assignment will fail
)
```
The proper way to work with closures will be as follows:
```Nim
type MyObject = object
  fn: ptr proc() # fn is now a pointer to a closure

# initialize pt with destructor for clean up
let pt = initUniquePtr[MyObject](
  proc(o: var MyObject) =
    autoDealloc(o.fn) # clean up: deallocate the closure
)
pt.write(proc(o: var MyObject) =
  o.fn = autoAlloc[proc()]() # before the first assignment, allocate memory for the closure
  o.fn[] = proc() = echo "Hey" # closure assignment
)

pt.write(proc(o: var MyObject) =
  o.fn[] = proc[] = echo "Hello World!" # subsequent assignments do not need memory allocation.
)

pt.read(proc(o: MyObject) = o.fn[]()) # output: "Hello World!"
```
