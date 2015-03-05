
.PHONY: test all luac clean rock install tlc lua

LUAS= ./subprocess/types.lua  ./subprocess/exceptions.lua  ./subprocess/posix.lua  ./subprocess/windows.lua  ./subprocess.lua
LUACS=./subprocess/types.luac ./subprocess/exceptions.luac ./subprocess/posix.luac ./subprocess/windows.luac ./subprocess.luac

PREFIX=/usr/local
INST_LIBDIR=$(PREFIX)/lib/lua/5.3/
INST_LUADIR=$(PREFIX)/share/lua/5.3/

SYSCALL_INCDIR=/usr/include
LIBFLAG=-shared
LUA_INCDIR=/usr/local/include

EXISTS=test -f
ECHO=echo -n

TLCFLAGS=

POSIX_CORE=subprocess/posix/core.so
POSIX_CORE_SOURCES=subprocess/posix/compat-5.3.c subprocess/posix/close_fds.c subprocess/inheritable.c subprocess/posix/core.c
POSIX_CORE_HEADERS=subprocess/posix/compat-5.3.h subprocess/posix/close_fds.h subprocess/inheritable.h

all: $(POSIX_CORE) $(LUACS) test

lua: $(LUAS)
luac: $(LUACS)

test:
	LUA_PATH="$$PWD/?.luac;$$LUA_PATH" lua test/subprocess_spec.lua

busted: $(LUAS)
	LUA_PATH="$$PWD/?.luac;$$LUA_PATH" busted test

$(POSIX_CORE): $(POSIX_CORE_SOURCES) $(POSIX_CORE_HEADERS) 
	$(CC) $(CFLAGS) $(LIBFLAG) -o $@ -I$(LUA_INCDIR) $(POSIX_CORE_SOURCES) `$(EXISTS) "$(SYSCALL_INCDIR)/sys/syscall.h" && $(ECHO) "-DHAVE_SYS_SYSCALL_H"`

$(LUAS): %.lua: %.tl
	tlc $(TLCFLAGS) -o $@ $^ || true

$(LUACS): %.luac: %.tl
	mkdir -p .out/`dirname $^`
	tlc $(TLCFLAGS) -o .out/$^ $^ && { cd .out && luac -o ../$@ $^ && rm $^ ;} || { cd .out && luac -o ../$@ $^ && rm $^ && cd .. && touch $^ ;}

rock: $(LUAS) $(POSIX_CORE)

install:
	mkdir -p $(INST_LIBDIR)/`dirname $(POSIX_CORE)`
	cp -a $(POSIX_CORE) $(INST_LIBDIR)/$(POSIX_CORE)
	mkdir -p $(INST_LUADIR)/subprocess
	for i in $(LUAS); do cp -a $$i $(INST_LUADIR)/$$i; done

tlc:
	cd /Users/hisham/projects/github/typedlua && luarocks make --local

clean:
	rm -f $(LUAS) $(LUACS) $(POSIX_CORE)
	rm -rf .out

