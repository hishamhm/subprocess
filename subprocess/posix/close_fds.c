
#ifdef HAVE_SYS_SYSCALL_H
#include <sys/syscall.h>
#endif

#if (_BSD_SOURCE || _SVID_SOURCE || (_POSIX_C_SOURCE >= 200809L || _XOPEN_SOURCE >= 700))
#define HAVE_DIRFD
#endif

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

#if defined(__FreeBSD__) || (defined(__APPLE__) && defined(__MACH__))
# define FD_DIR "/dev/fd"
#else
# define FD_DIR "/proc/self/fd"
#endif


/* Get the maximum file descriptor that could be opened by this process.
 * This function is async signal safe for use between fork() and exec().
 */
static long safe_get_max_fd(void) {
   long local_max_fd;
#if defined(__NetBSD__)
   local_max_fd = fcntl(0, F_MAXFD);
   if (local_max_fd >= 0) {
      return local_max_fd;
   }
#endif
#ifdef _SC_OPEN_MAX
   local_max_fd = sysconf(_SC_OPEN_MAX);
   if (local_max_fd != -1) {
      return local_max_fd;
   }
#endif
   return 256;  /* Matches legacy Lib/subprocess.py behavior. */
}


/* Convert ASCII to a positive int, no libc call. no overflow. -1 on error. */
static int pos_int_from_ascii(char *name) {
   int num = 0;
   while (*name >= '0' && *name <= '9') {
      num = num * 10 + (*name - '0');
      ++name;
   }
   if (*name) {
      return -1;  /* Non digit found, not a number. */
   }
   return num;
}


#if defined(__FreeBSD__)
/* When /dev/fd isn't mounted it is often a static directory populated
 * with 0 1 2 or entries for 0 .. 63 on FreeBSD, NetBSD and OpenBSD.
 * NetBSD and OpenBSD have a /proc fs available (though not necessarily
 * mounted) and do not have fdescfs for /dev/fd.  MacOS X has a devfs
 * that properly supports /dev/fd.
 */
static int is_fdescfs_mounted_on_dev_fd(void) {
   struct stat dev_stat;
   struct stat dev_fd_stat;
   if (stat("/dev", &dev_stat) != 0) {
      return 0;
   }
   if (stat(FD_DIR, &dev_fd_stat) != 0) {
      return 0;
   }
   if (dev_stat.st_dev == dev_fd_stat.st_dev) {
      return 0;  /* / == /dev == /dev/fd means it is static. #fail */
   }
   return 1;
}
#endif


/* Is fd found in the sorted Lua array? */
static int is_fd_in_sorted_fd_sequence(int fd, lua_State* L, int FDS_TO_KEEP)
{
    /* Binary search. */
    int search_min = 0;
    int search_max = luaL_len(L, FDS_TO_KEEP) - 1;
    if (search_max < 0)
        return 0;
    do {
        long middle = (search_min + search_max) / 2;
        long middle_fd;
        
        lua_geti(L, FDS_TO_KEEP, middle + 1);
        middle_fd = lua_tointeger(L, -1);
        lua_pop(L, 1);

        if (fd == middle_fd)
            return 1;
        if (fd > middle_fd)
            search_min = middle + 1;
        else
            search_max = middle - 1;
    } while (search_min <= search_max);
    return 0;
}


/******************************************************************************
 * Implementation 0: portable, brute-force (used as a fallback below)
 *****************************************************************************/


/* Close all file descriptors in the range from start_fd and higher
 * except for those in the table at index FDS_TO_KEEP. If the range defined by
 * [start_fd, safe_get_max_fd()) is large this will take a long
 * time as it calls close() on EVERY possible fd.
 *
 * It isn't possible to know for sure what the max fd to go up to
 * is for processes with the capability of raising their maximum.
 */
void close_fds_by_brute_force(long start_fd, lua_State* L, int FDS_TO_KEEP) {
   long end_fd = safe_get_max_fd();
   int num_fds_to_keep = luaL_len(L, FDS_TO_KEEP);
   int keep_seq_idx;
   int fd_num;
   /* As FDS_TO_KEEP is sorted we can loop through the list closing
    * fds inbetween any in the keep list falling within our range. */
   for (keep_seq_idx = 0; keep_seq_idx < num_fds_to_keep; ++keep_seq_idx) {
      lua_Integer keep_fd;
      
      lua_geti(L, FDS_TO_KEEP, keep_seq_idx + 1);
      keep_fd = lua_tointeger(L, -1);
      lua_pop(L, 1);
      
      if (keep_fd < start_fd)
         continue;
      for (fd_num = start_fd; fd_num < keep_fd; ++fd_num) {
         while (close(fd_num) < 0 && errno == EINTR);
      }
      start_fd = keep_fd + 1;
   }
   if (start_fd <= end_fd) {
      for (fd_num = start_fd; fd_num < end_fd; ++fd_num) {
         while (close(fd_num) < 0 && errno == EINTR);
      }
   }
}


#if defined(__linux__) && defined(HAVE_SYS_SYSCALL_H)

/******************************************************************************
 * Implementation 1: Linux, syscall
 *****************************************************************************/


/* It doesn't matter if d_name has room for NAME_MAX chars; we're using this
 * only to read a directory of short file descriptor number names.  The kernel
 * will return an error if we didn't give it enough space.  Highly Unlikely.
 * This structure is very old and stable: It will not change unless the kernel
 * chooses to break compatibility with all existing binaries.  Highly Unlikely.
 */
struct linux_dirent64 {
   unsigned long long d_ino;
   long long d_off;
   unsigned short d_reclen;     /* Length of this linux_dirent */
   unsigned char  d_type;
   char           d_name[256];  /* Filename (null-terminated) */
};


/* Originally called _close_open_fds_safe in Python sources.
 *
 * Original comments:
 * ------------------
 * Close all open file descriptors in the range from start_fd and higher
 * Do not close any in the sorted FDS_TO_KEEP list.
 *
 * This version is async signal safe as it does not make any unsafe C library
 * calls, malloc calls or handle any locks.  It is _unfortunate_ to be forced
 * to resort to making a kernel system call directly but this is the ONLY api
 * available that does no harm.  opendir/readdir/closedir perform memory
 * allocation and locking so while they usually work they are not guaranteed
 * to (especially if you have replaced your malloc implementation).  A version
 * of this function that uses those can be found in the _maybe_unsafe variant.
 *
 * This is Linux specific because that is all I am ready to test it on.  It
 * should be easy to add OS specific dirent or dirent64 structures and modify
 * it with some cpp #define magic to work on other OSes as well if you want.
 */
void close_open_fds(int start_fd, lua_State* L, int FDS_TO_KEEP) {
   int fd_dir_fd;

   fd_dir_fd = open(FD_DIR, O_RDONLY);
   if (fd_dir_fd == -1) {
      /* No way to get a list of open fds. */
      close_fds_by_brute_force(start_fd, L, FDS_TO_KEEP);
      return;
   } else {
      char buffer[sizeof(struct linux_dirent64)];
      int bytes;
      while ((bytes = syscall(SYS_getdents64, fd_dir_fd,
                             (struct linux_dirent64 *)buffer,
                             sizeof(buffer))) > 0) {
         struct linux_dirent64 *entry;
         int offset;
         for (offset = 0; offset < bytes; offset += entry->d_reclen) {
            int fd;
            entry = (struct linux_dirent64 *)(buffer + offset);
            if ((fd = pos_int_from_ascii(entry->d_name)) < 0)
               continue;  /* Not a number. */
            if (fd != fd_dir_fd && fd >= start_fd &&
               !is_fd_in_sorted_fd_sequence(fd, L, FDS_TO_KEEP)) {
               while (close(fd) < 0 && errno == EINTR);
            }
         }
      }
      while (close(fd_dir_fd) < 0 && errno == EINTR);
   }
}


#else  /* NOT (defined(__linux__) && defined(HAVE_SYS_SYSCALL_H)) */

/******************************************************************************
 * Implementation 2: portable fallback
 *****************************************************************************/


/* Originally called _close_open_fds_maybe_unsafe in Python sources.
 *
 * Original comments:
 * ------------------
 * Close all open file descriptors from start_fd and higher.
 * Do not close any in the sorted FDS_TO_KEEP list.
 *
 * This function violates the strict use of async signal safe functions. :(
 * It calls opendir(), readdir() and closedir().  Of these, the one most
 * likely to ever cause a problem is opendir() as it performs an internal
 * malloc().  Practically this should not be a problem.  The Java VM makes the
 * same calls between fork and exec in its own UNIXProcess_md.c implementation.
 *
 * readdir_r() is not used because it provides no benefit.  It is typically
 * implemented as readdir() followed by memcpy().  See also:
 *   http://womble.decadent.org.uk/readdir_r-advisory.html
 */
void close_open_fds(long start_fd, lua_State* L, int FDS_TO_KEEP)
{
    DIR *proc_fd_dir;
#ifndef HAVE_DIRFD
    while (is_fd_in_sorted_fd_sequence(start_fd, L, FDS_TO_KEEP)) {
        ++start_fd;
    }
    /* Close our lowest fd before we call opendir so that it is likely to
     * reuse that fd otherwise we might close opendir's file descriptor in
     * our loop.  This trick assumes that fd's are allocated on a lowest
     * available basis. */
    while (close(start_fd) < 0 && errno == EINTR);
    ++start_fd;
#endif

#if defined(__FreeBSD__)
    if (!is_fdescfs_mounted_on_dev_fd())
        proc_fd_dir = NULL;
    else
#endif
        proc_fd_dir = opendir(FD_DIR);
    if (!proc_fd_dir) {
        /* No way to get a list of open fds. */
        close_fds_by_brute_force(start_fd, L, FDS_TO_KEEP);
    } else {
        struct dirent *dir_entry;
#ifdef HAVE_DIRFD
        int fd_used_by_opendir = dirfd(proc_fd_dir);
#else
        int fd_used_by_opendir = start_fd - 1;
#endif
        errno = 0;
        while ((dir_entry = readdir(proc_fd_dir))) {
            int fd;
            if ((fd = pos_int_from_ascii(dir_entry->d_name)) < 0)
                continue;  /* Not a number. */
            if (fd != fd_used_by_opendir && fd >= start_fd &&
                !is_fd_in_sorted_fd_sequence(fd, L, FDS_TO_KEEP)) {
                while (close(fd) < 0 && errno == EINTR);
            }
            errno = 0;
        }
        if (errno) {
            /* readdir error, revert behavior. Highly Unlikely. */
            close_fds_by_brute_force(start_fd, L, FDS_TO_KEEP);
        }
        closedir(proc_fd_dir);
    }
}


#endif  /* else NOT (defined(__linux__) && defined(HAVE_SYS_SYSCALL_H)) */


