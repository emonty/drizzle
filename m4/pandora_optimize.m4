dnl  Copyright (C) 2009 Sun Microsystems, Inc.
dnl This file is free software; Sun Microsystems, Inc.
dnl gives unlimited permission to copy and/or distribute it,
dnl with or without modifications, as long as this notice is preserved.

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
