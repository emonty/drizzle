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

dnl The single build-setup macro for Drizzle. The build targets one OS
dnl (Linux) and one compiler (GCC), so this macro takes no arguments:
dnl every setup choice for the target is hard-coded in the body below.
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

  AX_CXX_COMPILE_STDCXX([23],[ext],[mandatory])
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

dnl Record the build/target triplet in config.h. Linux is the only
dnl supported target, so TARGET_OS_LINUX is unconditional.
AC_DEFUN([PANDORA_PLATFORM],[
  AC_DEFINE_UNQUOTED([HOST_VENDOR], ["$host_vendor"],[Vendor of Build System])
  AC_DEFINE_UNQUOTED([HOST_OS], ["$host_os"], [OS of Build System])
  AC_DEFINE_UNQUOTED([HOST_CPU], ["$host_cpu"], [CPU of Build System])

  AC_DEFINE_UNQUOTED([TARGET_VENDOR], ["$target_vendor"],[Vendor of Target System])
  AC_DEFINE_UNQUOTED([TARGET_OS], ["$target_os"], [OS of Target System])
  AC_DEFINE_UNQUOTED([TARGET_CPU], ["$target_cpu"], [CPU of Target System])

  PANDORA_OPTIMIZE_BITFIELD=1
  AC_SUBST(PANDORA_OPTIMIZE_BITFIELD)

  TARGET_LINUX="true"
  AC_SUBST(TARGET_LINUX)
  AC_DEFINE([TARGET_OS_LINUX], [1], [Whether we build for Linux])
])

dnl Optimization and debug flags for GCC.
AC_DEFUN([PANDORA_OPTIMIZE],[
  AS_IF([test "$GCC" = "yes"],[

    dnl Once we can use a modern autoconf, we can replace the std=gnu99
    dnl here with AC_PROG_CC_C99.
    CC="${CC} -std=gnu99"

    AM_CPPFLAGS="-g ${AM_CPPFLAGS}"

    DEBUG_CFLAGS="-O0"
    DEBUG_CXXFLAGS="-O0"

    OPTIMIZE_CFLAGS="-O2"
    OPTIMIZE_CXXFLAGS="-O2"
  ])

  AC_ARG_WITH([debug],
    [AS_HELP_STRING([--with-debug],
       [Add debug code/turns off optimizations (yes|no) @<:@default=no@:>@])],
    [with_debug=$withval],
    [with_debug=no])
  AS_IF([test "$with_debug" = "yes"],[
    # Debugging. No optimization.
    AM_CFLAGS="${AM_CFLAGS} ${DEBUG_CFLAGS} -DDEBUG"
    AM_CXXFLAGS="${AM_CXXFLAGS} ${DEBUG_CXXFLAGS} -DDEBUG"
  ],[
    # Optimized version. No debug
    AM_CFLAGS="${AM_CFLAGS} ${OPTIMIZE_CFLAGS}"
    AM_CXXFLAGS="${AM_CXXFLAGS} ${OPTIMIZE_CXXFLAGS}"
  ])
])

AC_DEFUN([PANDORA_WARNINGS],[

  dnl Drizzle always builds with -Werror and a fixed GCC warning set.
  ac_cv_warnings_as_errors=yes

  AC_ARG_ENABLE([gcc-profile-mode],
      [AS_HELP_STRING([--enable-gcc-profile-mode],
         [Toggle gcc profile mode @<:@default=off@:>@])],
      [ac_gcc_profile_mode="$enableval"],
      [ac_gcc_profile_mode="no"])

  AC_ARG_ENABLE([profiling],
      [AS_HELP_STRING([--enable-profiling],
         [Toggle profiling @<:@default=off@:>@])],
      [ac_profiling="$enableval"],
      [ac_profiling="no"])

  AC_ARG_ENABLE([coverage],
      [AS_HELP_STRING([--enable-coverage],
         [Toggle coverage @<:@default=off@:>@])],
      [ac_coverage="$enableval"],
      [ac_coverage="no"])

  AS_IF([test "$ac_profiling" = "yes"],[
    CC_PROFILING="-pg"
    GCOV_LIBS="-pg -lgcov"
    save_LIBS="${LIBS}"
    LIBS=""
    AC_CHECK_LIB(c_p, read)
    LIBC_P="${LIBS}"
    LIBS="${save_LIBS}"
    AC_SUBST(LIBC_P)
  ],[
    CC_PROFILING=" "
  ])

  AS_IF([test "$ac_coverage" = "yes"],
        [
          CC_COVERAGE="--coverage"
          GCOV_LIBS="-lgcov"
        ])

  SPHINX_WARNINGS="-W"

  CC_WARNINGS="-Werror -pedantic -Wall -Wundef -Wshadow -fdiagnostics-show-option -fno-strict-aliasing -Wno-strict-aliasing -Wextra -Wformat -Wno-format-nonliteral -Wno-format-security -Wstrict-prototypes -Wmissing-prototypes -Wredundant-decls -Wmissing-declarations -Wcast-align -Wlogical-op"
  CXX_WARNINGS="-Werror -pedantic -Wall -Wundef -Wshadow -fdiagnostics-show-option -fno-strict-aliasing -Wno-strict-aliasing -Wextra -Wformat -Wno-format-nonliteral -Wno-format-security -Woverloaded-virtual -Wnon-virtual-dtor -Wctor-dtor-privacy -Wno-long-long -Wmissing-declarations -Wframe-larger-than=32768 -Wno-redundant-decls"

  dnl Relaxations used by individual Makefile.am files to compile third-party
  dnl or generated code that cannot meet the full warning set.
  NO_STRICT_ALIASING="-fno-strict-aliasing -Wno-strict-aliasing"
  NO_SHADOW="-Wno-shadow"
  NO_REDUNDANT_DECLS="-Wno-redundant-decls"
  NO_WERROR="-Wno-error"
  PROTOSKIP_WARNINGS="-Wno-effc++ -Wno-shadow -Wno-missing-braces"
  PERMISSIVE_WARNINGS="-Wno-error -Wno-unused-function -fpermissive"
  PERMISSIVE_C_WARNINGS="-Wno-error -Wno-redundant-decls"
  INNOBASE_SKIP_WARNINGS="-Wno-error=literal-suffix -Wno-error=shift-negative-value -Wno-error=implicit-fallthrough -Wno-error=format-overflow -Wno-error=unused-variable"

  AC_SUBST(NO_CONVERSION)
  AC_SUBST(NO_REDUNDANT_DECLS)
  AC_SUBST(NO_UNREACHED)
  AC_SUBST(NO_SHADOW)
  AC_SUBST(NO_STRICT_ALIASING)
  AC_SUBST(NO_EFF_CXX)
  AC_SUBST(NO_OLD_STYLE_CAST)
  AC_SUBST(PROTOSKIP_WARNINGS)
  AC_SUBST(INNOBASE_SKIP_WARNINGS)
  AC_SUBST(BOOSTSKIP_WARNINGS)
  AC_SUBST(PERMISSIVE_WARNINGS)
  AC_SUBST(PERMISSIVE_C_WARNINGS)
  AC_SUBST(NO_WERROR)
  AC_SUBST([GCOV_LIBS])
  AC_SUBST([SPHINX_WARNINGS])
  AC_SUBST([INTLTOOL_WARNINGS])

])

AC_DEFUN([PANDORA_VERSION],[
  PANDORA_HEX_VERSION=`echo $VERSION | sed 's|[\-a-z0-9]*$||' | \
    awk -F. '{printf "0x%0.2d%0.3d%0.3d", $[]1, $[]2, $[]3}'`
  AC_SUBST([PANDORA_HEX_VERSION])
])

dnl Record the compiler version strings for the configure summary.
AC_DEFUN([PANDORA_CHECK_C_VERSION],[
  AC_MSG_CHECKING([C Compiler version])
  CC_VERSION=`$CC --version | sed 1q`
  AC_MSG_RESULT([$CC_VERSION])
  AC_SUBST(CC_VERSION)
])

AC_DEFUN([PANDORA_CHECK_CXX_VERSION],[
  AC_MSG_CHECKING([C++ Compiler version])
  CXX_VERSION=`$CXX --version | sed 1q`
  AC_MSG_RESULT([$CXX_VERSION])
  AC_SUBST(CXX_VERSION)
])

AC_DEFUN([PANDORA_ENABLE_DTRACE],[
  AC_ARG_ENABLE([dtrace],
    [AS_HELP_STRING([--disable-dtrace],
            [Build with support for the DTRACE. @<:@default=on@:>@])],
    [ac_cv_enable_dtrace="$enableval"],
    [ac_cv_enable_dtrace="yes"])

  AS_IF([test "$ac_cv_enable_dtrace" = "yes"],[
    AC_CHECK_PROGS([DTRACE], [dtrace])
    AC_CHECK_HEADERS(sys/sdt.h)

    AS_IF([test "x$ac_cv_prog_DTRACE" = "xdtrace" -a "x${ac_cv_header_sys_sdt_h}" = "xyes"],[

      AC_CACHE_CHECK([if dtrace works],[ac_cv_dtrace_works],[
        cat >conftest.d <<_ACEOF
provider Example {
  probe increment(int);
};
_ACEOF
        $DTRACE -h -o conftest.h -s conftest.d 2>/dev/zero
        AS_IF([test $? -eq 0],[ac_cv_dtrace_works=yes],
          [ac_cv_dtrace_works=no])
        rm -f conftest.h conftest.d
      ])
      AS_IF([test "x$ac_cv_dtrace_works" = "xyes"],[
        AC_DEFINE([HAVE_DTRACE], [1], [Enables DTRACE Support])
      ])
      AC_CACHE_CHECK([if dtrace should instrument object files],
        [ac_cv_dtrace_needs_objects],[
          cat >conftest.d <<_ACEOF
provider Example {
  probe increment(int);
};
_ACEOF
          $DTRACE -G -o conftest.d.o -s conftest.d 2>/dev/zero
          AS_IF([test $? -eq 0],[ac_cv_dtrace_needs_objects=yes],
            [ac_cv_dtrace_needs_objects=no])
          rm -f conftest.d.o conftest.d
      ])
      AC_SUBST(DTRACEFLAGS)
      ac_cv_have_dtrace=yes
    ])])

AM_CONDITIONAL([HAVE_DTRACE], [test "x$ac_cv_dtrace_works" = "xyes"])
AM_CONDITIONAL([DTRACE_NEEDS_OBJECTS],
               [test "x$ac_cv_dtrace_needs_objects" = "xyes"])

])

AC_DEFUN([PANDORA_TEST_VC_DIR],[
  pandora_building_from_vc=no

  if test -d ".bzr" ; then
    pandora_building_from_bzr=yes
    pandora_building_from_vc=yes
  else
    pandora_building_from_bzr=no
  fi

  if test -d ".svn" ; then
    pandora_building_from_svn=yes
    pandora_building_from_vc=yes
  else
    pandora_building_from_svn=no
  fi

  if test -d ".hg" ; then
    pandora_building_from_hg=yes
    pandora_building_from_vc=yes
  else
    pandora_building_from_hg=no
  fi

  if test -d ".git" ; then
    pandora_building_from_git=yes
    pandora_building_from_vc=yes
  else
    pandora_building_from_git=no
  fi
])

AC_DEFUN([PANDORA_BUILDING_FROM_VC],[
  m4_syscmd(PANDORA_TEST_VC_DIR
    [
    vc_changelog=yes

    PANDORA_RELEASE_DATE=`date +%Y.%m`
    PANDORA_RELEASE_NODOTS_DATE=`date +%Y%m`

    # Set some defaults
    PANDORA_VC_REVNO="0"
    PANDORA_VC_REVID="unknown"
    PANDORA_VC_BRANCH="bzr-export"

    if test "${pandora_building_from_bzr}" = "yes"; then
      echo "# Grabbing changelog and version information from bzr"
      PANDORA_BZR_REVNO=`bzr revno`
      if test "x$PANDORA_BZR_REVNO" != "x${PANDORA_VC_REVNO}" ; then
        PANDORA_VC_REVNO="${PANDORA_BZR_REVNO}"
        PANDORA_VC_REVID=`bzr log -r-1 --show-ids | grep revision-id | cut -f2 -d' ' | head -1`
        PANDORA_VC_BRANCH=`bzr nick`
        # Check if this branch has just been tagged (not yet committed)
        PANDORA_VC_TAG=`bzr tags -r-1 | cut -f1 -d' ' | head -1`
        # If not, then check if we have checked out a branch where most recent commit
        # was tagged, and there are no further (uncommitted) changes in the branch.
        if test "x${PANDORA_VC_TAG}" = "x"; then
            if test `bzr diff | wc -l` = 0; then
                PANDORA_VC_TAG=`bzr tags -r-2 | cut -f1 -d' ' | head -1`
            fi
        fi
        PANDORA_VC_LATEST_TAG=`bzr tags --sort=time | grep -v '\?'| cut -f1 -d' '  | tail -1`
        if test "x${vc_changelog}" = "xyes"; then
          bzr log --gnu > ChangeLog
        fi
      fi
    elif test "${pandora_building_from_git}" = "yes"; then
      echo "# Grabbing changelog and version information from git"
      PANDORA_VC_REVID=`git rev-parse HEAD 2>/dev/null`
      PANDORA_VC_REVNO=`git rev-list --count HEAD 2>/dev/null`
      PANDORA_VC_BRANCH=`git rev-parse --abbrev-ref HEAD 2>/dev/null`
      # Tag pointing at HEAD: HEAD itself is a release. Most recent
      # ancestor tag otherwise: used to build a `<tag>.<revno>-snapshot`
      # version. `git describe --abbrev=0` yields the bare tag.
      PANDORA_VC_TAG=`git tag --points-at HEAD 2>/dev/null | head -1`
      PANDORA_VC_LATEST_TAG=`git describe --tags --abbrev=0 2>/dev/null`
      if test "x${vc_changelog}" = "xyes"; then
        git --no-pager log --pretty=format:"%h %an %ad  %s" > ChangeLog 2>/dev/null
      fi
    fi

    if ! test -d config ; then
      mkdir -p config
    fi

    if test "${pandora_building_from_bzr}" = "yes" -o "${pandora_building_from_git}" = "yes" -o ! -f config/pandora_vc_revinfo ; then
      cat > config/pandora_vc_revinfo.tmp <<EOF
PANDORA_VC_REVNO=${PANDORA_VC_REVNO}
PANDORA_VC_REVID=${PANDORA_VC_REVID}
PANDORA_VC_BRANCH=${PANDORA_VC_BRANCH}
PANDORA_VC_TAG=${PANDORA_VC_TAG}
PANDORA_VC_LATEST_TAG=${PANDORA_VC_LATEST_TAG}
PANDORA_RELEASE_DATE=${PANDORA_RELEASE_DATE}
PANDORA_RELEASE_NODOTS_DATE=${PANDORA_RELEASE_NODOTS_DATE}
EOF
      if ! diff config/pandora_vc_revinfo.tmp config/pandora_vc_revinfo >/dev/null 2>&1 ; then
        mv config/pandora_vc_revinfo.tmp config/pandora_vc_revinfo
      fi
      rm -f config/pandora_vc_revinfo.tmp
    fi
  ])
])

AC_DEFUN([_PANDORA_READ_FROM_FILE],[
  $1=`grep $1 $2 | cut -f2 -d=`
])

AC_DEFUN([PANDORA_VC_VERSION],[
  AC_REQUIRE([PANDORA_BUILDING_FROM_VC])

  PANDORA_TEST_VC_DIR

  AS_IF([test -f ${srcdir}/config/pandora_vc_revinfo],[
    _PANDORA_READ_FROM_FILE([PANDORA_VC_REVNO],${srcdir}/config/pandora_vc_revinfo)
    _PANDORA_READ_FROM_FILE([PANDORA_VC_REVID],${srcdir}/config/pandora_vc_revinfo)
    _PANDORA_READ_FROM_FILE([PANDORA_VC_BRANCH],
                            ${srcdir}/config/pandora_vc_revinfo)
    _PANDORA_READ_FROM_FILE([PANDORA_VC_TAG],
                            ${srcdir}/config/pandora_vc_revinfo)
    _PANDORA_READ_FROM_FILE([PANDORA_VC_LATEST_TAG],
                            ${srcdir}/config/pandora_vc_revinfo)
    _PANDORA_READ_FROM_FILE([PANDORA_RELEASE_DATE],
                            ${srcdir}/config/pandora_vc_revinfo)
    _PANDORA_READ_FROM_FILE([PANDORA_RELEASE_NODOTS_DATE],
                            ${srcdir}/config/pandora_vc_revinfo)
  ])
  AS_IF([test "x${PANDORA_VC_BRANCH}" != x"${PACKAGE}"],[
    PANDORA_RELEASE_COMMENT="${PANDORA_VC_BRANCH}"
  ],[
    PANDORA_RELEASE_COMMENT="trunk"
  ])

  AS_IF([test "x${PANDORA_VC_TAG}" != "x"],[
    PANDORA_RELEASE_VERSION="${PANDORA_VC_TAG}"
    # We now support release tags to append a descriptive tag -stable, -rc, -beta, -alpha, -milestone.
    # But for the release id we want to remove that.
    PANDORA_VC_TAG_JUST_NUMBERS=`echo ${PANDORA_VC_TAG} | sed -e 's/-stable//' -e 's/-rc//' -e 's/-beta//' -e 's/-alpha//' -e 's/-milestone//'`
    PANDORA_RELEASE_VERSION_JUST_NUMBERS="${PANDORA_VC_TAG_JUST_NUMBERS}"
    # For release id we make sure each part is at least 2 digits, prepended with 0 when necessary.
    # Example: 1.2.3 should end up as 10203.
    # The sed's from left to right:
    #  1) Make sure minor version has at least 2 digits (2 -> 02)
    #  2) Make sure build version has at least 2 digits (3 -> 03)
    #  3) Remove dots (1.02.03 -> 10203)
    changequote(<<, >>)dnl
    PANDORA_RELEASE_ID=`echo ${PANDORA_VC_TAG_JUST_NUMBERS} | sed -e 's/\.\([0-9]\)\./.0\1./' | sed -e 's/\.\([0-9]\)$/.0\1/' | sed 's/[^0-9]//g'`
    changequote([, ])dnl
  ],[
    AS_IF([test "x${PANDORA_VC_LATEST_TAG}" != "x"],[
      # We now support release tags to append a descriptive tag -stable, -rc, -beta, -alpha, -milestone.
      # Since this is just a snapshot build, we need to remove that.
      PANDORA_VC_LATEST_TAG_JUST_NUMBERS=`echo ${PANDORA_VC_LATEST_TAG} | sed -e 's/-stable//' -e 's/-rc//' -e 's/-beta//' -e 's/-alpha//' -e 's/-milestone//'`
      PANDORA_RELEASE_VERSION="${PANDORA_VC_LATEST_TAG_JUST_NUMBERS}.${PANDORA_VC_REVNO}-snapshot"
      PANDORA_RELEASE_VERSION_JUST_NUMBERS="${PANDORA_VC_LATEST_TAG_JUST_NUMBERS}.${PANDORA_VC_REVNO}"
      changequote(<<, >>)dnl
      PANDORA_RELEASE_ID=`echo ${PANDORA_VC_LATEST_TAG_JUST_NUMBERS} | sed -e 's/\.\([0-9]\)\./.0\1./' | sed -e 's/\.\([0-9]\)$/.0\1/' | sed 's/[^0-9]//g'`
      changequote([, ])dnl
    ],[
      PANDORA_RELEASE_VERSION="${PANDORA_RELEASE_DATE}.${PANDORA_VC_REVNO}"
      PANDORA_RELEASE_VERSION_JUST_NUMBERS="${PANDORA_RELEASE_VERSION}"
      changequote(<<, >>)dnl
      PANDORA_RELEASE_ID=`echo ${PANDORA_RELEASE_DATE} | sed 's/[^0-9]//g'`
      changequote([, ])dnl
    ])
  ])


  VERSION="${PANDORA_RELEASE_VERSION}"
  AC_DEFINE_UNQUOTED([PANDORA_RELEASE_VERSION],["${PANDORA_RELEASE_VERSION}"],
                     [The real version of the software])
  AC_SUBST(PANDORA_RELEASE_VERSION_JUST_NUMBERS)
  AC_SUBST(PANDORA_VC_REVNO)
  AC_SUBST(PANDORA_VC_REVID)
  AC_SUBST(PANDORA_VC_BRANCH)
  AC_SUBST(PANDORA_RELEASE_DATE)
  AC_SUBST(PANDORA_RELEASE_NODOTS_DATE)
  AC_SUBST(PANDORA_RELEASE_COMMENT)
  AC_SUBST(PANDORA_RELEASE_VERSION)
  AC_SUBST(PANDORA_RELEASE_ID)
])

AC_DEFUN([PANDORA_VC_INFO_HEADER],[
  AC_REQUIRE([PANDORA_VC_VERSION])
  m4_define([PANDORA_VC_PREFIX],m4_toupper(m4_normalize(AC_PACKAGE_NAME))[_])

  AC_DEFINE_UNQUOTED(PANDORA_VC_PREFIX[VC_REVNO], [$PANDORA_VC_REVNO], [Version control revision number])
  AC_DEFINE_UNQUOTED(PANDORA_VC_PREFIX[VC_REVID], ["$PANDORA_VC_REVID"], [Version control revision ID])
  AC_DEFINE_UNQUOTED(PANDORA_VC_PREFIX[VC_BRANCH], ["$PANDORA_VC_BRANCH"], [Version control branch name])
  AC_DEFINE_UNQUOTED(PANDORA_VC_PREFIX[RELEASE_DATE], ["$PANDORA_RELEASE_DATE"], [Release date of version control checkout])
  AC_DEFINE_UNQUOTED(PANDORA_VC_PREFIX[RELEASE_NODOTS_DATE], [$PANDORA_RELEASE_NODOTS_DATE], [Numeric formatted release date of checkout])
  AC_DEFINE_UNQUOTED(PANDORA_VC_PREFIX[RELEASE_COMMENT], ["$PANDORA_RELEASE_COMMENT"], [Set to trunk if the branch is the main $PACKAGE branch])
  AC_DEFINE_UNQUOTED(PANDORA_VC_PREFIX[RELEASE_VERSION], ["$PANDORA_RELEASE_VERSION"], [Release date and revision number of checkout])
  AC_DEFINE_UNQUOTED(PANDORA_VC_PREFIX[RELEASE_ID], [$PANDORA_RELEASE_ID], [Numeric formatted release date and revision number of checkout])
])
