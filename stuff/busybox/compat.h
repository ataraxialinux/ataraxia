#include <stddef.h>
#include <stdarg.h>
#include <sys/types.h>

#define	__attribute__(x)
#define __dead		__attribute__((__noreturn__))
#define __pure		__attribute__((__const__))

#if !defined(DEF_WEAK)
#define DEF_WEAK(x)
#endif

extern const char* getprogname(void);
extern void setprogname(const char*);
void	*reallocarray(void *, size_t, size_t);
void		vwarnc(int, const char *, va_list)
			__attribute__((__format__ (printf, 2, 0)));
void		warnc(int, const char *, ...)
			__attribute__((__format__ (printf, 2, 3)));
__dead void		errc(int, int, const char *, ...)
			__attribute__((__format__ (printf, 3, 4)));
__dead void		verrc(int, int, const char *, va_list)
			__attribute__((__format__ (printf, 3, 0)));

int	strtofflags(char **, u_int32_t *, u_int32_t *);
void	*setmode(const char *);
mode_t	getmode(const void *, mode_t);
int	gid_from_group(const char *, gid_t *);
const char	*group_from_gid(gid_t, int);
int	uid_from_user(const char *, uid_t *);
const char	*user_from_uid(uid_t, int);
long long
	strtonum(const char *, long long, long long, const char **);
