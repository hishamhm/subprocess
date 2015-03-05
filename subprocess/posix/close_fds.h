
#ifndef SUBPROCESS_POSIX_CLOSE_FDS_H
#define SUBPROCESS_POSIX_CLOSE_FDS_H

#include "lua.h"

void close_fds_by_brute_force(long start_fd, lua_State* L, int FDS_TO_KEEP);
void close_open_fds(long start_fd, lua_State* L, int FDS_TO_KEEP);

#endif
