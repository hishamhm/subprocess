

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

subprocess_posix.time = function () 
  local tv = posix_sys_time.gettimeofday()
  return tv.tv_sec + (tv.tv_usec / 1000000)
end

subprocess_posix.check_close_fds = function (close_fds, pass_fds, stdin, stdout, stderr) 
  if close_fds == nil then 
    return true
  end

  if pass_fds then 
    if 0 < #(pass_fds) then 
      return true
    end
  end
  return close_fds
end

subprocess_posix.check_creationflags = function (creationflags) 
  if not (creationflags == 0) then 
    error("creationflags is only supported on Windows platforms")
  end
  return 0
end

subprocess_posix.wrap_handles = function (p2cwrite, c2pread, errread) 
  return p2cwrite, c2pread, errread
end

local function get_devnull (self) 
  if not (self.devnull) then 
    self.devnull = fcntl.open("/dev/null",fcntl.O_RDWR)
  end
  return self.devnull
end

subprocess_posix.get_handles = function (self, stdin, stdout, stderr) 
  local p2cread, p2cwrite = -(1), -(1)
  local c2pread, c2pwrite = -(1), -(1)
  local errread, errwrite = -(1), -(1)
  local errno

  if stdin == PIPE then 
    local r, w, e = unistd.pipe()
    if not (r) then 
      error(w,e)
    end
    p2cread, p2cwrite, errno = r, w, e
  elseif stdin == DEVNULL then 
    p2cread = self:get_devnull()
  elseif math.type(stdin) == "integer" then 
    p2cread = stdin
  elseif stdin then 

    p2cread = stdio.fileno(stdin)
  end

  if stdout == PIPE then 
    local r, w, e = unistd.pipe()
    if not (r) then 
      error(w,e)
    end
    c2pread, c2pwrite, errno = r, w, e
  elseif stdout == DEVNULL then 
    c2pwrite = self:get_devnull()
  elseif math.type(stdout) == "integer" then 
    c2pwrite = stdout
  elseif stdout then 

    c2pwrite = stdio.fileno(stdout)
  end

  if stderr == PIPE then 
    local r, w, e = unistd.pipe()
    if not (r) then 
      error(w,e)
    end
    errread, errwrite, errno = r, w, e
  elseif stderr == STDOUT then 
    errwrite = c2pwrite
  elseif stderr == DEVNULL then 
    errwrite = self:get_devnull()
  elseif math.type(stderr) == "integer" then 
    errwrite = stderr
  elseif stderr then 

    errwrite = stdio.fileno(stderr)
  end

  return p2cread, p2cwrite, c2pread, c2pwrite, errread, errwrite
end



subprocess_posix.communicate = function (...)  end



local function make_set (array) 
  local set = {}
  for _, elem in ipairs(array) do 
    set[elem] = true
  end
  return set
end

local function sorted (set) 
  local array = {}
  for k, _ in pairs(set) do 
    table.insert(array,k)
  end
  table.sort(array)
  return array
end





local function eintr_retry_call (fn, ...) 
  while true do 
    local res, err, errcode = fn(...)
    if not (res == nil) or not (errcode == errno.EINTR) then 
      return res, err, errcode
    end
  end
end

subprocess_posix.execute_child = function (self, cmd, executable_p, close_fds, pass_fds, cwd, env, startupinfo, creationflags, shell, p2cread, p2cwrite, c2pread, c2pwrite, errread, errwrite, start_new_session) 








  local args = {}

  if type(cmd) == "string" then 
    args[1] = cmd
  else 
    args = cmd
  end

  if shell then 
    table.insert(args,1,"/bin/sh")
    table.insert(args,2,"-c")
    if executable_p then 
      args[1] = executable_p
    end
  end
  self.args = args

  local executable = executable_p or args[1]





  local errpipe_read, errpipe_write = unistd.pipe()
  if not (errpipe_read) then 
    error("could not open error pipe")
  end
  local low_fds_to_close = {}
  while errpipe_write < 3 do 
    table.insert(low_fds_to_close,errpipe_write)
    errpipe_write = unistd.dup(errpipe_write)
  end
  for _, low_fd in ipairs(low_fds_to_close) do 
    unistd.close(low_fd)
  end

  local errpipe_data = ""
  pcall(function () 
    pcall(function () 






      local env_list
      if env and 0 < #(env) then 
        env_list = {}
        for k, v in pairs(env) do 
          table.insert(env_list,tostring(k) .. "=" .. tostring(v))
        end
      end

      local executable_list = {}
      local dname = libgen.dirname(executable)
      if dname == "." and not (executable:sub(1,2) == "./") then 

        local PATH = os.getenv("PATH") or ""
        for dir in PATH:gmatch("([^:]+):?") do 
          table.insert(executable_list,dir .. "/" .. executable)
        end
      else 
        executable_list[1] = executable
      end

      local fds_to_keep = make_set(pass_fds)
      fds_to_keep[errpipe_write] = true

      self.pid = core.fork_exec(args,executable_list,close_fds,sorted(fds_to_keep),cwd,env_list,p2cread,p2cwrite,c2pread,c2pwrite,errread,errwrite,errpipe_read,errpipe_write,start_new_session)






      self.child_created = true
    end)

    unistd.close(errpipe_write)

    if not (p2cread == -(1)) and not (p2cwrite == -(1)) and not (p2cread == self.devnull) then 
      unistd.close(p2cread)
    end
    if not (c2pwrite == -(1)) and not (c2pread == -(1)) and not (c2pwrite == self.devnull) then 
      unistd.close(c2pwrite)
    end
    if not (errwrite == -(1)) and not (errread == -(1)) and not (errwrite == self.devnull) then 
      unistd.close(errwrite)
    end
    local dn = self.devnull
    if dn then 
      unistd.close(dn)
      self.devnull = nil
    end

    self.closed_child_pipe_fds = true



    while true do 
      local part = eintr_retry_call(unistd.read,errpipe_read,50000)
      if not (part) or part == "" then break       end
      errpipe_data = errpipe_data .. part
      if 50000 <= #(errpipe_data) then 
        break
      end
    end
  end)

  unistd.close(errpipe_read)
  if 0 < #(errpipe_data) then 
    local pid, str, errcode = eintr_retry_call(wait.wait,self.pid)
    if not (pid) and not (errcode == errno.ECHILD) then 
      error(str)
    end

    local exception_name, hex_errno, err_msg = errpipe_data:match("([^:]+):([^:]+):([^:]+)")

    if not (exception_name) then 
      hex_errno = "00"
      err_msg = "Bad exception data from child: " .. errpipe_data
    end
    return nil, err_msg, tonumber(hex_errno,16)
  end
  return self
end

local function handle_exitstatus (self, res, sts) 
  if res == "exited" then 
    self.returncode = sts
  else 
    self.returncode = -(sts)
  end
end








local my_wait = wait.wait
local my_WNOHANG = wait.WNOHANG
local my_ECHILD = errno.ECHILD
subprocess_posix.poll = function (self, deadstate) 
  if not (self.returncode) then 


    local pid, res, sts = my_wait(self.pid,my_WNOHANG)
    if pid then 
      if pid == self.pid then 
        handle_exitstatus(self,res,sts)
      end
    else 
      if deadstate then 
        self.returncode = deadstate
      elseif sts == my_ECHILD then 







        self.returncode = 0
      end
    end
  end

  return self.returncode
end

local function try_wait (self, wait_flags) 
  return eintr_retry_call(wait.wait,self.pid,wait_flags)
end

subprocess_posix.wait = function (self, timeout, endtime) 
  if self.returncode then 
    return self.returncode
  end

  if endtime or timeout then 
    if not (endtime) then 
      endtime = subprocess_posix.time() + timeout
    elseif not (timeout) then 
      timeout = self.remaining_time(endtime)
    end
  end
  if endtime then 


    local delay = 0.0005
    while true do 

      if self.returncode then 
        break
      end
      local pid, res, sts = try_wait(self,wait.WNOHANG)
      assert(pid == self.pid or pid == 0)
      if pid == self.pid then 
        handle_exitstatus(self,res,sts)
        break
      end

      local remaining = self.remaining_time(endtime)
      if remaining <= 0 then 
        return nil, exceptions.TimeoutExpired(self.cmd,timeout)
      end
      delay = math.min(delay * 2,remaining,0.05)
      posix_time.nanosleep({tv_sec = math.floor(delay), tv_nsec = (delay - math.floor(delay)) * 1000000000})
    end
  else 
    while not (self.returncode) do 

      local pid, res, sts = try_wait(self,0)



      if pid == self.pid then 
        handle_exitstatus(self,res,sts)
      end
    end
  end

  return self.returncode
end





































subprocess_posix.kill = function (self) 
  signal.kill(self.pid,signal.SIGKILL)
end

subprocess_posix.terminate = function (self) 
  signal.kill(self.pid,signal.SIGTERM)
end

subprocess_posix.open = function (fd, mode) 
  return stdio.fdopen(fd,mode)
end

subprocess_posix.close = function (fd) 
  return unistd.close(fd)
end

return subprocess_posix


