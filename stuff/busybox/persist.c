#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include "doas.h"

#define PERSIST_DIR "/run/doas"
#define PERSIST_TIMEOUT 5 * 60

static int
ttyid(dev_t *tty)
{
	int fd, i;
	char buf[BUFSIZ], *p;
	ssize_t n;

	fd = open("/proc/self/stat", O_RDONLY);
	if (fd == -1)
		return -1;
	n = read(fd, buf, sizeof(buf) - 1);
	if (n >= 0)
		buf[n] = '\0';
	/* check that we read the whole file */
	n = read(fd, buf, 1);
	close(fd);
	if (n != 0)
		return -1;
	p = strrchr(buf, ')');
	if (!p)
		return -1;
	++p;
	/* ttr_nr is the 5th field after executable name, so skip the next 4 */
	for (i = 0; i < 4; ++i) {
		p = strchr(++p, ' ');
		if (!p)
			return -1;
	}
	*tty = strtol(p, &p, 10);
	if (*p != ' ')
		return -1;
	return 0;
}

static int
persistpath(char *buf, size_t len)
{
	dev_t tty;
	int n;

	if (ttyid(&tty) < 0)
		return -1;
	n = snprintf(buf, len, PERSIST_DIR "/%ju-%ju", (uintmax_t)getuid(), (uintmax_t)tty);
	if (n < 0 || n >= (int)len)
		return -1;
	return 0;
}

int
openpersist(int *valid)
{
	char path[256];
	struct stat st;
	struct timespec ts;
	int fd;

	if (stat(PERSIST_DIR, &st) < 0) {
		if (errno != ENOENT)
			return -1;
		if (mkdir(PERSIST_DIR, 0700) < 0)
			return -1;
	} else if (st.st_uid != 0 || st.st_mode != (S_IFDIR | 0700)) {
		return -1;
	}
	if (persistpath(path, sizeof(path)) < 0)
		return -1;
	fd = open(path, O_RDONLY);
	if (fd == -1) {
		char tmp[256];
		struct timespec ts[2] = { { .tv_nsec = UTIME_OMIT }, { 0 } };
		int n;

		n = snprintf(tmp, sizeof(tmp), PERSIST_DIR "/.tmp-%d", getpid());
		if (n < 0 || n >= (int)sizeof(tmp))
			return -1;
		fd = open(tmp, O_RDONLY | O_CREAT | O_EXCL, 0);
		if (fd == -1)
			return -1;
		if (futimens(fd, ts) < 0 || rename(tmp, path) < 0) {
			close(fd);
			unlink(tmp);
			return -1;
		}
		*valid = 0;
	} else {
		*valid = clock_gettime(CLOCK_BOOTTIME, &ts) == 0 &&
		         fstat(fd, &st) == 0 &&
		         (ts.tv_sec < st.st_mtim.tv_sec ||
		          ts.tv_sec == st.st_mtim.tv_sec && ts.tv_nsec < st.st_mtim.tv_nsec) &&
		         st.st_mtime - ts.tv_sec <= PERSIST_TIMEOUT;
	}
	return fd;
}

int
setpersist(int fd)
{
	struct timespec times[2];

	if (clock_gettime(CLOCK_BOOTTIME, &times[1]) < 0)
		return -1;
	times[0].tv_nsec = UTIME_OMIT;
	times[1].tv_sec += PERSIST_TIMEOUT;
	return futimens(fd, times);
}

int
clearpersist(void)
{
	char path[256];

	if (persistpath(path, sizeof(path)) < 0)
		return -1;
	if (unlink(path) < 0 && errno != ENOENT)
		return -1;
	return 0;
}
