#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/utsname.h>

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
#include <utmp.h>

extern char *__progname;

typedef enum {NOOP, HALT, REBOOT, POWEROFF} action_type;

#ifndef OUR_WTMP
#define OUR_WTMP "/var/log/wtmp"
#endif

#ifndef OUR_UTMP
#define OUR_UTMP "/run/utmp"
#endif

void write_wtmp(int boot) {
  int fd;

  if ((fd = open(OUR_WTMP, O_WRONLY|O_APPEND)) < 0)
    return;

  struct utmp utmp = {0};
  struct utsname uname_buf;
  struct timeval tv;

  gettimeofday(&tv, 0);
  utmp.ut_tv.tv_sec = tv.tv_sec;
  utmp.ut_tv.tv_usec = tv.tv_usec;

  utmp.ut_type = boot ? BOOT_TIME : RUN_LVL;

  strncpy(utmp.ut_name, boot ? "reboot" : "shutdown", sizeof utmp.ut_name);
  strncpy(utmp.ut_id , "~~", sizeof utmp.ut_id);
  strncpy(utmp.ut_line, boot ? "~" : "~~", sizeof utmp.ut_line);
  if (uname(&uname_buf) == 0)
    strncpy(utmp.ut_host, uname_buf.release, sizeof utmp.ut_host);

  write(fd, (char *)&utmp, sizeof utmp);
  close(fd);

  if (boot) {
    if ((fd = open(OUR_UTMP, O_WRONLY|O_APPEND)) < 0)
      return;
    write(fd, (char *)&utmp, sizeof utmp);
    close(fd);
  }
}

int main(int argc, char *argv[]) {
      write_wtmp(1);
      return 0;
}
