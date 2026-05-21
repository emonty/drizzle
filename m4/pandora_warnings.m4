dnl  Copyright (C) 2009 Sun Microsystems, Inc.
dnl This file is free software; Sun Microsystems, Inc.
dnl gives unlimited permission to copy and/or distribute it,
dnl with or without modifications, as long as this notice is preserved.

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

  dnl The warning set GCC accepts on the target. Previously each flag was
  dnl gated behind an AC_COMPILE_IFELSE probe; on a single supported
  dnl compiler the outcome of every probe is fixed.
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
