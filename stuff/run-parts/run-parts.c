/* run-parts: run a bunch of scripts in a directory
 *
 * Debian run-parts program
 * Copyright (C) 1996 Jeff Noxon <jeff@router.patch.net>,
 * Copyright (C) 1996-1999 Guy Maor <maor@debian.org>
 * Copyright (C) 2002-2012 Clint Adams <clint@debian.org>
 *
 * This is free software; see the GNU General Public License version 2
 * or later for copying conditions.  There is NO warranty.
 *
 * Based on run-parts.pl version 0.2, Copyright (C) 1994 Ian Jackson.
 *
 */

#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <getopt.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <signal.h>
#include <sys/time.h>
#include <regex.h>

#define RUNPARTS_NORMAL 0
#define RUNPARTS_ERE 1
#define RUNPARTS_LSBSYSINIT 100

int test_mode = 0;
int list_mode = 0;
int verbose_mode = 0;
int report_mode = 0;
int reverse_mode = 0;
int exitstatus = 0;
int regex_mode = 0;
int exit_on_error_mode = 0;
int new_session_mode = 0;

int argcount = 0, argsize = 0;
char **args = 0;

char *custom_ere;
regex_t hierre, tradre, excsre, classicalre, customre;

static void catch_signals();
static void restore_signals();

static char* regex_get_error(int errcode, regex_t *compiled);
static void  regex_compile_pattern(void);
static void  regex_clean(void);

void error(char *format, ...)
{
  va_list ap;

  fprintf(stderr, "run-parts: ");

  va_start(ap, format);
  vfprintf(stderr, format, ap);
  va_end(ap);

  fprintf(stderr, "\n");
}


void version()
{
  fprintf(stderr, "run-parts version 1.4.8.8");
  exit(0);
}


void usage()
{
  fprintf(stderr, "Usage: run-parts [OPTION]... DIRECTORY\n"
	  "      --test          print script names which would run, but don't run them.\n"
	  "      --list          print names of all valid files (can not be used with\n"
	  "                      --test)\n"
	  "  -v, --verbose       print script names before running them.\n"
	  "      --report        print script names if they produce output.\n"
	  "      --reverse       reverse execution order of scripts.\n"
	  "      --exit-on-error exit as soon as a script returns with a non-zero exit\n"
	  "                      code.\n"
	  "      --lsbsysinit    validate filenames based on LSB sysinit specs.\n"
	  "      --new-session   run each script in a separate process session\n"
	  "      --regex=PATTERN validate filenames based on POSIX ERE pattern PATTERN.\n"
	  "  -u, --umask=UMASK   sets umask to UMASK (octal), default is 022.\n"
	  "  -a, --arg=ARGUMENT  pass ARGUMENT to scripts, use once for each argument.\n"
	  "  -V, --version       output version information and exit.\n"
	  "  -h, --help          display this help and exit.\n");
  exit(0);
}


/* The octal conversion in libc is not foolproof; it will take the 8 and 9
 * digits under some circumstances.  We'll just have to live with it.
 */
void set_umask()
{
  int mask, result;

  result = sscanf(optarg, "%o", &mask);
  if ((result != 1) || (mask > 07777) || (mask < 0)) {
    error("bad umask value");
    exit(1);
  }

  umask(mask);
}

/* Add an argument to the commands that we will call.  Called once for
   every argument. */
void add_argument(char *newarg)
{
  if (argcount + 1 >= argsize) {
    argsize = argsize ? argsize * 2 : 4;
    args = realloc(args, argsize * (sizeof(char *)));
    if (!args) {
      error("failed to reallocate memory for arguments: %s", strerror(errno));
      exit(1);
    }
  }
  args[argcount++] = newarg;
  args[argcount] = 0;
}

/* True or false? Is this a valid filename? */
int valid_name(const struct dirent *d)
{
    char         *s;
    unsigned int  retval;

    s = (char *)&(d->d_name);

    if (regex_mode == RUNPARTS_ERE)
        retval = !regexec(&customre, s, 0, NULL, 0);

    else if (regex_mode == RUNPARTS_LSBSYSINIT) {

        if (!regexec(&hierre, s, 0, NULL, 0))
            retval = regexec(&excsre, s, 0, NULL, 0);

	else
            retval = !regexec(&tradre, s, 0, NULL, 0);

    } else {
        if (!regexec(&classicalre, s, 0, NULL, 0)) {
            retval = regexec(&excsre, s, 0, NULL, 0);
		}
	}

    return retval;
}

/* Execute a file */
void run_part(char *progname)
{
  int result, waited;
  int pid, r;
  int pout[2], perr[2];

  waited = 0;

  if (report_mode && (pipe(pout) || pipe(perr))) {
    error("pipe: %s", strerror(errno));
    exit(1);
  }
  if ((pid = fork()) < 0) {
    error("failed to fork: %s", strerror(errno));
    exit(1);
  }
  else if (!pid) {
    restore_signals();
    if (new_session_mode)
      setsid();
    if (report_mode) {
      if (dup2(pout[1], STDOUT_FILENO) == -1 ||
	  dup2(perr[1], STDERR_FILENO) == -1) {
	error("dup2: %s", strerror(errno));
	exit(1);
      }
      close(pout[0]);
      close(perr[0]);
      close(pout[1]);
      close(perr[1]);
    }
    args[0] = progname;
    execv(progname, args);
    error("failed to exec %s: %s", progname, strerror(errno));
    exit(1);
  }

  if (report_mode) {
    fd_set set;
    sigset_t tempmask;
    struct timespec zero_timeout;
    struct timespec *the_timeout;
    int max, printflag;
    ssize_t c;
    char buf[4096];

    sigemptyset(&tempmask);
    sigprocmask(0, NULL, &tempmask);
    sigdelset(&tempmask, SIGCHLD);

    memset(&zero_timeout, 0, sizeof(zero_timeout));
    the_timeout = NULL;

    close(pout[1]);
    close(perr[1]);
    max = pout[0] > perr[0] ? pout[0] + 1 : perr[0] + 1;
    printflag = 0;

    while (pout[0] >= 0 || perr[0] >= 0) {
      if (!waited) {
        r = waitpid(pid, &result, WNOHANG);
        if (r == -1) {
          error("waitpid: %s", strerror(errno));
          exit(1);
        }
        if (r != 0 && (WIFEXITED(result) || WIFSIGNALED(result))) {
          /* If the process dies, set a zero timeout. Rarely, some processes
           * leak file descriptors (e.g., by starting a naughty daemon).
           * select() would wait forever since the pipes wouldn't close.
           * We loop, with a zero timeout, until there's no data left, then
           * give up. This shouldn't affect non-leaky processes. */
          waited = 1;
          the_timeout = &zero_timeout;
        }
      }

      FD_ZERO(&set);
      if (pout[0] >= 0)
        FD_SET(pout[0], &set);
      if (perr[0] >= 0)
        FD_SET(perr[0], &set);
      r = pselect(max, &set, 0, 0, the_timeout, &tempmask);

      if (r < 0) {
        if (errno == EINTR)
            continue;

        error("select: %s", strerror(errno));
        exit(1);
      }
      else if (r > 0) {
	/* If STDOUT or STDERR get closed / full, we still run to completion
	 * (and just ignore that we can't output process output any more).
	 * Perhaps we should instead kill the child process we are running
	 * if that happens.
	 * For now partial writes are not retried to complete - that can
	 * and should be done, but needs care to ensure that we don't hang
	 * if the fd doesn't accept more data ever - or we need to decide that
	 * waiting is the appropriate thing to do.
	 */
	int ignored;
	if (pout[0] >= 0 && FD_ISSET(pout[0], &set)) {
	  c = read(pout[0], buf, sizeof(buf));
	  if (c > 0) {
	    if (!printflag) {
	      printf("%s:\n", progname);
	      fflush(stdout);
	      printflag = 1;
	    }
	    ignored = write(STDOUT_FILENO, buf, c);
	  }
	  else if (c == 0) {
	    close(pout[0]);
	    pout[0] = -1;
	  }
	  else if (c < 0) {
	    close(pout[0]);
	    pout[0] = -1;
	    error("failed to read from stdout pipe: %s", strerror (errno)); 
	  }
	}
	if (perr[0] >= 0 && FD_ISSET(perr[0], &set)) {
	  c = read(perr[0], buf, sizeof(buf));
	  if (c > 0) {
	    if (!printflag) {
	      fprintf(stderr, "%s:\n", progname);
	      fflush(stderr);
	      printflag = 1;
	    }
	    ignored = write(STDERR_FILENO, buf, c);
	  }
	  else if (c == 0) {
	    close(perr[0]);
	    perr[0] = -1;
	  }
	  else if (c < 0) {
	    close(perr[0]);
	    perr[0] = -1;
	    error("failed to read from error pipe: %s", strerror (errno)); 
	  }
	}
      }
      else if (r == 0 && waited) {
        /* Zero timeout, no data left. */
        close(perr[0]);
        perr[0] = -1;
        close(pout[0]);
        pout[0] = -1;
      }
      else {
	/* assert(FALSE): select was called with infinite timeout, so
	   it either returns successfully or is interrupted */
      }				/*if */
    }				/*while */
  }

  if (!waited) {
    r = waitpid(pid, &result, 0);

    if (r == -1) {
		  error("waitpid: %s", strerror(errno));
			exit(1);
    }
  }

  if (WIFEXITED(result) && WEXITSTATUS(result)) {
    error("%s exited with return code %d", progname, WEXITSTATUS(result));
    exitstatus = 1;
  }
  else if (WIFSIGNALED(result)) {
    error("%s exited because of uncaught signal %d", progname,
	  WTERMSIG(result));
    exitstatus = 1;
  }
}

static void handle_signal(int s)
{
    /* Do nothing */
}

/* Catch SIGCHLD with an empty function to interrupt select() */
static void catch_signals()
{
    struct sigaction act;
    sigset_t set;

    memset(&act, 0, sizeof(act));
    act.sa_handler = handle_signal;
    act.sa_flags = SA_NOCLDSTOP;
    sigaction(SIGCHLD, &act, NULL);

    sigemptyset(&set);
    sigaddset(&set, SIGCHLD);
    sigprocmask(SIG_BLOCK, &set, NULL);
}

/* Unblock signals before execing a child */
static void restore_signals()
{
    sigset_t set;
    sigemptyset(&set);
    sigaddset(&set, SIGCHLD);
    sigprocmask(SIG_UNBLOCK, &set, NULL);
}

/* Find the parts to run & call run_part() */
void run_parts(char *dirname)
{
  struct dirent **namelist;
  char *filename;
  size_t filename_length, dirname_length;
  int entries, i, result;
  struct stat st;

  /* dirname + "/" */
  dirname_length = strlen(dirname) + 1;
  /* dirname + "/" + ".." + "\0" (This will save one realloc.) */
  filename_length = dirname_length + 2 + 1;
  if (!(filename = malloc(filename_length))) {
    error("failed to allocate memory for path: %s", strerror(errno));
    exit(1);
  }
  strcpy(filename, dirname);
  strcat(filename, "/");

  /* scandir() isn't POSIX, but it makes things easy. */
  entries = scandir(dirname, &namelist, valid_name, alphasort);
  if (entries < 0) {
    error("failed to open directory %s: %s", dirname, strerror(errno));
    exit(1);
  }

  i = reverse_mode ? 0 : entries;
  for (i = reverse_mode ? (entries - 1) : 0;
       reverse_mode ? (i >= 0) : (i < entries); reverse_mode ? i-- : i++) {
    if (filename_length < dirname_length + strlen(namelist[i]->d_name) + 1) {
      filename_length = dirname_length + strlen(namelist[i]->d_name) + 1;
      if (!(filename = realloc(filename, filename_length))) {
	error("failed to reallocate memory for path: %s", strerror(errno));
	exit(1);
      }
    }
    strcpy(filename + dirname_length, namelist[i]->d_name);

    strcpy(filename, dirname);
    strcat(filename, "/");
    strcat(filename, namelist[i]->d_name);

    result = stat(filename, &st);
    if (result < 0) {
      error("failed to stat component %s: %s", filename, strerror(errno));
      if (exit_on_error_mode) {
        exit(1);
      }
      else
        continue;
    }

    if (S_ISREG(st.st_mode)) {
      if (!access(filename, X_OK)) {
	if (test_mode) {
	  printf("%s\n", filename);
	}
	else if (list_mode) {
	  if (!access(filename, R_OK))
	    printf("%s\n", filename);
	}
	else {
	  if (verbose_mode)
	    if (argcount) {
	      char **a = args;

	      fprintf(stderr, "run-parts: executing %s", filename);
	      while(*(++a))
		fprintf(stderr, " %s", *a);
	      fprintf(stderr, "\n");
	    } else {
	      fprintf(stderr, "run-parts: executing %s\n", filename);
	    }
	  run_part(filename);
	  if (exitstatus != 0 && exit_on_error_mode) return;
	}
      }
      else if (!access(filename, R_OK)) {
	if (list_mode) {
	  printf("%s\n", filename);
	}
      }
      else if (S_ISLNK(st.st_mode)) {
	if (!list_mode) {
	  error("run-parts: component %s is a broken symbolic link\n",filename);
	  exitstatus = 1;
	}
      }
    }
    else if (!S_ISDIR(st.st_mode)) {
      if (!list_mode) {
	error("run-parts: component %s is not an executable plain file\n",
	       filename);
	exitstatus = 1;
      }
    }

    free(namelist[i]);
  }
  free(namelist);
  free(filename);
}

/* Process options */
int main(int argc, char *argv[])
{
  custom_ere = NULL;
  umask(022);
  add_argument(0);

  for (;;) {
    int c;
    int option_index = 0;

    static struct option long_options[] = {
      {"test", 0, &test_mode, 1},
      {"list", 0, &list_mode, 1},
      {"verbose", 0, 0, 'v'},
      {"report", 0, &report_mode, 1},
      {"reverse", 0, &reverse_mode, 1},
      {"umask", 1, 0, 'u'},
      {"arg", 1, 0, 'a'},
      {"help", 0, 0, 'h'},
      {"version", 0, 0, 'V'},
      {"lsbsysinit", 0, &regex_mode, RUNPARTS_LSBSYSINIT},
      {"regex", 1, &regex_mode, RUNPARTS_ERE},
      {"exit-on-error", 0, &exit_on_error_mode, 1},
      {"new-session", 0, &new_session_mode, 1},
      {0, 0, 0, 0}
    };

    c = getopt_long(argc, argv, "u:ha:vV", long_options, &option_index);
    if (c == EOF)
      break;
    switch (c) {
    case 0:
      if(option_index==10) { /* hardcoding this will lead to trouble */
        custom_ere = strdup(optarg);
      }
      break;
    case 'u':
      set_umask();
      break;
    case 'a':
      add_argument(optarg);
      break;
    case 'h':
      usage();
      break;
    case 'v':
      verbose_mode = 1;
      break;
    case 'V':
      version();
      break;
    default:
      fprintf(stderr, "Try `run-parts --help' for more information.\n");
      exit(1);
    }
  }

  /* We require exactly one argument: the directory name */
  if (optind != (argc - 1)) {
    error("missing operand");
    fprintf(stderr, "Try `run-parts --help' for more information.\n");
    exit(1);
  } else if (list_mode && test_mode) {
    error("--list and --test can not be used together");
    fprintf(stderr, "Try `run-parts --help' for more information.\n");
    exit(1);
  } else {
    catch_signals();
    regex_compile_pattern();
    run_parts(argv[optind]);
    regex_clean();

    free(args);
    free(custom_ere);

    return exitstatus;
  }
}

/*
 * Compile patterns used by the application
 *
 * In order for a string to be matched by a pattern, this pattern must be
 * compiled with the regcomp function. If an error occurs, the application
 * exits and displays the error.
 */
static void
regex_compile_pattern (void)
{
    int      err;
    regex_t *pt_regex;

    if (regex_mode == RUNPARTS_ERE) {

        if ((err = regcomp(&customre, custom_ere,
                    REG_EXTENDED | REG_NOSUB)) != 0)
            pt_regex = &customre;

    } else if (regex_mode == RUNPARTS_LSBSYSINIT) {

        if ( (err = regcomp(&hierre, "^_?([a-z0-9_.]+-)+[a-z0-9]+$",
                    REG_EXTENDED | REG_NOSUB)) != 0)
            pt_regex = &hierre;

        else if ( (err = regcomp(&excsre, "^[a-z0-9-].*(\.rpm(save|new|orig)|~|,v)$",
                    REG_EXTENDED | REG_NOSUB)) != 0)
            pt_regex = &excsre;

        else if ( (err = regcomp(&tradre, "^[a-z0-9][a-z0-9-]*$", REG_NOSUB))
                    != 0)
            pt_regex = &tradre;

    } else if ( (err = regcomp(&classicalre, "^.+$",
                    REG_EXTENDED | REG_NOSUB)) != 0)
			pt_regex = &classicalre;
        else if ( (err = regcomp(&excsre, "^[.]|(\.rpm(save|new|orig)|~|,v)$",
                    REG_EXTENDED | REG_NOSUB)) != 0)
            pt_regex = &excsre;

    if (err != 0) {
        fprintf(stderr, "Unable to build regexp: %s", \
                            regex_get_error(err, pt_regex));
        exit(1);
    }
}

/*
 * Get a regex error.
 *
 * This function allocates a buffer to store the regex error description.
 * If a buffer cannot be allocated, then the use of xmalloc will end the
 * program.
 *
 * @errcode: return error code from a one of the regex functions
 * @compiled: compile pattern which causes the failure
 *
 * It returns a pointer on the current regex error description.
 */
static char *
regex_get_error(int errcode, regex_t *compiled)
{
    size_t  length;
    char     *buf;

    length = regerror(errcode, compiled, NULL, 0);
    buf    = malloc(length);
    if (buf == 0) {
        error("Virtual memory exhausted\n");
        exit(1);
    }

    regerror(errcode, compiled, buf, length);

    return buf;
}

/*
 * Clean the compiled patterns according to the current regex_mode
 */
static void
regex_clean(void)
{
    if (regex_mode == RUNPARTS_ERE)
        regfree(&customre);

    else if (regex_mode == RUNPARTS_LSBSYSINIT) {
        regfree(&hierre);
        regfree(&excsre);
        regfree(&tradre);

    } else {
        regfree(&classicalre);
        regfree(&excsre);
	}
}
