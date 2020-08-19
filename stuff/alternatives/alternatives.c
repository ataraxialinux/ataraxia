/* Copyright 1997-2009 Red Hat, Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License, version 2,
 * as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA
 */
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <libintl.h>
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <limits.h>

#define FLAGS_TEST (1 << 0)
#define FLAGS_VERBOSE (1 << 1)
#define FLAGS_KEEP_MISSING (1 << 2)

#define FL_TEST(flags) ((flags)&FLAGS_TEST)
#define FL_VERBOSE(flags) ((flags)&FLAGS_VERBOSE)
#define FL_KEEP_MISSING(flags) ((flags)&FLAGS_KEEP_MISSING)

#define _(foo) gettext(foo)

struct linkSet {
    char *title;    /* print */
    char *facility; /* /usr/bin/lpr */
    char *target;   /* /usr/bin/lpr.LPRng */
};

struct alternative {
    int priority;
    struct linkSet master;
    struct linkSet *slaves;
    char *initscript;
    int numSlaves;
    char *family;
};

struct alternativeSet {
    enum alternativeMode { AUTO, MANUAL } mode;
    struct alternative *alts;
    int numAlts;
    int best, current;
    char *currentLink;
};

enum programModes {
    MODE_UNKNOWN,
    MODE_INSTALL,
    MODE_REMOVE,
    MODE_REMOVE_ALL,
    MODE_AUTO,
    MODE_DISPLAY,
    MODE_CONFIG,
    MODE_SET,
    MODE_SLAVE,
    MODE_VERSION,
    MODE_USAGE,
    MODE_LIST,
    MODE_ADD_SLAVE,
    MODE_REMOVE_SLAVE
};

static int usage(int rc) {
    printf(_("alternatives version %s - Copyright (C) 2001 Red Hat, Inc.\n"),
           VERSION);
    printf(_("This may be freely redistributed under the terms of the GNU "
             "Public License.\n\n"));
    printf(
        _("usage: alternatives --install <link> <name> <path> <priority>\n"));
    printf(_("                    [--initscript <service>]\n"));
    printf(_("                    [--family <family>]\n"));
    printf(_("                    [--slave <slave_link> <slave_name> <slave_path>]*\n"));
    printf(_("       alternatives --remove <name> <path>\n"));
    printf(_("       alternatives --auto <name>\n"));
    printf(_("       alternatives --config <name>\n"));
    printf(_("       alternatives --display <name>\n"));
    printf(_("       alternatives --set <name> <path>\n"));
    printf(_("       alternatives --list\n"));
    printf(_("       alternatives --remove-all <name>\n"));
    printf(_("       alternatives --add-slave <name> <path> <slave_link> <slave_name> <slave_path>\n"));
    printf(_("       alternatives --remove-slave <name> <path> <slave_name>\n"));
    printf(_("\n"));
    printf(_("common options: --verbose --test --help --usage --version "
             "--keep-missing\n"));
    printf(_("                --altdir <directory> --admindir <directory>\n"));

    exit(rc);
}

const char *normalize_path(const char *s) {
    if (s) {
        const char *src = s;
        char *dst = (char *)s;
        while ((*dst = *src) != '\0') {
            do {
                src++;
            } while (*dst == '/' && *src == '/');
            dst++;
        }
    }  
    return (const char *)s;
}

int streq(const char *a, const char *b) {
    if (a && b)
        return strcmp(a, b) ? 0 : 1;

    if (!a && !b)
        return 1;

    return 0;
}

int altBetter(struct alternative new, struct alternative old, char *family) {
    if (!family || (streq(old.family, family) == streq(new.family, family)))
        return new.priority > old.priority;

    if (streq(new.family, family))
        return 1;

    return 0;
}

static int isSystemd(char *initscript) {
    char tmppath[500];
    struct stat sbuf;

    snprintf(tmppath, 500, "/lib/systemd/system/%s.service", initscript);
    if (!stat(tmppath, &sbuf))
        return 1;

    snprintf(tmppath, 500, "/etc/systemd/system/%s.service", initscript);
    if (!stat(tmppath, &sbuf))
        return 1;

    return 0;
}

static void setupSingleArg(enum programModes *mode, const char ***nextArgPtr,
                           enum programModes newMode, char **title) {
    const char **nextArg = *nextArgPtr;

    if (*mode != MODE_UNKNOWN)
        usage(2);
    *mode = newMode;
    nextArg++;

    if (!*nextArg || **nextArg == '/')
        usage(2);
    *title = strdup(*nextArg);
    *nextArgPtr = nextArg + 1;
}

static void setupDoubleArg(enum programModes *mode, const char ***nextArgPtr,
                           enum programModes newMode, char **title,
                           char **target) {
    const char **nextArg = *nextArgPtr;

    if (*mode != MODE_UNKNOWN)
        usage(2);
    *mode = newMode;
    nextArg++;

    if (!*nextArg || **nextArg == '/')
        usage(2);
    *title = strdup(*nextArg);
    nextArg++;

    if (!*nextArg)
        usage(2);
    *target = strdup(normalize_path(*nextArg));
    *nextArgPtr = nextArg + 1;
}

static void setupTripleArg(enum programModes *mode, const char ***nextArgPtr,
                           enum programModes newMode, char **title,
                           char **target, char **slaveTitle) {
    const char **nextArg = *nextArgPtr;

    if (*mode != MODE_UNKNOWN)
        usage(2);
    *mode = newMode;
    nextArg++;

    if (!*nextArg || **nextArg == '/')
        usage(2);
    *title = strdup(*nextArg);
    nextArg++;

    if (!*nextArg)
        usage(2);
    *target = strdup(normalize_path(*nextArg));
    nextArg++;

    if (!*nextArg)
        usage(2);
    *slaveTitle = strdup(*nextArg);
    *nextArgPtr = nextArg + 1;
}

static void setupLinkSet(struct linkSet *set, const char ***nextArgPtr) {
    const char **nextArg = *nextArgPtr;

    if (!*nextArg || **nextArg != '/')
        usage(2);
    set->facility = strdup(normalize_path(*nextArg));
    nextArg++;

    if (!*nextArg || **nextArg == '/')
        usage(2);
    set->title = strdup(*nextArg);
    nextArg++;

    if (!*nextArg || **nextArg != '/')
        usage(2);
    set->target = strdup(normalize_path(*nextArg));
    *nextArgPtr = nextArg + 1;
}

char *parseLine(char **buf) {
    char *start = *buf;
    char *end;

    if (!*buf || !**buf)
        return NULL;

    end = strchr(start, '\n');
    if (!end) {
        *buf = start + strlen(start);
    } else {
        *buf = end + 1;
        *end = '\0';
    }

    while (isspace(*start) && *start)
        start++;

    return strdup(start);
}

/* Function to clean path form unnecessary backslashes
 * It will make from //abcd///efgh/ -> /abcd/efgh/
 */
void clean_path(char *path) {
    char *pr = path;  // reading pointer
    char *pw = path;  // writing pointer
  
    while (*pr) {
        *pw = *pr;
        pr++;
        if ((*pw == '/') && (*pr != '/')) {
            pw++;
        } else if (*pw != '/') {
            pw++;
        }
    }
    *pw = '\0';
}

static int readConfig(struct alternativeSet *set, const char *title,
                      const char *altDir, const char *stateDir, int flags) {
    char *path;
    int fd;
    int i;
    struct stat sb;
    char *buf;
    char *end;
    char *line;
    struct {
        char *facility;
        char *title;
    } *groups = NULL;
    int numGroups = 0;
    char linkBuf[PATH_MAX];

    set->alts = NULL;
    set->numAlts = 0;
    set->mode = AUTO;
    set->best = 0;
    set->current = -1;

    path = alloca(strlen(stateDir) + strlen(title) + 2);
    sprintf(path, "%s/%s", stateDir, title);

    clean_path(path);

    if (FL_VERBOSE(flags))
        printf(_("reading %s\n"), path);

    if ((fd = open(path, O_RDONLY)) < 0) {
        if (errno == ENOENT)
            return 3;
        fprintf(stderr, _("failed to open %s: %s\n"), path, strerror(errno));
        return 1;
    }

    fstat(fd, &sb);
    buf = alloca(sb.st_size + 1);
    if (read(fd, buf, sb.st_size) != sb.st_size) {
        close(fd);
        fprintf(stderr, _("failed to read %s: %s\n"), path, strerror(errno));
        return 1;
    }
    close(fd);
    buf[sb.st_size] = '\0';

    line = parseLine(&buf);
    if (!line) {
        fprintf(stderr, _("%s empty!\n"), path);
        return 1;
    }

    if (!strcmp(line, "auto")) {
        set->mode = AUTO;
    } else if (!strcmp(line, "manual")) {
        set->mode = MANUAL;
    } else {
        fprintf(stderr, _("bad mode on line 1 of %s\n"), path);
        return 1;
    }
    free(line);

    line = parseLine(&buf);
    if (!line || *line != '/') {
        fprintf(stderr, _("bad primary link in %s\n"), path);
        return 1;
    }

    groups = realloc(groups, sizeof(*groups));
    groups[0].title = strdup(title);
    groups[0].facility = line;
    numGroups = 1;

    line = parseLine(&buf);
    while (line && *line) {
        if (*line == '/') {
            fprintf(stderr, _("path %s unexpected in %s\n"), line, path);
            return 1;
        }

        groups = realloc(groups, sizeof(*groups) * (numGroups + 1));
        groups[numGroups].title = line;

        line = parseLine(&buf);
        if (!line || !*line) {
            fprintf(stderr, _("missing path for slave %s in %s\n"), line, path);
            return 1;
        }

        groups[numGroups++].facility = line;

        line = parseLine(&buf);
    }

    if (!line) {
        fprintf(stderr, _("unexpected end of file in %s\n"), path);
        return 1;
    }

    line = parseLine(&buf);
    while (line && *line) {
        set->alts = realloc(set->alts, (set->numAlts + 1) * sizeof(*set->alts));

        if (*line != '/') {
            fprintf(stderr, _("path to alternate expected in %s\n"), path);
            fprintf(stderr, _("unexpected line in %s: %s\n"), path, line);
            return 1;
        }

        set->alts[set->numAlts].master.facility = strdup(normalize_path(groups[0].facility));
        set->alts[set->numAlts].master.title = strdup(groups[0].title);
        set->alts[set->numAlts].master.target = line;
        set->alts[set->numAlts].numSlaves = numGroups - 1;
        if (numGroups > 1)
            set->alts[set->numAlts].slaves = malloc(
                (numGroups - 1) * sizeof(*set->alts[set->numAlts].slaves));
        else
            set->alts[set->numAlts].slaves = NULL;

        line = parseLine(&buf);
        set->alts[set->numAlts].priority = -1;
        set->alts[set->numAlts].initscript = NULL;
        set->alts[set->numAlts].family = NULL;

        if (line && line[0] == '@') {
            line++;
            end = strchr(line, '@');
            if (!end || (end == line)) {
                fprintf(stderr,
                        _("closing '@' missing or the family is empty in %s\n"),
                        path);
                fprintf(stderr, _("unexpected line in %s: %s\n"), path, line);
                return 1;
            }
            *end = '\0';
            set->alts[set->numAlts].family = strdup(line);
            line = end + 1;
        }

        set->alts[set->numAlts].priority = strtol(line, &end, 0);

        if (!end || (end == line)) {
            fprintf(stderr, _("numeric priority expected in %s\n"), path);
            fprintf(stderr, _("unexpected line in %s: %s\n"), path, line);
            return 1;
        }
        if (end) {
            while (*end && isspace(*end))
                end++;
            if (strlen(end)) {
                set->alts[set->numAlts].initscript = strdup(end);
            }
        }

        if (set->alts[set->numAlts].priority > set->alts[set->best].priority)
            set->best = set->numAlts;

        for (i = 1; i < numGroups; i++) {
            line = parseLine(&buf);
            if (line && strlen(line) && *line != '/') {
                fprintf(stderr, _("slave path expected in %s\n"), path);
                fprintf(stderr, _("unexpected line in %s: %s\n"), path, line);
                return 1;
            }

            set->alts[set->numAlts].slaves[i - 1].title =
                strdup(groups[i].title);
            set->alts[set->numAlts].slaves[i - 1].facility =
                strdup(normalize_path(groups[i].facility));
            set->alts[set->numAlts].slaves[i - 1].target =
                (line && strlen(line)) ? line : NULL;
        }

        set->numAlts++;

        line = parseLine(&buf);
    }

    while (line) {
        line = parseLine(&buf);
        if (line && *line) {
            fprintf(stderr, _("unexpected line in %s: %s\n"), path, line);
            return 1;
        }
    }

    sprintf(path, "%s/%s", altDir, set->alts[0].master.title);

    if (((i = readlink(path, linkBuf, sizeof(linkBuf) - 1)) < 0)) {
        fprintf(stderr, _("failed to read link %s: %s\n"),
                set->alts[0].master.facility, strerror(errno));
        return 2;
    }

    linkBuf[i] = '\0';

    for (i = 0; i < set->numAlts; i++)
        if (!strcmp(linkBuf, set->alts[i].master.target))
            break;

    if (i == set->numAlts) {
        set->mode = MANUAL;
        set->current = -1;
        if (FL_VERBOSE(flags))
            printf(
                _("link points to no alternative -- setting mode to manual\n"));
    } else {
        if (i != set->best && set->mode == AUTO) {
            set->mode = MANUAL;
            if (FL_VERBOSE(flags))
                printf(_("link changed -- setting mode to manual\n"));
        }
        set->current = i;
    }

    set->currentLink = strdup(normalize_path(linkBuf));

    return 0;
}

static int isLink(char *path) {
    struct stat sbuf;
    int rc = 0;

    rc = lstat(path, &sbuf);
    if (!rc) {
        rc = S_ISLNK(sbuf.st_mode);
    }
    return rc;
}

static int removeLinks(struct linkSet *l, const char *altDir, int flags) {
    char *sl;

    if (FL_KEEP_MISSING(flags))
        return 0;

    sl = alloca(strlen(altDir) + strlen(l->title) + 2);
    sprintf(sl, "%s/%s", altDir, l->title);
    if (FL_TEST(flags)) {
        printf(_("would remove %s\n"), sl);
    } else if (isLink(sl) && unlink(sl) && errno != ENOENT) {
        fprintf(stderr, _("failed to remove link %s: %s\n"), sl,
                strerror(errno));
        return 1;
    }
    if (FL_TEST(flags)) {
        printf(_("would remove %s\n"), l->facility);
    } else if (isLink(l->facility) && unlink(l->facility) && errno != ENOENT) {
        fprintf(stderr, _("failed to remove link %s: %s\n"), l->facility,
                strerror(errno));
        return 1;
    }

    return 0;
}

static int makeLinks(struct linkSet *l, const char *altDir, int flags) {
    char *sl;
    char buf[PATH_MAX];

    sl = alloca(strlen(altDir) + strlen(l->title) + 2);
    sprintf(sl, "%s/%s", altDir, l->title);

    if (isLink(l->facility)) {
        if (FL_TEST(flags)) {
            printf(_("would link %s -> %s\n"), l->facility, sl);
        } else {
            memset(buf, 0, sizeof(buf));
            readlink(l->facility, buf, sizeof(buf));

            if(!streq(sl, buf)) {
                unlink(l->facility);

                if (symlink(sl, l->facility)) {
                    fprintf(stderr, _("failed to link %s -> %s: %s\n"), l->facility,
                            sl, strerror(errno));
                    return 1;
                }
            }
        }
    } else
        fprintf(
            stderr,
            _("failed to link %s -> %s: %s exists and it is not a symlink\n"),
            l->facility, sl, l->facility);

    if (FL_TEST(flags)) {
        printf(_("would link %s -> %s\n"), sl, l->target);
    } else {
        memset(buf, 0, sizeof(buf));
        readlink(sl, buf, sizeof(buf));

        if(!streq(l->target, buf)) {
            if (unlink(sl) && errno != ENOENT) {
                fprintf(stderr, _("failed to remove link %s: %s\n"), sl,
                        strerror(errno));
                return 1;
            }

            if (symlink(l->target, sl)) {
                fprintf(stderr, _("failed to link %s -> %s: %s\n"), sl, l->target,
                        strerror(errno));
                return 1;
            }
        }
    }

    return 0;
}

static int writeState(struct alternativeSet *set, const char *altDir,
                      const char *stateDir, int forceLinks, int flags) {
    char *path;
    char *path2;
    int fd;
    FILE *f;
    int i, j;
    int rc = 0;
    struct alternative *alt;

    path = alloca(strlen(stateDir) + strlen(set->alts[0].master.title) + 6);
    sprintf(path, "%s/%s.new", stateDir, set->alts[0].master.title);

    path2 = alloca(strlen(stateDir) + strlen(set->alts[0].master.title) + 2);
    sprintf(path2, "%s/%s", stateDir, set->alts[0].master.title);

    if (FL_TEST(flags))
        fd = dup(1);
    else
        fd = open(path, O_RDWR | O_CREAT | O_EXCL, 0644);

    if (fd < 0) {
        if (errno == EEXIST)
            fprintf(stderr, _("%s already exists\n"), path);
        else
            fprintf(stderr, _("failed to create %s: %s\n"), path,
                    strerror(errno));
        return 1;
    }

    f = fdopen(fd, "w");
    fprintf(f, "%s\n", set->mode == AUTO ? "auto" : "manual");
    fprintf(f, "%s\n", set->alts[0].master.facility);
    for (i = 0; i < set->alts[0].numSlaves; i++) {
        fprintf(f, "%s\n", set->alts[0].slaves[i].title);
        fprintf(f, "%s\n", set->alts[0].slaves[i].facility);
    }
    fprintf(f, "\n");

    for (i = 0; i < set->numAlts; i++) {
        fprintf(f, "%s\n", set->alts[i].master.target);
        if (set->alts[i].family)
            fprintf(f, "@%s@", set->alts[i].family);
        fprintf(f, "%d", set->alts[i].priority);
        if (set->alts[i].initscript)
            fprintf(f, " %s", set->alts[i].initscript);
        fprintf(f, "\n");

        for (j = 0; j < set->alts[i].numSlaves; j++) {
            if (set->alts[i].slaves[j].target)
                fprintf(f, "%s", set->alts[i].slaves[j].target);
            fprintf(f, "\n");
        }
    }

    fclose(f);

    if (!FL_TEST(flags) && rename(path, path2)) {
        fprintf(stderr, _("failed to replace %s with %s: %s\n"), path2, path,
                strerror(errno));
        unlink(path);
        return 1;
    }

    if (set->mode == AUTO)
        set->current = set->best;

    alt = set->alts + (set->current > 0 ? set->current : 0);

    if (forceLinks || set->mode == AUTO) {
        rc |= makeLinks(&alt->master, altDir, flags);
        for (i = 0; i < alt->numSlaves; i++) {
            if (alt->slaves[i].target)
                rc |= makeLinks(alt->slaves + i, altDir, flags);
            else
                rc |= removeLinks(alt->slaves + i, altDir, flags);
        }
    }

    if (!FL_TEST(flags)) {
        if (alt->initscript) {
            if (isSystemd(alt->initscript)) {
                asprintf(&path, "/bin/systemctl -q is-enabled %s.service || "
                                "/bin/systemctl -q preset %s.service",
                         alt->initscript, alt->initscript);
                if (FL_VERBOSE(flags))
                    printf(_("running %s\n"), path);
                system(path);
                free(path);
            } else {
                asprintf(&path, "/sbin/chkconfig --add %s", alt->initscript);
                if (FL_VERBOSE(flags))
                    printf(_("running %s\n"), path);
                system(path);
                free(path);
            }
        }
        for (i = 0; i < set->numAlts; i++) {
            struct alternative *tmpalt = set->alts + i;
            if (tmpalt != alt && tmpalt->initscript) {
                if (isSystemd(tmpalt->initscript)) {
                    asprintf(&path, "/bin/systemctl -q disable %s.service",
                             tmpalt->initscript);
                    if (FL_VERBOSE(flags))
                        printf(_("running %s\n"), path);
                    system(path);
                    free(path);
                } else {
                    asprintf(&path, "/sbin/chkconfig --del %s",
                             tmpalt->initscript);
                    if (FL_VERBOSE(flags))
                        printf(_("running %s\n"), path);
                    system(path);
                    free(path);
                }
            }
        }
    }

    return rc;
}

static int linkCmp(const void *a, const void *b) {
    struct linkSet *one = (struct linkSet *)a, *two = (struct linkSet *)b;

    return strcmp(one->facility, two->facility);
}

static void fillTemplateFrom(struct alternative source,
                             struct alternative *template) {
    template->numSlaves = source.numSlaves;
    template->slaves = malloc(source.numSlaves * sizeof(struct linkSet));
    memcpy(template->slaves, source.slaves,
           source.numSlaves * sizeof(struct linkSet));
}

static void addSlaveToAlternative(struct alternative *template,
                                  struct linkSet slave) {
    int i;
    for (i = 0; i < template->numSlaves; i++) {
        if (streq(slave.facility, template->slaves[i].facility))
            break;
    }
    if (i == template->numSlaves) {
        template->slaves =
            realloc(template->slaves,
                    (template->numSlaves + 1) * sizeof(struct linkSet));

        memcpy(&template->slaves[i], &slave, sizeof(struct linkSet));

        template->numSlaves++;
    }
}

static int matchSlaves(struct alternativeSet *set,
                       struct alternative template) {
    int i, j, k;
    struct linkSet *newLinks;

    /* Sort the list for file legibility */
    qsort(template.slaves, template.numSlaves, sizeof(struct linkSet), linkCmp);

    /* need to match the slaves up; newLinks will parallel the original
       ordering */
    for (k = 0; k < set->numAlts; k++) {
        newLinks = malloc(sizeof(struct linkSet) * template.numSlaves);
        if (!newLinks)
            return 3;

        newLinks =
            memset(newLinks, 0, sizeof(struct linkSet) * template.numSlaves);

        for (j = 0; j < template.numSlaves; j++) {
            for (i = 0; i < set->alts[k].numSlaves; i++) {
                if (!strcmp(set->alts[k].slaves[i].title,
                            template.slaves[j].title))
                    break;
            }
            /* check if the slave in alternatives exist they have same name
             * and link*/
            if (i < set->alts[k].numSlaves) {
                if (strcmp(set->alts[k].slaves[i].facility,
                           template.slaves[j].facility)) {
                    fprintf(
                        stderr, _("link %s incorrect for slave %s (%s %s)\n"),
                        set->alts[k].slaves[i].facility,
                        set->alts[k].slaves[i].title,
                        template.slaves[j].facility, template.slaves[j].title);
                    return 2;
                }
                newLinks[j] = set->alts[k].slaves[i];
            } else {
                /* alternative did not have a record about a slave, let's add it
                 * with empty target */
                newLinks[j].title = template.slaves[j].title;
                newLinks[j].facility = template.slaves[j].facility;
                newLinks[j].target = NULL;
            }
        }
        /* memory link */
        free(set->alts[k].slaves);
        set->alts[k].slaves = newLinks;
        set->alts[k].numSlaves = template.numSlaves;
    }
    return 0;
}

static struct alternative *findAlternativeInSet(struct alternativeSet set,
                                                char *target) {
    int i;

    for (i = 0; i < set.numAlts; i++)
        if (streq(set.alts[i].master.target, target))
            return set.alts + i;
    return NULL;
}

static void removeUnusedSlavesFromTemplate(struct alternativeSet set,
                                           struct alternative *template,
                                           const char *altDir, int flags) {
    int i, j, k = 0;
    int found;

    if (set.numAlts == 0)
        return;

    for (i = 0; i < template->numSlaves; i++) {
        found = 0;
        for (j = 0; j < set.numAlts && !found; j++)
            for (k = 0; k < set.alts[j].numSlaves && !found; k++)
                if (streq(template->slaves[i].title,
                          set.alts[j].slaves[k].title) &&
                    set.alts[j].slaves[k].target)
                    found = 1;

        if (!found) {
            removeLinks(template->slaves + i, altDir, flags);
            template->numSlaves--;
            if (i != template->numSlaves) {
                template->slaves[i] = template->slaves[template->numSlaves];
                i--;
            }
        }
    }
}

static int removeSlave(char *title, char *target, char *slaveTitle,
                       const char *altDir, const char *stateDir, int flags) {
    struct alternative template, *a = NULL;
    struct alternativeSet set;
    int i;

    if (readConfig(&set, title, altDir, stateDir, flags))
        return 2;

    a = findAlternativeInSet(set, target);
    if (!a) {
        fprintf(stderr,
                _("%s has not been configured as an alternative for %s\n"),
                target, title);
        return 2;
    }

    for (i = 0; i < a->numSlaves; i++) {
        if (streq(a->slaves[i].title, slaveTitle)) {
            a->slaves[i].target = NULL;
            fillTemplateFrom(*a, &template);
            removeUnusedSlavesFromTemplate(set, &template, altDir, flags);
            matchSlaves(&set, template);
            if (writeState(&set, altDir, stateDir, 1, flags))
                return 2;
            return 0;
        }
    }
    fprintf(
        stderr,
        _("%s has not been configured as an slave alternative for %s (%s)\n"),
        slaveTitle, title, target);
    return 2;
}

static int addSlave(char *title, char *target, struct linkSet newSlave,
                    const char *altDir, const char *stateDir, int flags) {
    struct alternativeSet set;
    int i;
    struct alternative *a = NULL;
    struct alternative template;

    if (readConfig(&set, title, altDir, stateDir, flags))
        return 2;

    a = findAlternativeInSet(set, target);

    if (!a) {
        fprintf(stderr,
                _("%s has not been configured as an alternative for %s\n"),
                target, title);
        return 2;
    }

    fillTemplateFrom(*a, &template);
    addSlaveToAlternative(&template, newSlave);
    matchSlaves(&set, template);

    /* let's check if such slave already exists, in this case we will just
     * update the link */
    for (i = 0; i < a->numSlaves; i++) {
        if (streq(a->slaves[i].title, newSlave.title)) {
            a->slaves[i].target = newSlave.target;
            break;
        }
    }

    if (writeState(&set, altDir, stateDir, 1, flags))
        return 2;

    return 0;
}

static int addService(struct alternative newAlt, const char *altDir,
                      const char *stateDir, int flags) {
    struct alternativeSet set;
    struct alternative template;
    struct alternative *alt = NULL;

    int i, rc;
    int forceLinks = 0;

    if ((rc = readConfig(&set, newAlt.master.title, altDir, stateDir, flags)) &&
        rc != 3 && rc != 2)
        return 2;

    if (set.numAlts) {
        if (strcmp(newAlt.master.facility, set.alts[0].master.facility)) {
            fprintf(stderr, _("the primary link for %s must be %s\n"),
                    set.alts[0].master.title, set.alts[0].master.facility);
            return 2;
        }

        /* Determine the maximal set of slave links. */
        fillTemplateFrom(set.alts[0], &template);
        for (i = 0; i < newAlt.numSlaves; i++)
            addSlaveToAlternative(&template, newAlt.slaves[i]);

        alt = findAlternativeInSet(set, newAlt.master.target);

        if (alt) {
            *alt = newAlt;
            forceLinks = 1;
            /* Check for slaves no alternative provides */
            removeUnusedSlavesFromTemplate(set, &template, altDir, flags);
        } else {
            set.alts = realloc(set.alts, sizeof(*set.alts) * (set.numAlts + 1));
            set.alts[set.numAlts] = newAlt;
            if (set.alts[set.best].priority < newAlt.priority)
                set.best = set.numAlts;
            set.numAlts++;
        }

        if (matchSlaves(&set, template))
            return 2;
    } else {
        set.alts = realloc(set.alts, sizeof(*set.alts) * (set.numAlts + 1));
        set.alts[set.numAlts] = newAlt;
        if (set.alts[set.best].priority < newAlt.priority)
            set.best = set.numAlts;
        set.numAlts++;
    }

    if (writeState(&set, altDir, stateDir, forceLinks, flags))
        return 2;

    return 0;
}

static int displayService(char *title, const char *altDir, const char *stateDir,
                          int flags) {
    struct alternativeSet set;

    int alt;
    int slave;

    if (readConfig(&set, title, altDir, stateDir, flags))
        return 2;

    if (set.mode == AUTO)
        printf(_("%s - status is auto.\n"), title);
    else
        printf(_("%s - status is manual.\n"), title);

    printf(_(" link currently points to %s\n"), set.currentLink);

    for (alt = 0; alt < set.numAlts; alt++) {
        printf("%s - ", set.alts[alt].master.target);
        if (set.alts[alt].family)
            printf(_("family %s "), set.alts[alt].family);
        printf(_("priority %d\n"), set.alts[alt].priority);
        for (slave = 0; slave < set.alts[alt].numSlaves; slave++) {
            printf(_(" slave %s: %s\n"), set.alts[alt].slaves[slave].title,
                   set.alts[alt].slaves[slave].target);
        }
    }

    printf(_("Current `best' version is %s.\n"),
           set.alts[set.best].master.target);

    return 0;
}

static int autoService(char *title, const char *altDir, const char *stateDir,
                       int flags) {
    struct alternativeSet set;

    if (readConfig(&set, title, altDir, stateDir, flags))
        return 2;
    set.current = set.best;
    set.mode = AUTO;

    if (writeState(&set, altDir, stateDir, 0, flags))
        return 2;

    return 0;
}

static int configService(char *title, const char *altDir, const char *stateDir,
                         int flags) {
    struct alternativeSet set;
    int i;
    char choice[200];
    char *end = NULL;
    char *nicer = NULL;
    ;

    if (readConfig(&set, title, altDir, stateDir, flags))
        return 2;

    do {
        printf("\n");
        printf(ngettext(_("There is %d program that provides '%s'.\n"),
                        _("There are %d programs which provide '%s'.\n"),
                        set.numAlts),
               set.numAlts, set.alts[0].master.title);
        printf("\n");
        printf(_("  Selection    Command\n"));
        printf("-----------------------------------------------\n");

        for (i = 0; i < set.numAlts; i++) {
            if (set.alts[i].family)
                asprintf(&nicer, "%s (%s)", set.alts[i].family,
                         set.alts[i].master.target);
            printf("%c%c %-4d        %s\n", i == set.best ? '*' : ' ',
                   i == set.current ? '+' : ' ', i + 1,
                   nicer ?: set.alts[i].master.target);
            free(nicer);
            nicer = NULL;
            ;
        }
        printf("\n");
        printf(_("Enter to keep the current selection[+], or type selection "
                 "number: "));

        if (!fgets(choice, sizeof(choice), stdin)) {
            fprintf(stderr, _("\nerror reading choice\n"));
            return 2;
        }
        i = strtol(choice, &end, 0);
        if ((*end == '\n') && (end != choice)) {
            set.current = i - 1;
        }
    } while (!end || *end != '\n' || (set.current < 0) ||
             (set.current >= set.numAlts));

    set.mode = MANUAL;
    if (writeState(&set, altDir, stateDir, 1, flags))
        return 2;

    return 0;
}

static int setService(const char *title, const char *target, const char *altDir,
                      const char *stateDir, int flags) {
    struct alternativeSet set;
    int found = -1;
    int i, r;

    r = readConfig(&set, title, altDir, stateDir, flags);
    if (r) {
        if (r == 3) {
            fprintf(stderr,
                _("cannot access %s/%s: No such file or directory\n"), stateDir, title);
        }
        return 2;
    }

    for (i = 0; i < set.numAlts; i++)
        if (!strcmp(set.alts[i].master.target, target)) {
            found = i;
            break;
        }

    if (found == -1)
        for (i = 0; i < set.numAlts; i++)
            if (set.alts[i].family && !strcmp(set.alts[i].family, target))
                if (found == -1 ||
                    (set.alts[i].priority > set.alts[found].priority))
                    found = i;

    if (found == -1) {
        fprintf(stderr,
                _("%s has not been configured as an alternative for %s\n"),
                target, title);
        return 2;
    }

    set.current = found;
    set.mode = MANUAL;

    if (writeState(&set, altDir, stateDir, 1, flags))
        return 2;

    return 0;
}

static int removeService(const char *title, const char *target,
                         const char *altDir, const char *stateDir, int flags) {
    int rc;
    struct alternativeSet set;
    int i;
    char *family = NULL;
    int forceLinks = 0;

    if (readConfig(&set, title, altDir, stateDir, flags))
        return 2;

    for (i = 0; i < set.numAlts; i++)
        if (!strcmp(set.alts[i].master.target, target))
            break;

    if (i == set.numAlts) {
        fprintf(stderr,
                _("%s has not been configured as an alternative for %s\n"),
                target, title);
        return 2;
    }

    if (set.numAlts == 1) {
        char *path;

        rc = removeLinks(&set.alts[0].master, altDir, flags);

        for (i = 0; i < set.alts[0].numSlaves; i++)
            rc |= removeLinks(set.alts[0].slaves + i, altDir, flags);

        path = alloca(strlen(stateDir) + strlen(title) + 2);
        sprintf(path, "%s/%s", stateDir, title);
        if (FL_TEST(flags)) {
            printf(_("(would remove %s\n"), path);
        } else if (unlink(path)) {
            fprintf(stderr, _("failed to remove %s: %s\n"), path,
                    strerror(errno));
            rc |= 1;
        }

        if (rc)
            return 2;
        else
            return 0;
    }

    if (set.current != -1)
        family = set.alts[set.current].family;

    /* If the current link is what we're removing, reset it. */
    if (set.current == i)
        set.current = -1;

    /* Replace removed link set with last one */
    set.alts[i] = set.alts[set.numAlts - 1];
    if (set.current == (set.numAlts - 1))
        set.current = i;
    set.numAlts--;

    set.best = 0;
    for (i = 0; i < set.numAlts; i++)
        if (altBetter(set.alts[i], set.alts[set.best], family))
            set.best = i;

    if (set.current == -1) {
        if (!family || !streq(family, set.alts[set.best].family))
            set.mode = AUTO;
        else
            forceLinks = 1;
        set.current = set.best;
    }

    if (writeState(&set, altDir, stateDir, forceLinks, flags))
        return 2;

    return 0;
}

static int removeAll(const char *title, const char *altDir,
                     const char *stateDir, int flags) {
    struct alternativeSet set;

    int alt;
    int ret_val = 0;

    if (readConfig(&set, title, altDir, stateDir, flags))
        return 2;

    for (alt = 0; alt < set.numAlts; alt++) {
        ret_val += removeService(title, set.alts[alt].master.target, altDir,
                                 stateDir, flags);
    }

    return (ret_val > 1) ? 2 : 0;
}

static int listServices(const char *altDir, const char *stateDir, int flags) {
    DIR *dir;
    struct dirent *ent;
    struct alternativeSet set;
    int max_name = 0;
    int l;

    dir = opendir(stateDir);
    if (dir == NULL)
        return 2;

    while ((ent = readdir(dir)) != NULL) {
        if (!strcmp(ent->d_name, ".") || !strcmp(ent->d_name, ".."))
            continue;

        l = strlen(ent->d_name);
        max_name = max_name > l ? max_name : l;
    }

    rewinddir(dir);

    while ((ent = readdir(dir)) != NULL) {
        if (!strcmp(ent->d_name, ".") || !strcmp(ent->d_name, ".."))
            continue;

        if (readConfig(&set, ent->d_name, altDir, stateDir, flags))
            return 2;

        printf("%-*s\t%s\t%s\n", max_name, ent->d_name,
               set.mode == AUTO ? "auto  " : "manual", set.currentLink);
    }

    closedir(dir);

    return 0;
}

int main(int argc, const char **argv) {
    const char **nextArg;
    char *end;
    char *title, *target, *slaveTitle;
    enum programModes mode = MODE_UNKNOWN;
    struct alternative newAlt = {-1, {NULL, NULL, NULL}, NULL, NULL, 0, NULL};
    int flags = 0;
    char *altDir = "/etc/alternatives";
    char *stateDir = "/var/lib/alternatives";
    struct stat sb;
    struct linkSet newSet = {NULL, NULL, NULL};

    setlocale(LC_ALL, "");
    bindtextdomain("chkconfig", "/usr/share/locale");
    textdomain("chkconfig");

    if (!argv[1])
        return usage(2);

    nextArg = argv + 1;
    while (*nextArg) {
        if (!strcmp(*nextArg, "--install")) {
            if (mode != MODE_UNKNOWN && mode != MODE_SLAVE)
                usage(2);
            mode = MODE_INSTALL;
            nextArg++;

            setupLinkSet(&newAlt.master, &nextArg);

            if (!*nextArg)
                usage(2);
            newAlt.priority = strtol(*nextArg, &end, 0);
            if (!end || *end)
                usage(2);
            nextArg++;
        } else if (!strcmp(*nextArg, "--add-slave")) {
            setupDoubleArg(&mode, &nextArg, MODE_ADD_SLAVE, &title, &target);
            setupLinkSet(&newSet, &nextArg);
        } else if (!strcmp(*nextArg, "--remove-slave")) {
            setupTripleArg(&mode, &nextArg, MODE_REMOVE_SLAVE, &title, &target, &slaveTitle);
        } else if (!strcmp(*nextArg, "--slave")) {
            if (mode != MODE_UNKNOWN && mode != MODE_INSTALL)
                usage(2);
            if (mode == MODE_UNKNOWN)
                mode = MODE_SLAVE;
            nextArg++;

            newAlt.slaves = realloc(newAlt.slaves, sizeof(*newAlt.slaves) *
                                                       (newAlt.numSlaves + 1));
            setupLinkSet(newAlt.slaves + newAlt.numSlaves, &nextArg);
            newAlt.numSlaves++;
        } else if (!strcmp(*nextArg, "--initscript")) {
            if (mode != MODE_UNKNOWN && mode != MODE_INSTALL)
                usage(2);
            nextArg++;

            if (!*nextArg)
                usage(2);
            newAlt.initscript = strdup(*nextArg);
            nextArg++;
        } else if (!strcmp(*nextArg, "--family")) {
            if (mode != MODE_UNKNOWN && mode != MODE_INSTALL)
                usage(2);
            nextArg++;

            if (!*nextArg)
                usage(2);
            newAlt.family = strdup(*nextArg);

            if (strchr(newAlt.family, '@')) {
                printf(_("--family can't contain the symbol '@'\n"));
                usage(2);
            }
            nextArg++;
        } else if (!strcmp(*nextArg, "--remove")) {
            setupDoubleArg(&mode, &nextArg, MODE_REMOVE, &title, &target);
        } else if (!strcmp(*nextArg, "--remove-all")) {
            setupSingleArg(&mode, &nextArg, MODE_REMOVE_ALL, &title);
        } else if (!strcmp(*nextArg, "--set")) {
            setupDoubleArg(&mode, &nextArg, MODE_SET, &title, &target);
        } else if (!strcmp(*nextArg, "--auto")) {
            setupSingleArg(&mode, &nextArg, MODE_AUTO, &title);
        } else if (!strcmp(*nextArg, "--display")) {
            setupSingleArg(&mode, &nextArg, MODE_DISPLAY, &title);
        } else if (!strcmp(*nextArg, "--config")) {
            setupSingleArg(&mode, &nextArg, MODE_CONFIG, &title);
        } else if (!strcmp(*nextArg, "--help") ||
                   !strcmp(*nextArg, "--usage")) {
            if (mode != MODE_UNKNOWN)
                usage(2);
            mode = MODE_USAGE;
            nextArg++;
        } else if (!strcmp(*nextArg, "--test")) {
            flags |= FLAGS_TEST;
            nextArg++;
        } else if (!strcmp(*nextArg, "--verbose")) {
            flags |= FLAGS_VERBOSE;
            nextArg++;
        } else if (!strcmp(*nextArg, "--keep-missing")) {
            flags |= FLAGS_KEEP_MISSING;
            nextArg++;
        } else if (!strcmp(*nextArg, "--version")) {
            if (mode != MODE_UNKNOWN)
                usage(2);
            mode = MODE_VERSION;
            nextArg++;
        } else if (!strcmp(*nextArg, "--altdir")) {
            nextArg++;
            if (!*nextArg)
                usage(2);
            altDir = strdup(normalize_path(*nextArg));
            nextArg++;
        } else if (!strcmp(*nextArg, "--admindir")) {
            nextArg++;
            if (!*nextArg)
                usage(2);
            stateDir = strdup(normalize_path(*nextArg));
            nextArg++;
        } else if (!strcmp(*nextArg, "--list")) {
            if (mode != MODE_UNKNOWN)
                usage(2);
            mode = MODE_LIST;
            nextArg++;
        } else {
            usage(2);
        }
    }

    if (stat(altDir, &sb) || !S_ISDIR(sb.st_mode) || access(altDir, F_OK)) {
        fprintf(stderr, _("altdir %s invalid\n"), altDir);
        return (2);
    }

    if (stat(stateDir, &sb) || !S_ISDIR(sb.st_mode) || access(stateDir, F_OK)) {
        fprintf(stderr, _("admindir %s invalid\n"), stateDir);
        return (2);
    }

    switch (mode) {
    case MODE_UNKNOWN:
        usage(2);
    case MODE_USAGE:
        usage(0);
    case MODE_VERSION:
        printf(_("alternatives version %s\n"), VERSION);
        exit(0);
    case MODE_INSTALL:
        return addService(newAlt, altDir, stateDir, flags);
    case MODE_ADD_SLAVE:
        return addSlave(title, target, newSet, altDir, stateDir, flags);
    case MODE_REMOVE_SLAVE:
        return removeSlave(title, target, slaveTitle, altDir, stateDir, flags);
    case MODE_DISPLAY:
        return displayService(title, altDir, stateDir, flags);
    case MODE_AUTO:
        return autoService(title, altDir, stateDir, flags);
    case MODE_CONFIG:
        return configService(title, altDir, stateDir, flags);
    case MODE_SET:
        return setService(title, target, altDir, stateDir, flags);
    case MODE_REMOVE:
        return removeService(title, target, altDir, stateDir, flags);
    case MODE_REMOVE_ALL:
        return removeAll(title, altDir, stateDir, flags);
    case MODE_SLAVE:
        usage(2);
    case MODE_LIST:
        return listServices(altDir, stateDir, flags);
    }

    abort();
}
