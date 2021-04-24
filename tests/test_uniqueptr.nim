import ../src/nptr

template expectError(body: untyped): untyped =
  var hasError: bool
  try:
    body
  except:
    hasError = true
  doAssert hasError

block uniquePtr1:
  var pt = initUniquePtr[string]()
  pt.write(proc(s: var string) = s = "Hello World")

  var cp = pt # moved
  cp.read(proc(s: string) = doAssert s == "Hello World")

block uniquePtrAccessViolationTest:
  var pt = initUniquePtr[int]()
  proc work(p: UniquePtr[int]) = discard
  work(move pt)
  expectError:
    pt.read(proc(i: int) = discard)

block destructorUniquePtrTest:
  var isCalled: bool
  block:
    discard initUniquePtr[int](proc(s: var int) = isCalled = true)
  doAssert isCalled

block uniquePtrClosure:
  type closure = object
    fn: proc()
  var isCalled: bool
  var pt = initUniquePtr[closure]()
  pt.write(proc(c: var closure) = c.fn = proc() = isCalled = true)
  pt.read(proc(c: closure) = c.fn())
  doAssert isCalled

block uniquePtrDestructor:
  var callCount: int
  block:
    var p1 = initUniquePtr[int](proc(i: var int) = callCount += 1)
    p1.write(proc(i:var int) = i=8)
    var p2 = p1
    var p3 = p2
    p3.read(proc(i: int) = doAssert i==8)
  doAssert callCount == 1

block uniquePtrCopy:
  var p1 = initUniquePtr[int]()
  p1.write(proc(i: var int) = i=8)
  var p2 = p1
  var p3 = p2
  p3.read(proc(i: int) = doAssert i==8)
  var p4 = p1
  expectError:
    p4.read(proc(i: int) = doAssert i==0)