import ../src/nptr

block sharedPtr1:
  var pt = initSharedPtr[string]()
  pt.write(proc(s: var string) = s = "Hello World")

  var cp = pt # moved
  cp.read(proc(s: string) = doAssert s == "Hello World")

block destructorSharedPtrTest:
  var isCalled: bool
  block:
    discard initSharedPtr[int](proc(s: var int) = isCalled = true)
  doAssert isCalled

block sharedPtrClosure:
  type closure = object
    fn: proc()
  var isCalled: bool
  var pt = initSharedPtr[closure]()
  pt.write(proc(c: var closure) =
    c.fn = proc() = isCalled = true
  )
  pt.read(proc(c: closure) = c.fn())
  doAssert isCalled

block sharedPtrAccess:
  var p = initSharedPtr[string]()
  p.writeLock v:
    v[] = "Hello"
  p.writeLock v:
    v[].add(" World")
  doAssert p.readLock()[] == "Hello World"