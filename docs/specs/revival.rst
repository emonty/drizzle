.. _spec-revival:

==========================
Drizzle Revival (2026)
==========================

:Status: In progress
:Target endpoint: Ubuntu 26.04 LTS, multi-arch (amd64 + arm64) container
:Last updated: 2026-05

This spec is the load-bearing roadmap for reviving the Drizzle code base
from its 2013 state (Ubuntu 12.04 base, autotools + Pandora macro layer,
no working tests in CI) to a modern, single-target, container-first
database server.

A team of contributors (or subagents) executes this spec phase by phase.
Each phase has explicit Objective / Tasks / Done-when / Risks sections.
File paths and ``podman`` invocations are concrete; copy-paste is
expected.

.. contents:: Contents
   :local:
   :depth: 2


Context and goals
=================

Drizzle was last actively developed around 2013. The current state:

* ``configure.ac`` is at version 7.2; ~300 lines, plus a heavy "Pandora"
  m4 macro layer (~55 of 136 m4 files).
* 82 plugins are registered via ``config/pandora-plugin.ini`` and a
  ``config/pandora-plugin`` Python enumeration script.
* The repo's ``Dockerfile`` builds against Ubuntu 12.04 (Precise, long
  EOL) using ``bindep-rs`` to install ``bindep.txt``. The build runs;
  tests do not.
* Sphinx docs are well established (65 RST files); a ``Doxyfile`` also
  exists but Sphinx is the primary documentation surface.

We are reviving the project with a small set of strong constraints:

* **Single OS target, ever.** Whatever the ``Dockerfile`` ``FROM``
  line says is the *only* environment we support. No portability code
  paths.
* **Two CPU architectures**: ``linux/amd64`` and ``linux/arm64``. Both
  are 64-bit little-endian. Eventually shipped as a multi-arch podman
  manifest.
* **Keep autotools.** ``automake`` makefiles are loved; ``make
  distcheck`` must keep working even if we never ship a source tarball.
* **podman everywhere.** Every documented build/test invocation uses
  ``podman``.
* **Goal endpoint:** Ubuntu 26.04 base, every plugin built by default,
  Sphinx-only docs, full Zuul CI on OpenDev.


Foundational principles
=======================

These principles apply throughout every phase. They are not optional.

Strip the check, hardcode the answer
------------------------------------

When an autoconf probe is excised, the flag, define, or behavior it
would have enabled on the target *must remain*. Examples:

* ``AX_PTHREAD`` — don't probe; unconditionally add ``-pthread`` to
  ``AM_CFLAGS``/``AM_CXXFLAGS``/``AM_LDFLAGS`` and ``AC_DEFINE([HAVE_PTHREAD],[1])``.
* 64-bit sizes — don't probe ``sizeof(void*)``; hardcode
  ``SIZEOF_VOIDP=8``, ``SIZEOF_LONG=8``, ``SIZEOF_SIZE_T=8``,
  ``SIZEOF_OFF_T=8``, ``SIZEOF_LONG_LONG=8``.
* Large-file support — don't probe; unconditional
  ``-D_FILE_OFFSET_BITS=64``.
* POSIX/glibc-guaranteed functions (``memmove``, ``strerror``,
  ``inet_ntoa``, etc.) — delete the ``AC_CHECK_FUNCS`` probe; either
  delete the corresponding ``#ifdef HAVE_*`` in source or
  ``AC_DEFINE`` the symbol unconditionally.
* Standard C++ headers (``<cstdint>``, ``<unordered_map>``,
  ``<memory>``) — assume present.
* Visibility — don't probe ``gl_VISIBILITY``; hardcode
  ``-fvisibility=hidden -fvisibility-inlines-hidden``.
* Stack-direction probe (``DRIZZLE_STACK_DIRECTION``) — hardcode
  "grows down".
* Endianness — hardcode little-endian.

The end-state ``configure.ac`` does *almost no probing* but produces
the same ``config.h`` and same compile/link flags as the old one
would have on amd64/arm64 Linux.

For each deletion the contributor must verify that the corresponding
define/flag is preserved (via ``AC_DEFINE`` of a constant, via
unconditional ``AM_CPPFLAGS`` additions, or via deletion of the
now-redundant ``#ifdef`` in source).

Aggressive commit splitting; every commit green
-----------------------------------------------

* **Deep stacks of small commits are loved.** Every bullet point in the
  phase task lists below is, by default, *its own commit* — often more
  than one. Removing the haildb plugin is one commit. Removing
  tokyocabinet is a second commit. Each independent
  ``m4/pandora_*.m4`` deletion is its own commit.
* **One semantic change per commit.** A commit may contain only the
  deletion of dead code, or only the addition of a hardcoded
  equivalent. When deletion plus replacement together tell a single
  reviewable story, they go in one commit; when they tell two stories,
  two commits.
* **Every commit is fully green.** ``podman build --target=build``
  succeeds, ``podman build --target=test`` succeeds, ``make unit``
  exits 0, ``make test-drizzle`` exits 0 (modulo the current phase's
  recorded skiplist). No commit may knowingly break tests — not even
  transiently. If a change requires a sequence, structure the
  sequence so intermediate steps stay green (typical pattern:
  *add new code* → *migrate callers* → *delete old code*, three
  commits, each green).
* This invariant is bisect-load-bearing. Future debugging walks dozens
  of small commits with ``git bisect``; any "broken in the middle"
  commit defeats bisect for the rest of the stack.
* Zuul's ``vouched`` and ``gate`` pipelines run on every commit in a
  stack, not just the tip. A red commit anywhere in the stack blocks
  the merge.
* **Commit messages describe why, not what.** The diff shows what.

No gravestone comments
----------------------

When code is removed, it is *gone*. Git log is the breadcrumb. Do not
leave ``// removed X``, ``/* was: ... */``, or ``# this used to ...``
comments in source files, m4 files, ``Makefile.am``, ``plugin.ini``,
or anywhere else.

The narrow exception: if a removal genuinely needs to *warn future
contributors away* from re-introducing a pattern, a comment about the
*constraint* is fine, but never about the *history*.

Multi-arch readiness from the start
-----------------------------------

Both targets (amd64 and arm64) are 64-bit, little-endian, 8-byte
pointer. These are safe hardcoded assumptions. But:

* No x86-only intrinsics (SSE/AVX) without an aarch64 fallback.
* No x86-only inline asm.
* Pandora's host-architecture detection branches that distinguish
  ``x86_64`` from ``aarch64`` (atomic ops, byte-swap intrinsics)
  **stay**. Every other architecture branch (``i386``, ``i686``,
  ``sparc``, ``sparc64``, ``powerpc``, ``ppc64``, ``ia64``, ``mips``,
  ``mips64``, ``s390``, ``alpha``, big-endian) gets deleted.


Phase map
=========

.. list-table::
   :header-rows: 1
   :widths: 5 35 12 8

   * - Phase
     - Title
     - Ubuntu
     - Effort
   * - 0
     - Tests in container, Zuul wiring, RST spec landed
     - 12.04
     - M
   * - 1
     - Strip dead platforms; delete dead-dep plugins
     - 12.04
     - L
   * - 2
     - Pandora slim-down to ``m4/drizzle.m4``
     - 12.04
     - M
   * - 3
     - LTS bump 14.04
     - 14.04
     - M
   * - 4
     - LTS bump 16.04 (C++11 baseline)
     - 16.04
     - M
   * - 5
     - LTS bump 18.04 (Boost 1.65, OpenSSL 1.1, fs v2→v3)
     - 18.04
     - L
   * - 6
     - LTS bump 20.04 (protobuf 3, C++17, PCRE2)
     - 20.04
     - XL
   * - 7
     - LTS bump 22.04 (OpenSSL 3)
     - 22.04
     - L
   * - 8
     - LTS bump 24.04
     - 24.04
     - M
   * - 9
     - LTS bump 26.04 (multi-arch gating, clean bindep)
     - 26.04
     - M
   * - 10
     - Plugin enable-by-default sweep
     - 26.04
     - L
   * - 11
     - Sphinx-only docs (Doxygen removal)
     - 26.04
     - S


Dead-dep policy
===============

These decisions are settled and apply across all phases:

* ``plugin/haildb/`` — **delete entirely** in Phase 1. ``libhaildb``
  is gone from modern Ubuntu; the engine is dead upstream.
* tokyocabinet plugin — **delete entirely** in Phase 1.
  ``libtokyocabinet`` is unmaintained and gone from modern Ubuntu.
* ``plugin/js/`` (v8) — **keep in tree, mark disabled.** Set
  ``build_conditional=false`` in ``plugin/js/plugin.ini`` in Phase 1.
  Add a ``plugin/js/README.revival`` note describing the intent to
  rewrite against modern Node/V8. Source files stay put so we know
  what we owe.
* ``libcloog-ppl-dev`` — **drop from bindep.txt** in Phase 1. Only
  needed by GCC 4.x Graphite; GCC 5+ uses ISL internally. The
  ``-floop-parallelize-all`` probes in ``m4/pandora_warnings.m4`` and
  ``m4/ax_harden_compiler_flags.m4`` go away in the same phase
  (marginal optimization, not worth the noise).


Phase 0 — Tests in container, Zuul wiring, spec landed
======================================================

Objective
---------

The container currently only builds. Phase 0 wires tests into the
container, sets up Zuul CI on OpenDev with the buildset-registry
pattern, and lands this RST spec itself. No C++ source is touched.

Phase 0 is the foundation: every subsequent phase relies on
"``podman build --target=test`` is green" as its definition of done,
and on Zuul to enforce that in CI.

Tasks
-----

Each bullet is a candidate commit. Sequence within the phase is
fluid; the test-stage Dockerfile work and the Zuul work can land in
parallel stacks.

* Land this spec at ``docs/specs/revival.rst`` and wire it into
  ``docs/index.rst`` under a new ``Specifications`` section.
* Create ``docs/specs/index.rst``.
* Refactor ``Dockerfile`` into three named stages:

  - ``base`` — apt sources + bindep install.
  - ``build`` — ``autoreconf -i && ./configure && make -j$(nproc)``
    (current behavior preserved exactly).
  - ``test`` — installs DTR runtime deps, sets working dir to the
    build artifacts cache, default ``CMD`` runs the test entrypoint.

* Add ``support-files/docker/run-tests.sh`` invoked by the test
  stage ``CMD``. Script:

  - exports ``DTR_BUILD_THREAD=$$``;
  - runs ``make unit`` first (boost.test, no servers);
  - runs ``make test-drizzle`` with ``--force --fast`` against the
    ``NORMAL_TESTS`` suite list;
  - exits non-zero on any failure that isn't in
    ``tests/skiplist.precise.txt``.

* Extend ``bindep.txt`` with a ``[test platform:dpkg]`` profile
  (``perl``, ``libdbi-perl``, ``libdbd-mysql-perl``, ``subunit``).
* Record the baseline ``tests/skiplist.precise.txt``. Each entry has a
  one-line rationale. This is the gate; no subsequent phase may grow
  it without recorded reason.
* Add ``zuul.d/projects.yaml`` mapping the project to the four
  pipelines: ``check``, ``vouched``, ``gate``, ``promote``.
* Add ``zuul.d/jobs.yaml`` defining the jobs listed under
  :ref:`spec-revival-ci`.
* Add ``support-files/ci/regress.sh`` — a local-developer mirror of
  the Zuul invocations. One-command "run what CI runs."

Local invocations (documented for contributors)
-----------------------------------------------

Inner loop — fast iteration, build only:

.. code-block:: console

   podman build --platform linux/amd64 --target=build -t drizzle:build .

Verification — build then run tests:

.. code-block:: console

   podman build --platform linux/amd64 --target=test -t drizzle:test .
   podman run --rm --net=host drizzle:test

arm64 readiness check (no test gating yet, just configure+compile):

.. code-block:: console

   podman build --platform linux/arm64 --target=build -t drizzle:build-arm64 .

Mirror of CI:

.. code-block:: console

   ./support-files/ci/regress.sh

Test target choice
------------------

* ``make unit`` (boost.test, ``unittests/``).
* ``make test-drizzle`` with ``NORMAL_TESTS`` (DTR / Perl harness via
  ``tests/test-run.pl``).
* **Skipped at this phase:** ``kewpie``, ``test-big``, ``test-randgen``.
  Too slow and/or Python-2 dependent. Revisit in Phase 10 if useful.

Container test runtime needs
----------------------------

* Writable vardir under ``/build`` (the build cache mount).
* ``DTR_BUILD_THREAD=$$`` for port-offset uniqueness within a single
  container.
* ``--net=host`` for port binding **on the test stage only**. The
  ``build`` stage stays network-clean.
* No "drizzle" UNIX user required (the historical guard has already
  been removed; see ``a82202956``).

Done when
---------

* ``podman build --target=build`` succeeds on amd64 (regression check
  of current behavior).
* ``podman build --target=test`` succeeds on amd64.
* ``podman run --rm --net=host drizzle:test`` exits 0, with any
  failures matching ``tests/skiplist.precise.txt``.
* ``podman build --platform linux/arm64 --target=build`` succeeds
  (configure + compile only; tests not gating until Phase 9).
* Zuul ``check`` pipeline runs ``drizzle-lint`` green.
* Zuul ``vouched`` pipeline runs ``drizzle-build-image`` +
  ``drizzle-unit-tests`` + ``drizzle-dtr-tests`` + ``drizzle-distcheck``
  green.
* ``make html`` in ``docs/`` builds this spec without warnings.

Risks
-----

* DTR's vardir lives in ``/build`` (the cache mount), not in the
  read-only bind-mounted source. Confirm the cache survives between
  ``build`` and ``test`` stages.
* Rootless podman port binding can collide. ``--net=host`` solves it
  for now; revisit if multi-tenant CI runners need isolation.


Phase 1 — Strip dead platforms, delete dead-dep plugins
=======================================================

Objective
---------

Mechanically delete every conditional that pertains to a platform,
compiler, or architecture we will never target — while preserving the
flags and defines those conditionals would have set on amd64/arm64
Linux. Delete dead-dep plugins per the :ref:`dead-dep policy
<spec-revival>`.

Tasks
-----

**Platform and compiler conditionals.** Each item below is at least
one commit; many are multiple commits.

* ``m4/pandora_platform.m4``: delete Solaris/Darwin/FreeBSD/mingw32
  arms in both ``case "$host_os"`` blocks. Delete SUNCC/INTELCC
  detection. **Hardcode** the Linux-GNU branch behavior
  (``_GNU_SOURCE`` define, glibc-style paths).
* ``m4/pandora_warnings.m4``: delete INTELCC and SUNCC arms.
  **Hardcode** the GCC warnings set the Linux/GCC arm applied
  (``-Wall -Wextra -Wformat=2 -Wmissing-declarations``, etc.) as
  unconditional ``AM_CFLAGS``/``AM_CXXFLAGS``. Delete the
  ``-floop-parallelize-all`` probe.
* ``m4/ax_harden_compiler_flags.m4``: delete ``-floop-parallelize-all``
  references. **Hardcode** the GCC hardening flags this macro was
  probing (``-fstack-protector-strong``, ``-D_FORTIFY_SOURCE=2``,
  ``-Wl,-z,relro,-z,now``, etc.) as unconditional flags.
* ``m4/pandora_canonical.m4``: drop the ``force-gcc42``,
  ``PCT_FORCE_GCC42``, and ``gnulib`` arms.
* ``configure.ac:39``: simplify ``PANDORA_CANONICAL_TARGET`` arguments
  (drop ``force-gcc42``).
* ``configure.ac:280-292``: delete the FreeBSD post-configure echo
  block.
* Delete (verifying no live references with ``grep`` per file):

  - ``m4/pandora_ensure_gcc_version.m4`` (assume modern GCC)
  - ``m4/pandora_have_libbdb.m4``
  - ``m4/pandora_have_libndbclient.m4``
  - ``m4/pandora_have_libhaildb.m4``
  - ``m4/pandora_have_libtokyocabinet.m4``

* ``m4/pandora_64bit.m4`` — **rewrite, do not delete.** Both targets
  are 64-bit, so the probe is unnecessary, but the *behavior*
  (defining ``SIZEOF_VOIDP=8``, ``SIZEOF_LONG=8``, ``SIZEOF_SIZE_T=8``,
  enabling ``-D_FILE_OFFSET_BITS=64``) must remain. Replace the macro
  body with unconditional ``AC_DEFINE`` lines and the appropriate
  ``AM_CFLAGS += -D_FILE_OFFSET_BITS=64``. (Will fold into
  ``m4/drizzle.m4`` in Phase 2.)
* Delete the ``AX_PTHREAD`` invocation; **hardcode** ``-pthread`` into
  ``AM_CFLAGS``/``AM_CXXFLAGS``/``AM_LDFLAGS`` and
  ``AC_DEFINE([HAVE_PTHREAD],[1])``.
* Delete the ``gl_VISIBILITY`` invocation; **hardcode**
  ``-fvisibility=hidden -fvisibility-inlines-hidden`` into
  ``AM_CXXFLAGS`` and ``HAVE_VISIBILITY=1``.
* ``AC_CHECK_FUNCS``/``AC_CHECK_HEADERS`` audit. This is itself a stack
  of small commits — one probe (or one tight logical group) per
  commit. For every probe of a POSIX/glibc-guaranteed function or
  header (``memmove``, ``strerror``, ``inet_ntoa``, ``<stdint.h>``,
  ``<inttypes.h>``, ``<cstdint>``, ``<unordered_map>``, etc.):

  - delete the probe; and
  - delete the corresponding ``#ifdef HAVE_*`` in source (preferred,
    same commit); or
  - if the ``#ifdef`` is widely scattered, ``AC_DEFINE`` the symbol
    unconditionally for now and remove the ``#ifdef``\ s in a
    follow-up commit.

* ``AC_CHECK_SIZEOF(off_t|size_t|long long)`` — delete; hardcode to 8.
* ``DRIZZLE_STACK_DIRECTION`` — delete; hardcode "grows down".

**Architecture handling (multi-arch — amd64 + arm64).**

* In ``m4/pandora_platform.m4`` (or wherever host CPU is examined):
  **keep** branches distinguishing ``x86_64`` from ``aarch64``
  (atomic ops, byte-swap intrinsics, cache-line size if used).
  Delete branches for ``i386``, ``i686``, ``sparc``, ``sparc64``,
  ``powerpc``, ``ppc64``, ``ia64``, ``mips``, ``mips64``, ``s390``,
  ``alpha``, etc. Hardcode little-endian; delete any big-endian
  conditional code paths.
* Audit source for x86-specific intrinsics (``__builtin_ia32_*``,
  ``_mm_*``, SSE/AVX) and x86 inline asm. List any findings in the
  :ref:`spec-revival-multiarch-hazards` appendix so later phases know
  where aarch64 paths are needed. Don't fix in Phase 1 unless trivial.

**Plugin and dependency deletions.** Each is its own commit:

* Delete ``win32/`` directory.
* Delete ``plugin/haildb/`` (or the actual haildb plugin path).
* Delete the tokyocabinet plugin.
* Set ``build_conditional=false`` in ``plugin/js/plugin.ini`` and add
  ``plugin/js/README.revival`` describing the modern-V8/Node rewrite
  intent. Leave source files alone.
* Drop ``libcloog-ppl-dev`` from ``bindep.txt``.

Done when
---------

.. code-block:: console

   grep -ri 'solaris\|freebsd\|mingw32\|SUNCC\|INTELCC\|TARGET_OSX\|cloog' m4/ configure.ac

returns empty.

.. code-block:: console

   grep -ri 'i386\|i686\|powerpc\|ppc64\|sparc\|mips\|s390\|ia64\|alpha\|BIG_ENDIAN' m4/ configure.ac

returns only the curated amd64/arm64 branches we intentionally kept.

.. code-block:: console

   wc -l m4/*.m4

shows a ≥40% drop in total line count vs the Phase 0 baseline.

* Phase 0 tests still pass on amd64 with unchanged
  ``tests/skiplist.precise.txt``.
* ``podman build --platform linux/arm64 --target=build`` still gets
  through ``./configure`` cleanly. Test failures on arm64 are recorded
  in :ref:`spec-revival-multiarch-hazards` but not gating until
  Phase 9.

Risks
-----

* Removing ``gnulib`` may surface latent dependencies. Land that
  removal in its own commit so a revert is cheap.
* ``m4/pandora_extensions.m4`` provides ``AC_USE_SYSTEM_EXTENSIONS``
  wrapping. Verify it isn't load-bearing before deletion.


Phase 2 — Pandora slim-down to ``m4/drizzle.m4``
================================================

Objective
---------

Excise the Pandora macro layer as a *layer* while preserving every
piece of behavior it provides. End state: a single ``m4/drizzle.m4``
(~400 lines) plus a small number of upstream third-party m4 files
(``boost.m4``, the kept-deliberately ``pandora_plugins.m4``,
gettext machinery).

Tasks
-----

* Create ``m4/drizzle.m4`` consolidating the live Pandora
  responsibilities into a single ``DRIZZLE_BUILD_SETUP`` macro.
  Inside the macro, hardcode the Phase 1 answers: ``-pthread``,
  ``-fvisibility=hidden``, the sizeof defines, ``_FILE_OFFSET_BITS=64``,
  the GCC warning flags, the hardening flags.
* Rewrite ``configure.ac:39`` to call ``DRIZZLE_BUILD_SETUP`` in place
  of ``PANDORA_CANONICAL_TARGET``.
* Replace each library-presence macro with straight
  ``PKG_CHECK_MODULES``. ``libprotobuf``, ``libz``, ``libssl``,
  ``libpcre``, ``libreadline``, ``libdl`` all have stable
  pkg-config files on modern Ubuntu. Each replacement is its own
  commit.
* Keep ``m4/pandora_plugins.m4`` and ``config/pandora-plugin``
  (load-bearing plugin enumeration).
* Delete the now-unused ``m4/pandora_*.m4`` files (one or more
  commits).

Done when
---------

* ``ls m4/pandora_*.m4`` returns ≤2 files (``pandora_plugins.m4``,
  possibly a thin ``pandora_canonical.m4`` compatibility shim if any
  external scripts reference it).
* ``configure.ac`` is under 250 lines.
* Phase 0 tests still pass on amd64.
* ``./configure`` succeeds on arm64.

Risks
-----

* ``pandora_plugins.m4`` is the most opaque file in the layer — it
  generates ``am__plugin_LIST`` and the load-list. Treat it as
  load-bearing infrastructure. Do not rewrite; verify it still works
  after surrounding deletions.


.. _spec-revival-lts-template:

Phases 3–9 — LTS bump template
==============================

Each LTS bump follows the same shape. Sub-phases per LTS are listed
afterward.

Template tasks
--------------

1. Bump ``Dockerfile`` ``FROM ubuntu:X.04``. Verify Canonical
   publishes both ``linux/amd64`` and ``linux/arm64`` for the image
   (true for all current LTS images).
2. Update ``bindep.txt``: replace ``[platform:ubuntu-PREVIOUS]``
   selector lines with ``[platform:ubuntu-CURRENT]``, adjusting
   versioned package names (boost, protobuf, etc.). One commit.
3. Build on amd64:

   .. code-block:: console

      podman build --platform linux/amd64 --target=build .

   Triage compile breakage. Fix code. ``-Wno-xxx`` permitted only as
   last resort, with a written rationale in the commit message.

4. Test on amd64:

   .. code-block:: console

      podman build --platform linux/amd64 --target=test .
      podman run --rm --net=host <image>

   Fix test failures. If fixing is impossible, stop and discuss
   whether skiplist is acceptible.

5. Build on arm64:

   .. code-block:: console

      podman build --platform linux/arm64 --target=build .

   Must succeed. Test runs on arm64 are encouraged but not gating
   until Phase 9.

6. ``make distcheck`` must pass on amd64.
7. Tag the resulting image per-arch:

   .. code-block:: console

      podman tag drizzle:test drizzle:ubuntu-X.04-phaseN-amd64
      podman tag drizzle:test-arm64 drizzle:ubuntu-X.04-phaseN-arm64

Phase-specific notes
--------------------

Phase 3 — Ubuntu 14.04
~~~~~~~~~~~~~~~~~~~~~~

Lightest LTS bump. Boost 1.46 → 1.54; protobuf still 2.x; OpenSSL
still 1.0. Mostly warning-flag drift.

Phase 4 — Ubuntu 16.04 (C++11 baseline)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* Add ``AX_CXX_COMPILE_STDCXX([11],[noext],[mandatory])`` to
  ``configure.ac`` — one commit.
* Delete now-redundant C++11-capability m4 files
  (``pandora_check_cxx_standard.m4``, ``pandora_shared_ptr.m4``,
  ``pandora_stl_hash.m4``, ``ax_cxx_compile_stdcxx_0x.m4``,
  ``ax_cxx_header_stdcxx_98.m4``) — one commit per file.
* Mechanical rename ``boost::shared_ptr`` → ``std::shared_ptr``
  across ``drizzled/``. Stack of small commits, one per directory or
  logical unit so each stays green.
* Mechanical rename ``boost::unordered_map`` → ``std::unordered_map``
  similarly.

Phase 5 — Ubuntu 18.04 (Boost 1.65, OpenSSL 1.1)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

First real friction phase. Sub-stacks:

* Audit ``#include <boost/...>`` across ``drizzled/`` and ``plugin/``.
  Replace ``boost/foreach.hpp`` with C++11 range-for (one commit per
  consumer).
* Migrate ``boost::filesystem`` v2 API to v3. Dedicate this to its
  own contributor; it's the worst single transition of Phase 5.
* OpenSSL 1.1 makes ``SSL_CTX`` and friends opaque. Replace direct
  field access with accessor functions. Audit ``plugin/auth_*``,
  ``client/``, ``drizzled/``.
* Add ``-Wimplicit-fallthrough`` annotations or ``[[fallthrough]];``.

Phase 6 — Ubuntu 20.04 (protobuf 3, C++17, PCRE2)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Hardest phase. Three near-simultaneous breaks. Land as three
sub-stacks; the order below is the recommended sequencing.

* **6a: protobuf 2 → 3.** Regenerate ``.pb.cc`` / ``.pb.h`` at
  configure time; stop versioning generated code. Update API uses
  (``set_allocated_*`` semantics; ``Reflection`` API churn; arena
  allocation).
* **6b: libpcre1 → libpcre2.** Rewrite ``m4/pandora_have_libpcre.m4``
  (or its replacement in ``m4/drizzle.m4``) to
  ``PKG_CHECK_MODULES([PCRE2],[libpcre2-8])``. Audit
  ``plugin/regex_policy/`` and any other direct PCRE callers.
* **6c: C++17 sweep.** ``std::auto_ptr`` → ``std::unique_ptr``;
  ``std::random_shuffle`` → ``std::shuffle`` + ``std::mt19937``;
  ``register`` keyword removed; ``throw()`` → ``noexcept``.

Bump ``BOOST_REQUIRE([1.46])`` to ``BOOST_REQUIRE([1.71])`` in
``configure.ac``.

Phase 7 — Ubuntu 22.04 (OpenSSL 3)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* Migrate direct ``SHA1_*``/``MD5_*``/``HMAC_*`` calls to ``EVP_*``
  equivalents (``plugin/md5/``, ``plugin/auth_http/``,
  ``drizzled/sha1.cc`` if present).
* Either fix every ``OPENSSL_NO_DEPRECATED_3_0`` warning or accept
  ``-Wno-deprecated-declarations`` in a single compilation unit (auth
  code), explicitly noted in commit message.
* Bump Boost requirement to 1.74.

Phase 8 — Ubuntu 24.04
~~~~~~~~~~~~~~~~~~~~~~

Mostly free. GCC 13 / Boost 1.83 ``-Werror`` casualty sweep.

Phase 9 — Ubuntu 26.04 (final landing)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* Drop every ``[platform:ubuntu-*]`` selector from ``bindep.txt`` — we
  don't support those platforms anymore; the LTS bumps were one-way
  ratchets.
* **arm64 becomes fully gating.** ``make test-drizzle`` must pass on
  both architectures.
* Produce a multi-arch manifest:

  .. code-block:: console

     podman manifest create drizzle:26.04
     podman manifest add drizzle:26.04 drizzle:ubuntu-26.04-phase9-amd64
     podman manifest add drizzle:26.04 drizzle:ubuntu-26.04-phase9-arm64

* Fix any arm64-specific test failures accumulated during Phases 3–8.


Phase 10 — Plugin enable-by-default sweep
=========================================

Objective
---------

Every plugin in ``plugin/`` builds on the 26.04 target by default.
``bindep.txt`` covers every plugin's dep unconditionally. No
``build_conditional=`` line survives (modulo the v8 plugin, which
remains opt-out pending Node-based rewrite).

Tasks
-----

* Build all 82 plugins on 26.04 with the default ``configure``
  invocation. Categorize each failure:

  - **Easy fix** (warning flag, header path) — fix in this phase, one
    commit per plugin.
  - **Hard fix** (dead upstream API but modern alternative exists) —
    port to the modern API, separate commit per plugin.
  - **Hopeless** (truly dead upstream, no modern replacement) —
    delete the plugin entirely.

* Expand ``bindep.txt`` with every required dep, unconditionally.
* Delete every ``build_conditional=`` line from ``plugin/*/plugin.ini``
  except for ``plugin/js/plugin.ini``. Each deletion is its own commit
  (after proving the condition is always true on the 26.04 target).

Done when
---------

.. code-block:: console

   grep -l 'build_conditional' plugin/*/plugin.ini

returns only ``plugin/js/plugin.ini``.

* ``make`` builds every other plugin.
* ``make test-drizzle`` skiplist no larger than Phase 9's.

Optional: split production and test-client images
-------------------------------------------------

The user's stated target topology for CI:

   "A job builds a production container, then a second job runs all
   the tests against a server running from the container."

If appetite exists in Phase 10, split the Dockerfile into:

* ``production`` stage — ``drizzled`` binary + minimal runtime deps,
  no test harness, no perl.
* ``test-client`` stage — DTR/perl tooling but no ``drizzled``.

Then ``drizzle-dtr-tests`` in CI runs the production image as a
long-running container (``podman run -d``), and the test-client image
drives DTR against it via ``--network=container:<prod>`` or a podman
pod. This gives us the property that **the image we ship is the image
we test**.

Not gating for Phase 10 completion; tracked under
:ref:`spec-revival-future-work`.


Phase 11 — Sphinx-only docs
===========================

Objective
---------

Delete Doxygen entirely. Sphinx remains the only documentation
toolchain. Existing 65 RST files are the foundation.

Tasks
-----

* Delete ``docs/Doxyfile``.
* Delete ``plugin/innobase/Doxyfile``.
* Remove ``AC_CHECK_PROGS([DOXYGEN],[doxygen])`` from
  ``configure.ac``.
* Update ``docs/include.am`` to drop Doxygen rules and the
  ``SPHINX_BUILDDIR`` clean-local Doxygen-related entries.
* Migrate any salvageable architectural commentary from Doxygen
  comments into RST under ``docs/contributing/`` (or a new
  ``docs/internals/``).
* Drop the Doxygen entry from ``bindep.txt`` if present.


.. _spec-revival-ci:

CI strategy — Zuul on OpenDev
=============================

Pipeline model
--------------

CI runs on OpenDev Zuul. Pipeline mapping:

* **check** — cheap, fast-feedback jobs only: linting, ``autoreconf``
  syntax, ``./configure`` dry-run, docs build. Runs on every patchset,
  unreviewed.
* **vouched** — full build + test. Runs only after the OpenDev AI
  review agent has reviewed the change. This is where the heavy work
  lives — container build, full DTR run, ``make distcheck``,
  multi-arch builds.
* **gate** — identical to ``vouched`` (re-runs at merge time to catch
  races).
* **promote** — after merge, tags and pushes the final container
  image to the permanent registry.

Everything must always pass. There is no "soft" job; flaky tests get
fixed or get added to ``tests/skiplist.<phase>.txt`` with a recorded
reason only after explcit discussion as a last resort.

Job design (buildset-registry pattern)
--------------------------------------

We follow the canonical OpenDev container-build pattern: one job
builds the image into a per-buildset intermediate registry; downstream
jobs in the same buildset pull from that registry. Tests run against
the *exact same image artifact* that ``promote`` pushes, not a
re-build.

Job definitions live in ``zuul.d/jobs.yaml``. Pipeline mapping lives
in ``zuul.d/projects.yaml``.

Jobs:

* ``drizzle-lint`` — ``check`` pipeline only. Bare nodeset, no
  container. ``autoreconf -i``, ``./configure --no-create``, docs
  build smoke. ~2 minutes.
* ``drizzle-build-image`` — ``parent: opendev-build-container-image``.
  Builds the ``test`` Dockerfile stage into the buildset registry.
  Runs once per arch (``linux/amd64``, ``linux/arm64``) via Zuul's
  per-arch nodesets, producing two tags in the buildset registry.
* ``drizzle-unit-tests`` —
  ``parent: opendev-buildset-registry-consumer``. Pulls the image from
  the buildset registry; runs ``podman run --rm <image> make unit``.
  Depends on ``drizzle-build-image``.
* ``drizzle-dtr-tests`` — same parent. Pulls the image; runs
  ``make test-drizzle``. Depends on ``drizzle-build-image``.
* ``drizzle-distcheck`` — runs ``make distcheck`` against the built
  tree. Same parent pattern.
* ``drizzle-promote-image`` —
  ``parent: opendev-promote-container-image``. Only in the ``promote``
  pipeline. Re-tags the buildset-registry image into the permanent
  registry under the merge-commit SHA and ``latest``.

Pipeline composition:

* ``check`` — ``drizzle-lint``.
* ``vouched`` and ``gate`` — ``drizzle-build-image`` (amd64 + arm64),
  ``drizzle-unit-tests`` (both arches), ``drizzle-dtr-tests`` (both
  arches), ``drizzle-distcheck`` (amd64 only).
* ``promote`` — ``drizzle-promote-image``.

Per-phase image promotion
-------------------------

After each phase merges, the ``promote`` pipeline tags the image with
the phase name (e.g. ``drizzle:phase1-strip``,
``drizzle:phase3-ubuntu1404``) in addition to the SHA. This gives us a
permanent regression archive: any future change can
``podman run drizzle:phaseN make test-drizzle`` to verify it doesn't
regress prior phases.


.. _spec-revival-multiarch-hazards:

Appendix — Multi-arch hazards
=============================

A running list, populated during Phase 1's architecture audit and
extended through Phases 3–8. Each entry describes an x86-specific
construct in the source and a sketch of the aarch64 fix.

*(populated incrementally — leave this section short until the audit
runs)*


.. _spec-revival-future-work:

Future work
===========

Items tracked but explicitly out of scope until a named phase picks
them up:

* **v8 plugin rewrite** against modern V8 or Node embedding. The
  current plugin source stays in tree as a placeholder with
  ``build_conditional=false``.
* **Production/test-client Dockerfile split.** Described under
  :ref:`Phase 10 <spec-revival>`. The image we ship is the image we
  test.
* **kewpie revival** (Python 3 port) if/when interest arises. Skipped
  from the test-target list in Phase 0.
