
local exceptions = {}

local types = require("subprocess.types")

exceptions.TimeoutExpired = function (cmd, timeout, output) 
  return {type = "TimeoutExpired", timeout = timeout, cmd = cmd, output = output}
end






exceptions.CalledProcessError = function (returncode, cmd, output) 
  return {type = "CalledProcessError", returncode = returncode, cmd = cmd, output = output}
end






return exceptions


