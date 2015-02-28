
local subprocess = {}

-- TL? shouldn't need the extra parentheses
local mswindows = (package.cpath:lower()):match("%.dll")

local types = require("subprocess.types")

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

local function CalledProcessError(returncode: integer, cmd: PopenCmd, output: string?): CalledProcessError
   return {
      type = "CalledProcessError",
      returncode = returncode,
      cmd = cmd,
      output = output,
   }
end

local function TimeoutExpired(cmd: PopenCmd, timeout: integer, output: string?): TimeoutExpired
   return {
      type = "TimeoutExpired",
      timeout = timeout,
      cmd = cmd,
      output = output,
   }
end

--[[
This lists holds Popen instances for which the underlying process had not
exited at the time its __gc method got called: those processes are wait()ed
for synchronously from cleanup() when a new Popen object is created, to avoid
zombie processes.
]]
local active: {Popen} = {}

local function cleanup()
   local mark: {integer} = {}
   for i, inst in ipairs(active) do
      local res = inst:poll(math.maxinteger)
      if res then
         table.insert(mark, i)
      end
   end
   for i = #mark, 1 do
      table.remove(active, mark[i])
   end
end

local Popen_metatable = {
   __gc = function(self)
      if not self.child_created then
         -- We didn't get to successfully create a child process.
         return
      end
      -- In case the child hasn't been waited on, check if it's done.
      self:poll(math.maxinteger)
      if not self.returncode then
         -- Child is still running, keep us alive until we can wait on it.
         table.insert(active, self)
      end
   end
}

local function exit(self: Popen)
   if self.stdin then self.stdin:close() end
   if self.stdout then self.stdout:close() end
   if self.stderr then self.stderr:close() end
   -- Wait for the process to terminate, to avoid zombies.
   self:wait()
end

function communicate(self: Popen, input: string?, timeout: number?): (string?, string?)|(nil, nil, string)
   if self.communication_started and input then
      error("Cannot send input after starting communication")
   end
   
   local stdout, stderr
   --[[
   Optimization: If we are not worried about timeouts, we haven't
   started communicating, and we have one or zero pipes, using select()
   or threads is unnecessary.
   ]]
   local nils = (self.stdin and 1 or 0)
              + (self.stdout and 1 or 0)
              + (self.stderr and 1 or 0)
   if not timeout and not self.communication_started and nils >= 2 then
      stdout = nil
      stderr = nil
      if self.stdin then
         if input then
            local ok, err = pcall(self.stdin.write, self.stdin, input)
            if not ok then return nil, nil, err end
         end
         self.stdin:close()
      elseif self.stdout then
         stdout = self.stdout:read("*a")
         self.stdout:close()
      elseif self.stderr then
         stderr = self.stderr:read("*a")
         self.stderr:close()
      end
      self:wait()
   else
      local endtime = timeout and plat.time() + timeout or nil
      local ok
      ok, stdout, stderr = pcall(plat.communicate, input, endtime, timeout)
      self.communication_started = true
      self:wait({ timeout = self.remaining_time(endtime) })
   end
   return stdout, stderr
end

local function remaining_time(endtime: number?)
   return endtime and (endtime - plat.time())
end

local function check_timeout(self: Popen, endtime: number?, orig_timeout: number?)
   if not endtime then
      return nil
   end
   if plat.time() > endtime then
      return TimeoutExpired(self.args, orig_timeout)
   end
end

function Popen(args:PopenArgs, with_fn: nil|(Popen) -> ()): Popen
   local pass_fds = args.pass_fds or {}
   local close_fds = plat.check_close_fds(args.close_fds, pass_fds, args.stdin, args.stdout, args.stderr)
   local creationflags = plat.check_creationflags(args.creationflags or 0)
   local shell = (args.shell ~= nil) or false
   local restore_signals = (restore_signals ~= nil) or true
   local start_new_session = (args.start_new_session ~= nil) or false

   local self: PopenObject = {
      args = args.args,
      -- waitpid_lock = threading.Lock(), -- XXX not yet implemented
      input = nil,
      communication_started = false,
      closed_child_pipe_fds = false,
      child_created = false,
      exit = exit,
      get_devnull = plat.get_devnull,
      communicate = communicate,
      poll = plat.poll,
      remaining_time = remaining_time,
      check_timeout = check_timeout,
   }
   setmetatable(self, Popen_metatable)
   
   cleanup()

   --[[
   Input and output objects. The general principle is like
   this:

   Parent                   Child
   ------                   -----
   p2cwrite   ---stdin--->  p2cread
   c2pread    <--stdout---  c2pwrite
   errread    <--stderr---  errwrite

   On POSIX, the child objects are file descriptors.  On
   Windows, these are Windows file handles.  The parent objects
   are file descriptors on both platforms.  The parent objects
   are -1 when not using PIPEs. The child objects are -1
   when not redirecting.
   ]]
   
   local 
   p2cread, p2cwrite,
   c2pread, c2pwrite,
   errread, errwrite = get_handles(self, args.stdin, args.stdout, args.stderr)

   --[[
   We wrap OS handles *before* launching the child, otherwise a
   quickly terminating child could make our fds unwrappable
   ]]
   
   p2cwrite, c2pread, errread = plat.wrap_handles(p2cwrite, c2pread, errread)
   
   if p2cwrite ~= -1 then
      self.stdin = io.open(p2cwrite, "wb")
      if args.bufsize then self.stdin:setvbuf("full", args.bufsize) end
   end

   if c2pread ~= -1 then
      self.stdout = io.open(c2pread, "rb")
      if args.bufsize then self.stdout:setvbuf("full", args.bufsize) end
   end

   if errread ~= -1 then
      self.stderr = io.open(errread, "rb")
      if args.bufsize then self.stderr:setvbuf("full", args.bufsize) end
   end
   
   local ok, err, errcode = plat.execute_child(
                                args.args, args.executable, close_fds,
                                pass_fds, args.cwd, args.env,
                                args.startupinfo, creationflags, shell,
                                p2cread, p2cwrite,
                                c2pread, c2pwrite,
                                errread, errwrite,
                                restore_signals, start_new_session)

   if not ok then
      if self.stdin then self.stdin:close() end
      if self.stdout then self.stdout:close() end
      if self.stderr then self.stderr:close() end
      if not self.closed_child_pipe_fds then
         if args.stdin == PIPE then p2cread:close() end
         if args.stdout == PIPE then c2pwrite:close() end
         if args.stderr == PIPE then errwrite:close() end
      end
      return nil, err, errcode
   end
   
   if with_fn then
      local ret = { with_fn(self) }
      self:exit()
      return table.unpack(ret)
   end
   
   return self
end

function subprocess.call(args: PopenArgs)
   return Popen(args, function(p)
      local exit, err = p:wait(args.timeout)
      if err then
         p:kill()
         p:wait()
         return nil, err
      end
      return exit
   end)
end

function subprocess.check_call(args: PopenArgs)
   local exit, err = subprocess.call(args)
   if exit ~= 0 then
      error("Error calling process: "..tostring(exit).." "..tostring(err))
   end
   return 0
end

function subprocess.check_output(args: PopenArgs)
   if args.stdout then
      error("stdout argument not allowed, it will be overridden.")
   end
   local inputdata: string? = nil
   if args.input then
      if args.stdin then
         error("stdin and input arguments may not both be used.")
      end
      inputdata = args.input
      args.input = nil
      args.stdin = PIPE
   end
   
   args.stdout = PIPE
   return Popen(args, function(process)
      local output, err = process:communicate(inputdata, args.timeout)
      if err == "TimeoutExpired" then
         process:kill()
         output, err = process:communicate()
         return nil, TimeoutExpired(args.args, timeout, output)
      elseif err then
         process:kill()
         process:wait()
         return nil, err
      end
      local retcode = process:poll()
      if retcode > 0 then
         return nil, CalledProcessError(retcode, process.args, output)
      end
      return output
   end)
end

function subprocess.getstatusoutput(cmd: string)
   local status = 0
   local data, err = subprocess.check_output({args = cmd, shell = true, stderr = STDOUT})
   if err and err.type == "CalledProcessError" then
      data = err.output
      status = err.returncode
   end
   if data:sub(-1) == "\n" then
      data = data:sub(1,-2)
   end
   return status, data
end

function subprocess.getoutput(cmd: string)
   local _, data = subprocess.getstatusoutput(cmd)
   return data
end

return subprocess
