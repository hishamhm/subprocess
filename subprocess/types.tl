
interface CalledProcessError
   type: string
   returncode: integer
   cmd: string|{string}
   output: string?
end

interface TimeoutExpired
   type: string
   timeout: number?
   cmd: string|{string}
   output: string?
end

interface Popen
   args: string|{string}
   stdin: file?
   stdout: file?
   stderr: file?
   stdin_buf: string
   stdout_buf: string
   stderr_buf: string
   input: string?
   input_offset: integer
   communication_started: boolean
   pid: integer?
   returncode: integer?
   closed_child_pipe_fds: boolean
   child_created: boolean
   devnull: integer?
   fileobj2output: {any:{string}}
   
   exit: () => ()
   poll: (integer?) => (integer)
   remaining_time: (number) -> (number)
   check_timeout: (number?, number?) => (nil)|(TimeoutExpired)
   get_devnull: () -> (integer)
   wait: (number?, number?) => (integer)
   kill: () => ()
   terminate: () => ()
end

interface PopenArgs
   args: string|{string}
   bufsize: integer?
   executable: string?
   stdin: file?
   stdout: file?
   stderr: file?
   close_fds: boolean?
   shell: boolean?
   cwd: string?
   env: {string:string}?
   startupinfo: any -- XXX
   creationflags: integer?
   restore_signals: boolean?
   start_new_session: boolean?
   pass_fds: {any}?
   timeout: number?
   -- universal_newlines: boolean XXX not implemented
end

return {
   PIPE = -1,
   STDOUT = -2,
   DEVNULL = -3,
}

