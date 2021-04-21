import
  nptr

block weakPtr1:
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