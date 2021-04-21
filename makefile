.PHONY: clean tests

clean:
	rmdir /S /Q nimcache && rmdir /S /Q testresults && del /S /Q *.exe

tests:
	testament cat /