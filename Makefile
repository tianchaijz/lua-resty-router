.PHONY: test

test:
	# luarocks-5.1 install moonscript
	# luarocks-5.1 install busted
	util/lua-releng .
	busted spec/router.moon
