dnl  Copyright (C) 2009 Sun Microsystems, Inc.
dnl This file is free software; Sun Microsystems, Inc.
dnl gives unlimited permission to copy and/or distribute it,
dnl with or without modifications, as long as this notice is preserved.

#--------------------------------------------------------------------
# Check for libpcre2
#--------------------------------------------------------------------


AC_DEFUN([_PANDORA_SEARCH_LIBPCRE],[
  PKG_CHECK_MODULES([PCRE2], [libpcre2-8], [
    ac_cv_libpcre=yes
    LIBPCRE="$PCRE2_LIBS"
    LTLIBPCRE="$PCRE2_LIBS"
    AM_CPPFLAGS="$AM_CPPFLAGS $PCRE2_CFLAGS"
    AC_DEFINE([HAVE_LIBPCRE], [1],
              [Define to 1 if libpcre2 is available])
  ],[
    ac_cv_libpcre=no
  ])

  AC_SUBST([LIBPCRE])
  AC_SUBST([LTLIBPCRE])
  AM_CONDITIONAL(HAVE_LIBPCRE, [test "x${ac_cv_libpcre}" = "xyes"])
])

AC_DEFUN([_PANDORA_HAVE_LIBPCRE],[

  AC_ARG_ENABLE([libpcre],
    [AS_HELP_STRING([--disable-libpcre],
      [Build with libpcre support @<:@default=on@:>@])],
    [ac_enable_libpcre="$enableval"],
    [ac_enable_libpcre="yes"])

  _PANDORA_SEARCH_LIBPCRE
])


AC_DEFUN([PANDORA_HAVE_LIBPCRE],[
  AC_REQUIRE([_PANDORA_HAVE_LIBPCRE])
])

AC_DEFUN([_PANDORA_REQUIRE_LIBPCRE],[
  ac_enable_libpcre="yes"
  _PANDORA_SEARCH_LIBPCRE

  AS_IF([test x$ac_cv_libpcre = xno],[
    PANDORA_MSG_ERROR([libpcre2 is required for ${PACKAGE}. On Debian this can be found in libpcre2-dev. On RedHat this can be found in pcre2-devel.])
  ])
])

AC_DEFUN([PANDORA_REQUIRE_LIBPCRE],[
  AC_REQUIRE([_PANDORA_REQUIRE_LIBPCRE])
])
