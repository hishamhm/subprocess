
-- Windows implementation of the subprocess module.
local subprocess_windows = {}

require("subprocess.types")

subprocess_windows.MAXFD = 256
subprocess_windows.PLATFORM_DEFAULT_CLOSE_FDS = false

local function extend(t1, t2)
   for _, e in ipairs(t2) do
      table.insert(t1, e)
   end
end

--[[
    Translate a sequence of arguments into a command line
    string, using the same rules as the MS C runtime:

    1) Arguments are delimited by white space, which is either a
       space or a tab.

    2) A string surrounded by double quotation marks is
       interpreted as a single argument, regardless of white space
       contained within.  A quoted string can be embedded in an
       argument.

    3) A double quotation mark preceded by a backslash is
       interpreted as a literal double quotation mark.

    4) Backslashes are interpreted literally, unless they
       immediately precede a double quotation mark.

    5) If backslashes immediately precede a double quotation mark,
       every pair of backslashes is interpreted as a literal
       backslash.  If the number of backslashes is odd, the last
       backslash escapes the next double quotation mark as
       described in rule 3.
]]
local function list2cmdline(seq)

   -- See
   -- http://msdn.microsoft.com/en-us/library/17w5ykft.aspx
   -- or search http://msdn.microsoft.com for
   -- "Parsing C++ Command-Line Arguments"
   local result: {string} = {}
   for _, arg in ipairs(seq) do
      local bs_buf: {string} = {}
      
      -- Add a space to separate this argument from the others
      if #result > 0 then
         table.insert(result, " ")
      end
      
      local needquote = arg:match(" ") or arg:match("\t") or arg == ""
      if needquote then
         table.insert(result, '"')
      end
      
      for c in arg:gmatch(".") do
         if c == "\\" then
            -- Don't know if we need to double yet.
            table.insert(bs_buf, c)
         elseif c == '"' then
            -- Double backslashes.
            table.insert(result, ("\\"):rep( #bs_buf * 2) )
            bs_buf = {}
            table.insert(result, '\\"')
         else
            -- Normal char
            if bs_buf then
               extend(result, bs_buf)
               bs_buf = {}
            end
            table.insert(result, c)
         end
      end

      -- Add remaining backslashes, if any.
            
      if #bs_buf > 0 then
         extend(result, bs_buf)
      end
            
      if needquote then
         for _, bs in ipairs(bs_buf) do
            table.insert(result, bs)
         end
         table.insert(result, '"')
      end
   end
   return table.concat(result)
end

function subprocess_windows.check_close_fds(close_fds: boolean, pass_fds:{any}?, stdin: integer?, stdout: integer?, stderr: integer?)
   local any_stdio_set = stdin or stdout or stderr
   if close_fds == nil then
      return not any_stdio_set
   else
      if close_fds and any_stdio_set then
         error("close_fds is not supported on Windows platforms if you redirect stdin/stdout/stderr")
      end
   end
   return close_fds
end

function subprocess_windows.check_creationflags(creationflags: integer)
   return creationflags
end

function subprocess_windows.wrap_handles(p2cwrite, c2pread, errread)
   if p2cwrite ~= -1 then
      p2cwrite = msvcrt.open_osfhandle(p2cwrite.Detach(), 0)
   end
   if c2pread ~= -1 then
      c2pread = msvcrt.open_osfhandle(c2pread.Detach(), 0)
   end
   if errread ~= -1 then
      errread = msvcrt.open_osfhandle(errread.Detach(), 0)
   end
   return p2cwrite, c2pread, errread
end

return subprocess_windows
