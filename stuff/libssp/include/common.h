#ifndef _SECURE_COMMON_H
#define _SECURE_COMMON_H

#define __errorattr(msg) __attribute__((unavailable(msg)))
#define __warnattr(msg) __attribute__((deprecated(msg)))
#define __warnattr_real(msg) __attribute__((deprecated(msg)))
#define __enable_if(cond, msg) __attribute__((enable_if(cond, msg)))
#define __clang_error_if(cond, msg) __attribute__((diagnose_if(cond, msg, "error")))
#define __clang_warning_if(cond, msg) __attribute__((diagnose_if(cond, msg, "warning")))

#ifndef __printflike
#define	__printflike(fmtarg, firstvararg) \
	    __attribute__((__format__ (__printf__, fmtarg, firstvararg)))
#endif

#ifndef __overloadable
#define __overloadable __attribute__((overloadable))
#endif

#ifndef __RENAME
/* Used to rename functions so that the compiler emits a call to 'x' rather than the function this was applied to. */
#define __RENAME(x) __asm__(#x)
#endif

#if !defined(__LP64__) && defined(_FILE_OFFSET_BITS) && _FILE_OFFSET_BITS == 64
#  define __USE_FILE_OFFSET64 1
/*
 * Note that __RENAME_IF_FILE_OFFSET64 is only valid if the off_t and off64_t
 * functions were both added at the same API level because if you use this,
 * you only have one declaration to attach __INTRODUCED_IN to.
 */
#  define __RENAME_IF_FILE_OFFSET64(func) __RENAME(func)
#else
#  define __RENAME_IF_FILE_OFFSET64(func)
#endif

#if defined(__cplusplus)
#define __BIONIC_CAST(_k,_t,_v) (_k<_t>(_v))
#else
#define __BIONIC_CAST(_k,_t,_v) ((_t) (_v))
#endif

#define __BIONIC_FORTIFY_UNKNOWN_SIZE ((size_t) -1)

#if defined(_FORTIFY_SOURCE) && _FORTIFY_SOURCE > 0
/* FORTIFY can interfere with pattern-matching of clang-tidy/the static analyzer.  */
#  if !defined(__clang_analyzer__)
#    define __BIONIC_FORTIFY 1
/* ASAN has interceptors that FORTIFY's _chk functions can break.  */
#    if __has_feature(address_sanitizer)
#      define __BIONIC_FORTIFY_RUNTIME_CHECKS_ENABLED 0
#    else
#      define __BIONIC_FORTIFY_RUNTIME_CHECKS_ENABLED 1
#    endif
#  endif
#endif

#if defined(__BIONIC_FORTIFY)
#  if _FORTIFY_SOURCE == 2
#    define __bos_level 1
#  elif _FORTIFY_SOURCE == 3
#    define __bos_level 2
#  else
#    define __bos_level 0
#  endif
#else
#  define __bos_level 0
#endif

#if __bos_level == 2
#define __bosn(s, n) __builtin_dynamic_object_size((s), (n))
#define __bos(s) __bosn((s), __bos_level)
#else
#define __bosn(s, n) __builtin_object_size((s), (n))
#define __bos(s) __bosn((s), __bos_level)
#endif

#if defined(__BIONIC_FORTIFY)
#  define __bos0(s) __bosn((s), 0)
#  define __pass_object_size_n(n) __attribute__((pass_object_size(n)))
/*
 * FORTIFY'ed functions all have either enable_if or pass_object_size, which
 * makes taking their address impossible. Saying (&read)(foo, bar, baz); will
 * therefore call the unFORTIFYed version of read.
 */
#  define __call_bypassing_fortify(fn) (&fn)
/*
 * Because clang-FORTIFY uses overloads, we can't mark functions as `extern inline` without making
 * them available externally. FORTIFY'ed functions try to be as close to possible as 'invisible';
 * having stack protectors detracts from that (b/182948263).
 */
#  define __BIONIC_FORTIFY_INLINE static __inline__ __attribute__((no_stack_protector))

/*
 * We should use __BIONIC_FORTIFY_VARIADIC instead of __BIONIC_FORTIFY_INLINE
 * for variadic functions because compilers cannot inline them.
 * The __always_inline attribute is useless, misleading, and could trigger
 * clang compiler bug to incorrectly inline variadic functions.
 */
#  define __BIONIC_FORTIFY_VARIADIC static __inline__
/* Error functions don't have bodies, so they can just be static. */
#  define __BIONIC_ERROR_FUNCTION_VISIBILITY static __attribute__((unused))
#else
/* Further increase sharing for some inline functions */
#  define __pass_object_size_n(n)
#endif
#define __pass_object_size __pass_object_size_n(__bos_level)
#define __pass_object_size0 __pass_object_size_n(0)

/* Intended for use in unevaluated contexts, e.g. diagnose_if conditions. */
#define __bos_unevaluated_lt(bos_val, val) \
  ((bos_val) != __BIONIC_FORTIFY_UNKNOWN_SIZE && (bos_val) < (val))
#define __bos_unevaluated_le(bos_val, val) \
  ((bos_val) != __BIONIC_FORTIFY_UNKNOWN_SIZE && (bos_val) <= (val))
/* Intended for use in evaluated contexts. */
#define __bos_dynamic_check_impl_and(bos_val, op, index, cond) \
  ((bos_val) == __BIONIC_FORTIFY_UNKNOWN_SIZE ||                 \
   (__builtin_constant_p(index) && bos_val op index && (cond)))
#define __bos_dynamic_check_impl(bos_val, op, index) \
  __bos_dynamic_check_impl_and(bos_val, op, index, 1)
#define __bos_trivially_ge(bos_val, index) __bos_dynamic_check_impl((bos_val), >=, (index))
#define __bos_trivially_gt(bos_val, index) __bos_dynamic_check_impl((bos_val), >, (index))

/*
 * Used when we need to check for overflow when multiplying x and y. This
 * should only be used where __size_mul_overflow can not work, because it makes
 * assumptions that __size_mul_overflow doesn't (x and y are positive, ...),
 * *and* doesn't make use of compiler intrinsics, so it's probably slower than
 * __size_mul_overflow.
 */
#define __unsafe_check_mul_overflow(x, y) ((__SIZE_TYPE__)-1 / (x) < (y))

#endif
