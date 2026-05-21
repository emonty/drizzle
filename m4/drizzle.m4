dnl  Copyright (C) 2009 Sun Microsystems, Inc.
dnl This file is free software; Sun Microsystems, Inc.
dnl gives unlimited permission to copy and/or distribute it,
dnl with or without modifications, as long as this notice is preserved.

dnl Test whether madvise() is declared in C++ code.
AC_DEFUN([LOCAL_MADVISE],
    [AC_PREREQ([2.63])dnl
    AC_LANG_PUSH([C++])
    AC_CHECK_DECLS([madvise],[],[],[AC_INCLUDES_DEFAULT[
#if HAVE_SYS_MMAN_H
# include <sys/types.h>
# include <sys/mman.h>
#endif
      ]])
    AC_LANG_POP([C++])
    ])

AC_DEFUN([PANDORA_CANONICAL_VERSION],[0.175])

AC_DEFUN([PANDORA_MSG_ERROR],[
  AS_IF([test "x${pandora_cv_skip_requires}" != "xno"],[
    AC_MSG_ERROR($1)
  ],[
    AC_MSG_WARN($1)
  ])
])

AC_DEFUN([PANDORA_BLOCK_BAD_OPTIONS],[
  AS_IF([test "x${prefix}" = "x"],[
    PANDORA_MSG_ERROR([--prefix requires an argument])
  ])
])

dnl The single build-setup macro for Drizzle. It replaces the Pandora
dnl PANDORA_CANONICAL_TARGET orchestration: the build targets one OS
dnl (Linux) and one compiler (GCC), so the argument parsing that used to
dnl select require-cxx / version-from-vc / visibility behaviour is gone
dnl and those answers are fixed here.
AC_DEFUN([DRIZZLE_BUILD_SETUP],[
  PANDORA_BLOCK_BAD_OPTIONS

  # Prevent the build setup from injecting -O2 into CFLAGS; optimization
  # is controlled through AM_CFLAGS. A CFLAGS set on the command line
  # still takes precedence.
  AS_IF([test "x${ac_cv_env_CFLAGS_set}" = "x"],
        [CFLAGS=""])
  AS_IF([test "x${ac_cv_env_CXXFLAGS_set}" = "x"],
        [CXXFLAGS=""])

  m4_ifdef([AM_SILENT_RULES],[AM_SILENT_RULES([yes])])

  PANDORA_EXTENSIONS

  AC_REQUIRE([AC_PROG_CC])

  vc_changelog=yes
  PANDORA_VC_INFO_HEADER
  PANDORA_VERSION

  AC_REQUIRE([AC_PROG_CXX])
  PANDORA_EXTENSIONS
  AM_PROG_CC_C_O

  PANDORA_PLATFORM

  PANDORA_CHECK_CXX_STANDARD
  AS_IF([test "$ac_cv_cxx_stdcxx_98" = "no"],[
    PANDORA_MSG_ERROR([No working C++ Compiler has been found. ${PACKAGE} requires a C++ compiler that can handle C++98])
  ])
  AX_CXX_CINTTYPES

  PANDORA_CHECK_C_VERSION
  PANDORA_CHECK_CXX_VERSION

  AC_CACHE_CHECK([if system defines RUSAGE_THREAD], [ac_cv_rusage_thread],[
  AC_COMPILE_IFELSE([AC_LANG_PROGRAM(
      [[
#include <sys/time.h>
#include <sys/resource.h>
      ]],[[
      int x= RUSAGE_THREAD;
      ]])
    ],[
      ac_cv_rusage_thread=yes
    ],[
      ac_cv_rusage_thread=no
    ])
  ])
  AS_IF([test "$ac_cv_rusage_thread" = "no"],[
    AC_DEFINE([RUSAGE_THREAD], [RUSAGE_SELF],
      [Define if system doesn't define])
  ])

  LT_LIB_M

  PANDORA_OPTIMIZE

  LOCAL_MADVISE

  PANDORA_HAVE_GCC_ATOMICS

  PANDORA_HEADER_ASSERT

  PANDORA_WARNINGS

  PANDORA_ENABLE_DTRACE

  AC_LIB_PREFIX

  AX_PROG_SPHINX_BUILD

  AM_CPPFLAGS="-I\$(top_srcdir) -I\$(top_builddir) ${AM_CPPFLAGS}"

  PANDORA_USE_PIPE

  AH_TOP([
#ifndef __CONFIG_H__
#define __CONFIG_H__

#if defined(_FEATURES_H)
#error "You should include config.h as your first include file"
#endif

#include <config/top.h>
])
  mkdir -p config
  cat > config/top.h.stamp <<EOF_CONFIG_TOP

#if defined(_FILE_OFFSET_BITS)
# undef _FILE_OFFSET_BITS
#endif
EOF_CONFIG_TOP

  diff config/top.h.stamp config/top.h >/dev/null 2>&1 || mv config/top.h.stamp config/top.h
  rm -f config/top.h.stamp

  AH_BOTTOM([
#if defined(__cplusplus)
# include CSTDINT_H
# include CINTTYPES_H
#else
# include <stdint.h>
# include <inttypes.h>
#endif

#if !defined(HAVE_ULONG) && !defined(__USE_MISC)
# define HAVE_ULONG 1
typedef unsigned long int ulong;
#endif

/* Drizzle's networking code speaks the Win32 socket vocabulary; on a
 * POSIX target these map onto plain file-descriptor semantics. */
#define INVALID_SOCKET -1
#define SOCKET_ERROR -1
#define closesocket(a) close(a)
#define get_socket_errno() errno

#if defined(__cplusplus)
# if defined(DEBUG)
#  include <cassert>
#  include <cstddef>
# endif
template<typename To, typename From>
inline To implicit_cast(From const &f) {
  return f;
}
template<typename To, typename From>     // use like this: down_cast<T*>(foo);
inline To down_cast(From* f) {                   // so we only accept pointers
  // Ensures that To is a sub-type of From *.  This test is here only
  // for compile-time type checking, and has no overhead in an
  // optimized build at run-time, as it will be optimized away
  // completely.
  if (false) {
    implicit_cast<From*, To>(0);
  }

#if defined(DEBUG)
  assert(f == NULL || dynamic_cast<To>(f) != NULL);  // RTTI: debug mode only!
#endif
  return static_cast<To>(f);
}
#endif /* defined(__cplusplus) */

#endif /* __CONFIG_H__ */
  ])

  AM_CFLAGS="${AM_CFLAGS} ${CC_WARNINGS} ${CC_PROFILING} ${CC_COVERAGE}"
  AM_CXXFLAGS="${AM_CXXFLAGS} ${CXX_WARNINGS} ${CC_PROFILING} ${CC_COVERAGE}"

  AC_SUBST([AM_CFLAGS])
  AC_SUBST([AM_CXXFLAGS])
  AC_SUBST([AM_CPPFLAGS])
  AC_SUBST([AM_LDFLAGS])

])

AC_DEFUN([PANDORA_EXTENSIONS],[
  m4_ifdef([AC_USE_SYSTEM_EXTENSIONS],
    [AC_REQUIRE([AC_USE_SYSTEM_EXTENSIONS])],
    [AC_REQUIRE([AC_GNU_SOURCE])])
])

AC_DEFUN([gl_USE_SYSTEM_EXTENSIONS],[
  AC_REQUIRE([PANDORA_EXTENSIONS])
])

dnl Use -pipe to keep the compiler from spilling temp files to disk.
AC_DEFUN([PANDORA_USE_PIPE],[
  AS_IF([test "$GCC" = "yes"],[
    AC_CACHE_CHECK([for working -pipe], [pandora_cv_use_pipe], [
      AC_COMPILE_IFELSE([AC_LANG_SOURCE([[
#include <stdio.h>

int main(int argc, char** argv)
{
  (void) argc; (void) argv;
  return 0;
}
      ]])],
      [pandora_cv_use_pipe=yes],
      [pandora_cv_use_pipe=no])
    ])
    AS_IF([test "$pandora_cv_use_pipe" = "yes"],[
      AM_CFLAGS="-pipe ${AM_CFLAGS}"
      AM_CXXFLAGS="-pipe ${AM_CXXFLAGS}"
    ])
  ])
])

dnl Check whether to enable assertions.
AC_DEFUN([PANDORA_HEADER_ASSERT],[
  AC_CHECK_HEADERS(assert.h)
  AC_MSG_CHECKING([whether to enable assertions])
  AC_ARG_ENABLE([assert],
    [AS_HELP_STRING([--disable-assert],
       [Turn off assertions])],
    [ac_cv_assert="no"],
    [ac_cv_assert="yes"])
  AC_MSG_RESULT([$ac_cv_assert])

  AS_IF([test "$ac_cv_assert" = "no"],
    [AC_DEFINE(NDEBUG, 1, [Define to 1 if assertions should be disabled.])])
])

dnl Check for GCC atomic builtins.
AC_DEFUN([PANDORA_HAVE_GCC_ATOMICS],[
  AC_CACHE_CHECK(
    [whether the compiler provides atomic builtins],
    [ac_cv_gcc_atomic_builtins],
    [AC_LINK_IFELSE(
      [AC_LANG_PROGRAM([],[[
        int foo= -10; int bar= 10;
        if (!__sync_fetch_and_add(&foo, bar) || foo)
          return -1;
        bar= __sync_lock_test_and_set(&foo, bar);
        if (bar || foo != 10)
          return -1;
        bar= __sync_val_compare_and_swap(&bar, foo, 15);
        if (bar)
          return -1;
        return 0;
        ]])],
      [ac_cv_gcc_atomic_builtins=yes],
      [ac_cv_gcc_atomic_builtins=no])])

  AS_IF([test "x$ac_cv_gcc_atomic_builtins" = "xyes"],[
    AC_DEFINE(HAVE_GCC_ATOMIC_BUILTINS, 1,
              [Define to 1 if compiler provides atomic builtins.])
  ])
])
