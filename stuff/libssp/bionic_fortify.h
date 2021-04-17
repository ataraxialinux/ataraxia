/*
 * Copyright (C) 2016 The Android Open Source Project
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
 * OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 * AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
 * OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#pragma once

#undef _FORTIFY_SOURCE

#include <poll.h> // For struct pollfd.
#include <stdarg.h>
#include <stdlib.h>
#include <syslog.h>
#include <sys/select.h> // For struct fd_set.

#ifndef __predict_false
#define	__predict_false(exp)	__builtin_expect((exp) != 0, 0)
#endif

#ifndef __size_mul_overflow
#if __has_builtin(__builtin_umul_overflow) || __GNUC__ >= 5
#if defined(__LP64__)
#define __size_mul_overflow(a, b, result) __builtin_umull_overflow(a, b, result)
#else
#define __size_mul_overflow(a, b, result) __builtin_umul_overflow(a, b, result)
#endif
#else
extern __inline__ __always_inline __attribute__((gnu_inline))
int __size_mul_overflow(__SIZE_TYPE__ a, __SIZE_TYPE__ b, __SIZE_TYPE__ *result) {
    *result = a * b;
    static const __SIZE_TYPE__ mul_no_overflow = 1UL << (sizeof(__SIZE_TYPE__) * 4);
    return (a >= mul_no_overflow || b >= mul_no_overflow) && a > 0 && (__SIZE_TYPE__)-1 / a < b;
}
#endif
#endif

#ifndef __noreturn
#define __noreturn __attribute__((__noreturn__))
#endif

extern void __stack_chk_fail(void);
void __attribute__((visibility ("hidden"))) __stack_chk_fail_local(void) { __stack_chk_fail(); }

//
// LLVM can't inline variadic functions, and we don't want one definition of
// this per #include in libc.so, so no `static`.
//
inline void __fortify_fatal(const char* fmt, ...) {
  va_list args;
  va_start(args, fmt);
  syslog(LOG_CRIT, "FORTIFY: %s", fmt);
  va_end(args);
  __stack_chk_fail();
}

//
// Common helpers.
//

static inline void __check_fd_set(const char* fn, int fd, size_t set_size) {
  if (__predict_false(fd < 0)) {
    __fortify_fatal("%s: file descriptor %d < 0", fn, fd);
  }
  if (__predict_false(fd >= FD_SETSIZE)) {
    __fortify_fatal("%s: file descriptor %d >= FD_SETSIZE %d", fn, fd, FD_SETSIZE);
  }
  if (__predict_false(set_size < sizeof(fd_set))) {
    __fortify_fatal("%s: set size %zu is too small to be an fd_set", fn, set_size);
  }
}

static inline void __check_pollfd_array(const char* fn, size_t fds_size, nfds_t fd_count) {
  size_t pollfd_array_length = fds_size / sizeof(pollfd);
  if (__predict_false(pollfd_array_length < fd_count)) {
    __fortify_fatal("%s: %zu-element pollfd array too small for %u fds",
                    fn, pollfd_array_length, fd_count);
  }
}

static inline void __check_count(const char* fn, const char* identifier, size_t value) {
  if (__predict_false(value > SSIZE_MAX)) {
    __fortify_fatal("%s: %s %zu > SSIZE_MAX", fn, identifier, value);
  }
}

static inline void __check_buffer_access(const char* fn, const char* action,
                                         size_t claim, size_t actual) {
  if (__predict_false(claim > actual)) {
    __fortify_fatal("%s: prevented %zu-byte %s %zu-byte buffer", fn, claim, action, actual);
  }
}

#ifndef __GLIBC__
#define	__NBBY	8				/* number of bits in a byte */
typedef uint32_t __fd_mask;
#define __NFDBITS ((unsigned)(sizeof(__fd_mask) * __NBBY)) /* bits per mask */

static __inline void
__fd_set(int fd, fd_set *p)
{
	p->fds_bits[fd / __NFDBITS] |= (1U << (fd % __NFDBITS));
}
#define __FD_SET(n, p)	__fd_set((n), (p))

static __inline void
__fd_clr(int fd, fd_set *p)
{
	p->fds_bits[fd / __NFDBITS] &= ~(1U << (fd % __NFDBITS));
}
#define __FD_CLR(n, p)	__fd_clr((n), (p))

static __inline int
__fd_isset(int fd, const fd_set *p)
{
	return (p->fds_bits[fd / __NFDBITS] & (1U << (fd % __NFDBITS)));
}
#define __FD_ISSET(n, p)	__fd_isset((n), (p))

#endif
