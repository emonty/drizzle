dnl  Copyright (C) 2009 Sun Microsystems, Inc.
dnl This file is free software; Sun Microsystems, Inc.
dnl gives unlimited permission to copy and/or distribute it,
dnl with or without modifications, as long as this notice is preserved.

dnl AC_PANDORA_WARNINGS([less-warnings|warnings-always-on])
dnl   less-warnings turn on a limited set of warnings
dnl   warnings-always-on always set warnings=error regardless of tarball/vc

dnl @TODO: remove less-warnings option as soon as Drizzle is clean enough to
dnl        allow it
 
AC_DEFUN([PANDORA_WARNINGS],[
  m4_define([PW_LESS_WARNINGS],[no])
  m4_define([PW_WARN_ALWAYS_ON],[no])
  ifdef([m4_define],,[define([m4_define],   defn([define]))])
  ifdef([m4_undefine],,[define([m4_undefine],   defn([undefine]))])
  m4_foreach([pw_arg],[$*],[
    m4_case(pw_arg,
      [less-warnings],[
        m4_undefine([PW_LESS_WARNINGS])
        m4_define([PW_LESS_WARNINGS],[yes])
      ],
      [warnings-always-on],[
        m4_undefine([PW_WARN_ALWAYS_ON])
        m4_define([PW_WARN_ALWAYS_ON],[yes])
    ]) 
  ])

  dnl Drizzle always builds with -Werror. The pandora convention of relaxing
  dnl this for tarball builds is obsolete -- there are no tarball users.
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

  AS_IF([test "$GCC" = "yes"],[

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


	 
    AS_IF([test "$ac_cv_warnings_as_errors" = "yes"],[
      W_FAIL="-Werror"
      SPHINX_WARNINGS="-W"
      dnl INTLTOOL_WARNINGS="yes"
    ])

    AC_CACHE_CHECK([whether it is safe to use -fdiagnostics-show-option],
      [ac_cv_safe_to_use_fdiagnostics_show_option_],
      [save_CFLAGS="$CFLAGS"
       CFLAGS="-fdiagnostics-show-option ${AM_CFLAGS} ${CFLAGS}"
       AC_COMPILE_IFELSE(
         [AC_LANG_PROGRAM([],[])],
         [ac_cv_safe_to_use_fdiagnostics_show_option_=yes],
         [ac_cv_safe_to_use_fdiagnostics_show_option_=no])
       CFLAGS="$save_CFLAGS"])

    AS_IF([test "$ac_cv_safe_to_use_fdiagnostics_show_option_" = "yes"],
          [
            F_DIAGNOSTICS_SHOW_OPTION="-fdiagnostics-show-option"
          ])

    NO_STRICT_ALIASING="-fno-strict-aliasing -Wno-strict-aliasing"
    NO_SHADOW="-Wno-shadow"

      m4_if(PW_LESS_WARNINGS,[no],[
        BASE_WARNINGS_FULL="${W_CONVERSION} -Wstrict-aliasing -Wswitch-enum "
        CC_WARNINGS_FULL="-Wswitch-default -Wswitch-enum -Wwrite-strings"
        CXX_WARNINGS_FULL="-Weffc++ -Wold-style-cast"
        NO_OLD_STYLE_CAST="-Wno-old-style-cast"
        NO_EFF_CXX="-Wno-effc++"
      ],[
        BASE_WARNINGS_FULL="${NO_STRICT_ALIASING}"
      ])

      AS_IF([test "${ac_cv_assert}" = "no"],
            [NO_UNUSED="-Wno-unused-variable -Wno-unused-parameter"])
  
      AC_CACHE_CHECK([whether it is safe to use -Wextra],
        [ac_cv_safe_to_use_Wextra_],
        [save_CFLAGS="$CFLAGS"
         CFLAGS="${W_FAIL} -pedantic -Wextra ${AM_CFLAGS} ${CFLAGS}"
         AC_COMPILE_IFELSE([
           AC_LANG_PROGRAM(
           [[
#include <stdio.h>
           ]], [[]])
        ],
        [ac_cv_safe_to_use_Wextra_=yes],
        [ac_cv_safe_to_use_Wextra_=no])
      CFLAGS="$save_CFLAGS"])

      BASE_WARNINGS="${W_FAIL} -pedantic -Wall -Wundef -Wshadow ${NO_UNUSED} ${F_DIAGNOSTICS_SHOW_OPTION} ${BASE_WARNINGS_FULL}"
      AS_IF([test "$ac_cv_safe_to_use_Wextra_" = "yes"],
            [BASE_WARNINGS="${BASE_WARNINGS} -Wextra"],
            [BASE_WARNINGS="${BASE_WARNINGS} -W"])
  
      AC_CACHE_CHECK([whether it is safe to use -Wformat],
        [ac_cv_safe_to_use_wformat_],
        [save_CFLAGS="$CFLAGS"
         dnl Use -Werror here instead of ${W_FAIL} so that we don't spew
         dnl conversion warnings to all the tarball folks
         CFLAGS="-Wformat -Werror -pedantic ${AM_CFLAGS} ${CFLAGS}"
         AC_COMPILE_IFELSE(
           [AC_LANG_PROGRAM([[
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
void foo();
void foo()
{
  uint64_t test_u= 0;
  printf("This is a %" PRIu64 "test\n", test_u);
}
           ]],[[
foo();
           ]])],
           [ac_cv_safe_to_use_wformat_=yes],
           [ac_cv_safe_to_use_wformat_=no])
         CFLAGS="$save_CFLAGS"])
      AS_IF([test "$ac_cv_safe_to_use_wformat_" = "yes"],[
        BASE_WARNINGS="${BASE_WARNINGS} -Wformat -Wno-format-nonliteral -Wno-format-security"
        BASE_WARNINGS_FULL="${BASE_WARNINGS_FULL} -Wformat=2 -Wno-format-nonliteral -Wno-format-security"
        ],[
        BASE_WARNINGS="${BASE_WARNINGS} -Wno-format"
        BASE_WARNINGS_FULL="${BASE_WARNINGS_FULL} -Wno-format"
      ])


 
      AC_CACHE_CHECK([whether it is safe to use -Wconversion],
        [ac_cv_safe_to_use_wconversion_],
        [save_CFLAGS="$CFLAGS"
         dnl Use -Werror here instead of ${W_FAIL} so that we don't spew
         dnl conversion warnings to all the tarball folks
         CFLAGS="-Wconversion -Werror -pedantic ${AM_CFLAGS} ${CFLAGS}"
         AC_COMPILE_IFELSE(
           [AC_LANG_PROGRAM([[
#include <stdbool.h>
void foo(bool a)
{
  (void)a;
}
           ]],[[
foo(0);
           ]])],
           [ac_cv_safe_to_use_wconversion_=yes],
           [ac_cv_safe_to_use_wconversion_=no])
         CFLAGS="$save_CFLAGS"])
  
      AS_IF([test "$ac_cv_safe_to_use_wconversion_" = "yes"],
        [W_CONVERSION="-Wconversion"
        AC_CACHE_CHECK([whether it is safe to use -Wconversion with htons],
          [ac_cv_safe_to_use_Wconversion_],
          [save_CFLAGS="$CFLAGS"
           dnl Use -Werror here instead of ${W_FAIL} so that we don't spew
           dnl conversion warnings to all the tarball folks
           CFLAGS="-Wconversion -Werror -pedantic ${AM_CFLAGS} ${CFLAGS}"
           AC_COMPILE_IFELSE(
             [AC_LANG_PROGRAM(
               [[
#include <netinet/in.h>
               ]],[[
uint16_t x= htons(80);
               ]])],
             [ac_cv_safe_to_use_Wconversion_=yes],
             [ac_cv_safe_to_use_Wconversion_=no])
           CFLAGS="$save_CFLAGS"])
  
        AS_IF([test "$ac_cv_safe_to_use_Wconversion_" = "no"],
              [NO_CONVERSION="-Wno-conversion"])
      ])

      CC_WARNINGS="${BASE_WARNINGS} -Wstrict-prototypes -Wmissing-prototypes -Wredundant-decls -Wmissing-declarations -Wcast-align ${CC_WARNINGS_FULL}"
      CXX_WARNINGS="${BASE_WARNINGS} -Woverloaded-virtual -Wnon-virtual-dtor -Wctor-dtor-privacy -Wno-long-long ${CXX_WARNINGS_FULL}"

      AC_CACHE_CHECK([whether it is safe to use -Wmissing-declarations from C++],
        [ac_cv_safe_to_use_Wmissing_declarations_],
        [AC_LANG_PUSH(C++)
         save_CXXFLAGS="$CXXFLAGS"
         CXXFLAGS="-Werror -pedantic -Wmissing-declarations ${AM_CXXFLAGS}"
         AC_COMPILE_IFELSE([
           AC_LANG_PROGRAM(
           [[
#include <stdio.h>
           ]], [[]])
        ],
        [ac_cv_safe_to_use_Wmissing_declarations_=yes],
        [ac_cv_safe_to_use_Wmissing_declarations_=no])
        CXXFLAGS="$save_CXXFLAGS"
        AC_LANG_POP()
      ])
      AS_IF([test "$ac_cv_safe_to_use_Wmissing_declarations_" = "yes"],
            [CXX_WARNINGS="${CXX_WARNINGS} -Wmissing-declarations"])
  
      AC_CACHE_CHECK([whether it is safe to use -Wframe-larger-than],
        [ac_cv_safe_to_use_Wframe_larger_than_],
        [AC_LANG_PUSH(C++)
         save_CXXFLAGS="$CXXFLAGS"
         CXXFLAGS="-Werror -pedantic -Wframe-larger-than=32768 ${AM_CXXFLAGS}"
         AC_COMPILE_IFELSE([
           AC_LANG_PROGRAM(
           [[
#include <stdio.h>
           ]], [[]])
        ],
        [ac_cv_safe_to_use_Wframe_larger_than_=yes],
        [ac_cv_safe_to_use_Wframe_larger_than_=no])
        CXXFLAGS="$save_CXXFLAGS"
        AC_LANG_POP()
      ])
      AS_IF([test "$ac_cv_safe_to_use_Wframe_larger_than_" = "yes"],
            [CXX_WARNINGS="${CXX_WARNINGS} -Wframe-larger-than=32768"])
  
      AC_CACHE_CHECK([whether it is safe to use -Wlogical-op],
        [ac_cv_safe_to_use_Wlogical_op_],
        [save_CFLAGS="$CFLAGS"
         CFLAGS="${W_FAIL} -pedantic -Wlogical-op ${AM_CFLAGS} ${CFLAGS}"
         AC_COMPILE_IFELSE([
           AC_LANG_PROGRAM(
           [[
#include <stdio.h>
           ]], [[]])
        ],
        [ac_cv_safe_to_use_Wlogical_op_=yes],
        [ac_cv_safe_to_use_Wlogical_op_=no])
      CFLAGS="$save_CFLAGS"])
      AS_IF([test "$ac_cv_safe_to_use_Wlogical_op_" = "yes"],
            [CC_WARNINGS="${CC_WARNINGS} -Wlogical-op"])
  
      AC_CACHE_CHECK([whether it is safe to use -Wredundant-decls from C++],
        [ac_cv_safe_to_use_Wredundant_decls_],
        [AC_LANG_PUSH(C++)
         save_CXXFLAGS="${CXXFLAGS}"
         CXXFLAGS="${W_FAIL} -pedantic -Wredundant-decls ${AM_CXXFLAGS}"
         AC_COMPILE_IFELSE(
           [AC_LANG_PROGRAM([
template <typename E> struct C { void foo(); };
template <typename E> void C<E>::foo() { }
template <> void C<int>::foo();
            AC_INCLUDES_DEFAULT])],
            [ac_cv_safe_to_use_Wredundant_decls_=yes],
            [ac_cv_safe_to_use_Wredundant_decls_=no])
         CXXFLAGS="${save_CXXFLAGS}"
         AC_LANG_POP()])
      AS_IF([test "$ac_cv_safe_to_use_Wredundant_decls_" = "yes"],
            [CXX_WARNINGS="${CXX_WARNINGS} -Wredundant-decls"],
            [CXX_WARNINGS="${CXX_WARNINGS} -Wno-redundant-decls"])

      AC_CACHE_CHECK([whether it is safe to use -Wattributes from C++],
        [ac_cv_safe_to_use_Wattributes_],
        [AC_LANG_PUSH(C++)
         save_CXXFLAGS="${CXXFLAGS}"
         CXXFLAGS="${W_FAIL} -pedantic -Wattributes -fvisibility=hidden ${AM_CXXFLAGS}"
         AC_COMPILE_IFELSE(
           [AC_LANG_PROGRAM([
#include <google/protobuf/message.h>
#include <google/protobuf/descriptor.h>


const ::google::protobuf::EnumDescriptor* Table_TableOptions_RowType_descriptor();
enum Table_TableOptions_RowType {
  Table_TableOptions_RowType_ROW_TYPE_DEFAULT = 0,
  Table_TableOptions_RowType_ROW_TYPE_FIXED = 1,
  Table_TableOptions_RowType_ROW_TYPE_DYNAMIC = 2,
  Table_TableOptions_RowType_ROW_TYPE_COMPRESSED = 3,
  Table_TableOptions_RowType_ROW_TYPE_REDUNDANT = 4,
  Table_TableOptions_RowType_ROW_TYPE_COMPACT = 5,
  Table_TableOptions_RowType_ROW_TYPE_PAGE = 6
};

namespace google {
namespace protobuf {
template <>
inline const EnumDescriptor* GetEnumDescriptor<Table_TableOptions_RowType>() {
  return Table_TableOptions_RowType_descriptor();
}
}
}
            ])],
            [ac_cv_safe_to_use_Wattributes_=yes],
            [ac_cv_safe_to_use_Wattributes_=no])
          CXXFLAGS="${save_CXXFLAGS}"
          AC_LANG_POP()])
      AC_CACHE_CHECK([whether it is safe to use -Wno-attributes],
        [ac_cv_safe_to_use_Wno_attributes_],
        [save_CFLAGS="$CFLAGS"
         CFLAGS="${W_FAIL} -pedantic -Wno_attributes_ ${AM_CFLAGS} ${CFLAGS}"
         AC_COMPILE_IFELSE([
           AC_LANG_PROGRAM(
           [[
#include <stdio.h>
           ]], [[]])
        ],
        [ac_cv_safe_to_use_Wno_attributes_=yes],
        [ac_cv_safe_to_use_Wno_attributes_=no])
      CFLAGS="$save_CFLAGS"])

      dnl GCC 3.4 doesn't have -Wno-attributes, so we can't turn them off
      dnl by using that. 
      AS_IF([test "$ac_cv_safe_to_use_Wattributes_" != "yes"],[
        AS_IF([test "$ac_cv_safe_to_use_Wno_attributes_" = "yes"],[
          CC_WARNINGS="${CC_WARNINGS} -Wno-attributes"
          NO_ATTRIBUTES="-Wno-attributes"])])
  
  
      NO_REDUNDANT_DECLS="-Wno-redundant-decls"
      dnl TODO: Figure out a better way to deal with this:
      PROTOSKIP_WARNINGS="-Wno-effc++ -Wno-shadow -Wno-missing-braces ${NO_ATTRIBUTES}"
      NO_WERROR="-Wno-error"
      PERMISSIVE_WARNINGS="-Wno-error -Wno-unused-function -fpermissive"
      PERMISSIVE_C_WARNINGS="-Wno-error -Wno-redundant-decls"
      AS_IF([test "$host_vendor" = "apple"],[
        BOOSTSKIP_WARNINGS="-Wno-uninitialized"
      ])
  ])

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
