discard """
  matrix: "--threads:on"
"""

import
  ../src/nptr,
  threadpool

block weakPtr1:
  var sp = initSharedPtr[int]()
  var wp = sp.weak()

  proc increment(wp: WeakPtr[int]) =
    var sp = wp.promote()
    if sp.isNone():
      echo "got none"
      return
    sp.get().write(proc(i: var int) = i+=1)

  for _ in 0..4:
    spawn increment(wp)
  sync()

  sp.read(proc(i: int) = doAssert i == 5)