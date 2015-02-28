
typealias PopenCmd = string|{string}

interface CalledProcessError
   type: string
   returncode: integer
   cmd: PopenCmd
   output: string?
end

interface TimeoutExpired
   type: string
   timeout: number
   cmd: PopenCmd
   output: string?
end

interface Popen
   args: PopenCmd
   stdin: file?
   stdout: file?
   stderr: file?
   input: string?
   communication_started: boolean
   pid: ?
   returncode: ?
   closed_child_pipe_fds: boolean
   child_created: boolean
   devnull: file?
   
   exit: () => ()
   communicate(string?, number?) => (string?, string?)|(nil, nil, string)
   poll: () => ({any}?) => any
   remaining_time: (number?) -> (number?)
   check_timeout: (number?, number?) => (nil)|(TimeoutExpired)
end

interface PopenArgs
   args: PopenCmd
   bufsize: integer?
   executable: ?
   stdin: file?
   stdout: file?
   stderr: file?
   preexec_fn: ?
   close_fds: boolean?
   shell: boolean?
   cwd: ?
   env: ?
   startupinfo: ?
   creationflags: integer?
   restore_signals: boolean?
   start_new_session: boolean?
   pass_fds: {any}?
   -- universal_newlines: boolean XXX not implemented
end

return {
   PIPE = -1,
   STDOUT = -2,
   DEVNULL = -3,
}

