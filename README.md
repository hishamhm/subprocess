
subprocess
==========

This is a fork of 'subprocess'. 
A port of the Python subprocess module to (Typed) Lua.

Current status 
--------------

Very unfinished.

* POSIX: core `subprocess.Popen()` object creation works, and you can get
  three file descriptors `p.stdin`, `p.stderr`, `p.stdout` from it, 
  as well as `subprocess.call()`. `p:communicate()` (and all other
  methods that depend on it) not implemented yet.
* Windows: not implemented yet, but it's a matter of porting the
  Python version.

