dnl -*- mode: m4; c-basic-offset: 2; indent-tabs-mode: nil; -*-
dnl vim:expandtab:shiftwidth=2:tabstop=2:smarttab:
dnl   
dnl pandora-build: A pedantic build system
dnl Copyright (C) 2009 Sun Microsystems, Inc.
dnl This file is free software; Sun Microsystems
dnl gives unlimited permission to copy and/or distribute it,
dnl with or without modifications, as long as this notice is preserved.
dnl
dnl From Monty Taylor

AC_DEFUN([PANDORA_PLATFORM],[

  dnl Canonicalize the configuration name.

  AC_DEFINE_UNQUOTED([HOST_VENDOR], ["$host_vendor"],[Vendor of Build System])
  AC_DEFINE_UNQUOTED([HOST_OS], ["$host_os"], [OS of Build System])
  AC_DEFINE_UNQUOTED([HOST_CPU], ["$host_cpu"], [CPU of Build System])

  AC_DEFINE_UNQUOTED([TARGET_VENDOR], ["$target_vendor"],[Vendor of Target System])
  AC_DEFINE_UNQUOTED([TARGET_OS], ["$target_os"], [OS of Target System])
  AC_DEFINE_UNQUOTED([TARGET_CPU], ["$target_cpu"], [CPU of Target System])


  PANDORA_OPTIMIZE_BITFIELD=1

  TARGET_LINUX="true"
  AC_SUBST(TARGET_LINUX)
  AC_DEFINE([TARGET_OS_LINUX], [1], [Whether we build for Linux])

  AC_SUBST(PANDORA_OPTIMIZE_BITFIELD)

])
