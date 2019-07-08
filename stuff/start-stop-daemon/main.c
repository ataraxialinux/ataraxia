/*
 * A rewrite of the original Debian's start-stop-daemon Perl script
 * in C (faster - it is executed many times during system startup).
 *
 * Written by Marek Michalkiewicz <marekm@i17linuxb.ists.pwr.wroc.pl>,
 * public domain.  Based conceptually on start-stop-daemon.pl, by Ian
 * Jackson <ijackson@gnu.ai.mit.edu>.  May be used and distributed
 * freely for any purpose.  Changes by Christian Schwarz
 * <schwarz@monet.m.isar.de>, to make output conform to the Debian
 * Console Message Standard, also placed in public domain.  Minor
 * changes by Klee Dienes <klee@debian.org>, also placed in the Public
 * Domain.
 *
 * Changes by Ben Collins <bcollins@debian.org>, added --chuid, --background
 * and --make-pidfile options, placed in public domain as well.
 *
 * Port to OpenBSD by Sontri Tomo Huynh <huynh.29@osu.edu>
 *                 and Andreas Schuldei <andreas@schuldei.org>
 *
 * Changes by Ian Jackson: added --retry (and associated rearrangements).
 */

#if 0
#include <config.h>
#include <compat.h>

#include <dpkg/macros.h>
#else
# define VERSION 		"228"

# define WANT_SYSTEMD_NOTIFY	0 /* 1=yes */

# define HAVE_SYS_PARAM_H
# define HAVE_SYS_SYSCALL_H
# define HAVE_SYS_SYSCTL_H
# define HAVE_SYS_USER_H
# define HAVE_STDDEF_H
# define HAVE_ERROR_H
# define HAVE_ERR_H

# define HAVE_CLOCK_MONOTONIC
# define HAVE_GETDTABLESIZE
# define HAVE_IOPRIO_SET
# define HAVE_SETSID

# define DPKG_ATTR_NORET	__attribute__((noreturn))
# define DPKG_ATTR_PRINTF(X)
# define DPKG_ATTR_VPRINTF(X)

# define _GNU_SOURCE
# include <unistd.h>
#endif

#if defined(__linux__)
#  define OS_Linux
#elif defined(__GNU__)
#  define OS_Hurd
#elif defined(__FreeBSD__) || defined(__FreeBSD_kernel__)
#  define OS_FreeBSD
#elif defined(__NetBSD__)
#  define OS_NetBSD
#elif defined(__OpenBSD__)
#  define OS_OpenBSD
#elif defined(__DragonFly__)
#  define OS_DragonFlyBSD
#elif defined(__APPLE__) && defined(__MACH__)
#  define OS_Darwin
#elif defined(__sun)
#  define OS_Solaris
#elif defined(_AIX)
#  define OS_AIX
#elif defined(__hpux)
#  define OS_HPUX
#else
#  error Unknown architecture - cannot build start-stop-daemon
#endif

/* NetBSD needs this to expose struct proc. */
#define _KMEMUSER 1

#ifdef HAVE_SYS_PARAM_H
#include <sys/param.h>
#endif
#ifdef HAVE_SYS_SYSCALL_H
#include <sys/syscall.h>
#endif
#ifdef HAVE_SYS_SYSCTL_H
#include <sys/sysctl.h>
#endif
#ifdef HAVE_SYS_PROCFS_H
#include <sys/procfs.h>
#endif
#ifdef HAVE_SYS_PROC_H
#include <sys/proc.h>
#endif
#ifdef HAVE_SYS_USER_H
#include <sys/user.h>
#endif
#ifdef HAVE_SYS_PSTAT_H
#include <sys/pstat.h>
#endif
#include <sys/types.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/select.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/un.h>

#include <errno.h>
#include <limits.h>
#include <time.h>
#include <fcntl.h>
#include <dirent.h>
#include <ctype.h>
#include <string.h>
#include <pwd.h>
#include <grp.h>
#include <signal.h>
#include <termios.h>
#include <unistd.h>
#ifdef HAVE_STDDEF_H
#include <stddef.h>
#endif
#include <stdbool.h>
#include <stdarg.h>
#include <stdlib.h>
#include <stdio.h>
#include <getopt.h>
#ifdef HAVE_ERROR_H
#include <error.h>
#endif
#ifdef HAVE_ERR_H
#include <err.h>
#endif

#if defined(OS_Hurd)
#include <hurd.h>
#include <ps.h>
#endif

#if defined(OS_Darwin)
#include <libproc.h>
#endif

#ifdef HAVE_KVM_H
#include <kvm.h>
#if defined(OS_FreeBSD)
#define KVM_MEMFILE "/dev/null"
#else
#define KVM_MEMFILE NULL
#endif
#endif

#if defined(_POSIX_PRIORITY_SCHEDULING) && _POSIX_PRIORITY_SCHEDULING > 0
#include <sched.h>
#else
#define SCHED_OTHER -1
#define SCHED_FIFO -1
#define SCHED_RR -1
#endif

#if defined(OS_Linux)
/* This comes from TASK_COMM_LEN defined in Linux' include/linux/sched.h. */
#define PROCESS_NAME_SIZE 15
#elif defined(OS_Solaris)
#define PROCESS_NAME_SIZE 15
#elif defined(OS_Darwin)
#define PROCESS_NAME_SIZE 16
#elif defined(OS_AIX)
/* This comes from PRFNSZ defined in AIX's <sys/procfs.h>. */
#define PROCESS_NAME_SIZE 16
#elif defined(OS_NetBSD)
#define PROCESS_NAME_SIZE 16
#elif defined(OS_OpenBSD)
#define PROCESS_NAME_SIZE 16
#elif defined(OS_FreeBSD)
#define PROCESS_NAME_SIZE 19
#elif defined(OS_DragonFlyBSD)
/* On DragonFlyBSD MAXCOMLEN expands to 16. */
#define PROCESS_NAME_SIZE MAXCOMLEN
#endif

#if defined(SYS_ioprio_set) && defined(linux)
#define HAVE_IOPRIO_SET
#endif

#ifndef array_count
# define array_count(x) 	(sizeof(x) / sizeof((x)[0]))
#endif

#define IOPRIO_CLASS_SHIFT 13
#define IOPRIO_PRIO_VALUE(class, prio) (((class) << IOPRIO_CLASS_SHIFT) | (prio))
#define IO_SCHED_PRIO_MIN 0
#define IO_SCHED_PRIO_MAX 7

enum {
	IOPRIO_WHO_PROCESS = 1,
	IOPRIO_WHO_PGRP,
	IOPRIO_WHO_USER,
};

enum {
	IOPRIO_CLASS_NONE,
	IOPRIO_CLASS_RT,
	IOPRIO_CLASS_BE,
	IOPRIO_CLASS_IDLE,
};

enum action_code {
	ACTION_NONE,
	ACTION_START,
	ACTION_STOP,
	ACTION_STATUS,
};

enum match_code {
	MATCH_NONE	= 0,
	MATCH_PID	= 1 << 0,
	MATCH_PPID	= 1 << 1,
	MATCH_PIDFILE	= 1 << 2,
	MATCH_EXEC	= 1 << 3,
	MATCH_NAME	= 1 << 4,
	MATCH_USER	= 1 << 5,
};

/* Time conversion constants. */
enum {
	NANOSEC_IN_SEC      = 1000000000L,
	NANOSEC_IN_MILLISEC = 1000000L,
	NANOSEC_IN_MICROSEC = 1000L,
};

/* The minimum polling interval, 20ms. */
static const long MIN_POLL_INTERVAL = 20L * NANOSEC_IN_MILLISEC;

static enum action_code action;
static enum match_code match_mode;
static bool testmode = false;
static int quietmode = 0;
static int exitnodo = 1;
static bool background = false;
static bool close_io = true;
#if WANT_SYSTEMD_NOTIFY
static bool notify_await = false;
static int notify_timeout = 60;
static char *notify_sockdir;
static char *notify_socket;
#endif
static bool mpidfile = false;
static bool rpidfile = false;
static int signal_nr = SIGTERM;
static int user_id = -1;
static int runas_uid = -1;
static int runas_gid = -1;
static const char *userspec = NULL;
static char *changeuser = NULL;
static const char *changegroup = NULL;
static char *changeroot = NULL;
static const char *changedir = "/";
static const char *cmdname = NULL;
static char *execname = NULL;
static char *startas = NULL;
static pid_t match_pid = -1;
static pid_t match_ppid = -1;
static const char *pidfile = NULL;
static char *what_stop = NULL;
static const char *progname = "";
static int nicelevel = 0;
static int umask_value = -1;

static struct stat exec_stat;
#if defined(OS_Hurd)
static struct proc_stat_list *procset = NULL;
#endif

/* LSB Init Script process status exit codes. */
enum status_code {
	STATUS_OK = 0,
	STATUS_DEAD_PIDFILE = 1,
	STATUS_DEAD_LOCKFILE = 2,
	STATUS_DEAD = 3,
	STATUS_UNKNOWN = 4,
};

struct pid_list {
	struct pid_list *next;
	pid_t pid;
};

static struct pid_list *found = NULL;
static struct pid_list *killed = NULL;

/* Resource scheduling policy. */
struct res_schedule {
	const char *policy_name;
	int policy;
	int priority;
};

struct schedule_item {
	enum {
		sched_timeout,
		sched_signal,
		sched_goto,
		/* Only seen within parse_schedule and callees. */
		sched_forever,
	} type;
	/* Seconds, signal no., or index into array. */
	int value;
};

static struct res_schedule *proc_sched = NULL;
static struct res_schedule *io_sched = NULL;

static int schedule_length;
static struct schedule_item *schedule = NULL;


static void DPKG_ATTR_PRINTF(1)
debug(const char *format, ...)
{
	va_list arglist;

	if (quietmode >= 0)
		return;

	va_start(arglist, format);
	vprintf(format, arglist);
	va_end(arglist);
}

static void DPKG_ATTR_PRINTF(1)
info(const char *format, ...)
{
	va_list arglist;

	if (quietmode > 0)
		return;

	va_start(arglist, format);
	vprintf(format, arglist);
	va_end(arglist);
}

static void DPKG_ATTR_PRINTF(1)
warning(const char *format, ...)
{
	va_list arglist;

	fprintf(stderr, "%s: warning: ", progname);
	va_start(arglist, format);
	vfprintf(stderr, format, arglist);
	va_end(arglist);
}

static void DPKG_ATTR_NORET DPKG_ATTR_VPRINTF(2)
fatalv(int errno_fatal, const char *format, va_list args)
{
	va_list args_copy;

	fprintf(stderr, "%s: ", progname);
	va_copy(args_copy, args);
	vfprintf(stderr, format, args_copy);
	va_end(args_copy);
	if (errno_fatal)
		fprintf(stderr, " (%s)\n", strerror(errno_fatal));
	else
		fprintf(stderr, "\n");

	if (action == ACTION_STATUS)
		exit(STATUS_UNKNOWN);
	else
		exit(2);
}

static void DPKG_ATTR_NORET DPKG_ATTR_PRINTF(1)
fatal(const char *format, ...)
{
	va_list args;

	va_start(args, format);
	fatalv(0, format, args);
}

static void DPKG_ATTR_NORET DPKG_ATTR_PRINTF(1)
fatale(const char *format, ...)
{
	va_list args;

	va_start(args, format);
	fatalv(errno, format, args);
}

#define BUG(...) bug(__FILE__, __LINE__, __func__, __VA_ARGS__)

static void DPKG_ATTR_NORET DPKG_ATTR_PRINTF(4)
bug(const char *file, int line, const char *func, const char *format, ...)
{
	va_list arglist;

	fprintf(stderr, "%s:%s:%d:%s: internal error: ",
	        progname, file, line, func);
	va_start(arglist, format);
	vfprintf(stderr, format, arglist);
	va_end(arglist);

	if (action == ACTION_STATUS)
		exit(STATUS_UNKNOWN);
	else
		exit(3);
}

static void *
xmalloc(int size)
{
	void *ptr;

	ptr = malloc(size);
	if (ptr)
		return ptr;
	fatale("malloc(%d) failed", size);
}

static char *
xstrndup(const char *str, size_t n)
{
	char *new_str;

	new_str = strndup(str, n);
	if (new_str)
		return new_str;
	fatale("strndup(%s, %zu) failed", str, n);
}

static void
timespec_gettime(struct timespec *ts)
{
#ifdef HAVE_CLOCK_MONOTONIC
	if (clock_gettime(CLOCK_MONOTONIC, ts) < 0)
		fatale("clock_gettime failed");
#else
	struct timeval tv;

	if (gettimeofday(&tv, NULL) != 0)
		fatale("gettimeofday failed");

	ts->tv_sec = tv.tv_sec;
	ts->tv_nsec = tv.tv_usec * NANOSEC_IN_MICROSEC;
#endif
}

#define timespec_cmp(a, b, OP) \
	(((a)->tv_sec == (b)->tv_sec) ? \
	 ((a)->tv_nsec OP (b)->tv_nsec) : \
	 ((a)->tv_sec OP (b)->tv_sec))

static void
timespec_sub(struct timespec *a, struct timespec *b, struct timespec *res)
{
	res->tv_sec = a->tv_sec - b->tv_sec;
	res->tv_nsec = a->tv_nsec - b->tv_nsec;
	if (res->tv_nsec < 0) {
		res->tv_sec--;
		res->tv_nsec += NANOSEC_IN_SEC;
	}
}

static void
timespec_mul(struct timespec *a, int b)
{
	long nsec = a->tv_nsec * b;

	a->tv_sec *= b;
	a->tv_sec += nsec / NANOSEC_IN_SEC;
	a->tv_nsec = nsec % NANOSEC_IN_SEC;
}

static char *
newpath(const char *dirname, const char *filename)
{
	char *path;
	size_t path_len;

	path_len = strlen(dirname) + 1 + strlen(filename) + 1;
	path = xmalloc(path_len);
	snprintf(path, path_len, "%s/%s", dirname, filename);

	return path;
}

static int
parse_unsigned(const char *string, int base, int *value_r)
{
	long value;
	char *endptr;

	errno = 0;
	if (!string[0])
		return -1;

	value = strtol(string, &endptr, base);
	if (string == endptr || *endptr != '\0' || errno != 0)
		return -1;
	if (value < 0 || value > INT_MAX)
		return -1;

	*value_r = value;
	return 0;
}

static long
get_open_fd_max(void)
{
#ifdef HAVE_GETDTABLESIZE
	return getdtablesize();
#else
	return sysconf(_SC_OPEN_MAX);
#endif
}

#ifndef HAVE_SETSID
static void
detach_controlling_tty(void)
{
#ifdef HAVE_TIOCNOTTY
	int tty_fd;

	tty_fd = open("/dev/tty", O_RDWR);

	/* The current process does not have a controlling tty. */
	if (tty_fd < 0)
		return;

	if (ioctl(tty_fd, TIOCNOTTY, 0) != 0)
		fatale("unable to detach controlling tty");

	close(tty_fd);
#endif
}

static pid_t
setsid(void)
{
	if (setpgid(0, 0) < 0)
		return -1:

	detach_controlling_tty();

	return 0;
}
#endif

static void
wait_for_child(pid_t pid)
{
	pid_t child;
	int status;

	do {
		child = waitpid(pid, &status, 0);
	} while (child == -1 && errno == EINTR);

	if (child != pid)
		fatal("error waiting for child");

	if (WIFEXITED(status)) {
		int ret = WEXITSTATUS(status);

		if (ret != 0)
			fatal("child returned error exit status %d", ret);
	} else if (WIFSIGNALED(status)) {
		int signo = WTERMSIG(status);

		fatal("child was killed by signal %d", signo);
	} else {
		fatal("unexpected status %d waiting for child", status);
	}
}

#if WANT_SYSTEMD_NOTIFY
static void
cleanup_socket_dir(void)
{
	unlink(notify_socket);
	rmdir(notify_sockdir);
}

static char *
setup_socket_name(const char *suffix)
{
	const char *basedir;

	if (getuid() == 0 && access("/run", F_OK) == 0) {
		basedir = "/run";
	} else {
		basedir = getenv("TMPDIR");
		if (basedir == NULL)
			basedir = P_tmpdir;
	}

	if (asprintf(&notify_sockdir, "%s/%s.XXXXXX", basedir, suffix) < 0)
		fatale("cannot allocate socket directory name");

	if (mkdtemp(notify_sockdir) == NULL)
		fatale("cannot create socket directory %s", notify_sockdir);

	atexit(cleanup_socket_dir);

	if (chown(notify_sockdir, runas_uid, runas_gid))
		fatale("cannot change socket directory ownership");

	if (asprintf(&notify_socket, "%s/notify", notify_sockdir) < 0)
		fatale("cannot allocate socket name");

	setenv("NOTIFY_SOCKET", notify_socket, 1);

	return notify_socket;
}

static void
set_socket_passcred(int fd)
{
#ifdef SO_PASSCRED
	static const int enable = 1;

	setsockopt(fd, SOL_SOCKET, SO_PASSCRED, &enable, sizeof(enable));
#endif
}

static int
create_notify_socket(void)
{
	const char *sockname;
	struct sockaddr_un su;
	int fd, rc, flags;

	/* Create notification socket. */
	fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_NONBLOCK, 0);
	if (fd < 0)
		fatale("cannot create notification socket");

	/* We could set SOCK_CLOEXEC instead, but then we would need to
	 * check whether the socket call failed, try and then do this anyway,
	 * when we have no threading problems to worry about. */
	flags = fcntl(fd, F_GETFD);
	if (flags < 0)
		fatale("cannot read fd flags for notification socket");
	if (fcntl(fd, F_SETFD, flags | FD_CLOEXEC) < 0)
		fatale("cannot set close-on-exec flag for notification socket");

	sockname = setup_socket_name(".s-s-d-notify");

	/* Bind to a socket in a temporary directory, selected based on
	 * the platform. */
	memset(&su, 0, sizeof(su));
	su.sun_family = AF_UNIX;
	strncpy(su.sun_path, sockname, sizeof(su.sun_path) - 1);

	rc = bind(fd, &su, sizeof(su));
	if (rc < 0)
		fatale("cannot bind to notification socket");

	rc = chmod(su.sun_path, 0660);
	if (rc < 0)
		fatale("cannot change notification socket permissions");

	rc = chown(su.sun_path, runas_uid, runas_gid);
	if (rc < 0)
		fatale("cannot change notification socket ownership");

	/* XXX: Verify we are talking to an expected child? Although it is not
	 * clear whether this is feasible given the knowledge we have got. */
	set_socket_passcred(fd);

	return fd;
}

static void
wait_for_notify(int fd)
{
	struct timespec startat, now, elapsed, timeout, timeout_orig;
	fd_set fdrs;
	int rc;

	timeout.tv_sec = notify_timeout;
	timeout.tv_nsec = 0;
	timeout_orig = timeout;

	timespec_gettime(&startat);

	while (timeout.tv_sec >= 0 && timeout.tv_nsec >= 0) {
		FD_ZERO(&fdrs);
		FD_SET(fd, &fdrs);

		/* Wait for input. */
		debug("Waiting for notifications... (timeout %lusec %lunsec)\n",
		      timeout.tv_sec, timeout.tv_nsec);
		rc = pselect(fd + 1, &fdrs, NULL, NULL, &timeout, NULL);

		/* Catch non-restartable errors, that is, not signals nor
		 * kernel out of resources. */
		if (rc < 0 && (errno != EINTR && errno != EAGAIN))
			fatale("cannot monitor notification socket for activity");

		/* Timed-out. */
		if (rc == 0)
			fatal("timed out waiting for a notification");

		/* Update the timeout, as should not rely on pselect() having
		 * done that for us, which is an unportable assumption. */
		timespec_gettime(&now);
		timespec_sub(&now, &startat, &elapsed);
		timespec_sub(&timeout_orig, &elapsed, &timeout);

		/* Restartable error, a signal or kernel out of resources. */
		if (rc < 0)
			continue;

		/* Parse it and check for a supported notification message,
		 * once we get a READY=1, we exit. */
		for (;;) {
			ssize_t nrecv;
			char buf[4096];
			char *line, *line_next;

			nrecv = recv(fd, buf, sizeof(buf), 0);
			if (nrecv < 0 && (errno != EINTR && errno != EAGAIN))
				fatale("cannot receive notification packet");
			if (nrecv < 0)
				break;

			buf[nrecv] = '\0';

			for (line = buf; *line; line = line_next) {
				line_next = strchrnul(line, '\n');
				if (*line_next == '\n')
					*line_next++ = '\0';

				debug("Child sent some notification...\n");
				if (strncmp(line, "EXTEND_TIMEOUT_USEC=", 20) == 0) {
					int extend_usec = 0;

					if (parse_unsigned(line + 20, 10, &extend_usec) != 0)
						fatale("cannot parse extended timeout notification %s", line);

					/* Reset the current timeout. */
					timeout.tv_sec = extend_usec / 1000L;
					timeout.tv_nsec = (extend_usec % 1000L) *
					                  NANOSEC_IN_MILLISEC;
					timeout_orig = timeout;

					timespec_gettime(&startat);
				} else if (strncmp(line, "ERRNO=", 6) == 0) {
					int suberrno = 0;

					if (parse_unsigned(line + 6, 10, &suberrno) != 0)
						fatale("cannot parse errno notification %s", line);
					errno = suberrno;
					fatale("program failed to initialize");
				} else if (strcmp(line, "READY=1") == 0) {
					debug("-> Notification => ready for service.\n");
					return;
				} else {
					debug("-> Notification line '%s' received\n", line);
				}
			}
		}
	}
}
#endif /* WANT_SYSTEMD_NOTIFY */

static void
write_pidfile(const char *filename, pid_t pid)
{
	FILE *fp;
	int fd;

	fd = open(filename, O_CREAT | O_WRONLY | O_TRUNC | O_NOFOLLOW, 0666);
	if (fd < 0)
		fp = NULL;
	else
		fp = fdopen(fd, "w");

	if (fp == NULL)
		fatale("unable to open pidfile '%s' for writing", filename);

	fprintf(fp, "%d\n", pid);

	if (fclose(fp))
		fatale("unable to close pidfile '%s'", filename);
}

static void
remove_pidfile(const char *filename)
{
	if (unlink(filename) < 0 && errno != ENOENT)
		fatale("cannot remove pidfile '%s'", filename);
}

static void
daemonize(void)
{
#if WANT_SYSTEMD_NOTIFY
	int notify_fd = -1;
#endif
	pid_t pid;
	sigset_t mask;
	sigset_t oldmask;

	debug("Detaching to start %s...\n", startas);

	/* Block SIGCHLD to allow waiting for the child process while it is
	 * performing actions, such as creating a pidfile. */
	sigemptyset(&mask);
	sigaddset(&mask, SIGCHLD);
	if (sigprocmask(SIG_BLOCK, &mask, &oldmask) == -1)
		fatale("cannot block SIGCHLD");

#if WANT_SYSTEMD_NOTIFY
	if (notify_await)
		notify_fd = create_notify_socket();
#endif

	pid = fork();
	if (pid < 0)
		fatale("unable to do first fork");
	else if (pid) { /* First Parent. */
		/* Wait for the second parent to exit, so that if we need to
		 * perform any actions there, like creating a pidfile, we do
		 * not suffer from race conditions on return. */
		wait_for_child(pid);

#if WANT_SYSTEMD_NOTIFY
		if (notify_await) {
			/* Wait for a readiness notification from the second
			 * child, so that we can safely exit when the service
			 * is up. */
			wait_for_notify(notify_fd);
			close(notify_fd);
			cleanup_socket_dir();
		}
#endif

		_exit(0);
	}

	/* Create a new session. */
	if (setsid() < 0)
		fatale("cannot set session ID");

	pid = fork();
	if (pid < 0)
		fatale("unable to do second fork");
	else if (pid) { /* Second parent. */
		/* Set a default umask for dumb programs, which might get
		 * overridden by the --umask option later on, so that we get
		 * a defined umask when creating the pidfile. */
		umask(022);

		if (mpidfile && pidfile != NULL)
			/* User wants _us_ to make the pidfile. */
			write_pidfile(pidfile, pid);

		_exit(0);
	}

	if (sigprocmask(SIG_SETMASK, &oldmask, NULL) == -1)
		fatale("cannot restore signal mask");

	debug("Detaching complete...\n");
}

static void
pid_list_push(struct pid_list **list, pid_t pid)
{
	struct pid_list *p;

	p = xmalloc(sizeof(*p));
	p->next = *list;
	p->pid = pid;
	*list = p;
}

static void
pid_list_free(struct pid_list **list)
{
	struct pid_list *here, *next;

	for (here = *list; here != NULL; here = next) {
		next = here->next;
		free(here);
	}

	*list = NULL;
}

static void
usage(void)
{
	printf(
"Usage: start-stop-daemon [<option>...] <command>\n"
"\n");

	printf(
"Commands:\n"
"  -S, --start -- <argument>...  start a program and pass <arguments> to it\n"
"  -K, --stop                    stop a program\n"
"  -T, --status                  get the program status\n"
"  -H, --help                    print help information\n"
"  -V, --version                 print version\n"
"\n");

	printf(
"Matching options (at least one is required):\n"
"      --pid <pid>               pid to check\n"
"      --ppid <ppid>             parent pid to check\n"
"  -p, --pidfile <pid-file>      pid file to check\n"
"  -x, --exec <executable>       program to start/check if it is running\n"
"  -n, --name <process-name>     process name to check\n"
"  -u, --user <username|uid>     process owner to check\n"
"\n");

	printf(
"Options:\n"
"  -g, --group <group|gid>       run process as this group\n"
"  -c, --chuid <name|uid[:group|gid]>\n"
"                                change to this user/group before starting\n"
"                                  process\n"
"  -s, --signal <signal>         signal to send (default TERM)\n"
"  -a, --startas <pathname>      program to start (default is <executable>)\n"
"  -r, --chroot <directory>      chroot to <directory> before starting\n"
"  -d, --chdir <directory>       change to <directory> (default is /)\n"
"  -N, --nicelevel <incr>        add incr to the process' nice level\n"
"  -P, --procsched <policy[:prio]>\n"
"                                use <policy> with <prio> for the kernel\n"
"                                  process scheduler (default prio is 0)\n"
"  -I, --iosched <class[:prio]>  use <class> with <prio> to set the IO\n"
"                                  scheduler (default prio is 4)\n"
"  -k, --umask <mask>            change the umask to <mask> before starting\n"
"  -b, --background              force the process to detach\n"
#if WANT_SYSTEMD_NOTIFY
"      --notify-await            wait for a readiness notification\n"
"      --notify-timeout <int>    timeout after <int> seconds of notify wait\n"
#endif
"  -C, --no-close                do not close any file descriptor\n"
"  -m, --make-pidfile            create the pidfile before starting\n"
"      --remove-pidfile          delete the pidfile after stopping\n"
"  -R, --retry <schedule>        check whether processes die, and retry\n"
"  -t, --test                    test mode, don't do anything\n"
"  -o, --oknodo                  exit status 0 (not 1) if nothing done\n"
"  -q, --quiet                   be more quiet\n"
"  -v, --verbose                 be more verbose\n"
"\n");

	printf(
"Retry <schedule> is <item>|/<item>/... where <item> is one of\n"
" -<signal-num>|[-]<signal-name>  send that signal\n"
" <timeout>                       wait that many seconds\n"
" forever                         repeat remainder forever\n"
"or <schedule> may be just <timeout>, meaning <signal>/<timeout>/KILL/<timeout>\n"
"\n");

	printf(
"The process scheduler <policy> can be one of:\n"
"  other, fifo or rr\n"
"\n");

	printf(
"The IO scheduler <class> can be one of:\n"
"  real-time, best-effort or idle\n"
"\n");

	printf(
"Exit status:\n"
"  0 = done\n"
"  1 = nothing done (=> 0 if --oknodo)\n"
"  2 = with --retry, processes would not die\n"
"  3 = trouble\n"
"Exit status with --status:\n"
"  0 = program is running\n"
"  1 = program is not running and the pid file exists\n"
"  3 = program is not running\n"
"  4 = unable to determine status\n");
}

static void
do_version(void)
{
	printf("start-stop-daemon " VERSION " for " Ataraxia Linux.\n");
}

static void DPKG_ATTR_NORET
badusage(const char *msg)
{
	if (msg)
		fprintf(stderr, "%s: %s\n", progname, msg);
	fprintf(stderr, "Try '%s --help' for more information.\n", progname);

	if (action == ACTION_STATUS)
		exit(STATUS_UNKNOWN);
	else
		exit(3);
}

struct sigpair {
	const char *name;
	int signal;
};

static const struct sigpair siglist[] = {
	{ "ABRT",	SIGABRT	},
	{ "ALRM",	SIGALRM	},
	{ "FPE",	SIGFPE	},
	{ "HUP",	SIGHUP	},
	{ "ILL",	SIGILL	},
	{ "INT",	SIGINT	},
	{ "KILL",	SIGKILL	},
	{ "PIPE",	SIGPIPE	},
	{ "QUIT",	SIGQUIT	},
	{ "SEGV",	SIGSEGV	},
	{ "TERM",	SIGTERM	},
	{ "USR1",	SIGUSR1	},
	{ "USR2",	SIGUSR2	},
	{ "CHLD",	SIGCHLD	},
	{ "CONT",	SIGCONT	},
	{ "STOP",	SIGSTOP	},
	{ "TSTP",	SIGTSTP	},
	{ "TTIN",	SIGTTIN	},
	{ "TTOU",	SIGTTOU	}
};

static int
parse_pid(const char *pid_str, int *pid_num)
{
	if (parse_unsigned(pid_str, 10, pid_num) != 0)
		return -1;
	if (*pid_num == 0)
		return -1;

	return 0;
}

static int
parse_signal(const char *sig_str, int *sig_num)
{
	unsigned int i;

	if (parse_unsigned(sig_str, 10, sig_num) == 0)
		return 0;

	for (i = 0; i < array_count(siglist); i++) {
		if (strcmp(sig_str, siglist[i].name) == 0) {
			*sig_num = siglist[i].signal;
			return 0;
		}
	}
	return -1;
}

static int
parse_umask(const char *string, int *value_r)
{
	return parse_unsigned(string, 0, value_r);
}

static void
validate_proc_schedule(void)
{
#if defined(_POSIX_PRIORITY_SCHEDULING) && _POSIX_PRIORITY_SCHEDULING > 0
	int prio_min, prio_max;

	prio_min = sched_get_priority_min(proc_sched->policy);
	prio_max = sched_get_priority_max(proc_sched->policy);

	if (proc_sched->priority < prio_min)
		badusage("process scheduler priority less than min");
	if (proc_sched->priority > prio_max)
		badusage("process scheduler priority greater than max");
#endif
}

static void
parse_proc_schedule(const char *string)
{
	char *policy_str;
	size_t policy_len;
	int prio = 0;

	policy_len = strcspn(string, ":");
	policy_str = xstrndup(string, policy_len);

	if (string[policy_len] == ':' &&
	    parse_unsigned(string + policy_len + 1, 10, &prio) != 0)
		fatale("invalid process scheduler priority");

	proc_sched = xmalloc(sizeof(*proc_sched));
	proc_sched->policy_name = policy_str;

	if (strcmp(policy_str, "other") == 0) {
		proc_sched->policy = SCHED_OTHER;
		proc_sched->priority = 0;
	} else if (strcmp(policy_str, "fifo") == 0) {
		proc_sched->policy = SCHED_FIFO;
		proc_sched->priority = prio;
	} else if (strcmp(policy_str, "rr") == 0) {
		proc_sched->policy = SCHED_RR;
		proc_sched->priority = prio;
	} else
		badusage("invalid process scheduler policy");

	validate_proc_schedule();
}

static void
parse_io_schedule(const char *string)
{
	char *class_str;
	size_t class_len;
	int prio = 4;

	class_len = strcspn(string, ":");
	class_str = xstrndup(string, class_len);

	if (string[class_len] == ':' &&
	    parse_unsigned(string + class_len + 1, 10, &prio) != 0)
		fatale("invalid IO scheduler priority");

	io_sched = xmalloc(sizeof(*io_sched));
	io_sched->policy_name = class_str;

	if (strcmp(class_str, "real-time") == 0) {
		io_sched->policy = IOPRIO_CLASS_RT;
		io_sched->priority = prio;
	} else if (strcmp(class_str, "best-effort") == 0) {
		io_sched->policy = IOPRIO_CLASS_BE;
		io_sched->priority = prio;
	} else if (strcmp(class_str, "idle") == 0) {
		io_sched->policy = IOPRIO_CLASS_IDLE;
		io_sched->priority = 7;
	} else
		badusage("invalid IO scheduler policy");

	if (io_sched->priority < IO_SCHED_PRIO_MIN)
		badusage("IO scheduler priority less than min");
	if (io_sched->priority > IO_SCHED_PRIO_MAX)
		badusage("IO scheduler priority greater than max");
}

static void
set_proc_schedule(struct res_schedule *sched)
{
#if defined(_POSIX_PRIORITY_SCHEDULING) && _POSIX_PRIORITY_SCHEDULING > 0
	struct sched_param param;

	param.sched_priority = sched->priority;

	if (sched_setscheduler(getpid(), sched->policy, &param) == -1)
		fatale("unable to set process scheduler");
#endif
}

#ifdef HAVE_IOPRIO_SET
static inline int
ioprio_set(int which, int who, int ioprio)
{
	return syscall(SYS_ioprio_set, which, who, ioprio);
}
#endif

static void
set_io_schedule(struct res_schedule *sched)
{
#ifdef HAVE_IOPRIO_SET
	int io_sched_mask;

	io_sched_mask = IOPRIO_PRIO_VALUE(sched->policy, sched->priority);
	if (ioprio_set(IOPRIO_WHO_PROCESS, getpid(), io_sched_mask) == -1)
		warning("unable to alter IO priority to mask %i (%s)\n",
		        io_sched_mask, strerror(errno));
#endif
}

static void
parse_schedule_item(const char *string, struct schedule_item *item)
{
	const char *after_hyph;

	if (strcmp(string, "forever") == 0) {
		item->type = sched_forever;
	} else if (isdigit(string[0])) {
		item->type = sched_timeout;
		if (parse_unsigned(string, 10, &item->value) != 0)
			badusage("invalid timeout value in schedule");
	} else if ((after_hyph = string + (string[0] == '-')) &&
	           parse_signal(after_hyph, &item->value) == 0) {
		item->type = sched_signal;
	} else {
		badusage("invalid schedule item (must be [-]<signal-name>, "
		         "-<signal-number>, <timeout> or 'forever'");
	}
}

static void
parse_schedule(const char *schedule_str)
{
	char item_buf[20];
	const char *slash;
	int count, repeatat;
	size_t str_len;

	count = 0;
	for (slash = schedule_str; *slash; slash++)
		if (*slash == '/')
			count++;

	schedule_length = (count == 0) ? 4 : count + 1;
	schedule = xmalloc(sizeof(*schedule) * schedule_length);

	if (count == 0) {
		schedule[0].type = sched_signal;
		schedule[0].value = signal_nr;
		parse_schedule_item(schedule_str, &schedule[1]);
		if (schedule[1].type != sched_timeout) {
			badusage("--retry takes timeout, or schedule list"
			         " of at least two items");
		}
		schedule[2].type = sched_signal;
		schedule[2].value = SIGKILL;
		schedule[3] = schedule[1];
	} else {
		count = 0;
		repeatat = -1;
		while (*schedule_str) {
			slash = strchrnul(schedule_str, '/');
			str_len = (size_t)(slash - schedule_str);
			if (str_len >= sizeof(item_buf))
				badusage("invalid schedule item: far too long"
				         " (you must delimit items with slashes)");
			memcpy(item_buf, schedule_str, str_len);
			item_buf[str_len] = '\0';
			schedule_str = *slash ? slash + 1 : slash;

			parse_schedule_item(item_buf, &schedule[count]);
			if (schedule[count].type == sched_forever) {
				if (repeatat >= 0)
					badusage("invalid schedule: 'forever'"
					         " appears more than once");
				repeatat = count;
				continue;
			}
			count++;
		}
		if (repeatat == count)
			badusage("invalid schedule: 'forever' appears last, "
			         "nothing to repeat");
		if (repeatat >= 0) {
			schedule[count].type = sched_goto;
			schedule[count].value = repeatat;
			count++;
		}
		if (count != schedule_length)
			BUG("count=%d != schedule_length=%d",
			    count, schedule_length);
	}
}

static void
set_action(enum action_code new_action)
{
	if (action == new_action)
		return;

	if (action != ACTION_NONE)
		badusage("only one command can be specified");

	action = new_action;
}

#define OPT_PID		500
#define OPT_PPID	501
#define OPT_RM_PIDFILE	502
#define OPT_NOTIFY_AWAIT	503
#define OPT_NOTIFY_TIMEOUT	504

static void
parse_options(int argc, char * const *argv)
{
	static struct option longopts[] = {
		{ "help",	  0, NULL, 'H'},
		{ "stop",	  0, NULL, 'K'},
		{ "start",	  0, NULL, 'S'},
		{ "status",	  0, NULL, 'T'},
		{ "version",	  0, NULL, 'V'},
		{ "startas",	  1, NULL, 'a'},
		{ "name",	  1, NULL, 'n'},
		{ "oknodo",	  0, NULL, 'o'},
		{ "pid",	  1, NULL, OPT_PID},
		{ "ppid",	  1, NULL, OPT_PPID},
		{ "pidfile",	  1, NULL, 'p'},
		{ "quiet",	  0, NULL, 'q'},
		{ "signal",	  1, NULL, 's'},
		{ "test",	  0, NULL, 't'},
		{ "user",	  1, NULL, 'u'},
		{ "group",	  1, NULL, 'g'},
		{ "chroot",	  1, NULL, 'r'},
		{ "verbose",	  0, NULL, 'v'},
		{ "exec",	  1, NULL, 'x'},
		{ "chuid",	  1, NULL, 'c'},
		{ "nicelevel",	  1, NULL, 'N'},
		{ "procsched",	  1, NULL, 'P'},
		{ "iosched",	  1, NULL, 'I'},
		{ "umask",	  1, NULL, 'k'},
		{ "background",	  0, NULL, 'b'},
#if WANT_SYSTEMD_NOTIFY
		{ "notify-await", 0, NULL, OPT_NOTIFY_AWAIT},
		{ "notify-timeout", 1, NULL, OPT_NOTIFY_TIMEOUT},
#endif
		{ "no-close",	  0, NULL, 'C'},
		{ "make-pidfile", 0, NULL, 'm'},
		{ "remove-pidfile", 0, NULL, OPT_RM_PIDFILE},
		{ "retry",	  1, NULL, 'R'},
		{ "chdir",	  1, NULL, 'd'},
		{ NULL,		  0, NULL, 0  }
	};
	const char *pid_str = NULL;
	const char *ppid_str = NULL;
	const char *umask_str = NULL;
	const char *signal_str = NULL;
	const char *schedule_str = NULL;
	const char *proc_schedule_str = NULL;
	const char *io_schedule_str = NULL;
#if WANT_SYSTEMD_NOTIFY
	const char *notify_timeout_str = NULL;
#endif
	size_t changeuser_len;
	int c;

	for (;;) {
		c = getopt_long(argc, argv,
		                "HKSVTa:n:op:qr:s:tu:vx:c:N:P:I:k:bCmR:g:d:",
		                longopts, NULL);
		if (c == -1)
			break;
		switch (c) {
		case 'H':  /* --help */
			usage();
			exit(0);
		case 'K':  /* --stop */
			set_action(ACTION_STOP);
			break;
		case 'S':  /* --start */
			set_action(ACTION_START);
			break;
		case 'T':  /* --status */
			set_action(ACTION_STATUS);
			break;
		case 'V':  /* --version */
			do_version();
			exit(0);
		case 'a':  /* --startas <pathname> */
			startas = optarg;
			break;
		case 'n':  /* --name <process-name> */
			match_mode |= MATCH_NAME;
			cmdname = optarg;
			break;
		case 'o':  /* --oknodo */
			exitnodo = 0;
			break;
		case OPT_PID: /* --pid <pid> */
			match_mode |= MATCH_PID;
			pid_str = optarg;
			break;
		case OPT_PPID: /* --ppid <ppid> */
			match_mode |= MATCH_PPID;
			ppid_str = optarg;
			break;
		case 'p':  /* --pidfile <pid-file> */
			match_mode |= MATCH_PIDFILE;
			pidfile = optarg;
			break;
		case 'q':  /* --quiet */
			quietmode = true;
			break;
		case 's':  /* --signal <signal> */
			signal_str = optarg;
			break;
		case 't':  /* --test */
			testmode = true;
			break;
		case 'u':  /* --user <username>|<uid> */
			match_mode |= MATCH_USER;
			userspec = optarg;
			break;
		case 'v':  /* --verbose */
			quietmode = -1;
			break;
		case 'x':  /* --exec <executable> */
			match_mode |= MATCH_EXEC;
			execname = optarg;
			break;
		case 'c':  /* --chuid <username>|<uid> */
			/* We copy the string just in case we need the
			 * argument later. */
			changeuser_len = strcspn(optarg, ":");
			changeuser = xstrndup(optarg, changeuser_len);
			if (optarg[changeuser_len] == ':') {
				if (optarg[changeuser_len + 1] == '\0')
					fatal("missing group name");
				changegroup = optarg + changeuser_len + 1;
			}
			break;
		case 'g':  /* --group <group>|<gid> */
			changegroup = optarg;
			break;
		case 'r':  /* --chroot /new/root */
			changeroot = optarg;
			break;
		case 'N':  /* --nice */
			nicelevel = atoi(optarg);
			break;
		case 'P':  /* --procsched */
			proc_schedule_str = optarg;
			break;
		case 'I':  /* --iosched */
			io_schedule_str = optarg;
			break;
		case 'k':  /* --umask <mask> */
			umask_str = optarg;
			break;
		case 'b':  /* --background */
			background = true;
			break;
#if WANT_SYSTEMD_NOTIFY
		case OPT_NOTIFY_AWAIT:
			notify_await = true;
			break;
		case OPT_NOTIFY_TIMEOUT:
			notify_timeout_str = optarg;
			break;
#endif
		case 'C': /* --no-close */
			close_io = false;
			break;
		case 'm':  /* --make-pidfile */
			mpidfile = true;
			break;
		case OPT_RM_PIDFILE: /* --remove-pidfile */
			rpidfile = true;
			break;
		case 'R':  /* --retry <schedule>|<timeout> */
			schedule_str = optarg;
			break;
		case 'd':  /* --chdir /new/dir */
			changedir = optarg;
			break;
		default:
			/* Message printed by getopt. */
			badusage(NULL);
		}
	}

	if (pid_str != NULL) {
		if (parse_pid(pid_str, &match_pid) != 0)
			badusage("pid value must be a number greater than 0");
	}

	if (ppid_str != NULL) {
		if (parse_pid(ppid_str, &match_ppid) != 0)
			badusage("ppid value must be a number greater than 0");
	}

	if (signal_str != NULL) {
		if (parse_signal(signal_str, &signal_nr) != 0)
			badusage("signal value must be numeric or name"
			         " of signal (KILL, INT, ...)");
	}

	if (schedule_str != NULL) {
		parse_schedule(schedule_str);
	}

	if (proc_schedule_str != NULL)
		parse_proc_schedule(proc_schedule_str);

	if (io_schedule_str != NULL)
		parse_io_schedule(io_schedule_str);

	if (umask_str != NULL) {
		if (parse_umask(umask_str, &umask_value) != 0)
			badusage("umask value must be a positive number");
	}

#if WANT_SYSTEMD_NOTIFY
	if (notify_timeout_str != NULL)
		if (parse_unsigned(notify_timeout_str, 10, &notify_timeout) != 0)
			badusage("invalid notify timeout value");
#endif

	if (action == ACTION_NONE)
		badusage("need one of --start or --stop or --status");

	if (match_mode == MATCH_NONE ||
	    (!execname && !cmdname && !userspec &&
	     !pid_str && !ppid_str && !pidfile))
		badusage("need at least one of --exec, --pid, --ppid, --pidfile, --user or --name");

#ifdef PROCESS_NAME_SIZE
	if (cmdname && strlen(cmdname) > PROCESS_NAME_SIZE)
		warning("this system is not able to track process names\n"
		        "longer than %d characters, please use --exec "
		        "instead of --name.\n", PROCESS_NAME_SIZE);
#endif

	if (!startas)
		startas = execname;

	if (action == ACTION_START && !startas)
		badusage("--start needs --exec or --startas");

	if (mpidfile && pidfile == NULL)
		badusage("--make-pidfile requires --pidfile");
	if (rpidfile && pidfile == NULL)
		badusage("--remove-pidfile requires --pidfile");

	if (pid_str && pidfile)
		badusage("need either --pid or --pidfile, not both");

	if (background && action != ACTION_START)
		badusage("--background is only relevant with --start");

	if (!close_io && !background)
		badusage("--no-close is only relevant with --background");
}

static void
setup_options(void)
{
	if (execname) {
		char *fullexecname;

		/* If it's a relative path, normalize it. */
		if (execname[0] != '/')
			execname = newpath(changedir, execname);

		if (changeroot)
			fullexecname = newpath(changeroot, execname);
		else
			fullexecname = execname;

		if (stat(fullexecname, &exec_stat))
			fatale("unable to stat %s", fullexecname);

		if (fullexecname != execname)
			free(fullexecname);
	}

	if (userspec && parse_unsigned(userspec, 10, &user_id) < 0) {
		struct passwd *pw;

		pw = getpwnam(userspec);
		if (!pw)
			fatale("user '%s' not found", userspec);

		user_id = pw->pw_uid;
	}

	if (changegroup && parse_unsigned(changegroup, 10, &runas_gid) < 0) {
		struct group *gr;

		gr = getgrnam(changegroup);
		if (!gr)
			fatale("group '%s' not found", changegroup);
		changegroup = gr->gr_name;
		runas_gid = gr->gr_gid;
	}
	if (changeuser) {
		struct passwd *pw;
		struct stat st;

		if (parse_unsigned(changeuser, 10, &runas_uid) == 0)
			pw = getpwuid(runas_uid);
		else
			pw = getpwnam(changeuser);
		if (!pw)
			fatale("user '%s' not found", changeuser);
		changeuser = pw->pw_name;
		runas_uid = pw->pw_uid;
		if (changegroup == NULL) {
			/* Pass the default group of this user. */
			changegroup = ""; /* Just empty. */
			runas_gid = pw->pw_gid;
		}
		if (stat(pw->pw_dir, &st) == 0)
			setenv("HOME", pw->pw_dir, 1);
	}
}

#if defined(OS_Linux)
static const char *
proc_status_field(pid_t pid, const char *field)
{
	static char *line = NULL;
	static size_t line_size = 0;

	FILE *fp;
	char filename[32];
	char *value = NULL;
	ssize_t line_len;
	size_t field_len = strlen(field);

	sprintf(filename, "/proc/%d/status", pid);
	fp = fopen(filename, "r");
	if (!fp)
		return NULL;
	while ((line_len = getline(&line, &line_size, fp)) >= 0) {
		if (strncasecmp(line, field, field_len) == 0) {
			line[line_len - 1] = '\0';

			value = line + field_len;
			while (isspace(*value))
				value++;

			break;
		}
	}
	fclose(fp);

	return value;
}
#elif defined(OS_AIX)
static bool
proc_get_psinfo(pid_t pid, struct psinfo *psinfo)
{
	char filename[64];
	FILE *fp;

	sprintf(filename, "/proc/%d/psinfo", pid);
	fp = fopen(filename, "r");
	if (!fp)
		return false;
	if (fread(psinfo, sizeof(*psinfo), 1, fp) == 0) {
		fclose(fp);
		return false;
	}
	if (ferror(fp)) {
		fclose(fp);
		return false;
	}

	fclose(fp);

	return true;
}
#elif defined(OS_Hurd)
static void
init_procset(void)
{
	struct ps_context *context;
	error_t err;

	err = ps_context_create(getproc(), &context);
	if (err)
		error(1, err, "ps_context_create");

	err = proc_stat_list_create(context, &procset);
	if (err)
		error(1, err, "proc_stat_list_create");

	err = proc_stat_list_add_all(procset, 0, 0);
	if (err)
		error(1, err, "proc_stat_list_add_all");
}

static struct proc_stat *
get_proc_stat(pid_t pid, ps_flags_t flags)
{
	struct proc_stat *ps;
	ps_flags_t wanted_flags = PSTAT_PID | flags;

	if (!procset)
		init_procset();

	ps = proc_stat_list_pid_proc_stat(procset, pid);
	if (!ps)
		return NULL;
	if (proc_stat_set_flags(ps, wanted_flags))
		return NULL;
	if ((proc_stat_flags(ps) & wanted_flags) != wanted_flags)
		return NULL;

	return ps;
}
#elif defined(HAVE_KVM_H)
static kvm_t *
ssd_kvm_open(void)
{
	kvm_t *kd;
	char errbuf[_POSIX2_LINE_MAX];

	kd = kvm_openfiles(NULL, KVM_MEMFILE, NULL, O_RDONLY, errbuf);
	if (kd == NULL)
		errx(1, "%s", errbuf);

	return kd;
}

static struct kinfo_proc *
ssd_kvm_get_procs(kvm_t *kd, int op, int arg, int *count)
{
	struct kinfo_proc *kp;
	int lcount;

	if (count == NULL)
		count = &lcount;
	*count = 0;

#if defined(OS_OpenBSD)
	kp = kvm_getprocs(kd, op, arg, sizeof(*kp), count);
#else
	kp = kvm_getprocs(kd, op, arg, count);
#endif
	if (kp == NULL && errno != ESRCH)
		errx(1, "%s", kvm_geterr(kd));

	return kp;
}
#endif

#if defined(OS_Linux)
static bool
pid_is_exec(pid_t pid, const struct stat *esb)
{
	char lname[32];
	char lcontents[_POSIX_PATH_MAX + 1];
	char *filename;
	const char deleted[] = " (deleted)";
	int nread;
	struct stat sb;

	sprintf(lname, "/proc/%d/exe", pid);
	nread = readlink(lname, lcontents, sizeof(lcontents) - 1);
	if (nread == -1)
		return false;

	filename = lcontents;
	filename[nread] = '\0';

	/* OpenVZ kernels contain a bogus patch that instead of appending,
	 * prepends the deleted marker. Workaround those. Otherwise handle
	 * the normal appended marker. */
	if (strncmp(filename, deleted, strlen(deleted)) == 0)
		filename += strlen(deleted);
	else if (strcmp(filename + nread - strlen(deleted), deleted) == 0)
		filename[nread - strlen(deleted)] = '\0';

	if (stat(filename, &sb) != 0)
		return false;

	return (sb.st_dev == esb->st_dev && sb.st_ino == esb->st_ino);
}
#elif defined(OS_AIX)
static bool
pid_is_exec(pid_t pid, const struct stat *esb)
{
	struct stat sb;
	char filename[64];

	sprintf(filename, "/proc/%d/object/a.out", pid);

	if (stat(filename, &sb) != 0)
		return false;

	return sb.st_dev == esb->st_dev && sb.st_ino == esb->st_ino;
}
#elif defined(OS_Hurd)
static bool
pid_is_exec(pid_t pid, const struct stat *esb)
{
	struct proc_stat *ps;
	struct stat sb;
	const char *filename;

	ps = get_proc_stat(pid, PSTAT_ARGS);
	if (ps == NULL)
		return false;

	/* On old Hurd systems we have to use the argv[0] value, because
	 * there is nothing better. */
	filename = proc_stat_args(ps);
#ifdef PSTAT_EXE
	/* On new Hurd systems we can use the correct value, as long
	 * as it's not NULL nor empty, as it was the case on the first
	 * implementation. */
	if (proc_stat_set_flags(ps, PSTAT_EXE) == 0 &&
	    proc_stat_flags(ps) & PSTAT_EXE &&
	    proc_stat_exe(ps) != NULL &&
	    proc_stat_exe(ps)[0] != '\0')
		filename = proc_stat_exe(ps);
#endif

	if (stat(filename, &sb) != 0)
		return false;

	return (sb.st_dev == esb->st_dev && sb.st_ino == esb->st_ino);
}
#elif defined(OS_Darwin)
static bool
pid_is_exec(pid_t pid, const struct stat *esb)
{
	struct stat sb;
	char pathname[_POSIX_PATH_MAX];

	if (proc_pidpath(pid, pathname, sizeof(pathname)) < 0)
		return false;

	if (stat(pathname, &sb) != 0)
		return false;

	return (sb.st_dev == esb->st_dev && sb.st_ino == esb->st_ino);
}
#elif defined(OS_HPUX)
static bool
pid_is_exec(pid_t pid, const struct stat *esb)
{
	struct pst_status pst;

	if (pstat_getproc(&pst, sizeof(pst), (size_t)0, (int)pid) < 0)
		return false;
	return ((dev_t)pst.pst_text.psf_fsid.psfs_id == esb->st_dev &&
	        (ino_t)pst.pst_text.psf_fileid == esb->st_ino);
}
#elif defined(OS_FreeBSD)
static bool
pid_is_exec(pid_t pid, const struct stat *esb)
{
	struct stat sb;
	int error, mib[4];
	size_t len;
	char pathname[PATH_MAX];

	mib[0] = CTL_KERN;
	mib[1] = KERN_PROC;
	mib[2] = KERN_PROC_PATHNAME;
	mib[3] = pid;
	len = sizeof(pathname);

	error = sysctl(mib, 4, pathname, &len, NULL, 0);
	if (error != 0 && errno != ESRCH)
		return false;
	if (len == 0)
		pathname[0] = '\0';

	if (stat(pathname, &sb) != 0)
		return false;

	return (sb.st_dev == esb->st_dev && sb.st_ino == esb->st_ino);
}
#elif defined(HAVE_KVM_H)
static bool
pid_is_exec(pid_t pid, const struct stat *esb)
{
	kvm_t *kd;
	int argv_len = 0;
	struct kinfo_proc *kp;
	struct stat sb;
	char buf[_POSIX2_LINE_MAX];
	char **pid_argv_p;
	char *start_argv_0_p, *end_argv_0_p;
	bool res = false;

	kd = ssd_kvm_open();
	kp = ssd_kvm_get_procs(kd, KERN_PROC_PID, pid, NULL);
	if (kp == NULL)
		goto cleanup;

	pid_argv_p = kvm_getargv(kd, kp, argv_len);
	if (pid_argv_p == NULL)
		errx(1, "%s", kvm_geterr(kd));

	/* Find and compare string. */
	start_argv_0_p = *pid_argv_p;

	/* Find end of argv[0] then copy and cut of str there. */
	end_argv_0_p = strchr(*pid_argv_p, ' ');
	if (end_argv_0_p == NULL)
		/* There seems to be no space, so we have the command
		 * already in its desired form. */
		start_argv_0_p = *pid_argv_p;
	else {
		/* Tests indicate that this never happens, since
		 * kvm_getargv itself cuts of tailing stuff. This is
		 * not what the manpage says, however. */
		strncpy(buf, *pid_argv_p, (end_argv_0_p - start_argv_0_p));
		buf[(end_argv_0_p - start_argv_0_p) + 1] = '\0';
		start_argv_0_p = buf;
	}

	if (stat(start_argv_0_p, &sb) != 0)
		goto cleanup;

	res = (sb.st_dev == esb->st_dev && sb.st_ino == esb->st_ino);

cleanup:
	kvm_close(kd);

	return res;
}
#endif

#if defined(OS_Linux)
static bool
pid_is_child(pid_t pid, pid_t ppid)
{
	const char *ppid_str;
	pid_t proc_ppid;
	int rc;

	ppid_str = proc_status_field(pid, "PPid:");
	if (ppid_str == NULL)
		return false;

	rc = parse_pid(ppid_str, &proc_ppid);
	if (rc < 0)
		return false;

	return proc_ppid == ppid;
}
#elif defined(OS_Hurd)
static bool
pid_is_child(pid_t pid, pid_t ppid)
{
	struct proc_stat *ps;
	struct procinfo *pi;

	ps = get_proc_stat(pid, PSTAT_PROC_INFO);
	if (ps == NULL)
		return false;

	pi = proc_stat_proc_info(ps);

	return pi->ppid == ppid;
}
#elif defined(OS_Darwin)
static bool
pid_is_child(pid_t pid, pid_t ppid)
{
	struct proc_bsdinfo info;

	if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) < 0)
		return false;

	return (pid_t)info.pbi_ppid == ppid;
}
#elif defined(OS_AIX)
static bool
pid_is_child(pid_t pid, pid_t ppid)
{
	struct psinfo psi;

	if (!proc_get_psinfo(pid, &psi))
		return false;

	return (pid_t)psi.pr_ppid == ppid;
}
#elif defined(OS_HPUX)
static bool
pid_is_child(pid_t pid, pid_t ppid)
{
	struct pst_status pst;

	if (pstat_getproc(&pst, sizeof(pst), (size_t)0, (int)pid) < 0)
		return false;

	return pst.pst_ppid == ppid;
}
#elif defined(OS_FreeBSD)
static bool
pid_is_child(pid_t pid, pid_t ppid)
{
	struct kinfo_proc kp;
	int rc, mib[4];
	size_t len;

	mib[0] = CTL_KERN;
	mib[1] = KERN_PROC;
	mib[2] = KERN_PROC_PID;
	mib[3] = pid;
	len = sizeof(kp);

	rc = sysctl(mib, 4, &kp, &len, NULL, 0);
	if (rc != 0 && errno != ESRCH)
		return false;
	if (len == 0 || len != sizeof(kp))
		return false;

	return kp.ki_ppid == ppid;
}
#elif defined(HAVE_KVM_H)
static bool
pid_is_child(pid_t pid, pid_t ppid)
{
	kvm_t *kd;
	struct kinfo_proc *kp;
	pid_t proc_ppid;
	bool res = false;

	kd = ssd_kvm_open();
	kp = ssd_kvm_get_procs(kd, KERN_PROC_PID, pid, NULL);
	if (kp == NULL)
		goto cleanup;

#if defined(OS_FreeBSD)
	proc_ppid = kp->ki_ppid;
#elif defined(OS_OpenBSD)
	proc_ppid = kp->p_ppid;
#elif defined(OS_DragonFlyBSD)
	proc_ppid = kp->kp_ppid;
#else
	proc_ppid = kp->kp_proc.p_ppid;
#endif

	res = (proc_ppid == ppid);

cleanup:
	kvm_close(kd);

	return res;
}
#endif

#if defined(OS_Linux)
static bool
pid_is_user(pid_t pid, uid_t uid)
{
	struct stat sb;
	char buf[32];

	sprintf(buf, "/proc/%d", pid);
	if (stat(buf, &sb) != 0)
		return false;
	return (sb.st_uid == uid);
}
#elif defined(OS_Hurd)
static bool
pid_is_user(pid_t pid, uid_t uid)
{
	struct proc_stat *ps;

	ps = get_proc_stat(pid, PSTAT_OWNER_UID);
	return ps && (uid_t)proc_stat_owner_uid(ps) == uid;
}
#elif defined(OS_Darwin)
static bool
pid_is_user(pid_t pid, uid_t uid)
{
	struct proc_bsdinfo info;

	if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) < 0)
		return false;

	return info.pbi_ruid == uid;
}
#elif defined(OS_AIX)
static bool
pid_is_user(pid_t pid, uid_t uid)
{
	struct psinfo psi;

	if (!proc_get_psinfo(pid, &psi))
		return false;

	return psi.pr_uid == uid;
}
#elif defined(OS_HPUX)
static bool
pid_is_user(pid_t pid, uid_t uid)
{
	struct pst_status pst;

	if (pstat_getproc(&pst, sizeof(pst), (size_t)0, (int)pid) < 0)
		return false;
	return ((uid_t)pst.pst_uid == uid);
}
#elif defined(OS_FreeBSD)
static bool
pid_is_user(pid_t pid, uid_t uid)
{
	struct kinfo_proc kp;
	int rc, mib[4];
	size_t len;

	mib[0] = CTL_KERN;
	mib[1] = KERN_PROC;
	mib[2] = KERN_PROC_PID;
	mib[3] = pid;
	len = sizeof(kp);

	rc = sysctl(mib, 4, &kp, &len, NULL, 0);
	if (rc != 0 && errno != ESRCH)
		return false;
	if (len == 0 || len != sizeof(kp))
		return false;

	return kp.ki_ruid == uid;
}
#elif defined(HAVE_KVM_H)
static bool
pid_is_user(pid_t pid, uid_t uid)
{
	kvm_t *kd;
	uid_t proc_uid;
	struct kinfo_proc *kp;
	bool res = false;

	kd = ssd_kvm_open();
	kp = ssd_kvm_get_procs(kd, KERN_PROC_PID, pid, NULL);
	if (kp == NULL)
		goto cleanup;

#if defined(OS_FreeBSD)
	proc_uid = kp->ki_ruid;
#elif defined(OS_OpenBSD)
	proc_uid = kp->p_ruid;
#elif defined(OS_DragonFlyBSD)
	proc_uid = kp->kp_ruid;
#elif defined(OS_NetBSD)
	proc_uid = kp->kp_eproc.e_pcred.p_ruid;
#else
	if (kp->kp_proc.p_cred)
		kvm_read(kd, (u_long)&(kp->kp_proc.p_cred->p_ruid),
		         &proc_uid, sizeof(uid_t));
	else
		goto cleanup;
#endif

	res = (proc_uid == (uid_t)uid);

cleanup:
	kvm_close(kd);

	return res;
}
#endif

#if defined(OS_Linux)
static bool
pid_is_cmd(pid_t pid, const char *name)
{
	const char *comm;

	comm = proc_status_field(pid, "Name:");
	if (comm == NULL)
		return false;

	return strcmp(comm, name) == 0;
}
#elif defined(OS_Hurd)
static bool
pid_is_cmd(pid_t pid, const char *name)
{
	struct proc_stat *ps;
	size_t argv0_len;
	const char *argv0;
	const char *binary_name;

	ps = get_proc_stat(pid, PSTAT_ARGS);
	if (ps == NULL)
		return false;

	argv0 = proc_stat_args(ps);
	argv0_len = strlen(argv0) + 1;

	binary_name = basename(argv0);
	if (strcmp(binary_name, name) == 0)
		return true;

	/* XXX: This is all kinds of ugly, but on the Hurd there's no way to
	 * know the command name of a process, so we have to try to match
	 * also on argv[1] for the case of an interpreted script. */
	if (proc_stat_args_len(ps) > argv0_len) {
		const char *script_name = basename(argv0 + argv0_len);

		return strcmp(script_name, name) == 0;
	}

	return false;
}
#elif defined(OS_AIX)
static bool
pid_is_cmd(pid_t pid, const char *name)
{
	struct psinfo psi;

	if (!proc_get_psinfo(pid, &psi))
		return false;

	return strcmp(psi.pr_fname, name) == 0;
}
#elif defined(OS_HPUX)
static bool
pid_is_cmd(pid_t pid, const char *name)
{
	struct pst_status pst;

	if (pstat_getproc(&pst, sizeof(pst), (size_t)0, (int)pid) < 0)
		return false;
	return (strcmp(pst.pst_ucomm, name) == 0);
}
#elif defined(OS_Darwin)
static bool
pid_is_cmd(pid_t pid, const char *name)
{
	char pathname[_POSIX_PATH_MAX];

	if (proc_pidpath(pid, pathname, sizeof(pathname)) < 0)
		return false;

	return strcmp(pathname, name) == 0;
}
#elif defined(OS_FreeBSD)
static bool
pid_is_cmd(pid_t pid, const char *name)
{
	struct kinfo_proc kp;
	int rc, mib[4];
	size_t len;

	mib[0] = CTL_KERN;
	mib[1] = KERN_PROC;
	mib[2] = KERN_PROC_PID;
	mib[3] = pid;
	len = sizeof(kp);

	rc = sysctl(mib, 4, &kp, &len, NULL, 0);
	if (rc != 0 && errno != ESRCH)
		return false;
	if (len == 0 || len != sizeof(kp))
		return false;

	return strcmp(kp.ki_comm, name) == 0;
}
#elif defined(HAVE_KVM_H)
static bool
pid_is_cmd(pid_t pid, const char *name)
{
	kvm_t *kd;
	struct kinfo_proc *kp;
	char *process_name;
	bool res = false;

	kd = ssd_kvm_open();
	kp = ssd_kvm_get_procs(kd, KERN_PROC_PID, pid, NULL);
	if (kp == NULL)
		goto cleanup;

#if defined(OS_FreeBSD)
	process_name = kp->ki_comm;
#elif defined(OS_OpenBSD)
	process_name = kp->p_comm;
#elif defined(OS_DragonFlyBSD)
	process_name = kp->kp_comm;
#else
	process_name = kp->kp_proc.p_comm;
#endif

	res = (strcmp(name, process_name) == 0);

cleanup:
	kvm_close(kd);

	return res;
}
#endif

#if defined(OS_Hurd)
static bool
pid_is_running(pid_t pid)
{
	return get_proc_stat(pid, 0) != NULL;
}
#else /* !OS_Hurd */
static bool
pid_is_running(pid_t pid)
{
	if (kill(pid, 0) == 0 || errno == EPERM)
		return true;
	else if (errno == ESRCH)
		return false;
	else
		fatale("error checking pid %u status", pid);
}
#endif

static enum status_code
pid_check(pid_t pid)
{
	if (execname && !pid_is_exec(pid, &exec_stat))
		return STATUS_DEAD;
	if (match_ppid > 0 && !pid_is_child(pid, match_ppid))
		return STATUS_DEAD;
	if (userspec && !pid_is_user(pid, user_id))
		return STATUS_DEAD;
	if (cmdname && !pid_is_cmd(pid, cmdname))
		return STATUS_DEAD;
	if (action != ACTION_STOP && !pid_is_running(pid))
		return STATUS_DEAD;

	pid_list_push(&found, pid);

	return STATUS_OK;
}

static enum status_code
do_pidfile(const char *name)
{
	FILE *f;
	static pid_t pid = 0;

	if (pid)
		return pid_check(pid);

	f = fopen(name, "r");
	if (f) {
		enum status_code pid_status;

		/* If we are only matching on the pidfile, and it is owned by
		 * a non-root user, then this is a security risk, and the
		 * contents cannot be trusted, because the daemon might have
		 * been compromised.
		 *
		 * If the pidfile is world-writable we refuse to parse it.
		 *
		 * If we got /dev/null specified as the pidfile, we ignore the
		 * checks, as this is being used to run processes no matter
		 * what. */
		if (strcmp(name, "/dev/null") != 0) {
			struct stat st;
			int fd = fileno(f);

			if (fstat(fd, &st) < 0)
				fatale("cannot stat pidfile %s", name);

			if (match_mode == MATCH_PIDFILE &&
			    ((st.st_uid != getuid() && st.st_uid != 0) ||
			     ((st.st_gid != getgid() && st.st_gid != 0) &&
			      (st.st_mode & 0020))))
				fatal("matching only on non-root pidfile %s is insecure", name);
			if (st.st_mode & 0002)
				fatal("matching on world-writable pidfile %s is insecure", name);

		}

		if (fscanf(f, "%d", &pid) == 1)
			pid_status = pid_check(pid);
		else
			pid_status = STATUS_UNKNOWN;
		fclose(f);

		if (pid_status == STATUS_DEAD)
			return STATUS_DEAD_PIDFILE;
		else
			return pid_status;
	} else if (errno == ENOENT)
		return STATUS_DEAD;
	else
		fatale("unable to open pidfile %s", name);
}

#if defined(OS_Linux) || defined(OS_Solaris) || defined(OS_AIX)
static enum status_code
do_procinit(void)
{
	DIR *procdir;
	struct dirent *entry;
	int foundany;
	pid_t pid;
	enum status_code prog_status = STATUS_DEAD;

	procdir = opendir("/proc");
	if (!procdir)
		fatale("unable to opendir /proc");

	foundany = 0;
	while ((entry = readdir(procdir)) != NULL) {
		enum status_code pid_status;

		if (sscanf(entry->d_name, "%d", &pid) != 1)
			continue;
		foundany++;

		pid_status = pid_check(pid);
		if (pid_status < prog_status)
			prog_status = pid_status;
	}
	closedir(procdir);
	if (foundany == 0)
		fatal("nothing in /proc - not mounted?");

	return prog_status;
}
#elif defined(OS_Hurd)
static int
check_proc_stat(struct proc_stat *ps)
{
	pid_check(proc_stat_pid(ps));
	return 0;
}

static enum status_code
do_procinit(void)
{
	if (!procset)
		init_procset();

	proc_stat_list_for_each(procset, check_proc_stat);

	if (found)
		return STATUS_OK;
	else
		return STATUS_DEAD;
}
#elif defined(OS_Darwin)
static enum status_code
do_procinit(void)
{
	pid_t *pid_buf;
	int i, npids, pid_bufsize;
	enum status_code prog_status = STATUS_DEAD;

	npids = proc_listallpids(NULL, 0);
	if (npids == 0)
		return STATUS_UNKNOWN;

	/* Try to avoid sudden changes in number of PIDs. */
	npids += 4096;
	pid_bufsize = sizeof(pid_t) * npids;
	pid_buf = xmalloc(pid_bufsize);

	npids = proc_listallpids(pid_buf, pid_bufsize);
	if (npids == 0)
		return STATUS_UNKNOWN;

	for (i = 0; i < npids; i++) {
		enum status_code pid_status;

		pid_status = pid_check(pid_buf[i]);
		if (pid_status < prog_status)
			prog_status = pid_status;
	}

	free(pid_buf);

	return prog_status;
}
#elif defined(OS_HPUX)
static enum status_code
do_procinit(void)
{
	struct pst_status pst[10];
	int i, count;
	int idx = 0;
	enum status_code prog_status = STATUS_DEAD;

	while ((count = pstat_getproc(pst, sizeof(pst[0]), 10, idx)) > 0) {
		enum status_code pid_status;

		for (i = 0; i < count; i++) {
			pid_status = pid_check(pst[i].pst_pid);
			if (pid_status < prog_status)
				prog_status = pid_status;
		}
		idx = pst[count - 1].pst_idx + 1;
	}

	return prog_status;
}
#elif defined(OS_FreeBSD)
static enum status_code
do_procinit(void)
{
	struct kinfo_proc *kp;
	int rc, mib[3];
	size_t len = 0;
	int nentries, i;
	enum status_code prog_status = STATUS_DEAD;

	mib[0] = CTL_KERN;
	mib[1] = KERN_PROC;
	mib[2] = KERN_PROC_PROC;

	rc = sysctl(mib, 3, NULL, &len, NULL, 0);
	if (rc != 0 && errno != ESRCH)
		return STATUS_UNKNOWN;
	if (len == 0)
		return STATUS_UNKNOWN;

	kp = xmalloc(len);
	rc = sysctl(mib, 3, kp, &len, NULL, 0);
	if (rc != 0 && errno != ESRCH)
		return STATUS_UNKNOWN;
	if (len == 0)
		return STATUS_UNKNOWN;
	nentries = len / sizeof(*kp);

	for (i = 0; i < nentries; i++) {
		enum status_code pid_status;

		pid_status = pid_check(kp[i].ki_pid);
		if (pid_status < prog_status)
			prog_status = pid_status;
	}

	free(kp);

	return prog_status;
}
#elif defined(HAVE_KVM_H)
static enum status_code
do_procinit(void)
{
	kvm_t *kd;
	int nentries, i;
	struct kinfo_proc *kp;
	enum status_code prog_status = STATUS_DEAD;

	kd = ssd_kvm_open();
	kp = ssd_kvm_get_procs(kd, KERN_PROC_ALL, 0, &nentries);

	for (i = 0; i < nentries; i++) {
		enum status_code pid_status;
		pid_t pid;

#if defined(OS_FreeBSD)
		pid = kp[i].ki_pid;
#elif defined(OS_OpenBSD)
		pid = kp[i].p_pid;
#elif defined(OS_DragonFlyBSD)
		pid = kp[i].kp_pid;
#else
		pid = kp[i].kp_proc.p_pid;
#endif

		pid_status = pid_check(pid);
		if (pid_status < prog_status)
			prog_status = pid_status;
	}

	kvm_close(kd);

	return prog_status;
}
#endif

static enum status_code
do_findprocs(void)
{
	pid_list_free(&found);

	if (match_pid > 0)
		return pid_check(match_pid);
	else if (pidfile)
		return do_pidfile(pidfile);
	else
		return do_procinit();
}

static int
do_start(int argc, char **argv)
{
	int devnull_fd = -1;
	gid_t rgid;
	uid_t ruid;

	do_findprocs();

	if (found) {
		info("%s already running.\n", execname ? execname : "process");
		return exitnodo;
	}
	if (testmode && quietmode <= 0) {
		printf("Would start %s ", startas);
		while (argc-- > 0)
			printf("%s ", *argv++);
		if (changeuser != NULL) {
			printf(" (as user %s[%d]", changeuser, runas_uid);
			if (changegroup != NULL)
				printf(", and group %s[%d])", changegroup, runas_gid);
			else
				printf(")");
		}
		if (changeroot != NULL)
			printf(" in directory %s", changeroot);
		if (nicelevel)
			printf(", and add %i to the priority", nicelevel);
		if (proc_sched)
			printf(", with scheduling policy %s with priority %i",
			       proc_sched->policy_name, proc_sched->priority);
		if (io_sched)
			printf(", with IO scheduling class %s with priority %i",
			       io_sched->policy_name, io_sched->priority);
		printf(".\n");
	}
	if (testmode)
		return 0;
	debug("Starting %s...\n", startas);
	*--argv = startas;
	if (background)
		/* Ok, we need to detach this process. */
		daemonize();
	else if (mpidfile && pidfile != NULL)
		/* User wants _us_ to make the pidfile, but detach themself! */
		write_pidfile(pidfile, getpid());
	if (background && close_io) {
		devnull_fd = open("/dev/null", O_RDWR);
		if (devnull_fd < 0)
			fatale("unable to open '%s'", "/dev/null");
	}
	if (nicelevel) {
		errno = 0;
		if ((nice(nicelevel) == -1) && (errno != 0))
			fatale("unable to alter nice level by %i", nicelevel);
	}
	if (proc_sched)
		set_proc_schedule(proc_sched);
	if (io_sched)
		set_io_schedule(io_sched);
	if (umask_value >= 0)
		umask(umask_value);
	if (changeroot != NULL) {
		if (chdir(changeroot) < 0)
			fatale("unable to chdir() to %s", changeroot);
		if (chroot(changeroot) < 0)
			fatale("unable to chroot() to %s", changeroot);
	}
	if (chdir(changedir) < 0)
		fatale("unable to chdir() to %s", changedir);

	rgid = getgid();
	ruid = getuid();
	if (changegroup != NULL) {
		if (rgid != (gid_t)runas_gid)
			if (setgid(runas_gid))
				fatale("unable to set gid to %d", runas_gid);
	}
	if (changeuser != NULL) {
		/* We assume that if our real user and group are the same as
		 * the ones we should switch to, the supplementary groups
		 * will be already in place. */
		if (rgid != (gid_t)runas_gid || ruid != (uid_t)runas_uid)
			if (initgroups(changeuser, runas_gid))
				fatale("unable to set initgroups() with gid %d",
				      runas_gid);

		if (ruid != (uid_t)runas_uid)
			if (setuid(runas_uid))
				fatale("unable to set uid to %s", changeuser);
	}

	if (background && close_io) {
		int i;

		dup2(devnull_fd, 0); /* stdin */
		dup2(devnull_fd, 1); /* stdout */
		dup2(devnull_fd, 2); /* stderr */

		 /* Now close all extra fds. */
		for (i = get_open_fd_max() - 1; i >= 3; --i)
			close(i);
	}
	execv(startas, argv);
	fatale("unable to start %s", startas);
}

static void
do_stop(int sig_num, int *n_killed, int *n_notkilled)
{
	struct pid_list *p;

	do_findprocs();

	*n_killed = 0;
	*n_notkilled = 0;

	if (!found)
		return;

	pid_list_free(&killed);

	for (p = found; p; p = p->next) {
		if (testmode) {
			info("Would send signal %d to %d.\n", sig_num, p->pid);
			(*n_killed)++;
		} else if (kill(p->pid, sig_num) == 0) {
			pid_list_push(&killed, p->pid);
			(*n_killed)++;
		} else {
			if (sig_num)
				warning("failed to kill %d: %s\n",
				        p->pid, strerror(errno));
			(*n_notkilled)++;
		}
	}
}

static void
do_stop_summary(int retry_nr)
{
	struct pid_list *p;

	if (quietmode >= 0 || !killed)
		return;

	printf("Stopped %s (pid", what_stop);
	for (p = killed; p; p = p->next)
		printf(" %d", p->pid);
	putchar(')');
	if (retry_nr > 0)
		printf(", retry #%d", retry_nr);
	printf(".\n");
}

static void DPKG_ATTR_PRINTF(1)
set_what_stop(const char *format, ...)
{
	va_list arglist;
	int rc;

	va_start(arglist, format);
	rc = vasprintf(&what_stop, format, arglist);
	va_end(arglist);

	if (rc < 0)
		fatale("cannot allocate formatted string");
}

/*
 * We want to keep polling for the processes, to see if they've exited, or
 * until the timeout expires.
 *
 * This is a somewhat complicated algorithm to try to ensure that we notice
 * reasonably quickly when all the processes have exited, but don't spend
 * too much CPU time polling. In particular, on a fast machine with
 * quick-exiting daemons we don't want to delay system shutdown too much,
 * whereas on a slow one, or where processes are taking some time to exit,
 * we want to increase the polling interval.
 *
 * The algorithm is as follows: we measure the elapsed time it takes to do
 * one poll(), and wait a multiple of this time for the next poll. However,
 * if that would put us past the end of the timeout period we wait only as
 * long as the timeout period, but in any case we always wait at least
 * MIN_POLL_INTERVAL (20ms). The multiple (‘ratio’) starts out as 2, and
 * increases by 1 for each poll to a maximum of 10; so we use up to between
 * 30% and 10% of the machine's resources (assuming a few reasonable things
 * about system performance).
 */
static bool
do_stop_timeout(int timeout, int *n_killed, int *n_notkilled)
{
	struct timespec stopat, before, after, interval, maxinterval;
	int rc, ratio;

	timespec_gettime(&stopat);
	stopat.tv_sec += timeout;
	ratio = 1;
	for (;;) {
		timespec_gettime(&before);
		if (timespec_cmp(&before, &stopat, >))
			return false;

		do_stop(0, n_killed, n_notkilled);
		if (!*n_killed)
			return true;

		timespec_gettime(&after);

		if (!timespec_cmp(&after, &stopat, <))
			return false;

		if (ratio < 10)
			ratio++;

		timespec_sub(&stopat, &after, &maxinterval);
		timespec_sub(&after, &before, &interval);
		timespec_mul(&interval, ratio);

		if (interval.tv_sec < 0 || interval.tv_nsec < 0)
			interval.tv_sec = interval.tv_nsec = 0;

		if (timespec_cmp(&interval, &maxinterval, >))
			interval = maxinterval;

		if (interval.tv_sec == 0 &&
		    interval.tv_nsec <= MIN_POLL_INTERVAL)
			interval.tv_nsec = MIN_POLL_INTERVAL;

		rc = pselect(0, NULL, NULL, NULL, &interval, NULL);
		if (rc < 0 && errno != EINTR)
			fatale("select() failed for pause");
	}
}

static int
finish_stop_schedule(bool anykilled)
{
	if (rpidfile && pidfile && !testmode)
		remove_pidfile(pidfile);

	if (anykilled)
		return 0;

	info("No %s found running; none killed.\n", what_stop);

	return exitnodo;
}

static int
run_stop_schedule(void)
{
	int position, n_killed, n_notkilled, value, retry_nr;
	bool anykilled;

	if (testmode) {
		if (schedule != NULL) {
			info("Ignoring --retry in test mode\n");
			schedule = NULL;
		}
	}

	if (cmdname)
		set_what_stop("%s", cmdname);
	else if (execname)
		set_what_stop("%s", execname);
	else if (pidfile)
		set_what_stop("process in pidfile '%s'", pidfile);
	else if (match_pid > 0)
		set_what_stop("process with pid %d", match_pid);
	else if (match_ppid > 0)
		set_what_stop("process(es) with parent pid %d", match_ppid);
	else if (userspec)
		set_what_stop("process(es) owned by '%s'", userspec);
	else
		BUG("no match option, please report");

	anykilled = false;
	retry_nr = 0;

	if (schedule == NULL) {
		do_stop(signal_nr, &n_killed, &n_notkilled);
		do_stop_summary(0);
		if (n_notkilled > 0)
			info("%d pids were not killed\n", n_notkilled);
		if (n_killed)
			anykilled = true;
		return finish_stop_schedule(anykilled);
	}

	for (position = 0; position < schedule_length; position++) {
	reposition:
		value = schedule[position].value;
		n_notkilled = 0;

		switch (schedule[position].type) {
		case sched_goto:
			position = value;
			goto reposition;
		case sched_signal:
			do_stop(value, &n_killed, &n_notkilled);
			do_stop_summary(retry_nr++);
			if (!n_killed)
				return finish_stop_schedule(anykilled);
			else
				anykilled = true;
			continue;
		case sched_timeout:
			if (do_stop_timeout(value, &n_killed, &n_notkilled))
				return finish_stop_schedule(anykilled);
			else
				continue;
		default:
			BUG("schedule[%d].type value %d is not valid",
			    position, schedule[position].type);
		}
	}

	info("Program %s, %d process(es), refused to die.\n",
	     what_stop, n_killed);

	return 2;
}

int
main(int argc, char **argv)
{
	progname = argv[0];

	parse_options(argc, argv);
	setup_options();

	argc -= optind;
	argv += optind;

	if (action == ACTION_START)
		return do_start(argc, argv);
	else if (action == ACTION_STOP)
		return run_stop_schedule();
	else if (action == ACTION_STATUS)
		return do_findprocs();

	return 0;
}
