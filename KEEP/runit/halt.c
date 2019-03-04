#include <errno.h>
#include <unistd.h>
#include <err.h>
#include <string.h>
#include <sys/reboot.h>

extern char *__progname;

typedef enum {NOOP, HALT, REBOOT, POWEROFF} action_type;

int main(int argc, char *argv[]) {
  int do_sync = 1;
  int do_force = 0;
  int opt;
  action_type action = NOOP;

  if (strcmp(__progname, "halt") == 0)
    action = HALT;
  else if (strcmp(__progname, "reboot") == 0)
    action = REBOOT;
  else if (strcmp(__progname, "poweroff") == 0)
    action = POWEROFF;
  else
    warnx("no default behavior, needs to be called as halt/reboot/poweroff.");

  while ((opt = getopt(argc, argv, "dfhinw")) != -1)
    switch (opt) {
    case 'n':
      do_sync = 0;
      break;
    case 'w':
      action = NOOP;
      do_sync = 0;
      break;
    case 'd':
    case 'h':
    case 'i':
      /* silently ignored.  */
      break;
    case 'f':
      do_force = 1;
      break;
    default:
      errx(1, "Usage: %s [-n] [-f]", __progname);
    }

  if (do_sync)
    sync();

  switch (action) {
  case HALT:
    if (do_force)
      reboot(RB_HALT_SYSTEM);
    else
      execl("/bin/runit-init", "init", "0", (char*)0);
    err(1, "halt failed");
    break;
  case POWEROFF:
    if (do_force)
      reboot(RB_POWER_OFF);
    else
      execl("/bin/runit-init", "init", "0", (char*)0);
    err(1, "poweroff failed");
    break;
  case REBOOT:
    if (do_force)
      reboot(RB_AUTOBOOT);
    else
      execl("/bin/runit-init", "init", "6", (char*)0);
    err(1, "reboot failed");
    break;
  case NOOP:
    break;
  }

  return 0;
}
