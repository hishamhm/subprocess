

local subprocess_windows = {}

require("subprocess.types")

subprocess_windows.MAXFD = 256
subprocess_windows.PLATFORM_DEFAULT_CLOSE_FDS = false

local function extend (t1, t2) 
  for _, e in ipairs(t2) do 
    table.insert(t1,e)
  end
end

























local function list2cmdline (seq) 





  local result = {}
  for _, arg in ipairs(seq) do 
    local bs_buf = {}


    if 0 < #(result) then 
      table.insert(result," ")
    end

    local needquote = arg:match(" ") or arg:match("\t") or arg == ""
    if needquote then 
      table.insert(result,"\"")
    end

    for c in arg:gmatch(".") do 
      if c == "\\" then 

        table.insert(bs_buf,c)
      elseif c == "\"" then 

        table.insert(result,("\\"):rep(#(bs_buf) * 2))
        bs_buf = {}
        table.insert(result,"\\\"")
      else 

        if bs_buf then 
          extend(result,bs_buf)
          bs_buf = {}
        end
        table.insert(result,c)
      end
    end



    if 0 < #(bs_buf) then 
      extend(result,bs_buf)
    end

    if needquote then 
      for _, bs in ipairs(bs_buf) do 
        table.insert(result,bs)
      end
      table.insert(result,"\"")
    end
  end
  return table.concat(result)
end

subprocess_windows.check_close_fds = function (close_fds, pass_fds, stdin, stdout, stderr) 
  local any_stdio_set = stdin or stdout or stderr
  if close_fds == nil then 
    return not (any_stdio_set)
  else 
    if close_fds and any_stdio_set then 
      error("close_fds is not supported on Windows platforms if you redirect stdin/stdout/stderr")
    end
  end
  return close_fds
end

subprocess_windows.check_creationflags = function (creationflags) 
  return creationflags
end

subprocess_windows.wrap_handles = function (p2cwrite, c2pread, errread) 
  if not (p2cwrite == -(1)) then 
    p2cwrite = msvcrt.open_osfhandle(p2cwrite.Detach(),0)
  end
  if not (c2pread == -(1)) then 
    c2pread = msvcrt.open_osfhandle(c2pread.Detach(),0)
  end
  if not (errread == -(1)) then 
    errread = msvcrt.open_osfhandle(errread.Detach(),0)
  end
  return p2cwrite, c2pread, errread
end

return subprocess_windows


