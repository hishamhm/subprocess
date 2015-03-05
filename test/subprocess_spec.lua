
local subprocess = require("subprocess")

local executable = "lua"

if not describe then
   function describe(d, f) local ok, err = pcall(f); if not ok then print("Fail: "..err) end end
   function it(d, f) local ok, err = pcall(f); if not ok then print("Fail: "..err) end end
end

describe("subprocess module", function()
   describe("process test case", function()
      it("gives back file descriptors", function ()
         local p = subprocess.Popen({executable, '-e', 'os.exit(0)'}, {stdin = subprocess.PIPE, stdout = subprocess.PIPE, stderr = subprocess.PIPE})
         assert(io.type(p.stdin) == "file")
         assert(io.type(p.stdout) == "file")
         assert(io.type(p.stderr) == "file")
         p.stdin:close()
         p.stdout:close()
         p.stderr:close()
         p:wait()
      end)
      it("works with unbuffered IO", function ()
         local p = subprocess.Popen({executable, '-e', 'os.exit(0)'}, {stdin = subprocess.PIPE, stdout = subprocess.PIPE, stderr = subprocess.PIPE, bufsize=0})
         assert(p.stdin_buf == "no")
         assert(p.stdout_buf == "no")
         assert(p.stderr_buf == "no")
         p.stdin:close()
         p.stdout:close()
         p.stderr:close()
         p:wait()
      end)
      it("calls given an array", function ()
         local rc = subprocess.call({executable, '-e', 'os.exit(42)'})
         assert(rc == 42)
      end)
      it("kills a process with a timeout", function ()
         local rc, err = subprocess.call({executable, '-e', 'while true do end'}, {timeout = 0.1})
         assert((not rc) and err.type == "TimeoutExpired")
      end)
   end)
end)

print("Done!")

