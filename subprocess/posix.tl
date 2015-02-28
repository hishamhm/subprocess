
-- POSIX implementation of the subprocess module.
local subprocess_posix = {}

local types = require("subprocess.types")

local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")
local stdio = require("posix.stdio")
local libgen = require("posix.dirname")
local errno = require("posix.errno")

local PIPE_BUF = unistd._PC_PIPE_BUF

local PIPE = types.PIPE
local STDOUT = types.STDOUT
local DEVNULL = types.DEVNULL

subprocess_posix.MAXFD = unistd._SC_OPEN_MAX or 256

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

local function make_set(array)
   local set = {}
   for _, elem in ipairs(array) do
      set[elem] = true
   end
   return set
end

local function eintr_retry_call(fn, ...)
   while true do
      local res, err, errcode = fn(...)
      if errcode ~= errno.EINTR then
         return res, err, errcode
      end
   end
end

function subprocess_posix.execute_child(
      self:Popen, cmd: PopenCmd, executable: string?, close_fds: boolean,
      pass_fds: {any}, cwd, env,
      startupinfo, creationflags, shell: boolean,
      p2cread, p2cwrite,
      c2pread, c2pwrite,
      errread, errwrite,
      restore_signals, start_new_session)

   local args: {string} = {}
   if type(cmd) == "string" then
      args[1] = cmd
   else
      args = cmd
   end
   
   if shell then
      table.insert(args, 1, "/bin/sh")
      table.insert(args, 2, "-c")
      if executable then
         args[1] = executable
      end
   end
   
   if not executable then
      executable = args[1]
   end
   local orig_executable: string = executable
   
   --[[
   For transferring possible exec failure from child to parent.
   Data format: "exception name:hex errno:description"
   ]]
   local errpipe_read, errpipe_write = unistd.pipe()
   local low_fds_to_close = {}
   while errpipe_write < 3 do
      table.insert(low_fds_to_close, errpipe_write)
      errpipe_write = unistd.dup(errpipe_write)
   end
   for _, low_fd in ipairs(low_fds_to_close) do
      low_fd:close()
   end
   
   local errpipe_data = ""
   pcall(function()
      pcall(function()
         --[[
         We must avoid complex work that could involve
         malloc or free in the child process to avoid
         potential deadlocks, thus we do all this here.
         and pass it to fork_exec()
         ]]
         local env_list = {}
         if env and #env > 0 then
            for k, v in pairs(env) do
               table.insert(envlist, tostring(k).."="..tostring(v))
            end
         end
         
         local executable_list = {}
         local dname = libgen.dirname(executable)
         if dname == "." and executable:sub(1,2) ~= "./" then
            -- This matches the behavior of execvpe()
            local PATH = os.genenv("PATH")
            for dir in PATH:gmatch("([^:]+):?") do
               table.insert(executable_list, dir.."/"..executable)
            end
         else
            executable_list[1] = executable
         end
         
         local fds_to_keep = make_set(pass_fds)
         fds_to_keep[errpipe_write] = true
         
         self.pid = core.fork_exec(args, executable_list,
                                   close_fds, sorted(fds_to_keep),
                                   cwd, env_list,
                                   p2cread, p2cwrite, c2pread, c2pwrite,
                                   errread, errwrite,
                                   errpipe_read, errpipe_write,
                                   restore_signals, start_new_session)
         self.child_created = true
      end)
      -- be sure the FD is closed no matter what
      errpipe_write:close()
      
      if p2cread ~= -1 and p2cwrite ~= -1 and p2cread ~= self.devnull then
         p2cread:close()
      end
      if c2pwrite ~= -1 and c2pread ~= -1 and c2pwrite ~= self.devnull then
         cp2write:close()
      end
      if errwrite ~= -1 and errread ~= -1 and errwrite ~= self.devnull then
         errwrite:close()
      end
      if self.devnull then
         self.devnull:close()
      end
      -- Prevent a double close of these fds on error.
      self.closed_child_pipe_fds = true
      
      -- Wait for exec to fail or succeed; possibly raising an
      -- exception (limited in size)
      while true do
         local part = eintr_retry_call(unistd.read, errpipe_read, 50000)
         if not part then break end
         errpipe_data = errpipe_data .. part
         if #errpipe_data >= 50000 then
            break
         end
      end
   end)
   -- be sure the FD is closed no matter what
   errpipe_read:close()
   
   if #errpipe_data > 0 then
      local pid, str, errcode = eintr_retry_call(wait.wait, self.pid)
      if not pid and errcode ~= errno.ECHILD then
         error(str)
      end
      
      local exception_name, hex_errno, err_msg =
         errpipe_data:match("([^:]+):([^:]+):([^:]+)")
      if not exception_name then
         hex_errno = "00"
         err_msg = "Bad exception data from child: "..errpipe_data
      end
      return nil, err_msg, tonumber(hex_errno, 16)
   end
end

--[[
Check if child process has terminated.  Returns returncode
attribute.

This method is called by __gc, so it cannot reference anything
outside of the local scope (nor can any methods it calls).
]]
do
   local my_wait = wait.wait
   local my_WNOHANG = wait.WNOHANG
   local my_ECHILD = errno.ECHILD
   function subprocess_posix.poll(self: Popen, deadstate: integer?)
      if not self.returncode then
         -- self.waidpid_lock:acquire()
         -- if self.returncode then return self.returncode end
         local pid, res, sts = my_wait(self.pid, my_WNOHANG)
         if pid then
            if pid == self.pid then
               self:handle_exitstatus(sts)
            end
         else
            if deadstate then
               self.returncode = deadstate
            elseif sts == my_ECHILD then
               --[[
               This happens if SIGCLD is set to be ignored or
               waiting for child processes has otherwise been
               disabled for our process.  This child is dead, we
               can't get the status.
               http://bugs.python.org/issue15756
               ]]
               self.returncode = 0
            end
         end
         -- self.waitpid_lock:release()
      end
      return self.returncode
   end
end

return subprocess_posix
