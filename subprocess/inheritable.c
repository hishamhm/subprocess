
#ifdef MS_WINDOWS
#else
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#endif

int get_inheritable(int fd) {
#ifdef MS_WINDOWS
   HANDLE handle;
   DWORD flags = 0;

   handle = (HANDLE)_get_osfhandle(fd);
   if (handle == INVALID_HANDLE_VALUE) {
      return -1;
   }

   if (!GetHandleInformation(handle, &flags)) {
      return -1;
   }

   return (flags & HANDLE_FLAG_INHERIT);
#else
   int flags = 0;

   flags = fcntl(fd, F_GETFD, 0);
   if (flags == -1) {
      return -1;
   }
   return !(flags & FD_CLOEXEC);
#endif
}

int set_inheritable(int fd, int inheritable) {
#ifdef MS_WINDOWS
   HANDLE handle;
   DWORD flags;
#else
   int flags;
   int res;
#endif

#ifdef MS_WINDOWS
   handle = (HANDLE)_get_osfhandle(fd);
   if (handle == INVALID_HANDLE_VALUE) {
      return -1;
   }
   if (inheritable)
      flags = HANDLE_FLAG_INHERIT;
   else
      flags = 0;
   if (!SetHandleInformation(handle, HANDLE_FLAG_INHERIT, flags)) {
      return -1;
   }
   return 0;
#else
   flags = fcntl(fd, F_GETFD);
   if (flags < 0) {
      return -1;
   }
   if (inheritable)
      flags &= ~FD_CLOEXEC;
   else
      flags |= FD_CLOEXEC;
   res = fcntl(fd, F_SETFD, flags);
   if (res < 0) {
      return -1;
   }
   return 0;
#endif
}
