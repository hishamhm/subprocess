
#ifndef SUBPROCESS_INHERITABLE_H
#define SUBPROCESS_INHERITABLE_H

int get_inheritable(int fd);
int set_inheritable(int fd, int inheritable);

#endif

