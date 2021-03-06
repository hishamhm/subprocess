package = "subprocess"
version = "0.1-1"
source = {
   url = "git://github.com/hishamhm/subprocess",
   tag = "0.1",
}
description = {
   summary = "A port of the Python subprocess module to Lua",
   detailed = [[
   Provides a high-level Popen object, which contains file objects
   stdin, stderr and stdout for two-way communication with the
   subprocess and also operations such as wait(), kill() and
   timeout.
]],
   homepage = "http://github.com/hishamhm/subprocess",
   license = "MIT/X11 + PSF License Agreement for Python 3.4.3"
}
dependencies = {
   -- "typedlua" -- build time only
}
external_dependencies = {
   SYS_SYSCALL = {
      header = "sys/syscall.h"
   }
}
build = {
   type = "make",
   build_target = "rock",
   variables = {
      CFLAGS="$(CFLAGS)",
      LIBFLAG="$(LIBFLAG)",
      PREFIX="$(PREFIX)",
      LUA_INCDIR="$(LUA_INCDIR)",
      INST_LIBDIR="$(LIBDIR)",
      INST_LUADIR="$(LUADIR)",
      SYSCALL_INCDIR="$(SYS_SYSCALL_INCDIR)",
   }
}
