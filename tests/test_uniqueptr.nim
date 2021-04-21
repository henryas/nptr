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
    fn: ptr proc()
  var isCalled: bool
  var pt = initUniquePtr[closure](proc(c: var closure) =
    autoDealloc(c.fn)
  )
  pt.write(proc(c: var closure) =
    c.fn = autoAlloc[proc()]()
    c.fn[] = proc() = isCalled = false
  )
  pt.write(proc(c: var closure) =
    c.fn[] = proc() = isCalled = true
  )
  pt.read(proc(c: closure) = c.fn[]())
  doAssert isCalled