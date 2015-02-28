
-- POSIX implementation of the subprocess module.
local subprocess_posix = {}

local types = require("subprocess.types")

local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")
local stdio = require("posix.stdio")

local PIPE_BUF = unistd._PC_PIPE_BUF

local PIPE = types.PIPE
local STDOUT = types.STDOUT
local DEVNULL = types.DEVNULL

subprocess_posix.MAXFD = unistd._SC_OPEN_MAX or 256

function subprocess_posix.check_preexec_fn(preexec_fn)
   return preexec_fn
end

function subprocess_posix.check_close_fds(close_fds: boolean, pass_fds:{any}?, stdin: integer?, stdout: integer?, stderr: integer?)
   if close_fds == nil then
      return true
   end
   if #pass_fds > 0 then
      return true
   end
   return close_fds
end

function subprocess_posix.check_creationflags(creationflags: integer)
   if creationflags ~= 0 then
      error("creationflags is only supported on Windows platforms")
   end
   return 0
end

function subprocess_posix.wrap_handles(p2cwrite, c2pread, errread)
   return p2cwrite, c2pread, errread
end

local function get_devnull(self: Popen)
   if not self.devnull then
      self.devnull = fcntl.open("/dev/null", fcntl.O_RDWR)
   end
   return self.devnull
end

function subprocess_posix.get_handles(self: Popen, stdin: file|integer|nil, stdout: file|integer|nil, stderr: file|integer|nil): integer,integer,integer,integer,integer,integer
   local p2cread, p2cwrite = -1, -1
   local c2pread, c2pwrite = -1, -1
   local errread, errwrite = -1, -1
   local errno
   
   if stdin == PIPE then
      p2cread, p2cwrite, errno = unistd.pipe()
      if not p2cread then
         error(p2cwrite, errno)
      end
   elseif stdin == DEVNULL then
      p2cread = get_devnull()
   elseif type(stdin) == "number" then
      p2cread = stdin
   elseif stdin then
      -- Assuming file-like object
      p2cread = stdio.fileno(stdin)
   end

   if stdout == PIPE then
      c2pread, c2pwrite, errno = unistd.pipe()
      if not c2pread then
         error(c2pwrite, errno)
      end
   elseif stdout == DEVNULL then
      c2pwrite = get_devnull()
   elseif type(stdout) == "number" then
      c2pwrite = stdout
   elseif stdout then
      -- Assuming file-like object
      c2pwrite = stdio.fileno(stdout)
   end

   if stderr == PIPE then
      errread, errwrite, errno = unistd.pipe()
      if not errread then
         error(errwrite, errno)
      end
   elseif stderr == STDOUT then
      errwrite = c2pwrite
   elseif stderr == DEVNULL then
      errwrite = get_devnull()
   elseif type(stderr) == "number" then
      errwrite = stderr
   elseif stderr then
      -- Assuming file-like object
      errwrite = stdio.fileno(stderr)
   end
   
   return p2cread, p2cwrite,
          c2pread, c2pwrite,
          errread, errwrite
end

function subprocess_posix.communicate(...)
   -- TODO
end

function subprocess_posix.execute_child(args.args, args.executable, preexec_fn, close_fds,
                                        pass_fds, args.cwd, args.env,
                                        args.startupinfo, creationflags, shell,
                                        p2cread, p2cwrite,
                                        c2pread, c2pwrite,
                                        errread, errwrite,
                                        restore_signals, start_new_session)
   -- TODO
end


return subprocess_posix
