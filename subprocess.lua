
local subprocess = {}


local mswindows = (package.cpath:lower()):match("%.dll")

local types = require("subprocess.types")
local exceptions = require("subprocess.exceptions")

local plat
if mswindows then 
  plat = require("subprocess.windows")
else 
  plat = require("subprocess.posix")
end

local MAXFD = plat.MAXFD

local PIPE = types.PIPE
local STDOUT = types.PIPE
local DEVNULL = types.PIPE

subprocess.PIPE = types.PIPE
subprocess.STDOUT = types.PIPE
subprocess.DEVNULL = types.PIPE







local active = {}

local function cleanup () 
  local mark = {}
  for i, inst in ipairs(active) do 
    local res = inst:poll(math.maxinteger)
    if res then 
      table.insert(mark,i)
    end
  end
  for i = #(mark), 1 do 
    table.remove(active,mark[i])
  end
end

local Popen_metatable = {__gc = function (self) 

  if not (self.child_created) then 

    return 
  end

  self:poll(math.maxinteger)
  if not (self.returncode) then 

    table.insert(active,self)
  end
end}


local function exit (self) 
  if self.stdin then self.stdin:close()   end
  if self.stdout then self.stdout:close()   end
  if self.stderr then self.stderr:close()   end

  self:wait()
end

communicate = function (self, input, timeout) 
  if self.communication_started and input then 
    error("Cannot send input after starting communication")
  end

  local stdout, stderr





  local nils = (self.stdin and 1 or 0) + (self.stdout and 1 or 0) + (self.stderr and 1 or 0)


  if not (timeout) and not (self.communication_started) and 2 <= nils then 
    stdout = nil
    stderr = nil
    local self_stdin, self_stdout, self_stderr = self.stdin, self.stdout, self.stderr
    if self_stdin then 
      if input then 
        local ok, err = pcall(self_stdin.write,self_stdin,input)
        if not (ok) then return nil, nil, err         end
      end
      self_stdin:close()
    elseif self_stdout then 
      stdout = self_stdout:read("*a")
      self_stdout:close()
    elseif self_stderr then 
      stderr = self_stderr:read("*a")
      self_stderr:close()
    end
    self:wait()
  else 
    local endtime = timeout and plat.time() + timeout or nil
    local ok
    ok, stdout, stderr = pcall(plat.communicate,input,endtime,timeout)
    self.communication_started = true
    self:wait(endtime and self.remaining_time(endtime) or nil,endtime)
  end
  return stdout, stderr
end

local function remaining_time (endtime) 
  return (endtime - plat.time())
end

local function check_timeout (self, endtime, orig_timeout) 
  if not (endtime) then 
    return nil
  end
  if endtime < plat.time() then 
    return nil, exceptions.TimeoutExpired(self.args,orig_timeout)
  end
end

local function open_and_set_buf (fobj, fd, mode, bufsize) 
  local bufmode = "full"
  if not (fd == -(1)) then 
    local err
    fobj, err = plat.open(fd,mode)
    if bufsize then 
      bufmode = 0 < bufsize and "full" or "no"
      fobj:setvbuf(bufmode,bufsize)
    end
  end
  return fobj, bufmode
end

subprocess.Popen = function (args, kwargs, with_fn) 
  if not (kwargs) then kwargs = {}   end
  local pass_fds = kwargs.pass_fds or {}
  local close_fds = plat.check_close_fds(kwargs.close_fds,pass_fds,kwargs.stdin,kwargs.stdout,kwargs.stderr)
  local creationflags = plat.check_creationflags(kwargs.creationflags or 0)
  local shell = (not (kwargs.shell == nil)) or false
  local start_new_session = kwargs.start_new_session and true or false

  local self = {args = args, input = nil, input_offset = 0, communication_started = false, closed_child_pipe_fds = false, child_created = false, fileobj2output = {}, stdin_buf = "full", stdout_buf = "full", stderr_buf = "full", exit = exit, get_devnull = plat.get_devnull, communicate = communicate, poll = plat.poll, remaining_time = remaining_time, check_timeout = check_timeout, wait = plat.wait, kill = plat.kill, terminate = plat.terminate}






















  setmetatable(self,Popen_metatable)

  cleanup()



















  local p2cread, p2cwrite, c2pread, c2pwrite, errread, errwrite = plat.get_handles(self,kwargs.stdin,kwargs.stdout,kwargs.stderr)








  p2cwrite, c2pread, errread = plat.wrap_handles(p2cwrite,c2pread,errread)

  self.stdin, self.stdin_buf = open_and_set_buf(self.stdin,p2cwrite,"wb",kwargs.bufsize)
  self.stdout, self.stdout_buf = open_and_set_buf(self.stdout,c2pread,"rb",kwargs.bufsize)
  self.stderr, self.stderr_buf = open_and_set_buf(self.stderr,errread,"rb",kwargs.bufsize)

  local ok, err, errcode = plat.execute_child(self,args,kwargs.executable,close_fds,pass_fds,kwargs.cwd,kwargs.env,kwargs.startupinfo,creationflags,shell,p2cread,p2cwrite,c2pread,c2pwrite,errread,errwrite,start_new_session)








  if not (ok) then 
    if self.stdin then self.stdin:close()     end
    if self.stdout then self.stdout:close()     end
    if self.stderr then self.stderr:close()     end
    if not (self.closed_child_pipe_fds) then 
      if kwargs.stdin == PIPE then plat.close(p2cread)       end
      if kwargs.stdout == PIPE then plat.close(c2pwrite)       end
      if kwargs.stderr == PIPE then plat.close(errwrite)       end
    end
    return nil, err, errcode
  end
  if with_fn then 
    local ret = table.pack(with_fn(self))
    self:exit()
    return table.unpack(ret,1,ret.n)
  end

  return self
end

subprocess.call = function (args, kwargs) 
  return subprocess.Popen(args,kwargs,function (p) 
    local exit, err = p:wait(kwargs and kwargs.timeout)
    if err then 
      p:kill()
      p:wait()
      return nil, err
    end
    return exit
  end)
end

subprocess.check_call = function (args, kwargs) 
  local exit, err = subprocess.call(args,kwargs)
  if not (exit == 0) then 
    error("Error calling process: " .. tostring(exit) .. " " .. tostring(err))
  end
  return 0
end























































return subprocess


