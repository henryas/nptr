# nptr

Module nptr implements smart pointers for the Nim language. The objective is to
allow sharing of mutable variables across threads in a more convenient manner.
They also allow an easy management of an object's lifetime when the object has a
custom destructor.

The smart pointers have the following characteristics:
  * The smart pointers can be safely shared across threads.
  * The smart pointers support optional custom destructor.

There are three types of smart pointers: _UniquePtr_, _SharedPtr_, and
_WeakPtr_. They are unimaginatively named after the C++'s smart pointers:
_unique_ptr_, _shared_ptr_, and _weak_ptr_. Their functions and usage are
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
# pt points to nil now
sync()
```

## SharedPtr
SharedPtr implies multiple ownership of the object. The pointer can be copied
and moved around. When the last pointer goes out of scope, the object is
destroyed. If there is any custom destructor, the destructor will be called.
SharedPtr also acts as a read-write mutex. It allows multiple readers or a
single writer at any given time.

### Example:
```Nim
import threadpool

var pt = initSharedPtr[int]()
proc work(cp: SharedPtr[int]) =
  cp.write(proc(i: var int) =
    i+=1
  )
for _ in 0..4:
  spawn(work(pt))
sync()

pt.read(proc(i: int) = doAssert i==5)
```

## WeakPtr
WeakPtr allows a peek into the object held by SharedPtr. WeakPtr does not claim
ownership of the object and the object may be deleted by SharedPtr at any time
while WeakPtr is still around. In order to access the object, WeakPtr must be
promoted to SharedPtr first. If the object has been deleted, the promotion will
fail.

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
Custom destructor may be specified during the construction of UniquePtr and
SharedPtr.

### Example:
```Nim
var p = initSharedPtr[int](proc(i: ptr int) =
  # custom destructor here
)
```
