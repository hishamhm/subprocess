
-- POSIX implementation of the subprocess module.
local subprocess_posix = {}

local types = require("subprocess.types")
local exceptions = require("subprocess.exceptions")

local errno = require("posix.errno")
local fcntl = require("posix.fcntl")
local libgen = require("posix.libgen")
local posix_sys_time = require("posix.sys.time")
local posix_time = require("posix.time")
local signal = require("posix.signal")
local stdio = require("posix.stdio")
local unistd = require("posix.unistd")
local wait = require("posix.sys.wait")

local core = require("subprocess.posix.core")

local PIPE_BUF = unistd._PC_PIPE_BUF

local PIPE = types.PIPE
local STDOUT = types.STDOUT
local DEVNULL = types.DEVNULL

subprocess_posix.MAXFD = unistd._SC_OPEN_MAX or 256

function subprocess_posix.time()
   local tv = posix_sys_time.gettimeofday()
   return tv.tv_sec + (tv.tv_usec / 1000000)
end

function subprocess_posix.check_close_fds(close_fds: boolean, pass_fds:{any}?, stdin: integer?, stdout: integer?, stderr: integer?)
   if close_fds == nil then
      return true
   end
   -- TL? does not do inference in `and` expressions
   if pass_fds then
      if #pass_fds > 0 then
         return true
      end
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

function subprocess_posix.get_handles(self: Popen, stdin: file|integer|nil, stdout: file|integer|nil, stderr: file|integer|nil): (integer,integer,integer,integer,integer,integer)
   local p2cread, p2cwrite = -1, -1
   local c2pread, c2pwrite = -1, -1
   local errread, errwrite = -1, -1
   local errno
   
   if stdin == PIPE then
      local r, w, e = unistd.pipe()
      if not r then
         error(w, e)
      end
      p2cread, p2cwrite, errno = r, w, e
   elseif stdin == DEVNULL then
      p2cread = self:get_devnull()
   elseif type(stdin) == "integer" then
      p2cread = stdin
   elseif stdin then
      -- Assuming file-like object
      p2cread = stdio.fileno(stdin)
   end

   if stdout == PIPE then
      local r, w, e = unistd.pipe()
      if not r then
         error(w, e)
      end
      c2pread, c2pwrite, errno = r, w, e
   elseif stdout == DEVNULL then
      c2pwrite = self:get_devnull()
   elseif type(stdout) == "integer" then
      c2pwrite = stdout
   elseif stdout then
      -- Assuming file-like object
      c2pwrite = stdio.fileno(stdout)
   end

   if stderr == PIPE then
      local r, w, e = unistd.pipe()
      if not r then
         error(w, e)
      end
      errread, errwrite, errno = r, w, e
   elseif stderr == STDOUT then
      errwrite = c2pwrite
   elseif stderr == DEVNULL then
      errwrite = self:get_devnull()
   elseif type(stderr) == "integer" then
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

local function make_set(array:{any}): {any:boolean}
   local set: {any:boolean} = {}
   for _, elem in ipairs(array) do
      set[elem] = true
   end
   return set
end

local function sorted(set: {any:boolean})
   local array: {any} = {}
   for k, _ in pairs(set) do
      table.insert(array, k)
   end
   table.sort(array)
   return array
end

--[[
Call functions that have the (nil, err, errno) protocol
for errors, auto-retrying in case of EINTR.
]]
local function eintr_retry_call(fn, ...)
   while true do
      local res, err, errcode = fn(...)
      if res ~= nil or errcode ~= errno.EINTR then
         return res, err, errcode
      end
   end
end

function subprocess_posix.execute_child(
      self:Popen, cmd: string|{string}, executable_p: string?, close_fds: boolean,
      pass_fds: {any}, cwd, env,
      startupinfo, creationflags, shell: boolean,
      p2cread: integer, p2cwrite: integer,
      c2pread: integer, c2pwrite: integer,
      errread: integer, errwrite: integer,
      start_new_session: boolean)

   local args: {string} = {}

   if type(cmd) == "string" then
      args[1] = cmd
   else
      args = cmd
   end
   
   if shell then
      table.insert(args, 1, "/bin/sh")
      table.insert(args, 2, "-c")
      if executable_p then
         args[1] = executable_p
      end
   end
   self.args = args

   local executable: string = executable_p or args[1]
   
   --[[
   For transferring possible exec failure from child to parent.
   Data format: "exception name:hex errno:description"
   ]]
   local errpipe_read, errpipe_write = unistd.pipe()
   if not errpipe_read then
      error("could not open error pipe")
   end
   local low_fds_to_close: {integer} = {}
   while errpipe_write < 3 do
      table.insert(low_fds_to_close, errpipe_write)
      errpipe_write = unistd.dup(errpipe_write)
   end
   for _, low_fd in ipairs(low_fds_to_close) do
      unistd.close(low_fd)
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
         local env_list: {string}?
         if env and #env > 0 then
            env_list = {}
            for k, v in pairs(env) do
               table.insert(env_list, tostring(k).."="..tostring(v))
            end
         end
         
         local executable_list: {string} = {}
         local dname = libgen.dirname(executable)
         if dname == "." and executable:sub(1,2) ~= "./" then
            -- This matches the behavior of execvpe()
            local PATH = os.getenv("PATH") or ""
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
                                   start_new_session)
         self.child_created = true
      end)
      -- be sure the FD is closed no matter what
      unistd.close(errpipe_write)
      
      if p2cread ~= -1 and p2cwrite ~= -1 and p2cread ~= self.devnull then
         unistd.close(p2cread)
      end
      if c2pwrite ~= -1 and c2pread ~= -1 and c2pwrite ~= self.devnull then
         unistd.close(c2pwrite)
      end
      if errwrite ~= -1 and errread ~= -1 and errwrite ~= self.devnull then
         unistd.close(errwrite)
      end
      local dn = self.devnull  -- TL? 
      if dn then
         unistd.close(dn)
         self.devnull = nil
      end
      -- Prevent a double close of these fds on error.
      self.closed_child_pipe_fds = true

      -- Wait for exec to fail or succeed; possibly raising an
      -- exception (limited in size)
      while true do
         local part = eintr_retry_call(unistd.read, errpipe_read, 50000)
         if not part or part == "" then break end
         errpipe_data = errpipe_data .. part
         if #errpipe_data >= 50000 then
            break
         end
      end
   end)
   -- be sure the FD is closed no matter what
   unistd.close(errpipe_read)
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
   return self
end

local function handle_exitstatus(self: Popen, res: string, sts: integer)
   if res == "exited" then
      self.returncode = sts
   else
      self.returncode = -sts
   end
end

--[[
Check if child process has terminated.  Returns returncode
attribute.

This method is called by __gc, so it cannot reference anything
outside of the local scope (nor can any methods it calls).
]]
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
            handle_exitstatus(self, res, sts)
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

local function try_wait(self: Popen, wait_flags: integer?)
   return eintr_retry_call(wait.wait, self.pid, wait_flags)
end

function subprocess_posix.wait(self: Popen, timeout: number?, endtime: number?)
   if self.returncode then
      return self.returncode
   end
   -- endtime is preferred to timeout.  timeout is only used for printing.
   if endtime or timeout then
      if not endtime then
         endtime = subprocess_posix.time() + timeout
      elseif not timeout then
         timeout = self.remaining_time(endtime)
      end
   end
   if endtime then
      -- Enter a busy loop if we have a timeout.  This busy loop was
      -- cribbed from Lib/threading.py in Thread.wait() at r71065.
      local delay = 0.0005 -- 500 us -> initial delay of 1 ms
      while true do
         -- self.waitpid_lock:acquire(false)
         if self.returncode then
            break
         end
         local pid, res, sts = try_wait(self, wait.WNOHANG)
         assert(pid == self.pid or pid == 0)
         if pid == self.pid then
            handle_exitstatus(self, res, sts)
            break
         end
         -- self.waitpid_lock:release(false)
         local remaining = self.remaining_time(endtime)
         if remaining <= 0 then
            return nil, exceptions.TimeoutExpired(self.cmd, timeout)
         end
         delay = math.min(delay * 2, remaining, .05)
         posix_time.nanosleep({tv_sec = math.floor(delay), tv_nsec = (delay - math.floor(delay)) * 1000000000})
      end
   else
      while not self.returncode do
         -- self.waitpid_lock:acquire() do
         local pid, res, sts = try_wait(self, 0)
         -- Check the pid and loop as waitpid has been known to
         -- return 0 even without WNOHANG in odd situations.
         -- http://bugs.python.org/issue14396.
         if pid == self.pid then
            handle_exitstatus(self, res, sts)
         end
         -- end self.waitpid_lock:release()
      end
   end
   return self.returncode
end

--[[
function subprocess_posix.communicate(self: Popen, input:string?, endtime: number?, orig_timeout: number?)
   local stdin = self.stdin
   if stdin then
      if not self.communication_started then
         -- Flush stdio buffer.  This might block, if the user has
         -- been writing to .stdin in an uncontrolled fashion.
         stdin:flush()
         if not input then
            stdin:close()
         end
      end
   end

   --Only create this mapping if we haven't already.   
   if not self.communication_started then
      if self.stdout and not self.fileobj2output[self.stdout] then
         self.fileobj2output[self.stdout] = {}
      end
      if self.stderr and not self.fileobj2output[self.stderr] then
         self.fileobj2output[self.stderr] = {}
      end
   end
   
   local stdout: {string}? = self.stdout and self.fileobj2output[self.stdout]
   local stderr: {string}? = self.stderr and self.fileobj2output[self.stderr]
         
   if stdin and not self.input then
      self.input_offset = 0
      self.input = input
   end
   
   -- TODO port PopenSelector...
end
]]

function subprocess_posix.kill(self: Popen)
   signal.kill(self.pid, signal.SIGKILL)
end

function subprocess_posix.terminate(self: Popen)
   signal.kill(self.pid, signal.SIGTERM)
end

function subprocess_posix.open(fd: integer, mode:string): (file)|(nil,string,integer)
   return stdio.fdopen(fd, mode)
end

function subprocess_posix.close(fd: integer): (integer)|(nil, string, integer)
   return unistd.close(fd)
end

return subprocess_posix

