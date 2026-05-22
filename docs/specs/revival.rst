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
* The repo's ``Containerfile`` builds against Ubuntu 12.04 (Precise, long
  EOL) using ``bindep-rs`` to install ``bindep.txt``. The build runs;
  tests do not.
* Sphinx docs are well established (65 RST files); a ``Doxyfile`` also
  exists but Sphinx is the primary documentation surface.

We are reviving the project with a small set of strong constraints:

* **Single OS target, ever.** Whatever the ``Containerfile`` ``FROM``
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
  exits 0, ``make test-drizzle`` exits 0. No commit may break tests
   — not even transiently. If a change requires a sequence, structure the
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
   * - 1.5
     - Performance baseline harness
     - 12.04
     - M
   * - 2
     - Pandora slim-down to ``m4/drizzle.m4``
     - 12.04
     - M
   * - 2.5
     - Constant-fold the hardcoded defines into the source
     - 12.04
     - S
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
fluid; the test-stage Containerfile work and the Zuul work can land in
parallel stacks.

* Land this spec at ``docs/specs/revival.rst`` and wire it into
  ``docs/index.rst`` under a new ``Specifications`` section.
* Create ``docs/specs/index.rst``.
* Refactor ``Containerfile`` into three named stages:

  - ``base`` — apt sources + bindep install.
  - ``build`` — ``autoreconf -i && ./configure && make -j$(nproc)``
    (current behavior preserved exactly).
  - ``test`` — installs DTR runtime deps, sets working dir to the
    build artifacts cache, default ``CMD`` runs the test entrypoint.

* Add ``tools/run-tests.sh`` invoked by the test
  stage ``CMD``. Script:

  - exports ``DTR_BUILD_THREAD=$$``;
  - runs ``make unit`` first (boost.test, no servers);
  - runs ``make test-drizzle`` with ``--force --fast`` against the
    ``NORMAL_TESTS`` suite list;
  - exits non-zero on any failure

* Extend ``bindep.txt`` with a ``[test platform:dpkg]`` profile
  (``perl``, ``libdbi-perl``, ``libdbd-mysql-perl``, ``subunit``).
* Add ``zuul.d/projects.yaml`` mapping the project to the four
  pipelines: ``check``, ``vouched``, ``gate``, ``promote``.
* Add ``zuul.d/jobs.yaml`` defining the jobs listed under
  :ref:`spec-revival-ci`.
* Add ``tools/regress.sh`` — a local-developer mirror of
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

   ./tools/regress.sh

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
* ``podman run --rm --net=host drizzle:test`` exits 0
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

``configure.ac`` carries no dead-platform or dead-architecture
conditional:

.. code-block:: console

   grep -nE 'solaris|freebsd|mingw32|darwin|SUNCC|INTELCC|TARGET_OSX|cloog' configure.ac
   grep -nE 'i386|i686|powerpc|ppc64|sparc|mips|s390|ia64|BIG_ENDIAN' configure.ac

Both return empty.

The grep is scoped to ``configure.ac`` deliberately. The first-party
``m4/pandora_*.m4`` macros still carry Solaris/Intel/PowerPC arms at
the close of Phase 1; they are removed as each file is folded into
``m4/drizzle.m4`` in Phase 2 — writing the macro afresh drops the dead
arms without a throwaway in-place edit first. The vendored m4 files
(``boost.m4``, the gettext set, ``ax_pthread.m4``) keep their
portability code: they are upstream and regenerated, not hand-edited.
The ≥40% ``wc -l m4/*.m4`` reduction is consequently a Phase 2
outcome, measured there.

* Phase 0 tests still pass on amd64.
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


Phase 1.5 — Performance baseline harness
========================================

Objective
---------

Stand up a deterministic, hardware-independent performance measurement
*before* any code is restructured, so every later phase can be judged
against a frozen baseline. We have no dedicated performance hardware
and CI runs on shared nodes, so wall-clock time is meaningless.
Instead, count work synthetically: callgrind simulates execution and
counts instructions, which is reproducible run-to-run and identical on
any host.

This phase ships only measurement infrastructure — it changes no
server code. It exists so that Phase 2 onward have a signal.

Tasks
-----

* Add ``valgrind`` to ``bindep.txt`` under a new ``[perf
  platform:dpkg]`` profile (``callgrind``, ``massif`` and
  ``callgrind_annotate`` all ship with it). Add the Perl ``DBI`` /
  ``DBD`` packages ``sql-bench`` needs under the same profile.
* Workload: drive ``tests/test_tools/sql-bench`` against a drizzled
  instance — it already carries a drizzle server profile. Pin the
  dataset and iteration counts; single connection. If the ``DBD``
  path against the MySQL-protocol port proves unworkable on Precise,
  fall back to a bespoke deterministic SQL workload under ``perf/``;
  record which path was taken in the commit message.
* ``tools/perf.sh`` — install Drizzle and the workload driver, launch
  drizzled under ``valgrind --tool=callgrind --cache-sim=yes
  --branch-sim=yes``, run the workload, and parse
  ``callgrind_annotate`` into a JSON metrics file: total instructions
  (Ir), an estimated-cycles figure, and the L1-miss, LLC-miss and
  branch-mispredict totals. The whole process is instrumented — boot
  included — because toggling instrumentation mid-run needs ptrace,
  which the build container's kernel restricts; server boot is a
  stable constant, so it does not disturb deltas.
* Second pass over the same workload under ``valgrind --tool=massif``
  for peak heap.
* Record ``size(1)`` output for ``drizzled`` and every plugin
  ``.so`` — code-size tracking is free and tracks toolchain bloat.
* Commit captured numbers under a ``perf/`` directory in the tree.
  ``tools/perf.sh`` writes the current run there and diffs it against
  the committed baseline.
* Zuul: add a ``drizzle-perf`` job to the ``vouched`` and ``gate``
  pipelines running ``tools/perf.sh`` on every commit. **Non-gating**
  — it reports the delta against baseline; it does not fail the
  build.
* At the close of every later phase, run ``tools/perf.sh`` by hand
  and commit the numbers as ``perf/<release>.json`` —
  ``perf/14.04.json`` when Phase 3 lands, ``perf/16.04.json`` for
  Phase 4, and so on. ``perf/baseline.json`` (the 12.04 result) is
  never overwritten. The accumulating set of per-release files is the
  performance time series, all in one place — no external dashboard.
  Once the revival reaches 26.04 we revisit how to re-baseline.

Done when
---------

* ``tools/perf.sh`` produces its JSON metrics file end to end and
  diffs it against the baseline. Instruction count is reproducible to
  within a low-single-digit percent — drizzled is multithreaded and
  callgrind sums every thread, so background-thread work sets a
  ~2% noise floor. The job is for catching larger shifts; treat
  sub-~3% deltas as noise. (Driving the floor down — per-thread
  collection, quieter background plugins — is a later refinement.)
* A Phase 1 baseline is committed under ``perf/``.
* callgrind and massif are both available in the container via
  ``bindep.txt``.
* The ``drizzle-perf`` job runs in ``vouched`` and ``gate``.

Risks
-----

* ``sql-bench`` is Perl/DBI; the ``DBD`` path against drizzle's
  MySQL-protocol port may not work cleanly on Precise. The fallback
  is a bespoke ``perf/`` workload — circle back if ``DBD`` fights us.
* callgrind is a ~20–50× slowdown and the job runs per commit. Keep
  the workload small enough that the ``vouched``/``gate`` pass stays
  in single-digit minutes — run a subset of ``sql-bench``, not all of
  it.
* Across an LTS bump valgrind itself changes, which slightly shifts
  the instruction count; within a phase it is constant.
* drizzled is multithreaded and callgrind sums every thread, so
  background-thread work (InnoDB and friends) gives the instruction
  count a ~2% run-to-run noise floor. The harness lands with that
  understood; tightening it is future work.
* Non-deterministic SQL (``NOW()``, ``RAND()``, ``UUID()``) would
  destroy reproducibility — the curated workload uses none.


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
  Inside the macro, hardcode the Phase 1 answers: ``-pthread``, the
  visibility settings, the sizeof defines, ``STACK_DIRECTION``,
  ``TARGET_OS_LINUX``, and the GCC warning flags. (Compiler hardening
  is deliberately *not* among these — see :ref:`future work
  <spec-revival-future-work>`.)
* As each ``pandora_*.m4`` macro is folded into ``drizzle.m4``, write
  it afresh for GCC on amd64/arm64 — its dead Solaris/Intel/PowerPC
  arms simply do not get carried over. This absorbs the in-place
  dead-arm strip deferred from Phase 1: there is no throwaway
  intermediate edit, the arms vanish when the macro is rewritten.
* Rewrite ``configure.ac:39`` to call ``DRIZZLE_BUILD_SETUP`` in place
  of ``PANDORA_CANONICAL_TARGET``.
* Replace the library-presence macros with ``PKG_CHECK_MODULES``,
  one commit each. ``libz``, ``libssl``, ``libpcre`` and
  ``libprotobuf`` ship pkg-config files on the 12.04 base
  (``zlib.pc``, ``libssl.pc``, ``libpcre.pc``, ``protobuf.pc`` —
  verified). Two exceptions:

  - ``libdl`` has no pkg-config file on any release — ``dlopen`` is
    in glibc. Replace ``PANDORA_REQUIRE_LIBDL`` with
    ``AC_SEARCH_LIBS([dlopen],[dl])``.
  - ``readline`` did not ship ``readline.pc`` until readline 6.3
    (≈Ubuntu 16.04); the 12.04 readline 6.2 has none. Keep
    ``pandora_have_libreadline.m4`` for now; convert it to
    ``PKG_CHECK_MODULES`` at the LTS bump where ``readline.pc``
    first appears.

  Each replacement must keep the variables the ``Makefile.am`` files
  consume — ``$(LIBZ)``, ``$(LIBSSL)``, ``$(LIBPCRE)``/``$(LTLIBPCRE)``,
  ``$(LIBPROTOBUF)``/``$(LTLIBPROTOBUF)``, ``$(LIBDL_LIBS)`` — assigned
  from the ``*_LIBS`` pkg-config output, plus the ``HAVE_LIB*``
  ``config.h`` defines.
* Strip the dead ``AC_CHECK_SIZEOF`` probes from
  ``plugin/innobase/plugin.ac`` (the one ``plugin.ac`` carrying
  dead-platform cruft); hardcode the LP64 sizes it measured.
* Keep ``m4/pandora_plugins.m4`` and ``config/pandora-plugin``
  (load-bearing plugin enumeration).
* Delete the now-unused ``m4/pandora_*.m4`` files (one or more
  commits).
* Strip the dead version-control arms from the build-from-VC code in
  ``drizzle.m4``. ``PANDORA_TEST_VC_DIR`` and ``PANDORA_BUILDING_FROM_VC``
  probe for ``.bzr``, ``.svn``, ``.hg`` and ``.git``; the project is
  git and bzr/svn/hg are as dead as Solaris. Keep only the git arm —
  the ``bzr revno``/``bzr nick``/``bzr log`` extraction and the svn/hg
  branches go.
* Re-prefix the build macros from ``PANDORA_`` to ``DRIZZLE_``
  (``PANDORA_MSG_ERROR`` → ``DRIZZLE_MSG_ERROR``, ``PANDORA_WARNINGS``
  → ``DRIZZLE_WARNINGS``, and so on for every macro now living in
  ``drizzle.m4``), updating call sites in ``configure.ac``. This
  finishes excising the Pandora layer — once done, no ``PANDORA_``
  name survives outside the deliberately-kept ``pandora_plugins.m4``
  and the plugin-dependency have-lib macros (those re-prefix, or
  retire, with the Phase 10 plugin sweep). Land it last, as a
  mechanical rename once the macro set has settled.

Done when
---------

* The Pandora build-setup layer is gone: ``m4/drizzle.m4`` is the only
  orchestration file, and the surviving ``pandora_*.m4`` files are
  ``pandora_plugins.m4`` plus the plugin-dependency ``have-lib``
  macros still called by ``plugin/*/plugin.ac`` (``libaio``,
  ``libcurl``, ``libevent``, ``libgearman``, ``libldap``,
  ``libmemcached``, ``libv8``, flex). Those retire in Phase 10 with
  the plugin sweep — Phase 2 does not reach the original "≤2 files"
  target, and is not meant to.
* ``configure.ac`` is under 250 lines.
* ``grep -rnE 'solaris|freebsd|SUNCC|INTELCC|i386|powerpc|sparc'``
  over the first-party m4 (everything but ``boost.m4`` and the
  vendored gettext set) returns empty.
* ``wc -l m4/*.m4`` shows a substantial drop versus the Phase 0
  baseline. The original ≥40% figure assumed the plugin have-lib
  macros also went; with those correctly deferred to Phase 10, report
  the actual figure rather than forcing it.
* Phase 0 tests still pass on amd64.
* ``./configure`` succeeds on arm64.

Risks
-----

* ``pandora_plugins.m4`` is the most opaque file in the layer — it
  generates ``am__plugin_LIST`` and the load-list. Treat it as
  load-bearing infrastructure. Do not rewrite; verify it still works
  after surrounding deletions.


Phase 2.5 — Constant-fold the hardcoded defines into the source
===============================================================

Objective
---------

Phase 1 replaced a raft of autoconf probes with fixed ``AC_DEFINE``
constants, and Phase 2 adds more as it moves to ``PKG_CHECK_MODULES``.
A ``#define`` whose value can no longer vary makes every ``#ifdef``
and ``#if`` that tests it dead-reckonable: the preprocessor branch is
now always-taken or never-taken, and any C/C++ ``if`` written against
the value is a constant condition.

Phases 1 and 2 stop at the configure layer. Phase 2.5 follows each
hardcoded symbol into the source and removes the now-pointless
indirection — delete the dead preprocessor branch, inline the
constant, and simplify whatever conditional logic the old variability
forced. A static define still threaded through ``#ifdef``\ s is only
half-stripped; this phase finishes the job, in one pass over both
phases' constants.

This is a source-only phase; it changes no build behavior.

Tasks
-----

Each symbol below is at least one commit. Audit every consumer
(``grep`` the symbol across ``drizzled/``, ``client/``, ``plugin/``,
``libdrizzle*``), then collapse.

* ``STACK_DIRECTION`` (always ``-1``).
  ``drizzled/check_stack_overrun.cc`` derives a constant from it and
  branches on that constant; both the define-test and the branch fold
  away, simplifying the function body.
* ``HAVE_PTHREAD`` (always ``1``). Delete the ``#ifdef HAVE_PTHREAD``
  guards; the guarded code is unconditional.
* ``HAVE_VISIBILITY`` (always ``1``). Collapse the
  ``#if HAVE_VISIBILITY`` ladders in the ``visibility.h`` headers to
  their visibility-supported branch.
* ``TARGET_OS_LINUX`` (always ``1``). Delete the ``#ifdef`` guards in
  ``drizzled/definitions.h`` and ``libdrizzle/conn.cc``; the Linux
  branch is unconditional.
* ``SIZEOF_OFF_T`` / ``SIZEOF_SIZE_T`` / ``SIZEOF_LONG_LONG`` (always
  ``8``). Fold any ``#if SIZEOF_* == n`` selection to the 8-byte arm.
* Endianness. ``WORDS_BIGENDIAN`` is now never defined; delete the
  big-endian arm of every ``#ifdef WORDS_BIGENDIAN`` so only the
  little-endian path remains.
* The ``HAVE_LIB*`` symbols Phase 2's ``PKG_CHECK_MODULES`` switch
  left as foregone conclusions, and any ``HAVE_*`` the
  ``AC_CHECK_FUNCS``/``AC_CHECK_HEADERS`` audit chose to ``AC_DEFINE``
  unconditionally rather than strip in place.

When a folded symbol has no consumer left at all, drop the
``AC_DEFINE`` too: it existed only to be tested.

Done when
---------

* No ``#ifdef``/``#if`` in first-party source tests a symbol whose
  configure value is now a fixed constant.
* Phase 0 tests still pass on amd64.
* ``size(1)`` of ``drizzled`` is unchanged or smaller — this phase
  only removes dead branches.

Risks
-----

* A symbol tested in both a live and a dead branch can hide a behavior
  change if the wrong branch is kept. Cross-check each collapse against
  the value the configure layer actually hardcoded.


.. _spec-revival-lts-template:

Phases 3–9 — LTS bump template
==============================

Each LTS bump follows the same shape. Sub-phases per LTS are listed
afterward.

Template tasks
--------------

1. Bump the ``FROM`` line of the ``Containerfile`` ``base`` stage.
   Base images are pulled from quay.io rather than docker.io so that
   Zuul never trips docker.io's pull rate limits:

   - Through Ubuntu 20.04, use
     ``quay.io/inaugust/unsafe-old-distro-danger:X.04`` — mirrors of
     the EOL Ubuntu LTS images, with ``/etc/apt/sources.list``
     already repointed at ``old-releases.ubuntu.com`` for the
     releases that need it. This is why the ``base`` stage carries no
     ``old-releases`` ``sed``.
   - From Ubuntu 22.04 on, use ``quay.io/opendevmirror/ubuntu:X.04``,
     the OpenDev infrastructure mirror of the still-supported images.

   Both registries publish ``linux/amd64`` and ``linux/arm64``.
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

   Fix test failures.

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

* Switch the ``Containerfile`` ``base`` image from
  ``quay.io/inaugust/unsafe-old-distro-danger`` to
  ``quay.io/opendevmirror/ubuntu:22.04``. 22.04 is still supported, so
  the OpenDev mirror carries it and its apt sources need no rewrite.
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
* ``make test-drizzle`` passes.

Optional: split production and test-client images
-------------------------------------------------

The user's stated target topology for CI:

   "A job builds a production container, then a second job runs all
   the tests against a server running from the container."

If appetite exists in Phase 10, split the Containerfile into:

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
fixed.

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
  Builds the ``test`` Containerfile stage into the buildset registry.
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

**Phase 1 audit (amd64 source sweep).** The first-party source
(``drizzled/``, ``client/``, ``libdrizzle*``) was grepped for x86-only
intrinsics (``__builtin_ia32_*``, ``_mm_*``, the SSE/AVX
``*intrin.h`` headers), inline assembly (``__asm``, ``asm volatile``),
and architecture-pinned constructs (``rdtsc``, ``cpuid``, byte-swap
intrinsics). **No hazards found** — the server carries no hand-written
x86 codegen. Atomics already go through GCC's portable ``__sync``/
``__atomic`` builtins (see ``m4/pandora_have_gcc_atomics.m4``), which
lower correctly on aarch64. The list below therefore stays empty until
an LTS bump introduces something.


.. _spec-revival-future-work:

Future work
===========

Items tracked but explicitly out of scope until a named phase picks
them up:

* **v8 plugin rewrite** against modern V8 or Node embedding. The
  current plugin source stays in tree as a placeholder with
  ``build_conditional=false``.
* **Production/test-client Containerfile split.** Described under
  :ref:`Phase 10 <spec-revival>`. The image we ship is the image we
  test.
* **kewpie revival** (Python 3 port) if/when interest arises. Skipped
  from the test-target list in Phase 0.
* **Symbol visibility.** The build compiles ``drizzled`` and the
  plugins without ``-fvisibility=hidden``; only the ``libdrizzle``
  targets pass ``CFLAG_VISIBILITY`` per-target. Switching the whole
  build to hidden-by-default visibility is worthwhile — smaller
  exported symbol tables, faster loads — but it needs a dedicated
  pass to annotate every genuinely-public symbol first, so it is not
  folded into the Pandora slim-down.
* **Compiler hardening flags.** Phase 1 deleted the probe-based
  ``AX_HARDEN_COMPILER_FLAGS`` machinery (it was already commented out
  in ``configure.ac``), so the build currently applies no hardening.
  Re-introduce ``-fstack-protector-strong``, ``-D_FORTIFY_SOURCE``, and
  ``-Wl,-z,relro,-z,now`` once the revival reaches the 26.04 toolchain,
  where every flag is unconditionally available — GCC 4.6 on 12.04 has
  no ``-fstack-protector-strong``. Land it as its own change so the
  ``perf/`` time series can attribute the instruction-count delta to
  hardening rather than to a build-system phase.
