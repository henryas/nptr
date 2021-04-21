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