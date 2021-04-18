/*
 * Copyright (C) 2017 The Android Open Source Project
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

#ifndef _SECURE_POLL_H
#define _SECURE_POLL_H

#ifdef __cplusplus
extern "C" {
#endif

#include "common.h"

#include_next <poll.h>

#include <signal.h>

int __poll_chk(struct pollfd*, nfds_t, int, size_t);
int __ppoll_chk(struct pollfd*, nfds_t, const struct timespec*, const sigset_t*, size_t);

#if defined(__BIONIC_FORTIFY)
#define __bos_fd_count_trivially_safe(bos_val, fds, fd_count)              \
  __bos_dynamic_check_impl_and((bos_val), >=, (sizeof(*fds) * (fd_count)), \
                               (fd_count) <= __BIONIC_CAST(static_cast, nfds_t, -1) / sizeof(*fds))
__BIONIC_FORTIFY_INLINE
int poll(struct pollfd* const fds __pass_object_size, nfds_t fd_count, int timeout)
    __overloadable
    __clang_error_if(__bos_unevaluated_lt(__bos(fds), sizeof(*fds) * fd_count),
                     "in call to 'poll', fd_count is larger than the given buffer") {
#if __BIONIC_FORTIFY_RUNTIME_CHECKS_ENABLED
  size_t bos_fds = __bos(fds);
  if (!__bos_fd_count_trivially_safe(bos_fds, fds, fd_count)) {
    return __poll_chk(fds, fd_count, timeout, bos_fds);
  }
#endif
  return __call_bypassing_fortify(poll)(fds, fd_count, timeout);
}

__BIONIC_FORTIFY_INLINE
int ppoll(struct pollfd* const fds __pass_object_size, nfds_t fd_count, const struct timespec* timeout, const sigset_t* mask)
    __overloadable
    __clang_error_if(__bos_unevaluated_lt(__bos(fds), sizeof(*fds) * fd_count),
                     "in call to 'ppoll', fd_count is larger than the given buffer") {
#if __BIONIC_FORTIFY_RUNTIME_CHECKS_ENABLED
  size_t bos_fds = __bos(fds);
  if (!__bos_fd_count_trivially_safe(bos_fds, fds, fd_count)) {
    return __ppoll_chk(fds, fd_count, timeout, mask, bos_fds);
  }
#endif
  return __call_bypassing_fortify(ppoll)(fds, fd_count, timeout, mask);
}

#undef __bos_fd_count_trivially_safe

#endif

#ifdef __cplusplus
}
#endif

#endif
