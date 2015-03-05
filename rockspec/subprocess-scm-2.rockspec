package = "subprocess"
version = "scm-2"
source = {
   url = "git://github.com/hishamhm/subprocess",
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
supported_platforms = {
   "unix" -- at this point. "windows" also planned.
}
dependencies = {
   -- "typedlua" -- build time only
   platforms = {
      unix = {
         "luaposix >= 33.3.1"
      }
   }
}
external_dependencies = {
   platforms = {
      unix = {
         SYS_SYSCALL = {
            header = "sys/syscall.h"
         }
      }
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
   },
   platforms = {
      unix = {
         variables = {
            SYSCALL_INCDIR="$(SYS_SYSCALL_INCDIR)",
         }
      }
   }
}
