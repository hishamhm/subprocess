
local exceptions = {}

local types = require("subprocess.types")

function exceptions.TimeoutExpired(cmd: string|{string}, timeout: number?, output: string?): TimeoutExpired
   return {
      type = "TimeoutExpired",
      timeout = timeout,
      cmd = cmd,
      output = output,
   }
end

function exceptions.CalledProcessError(returncode: integer, cmd: string|{string}, output: string?): CalledProcessError
   return {
      type = "CalledProcessError",
      returncode = returncode,
      cmd = cmd,
      output = output,
   }
end

return exceptions