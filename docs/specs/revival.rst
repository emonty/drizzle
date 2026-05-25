.. _spec-revival:

==========================
Drizzle Revival (2026)
==========================

:Status: In progress
:Target endpoint: Ubuntu 26.04 LTS, multi-arch (amd64 + arm64) container
:Last updated: 2026-05

Status and next
===============

A fast orientation for any agent or contributor opening this file
cold. Read this block first; the rest of the spec is the roadmap.

* **Landed.** Phase 0 (tests in container, Zuul scaffolding sitting
  inert under ``future-zuul.d/``, this spec landed), Phase 1
  (dead-platform strip, ``m4/pandora_*.m4`` simplifications, dead-dep
  plugins deleted), Phase 2 (performance baseline harness under
  ``perf/``), Phase 3 (container hygiene and Phase 0 follow-ups),
  Phase 4 (LTS bump 12.04 → 14.04), Phase 5 (LTS bump 14.04 → 16.04;
  C++11 baseline; ``boost::shared_ptr`` / ``boost::unordered_map``
  swept to ``std::``), and Phase 6 (LTS bump 16.04 → 18.04; Boost
  1.65 link-graph fix-ups; GCC 7 ``-Wimplicit-fallthrough`` /
  ``-Wmemset-elt-size`` / ``-Wbool-compare`` / ``-Wmisleading-
  indentation`` sweep; ``readdir_r`` → ``readdir`` and
  ``__sync_fetch_and_add`` → ``__atomic_load_n``; C++03 dynamic-
  exception-spec sweep; ``drizzle_result_st`` constructor was missing
  two pointer initialisers — Bionic's stricter heap layout exposed
  the bug as a ``free(): invalid pointer`` in DTR's auth path).
  Each landed phase's commits are tagged in commit messages, *under
  their old numbers* for Phases 0–2 — what this spec now calls Phase
  2 appears in older commits as Phase 1.5. See the Renumber note
  below for the full map.
* **In progress.** Phase 7 has its first local layers: C++17 build
  mode is enabled, the base image and bindep selectors are on Ubuntu
  20.04, protobuf 3 / Boost 1.71 / GCC 9 fallout is green on amd64,
  and Focal perf numbers are recorded in ``perf/20.04.json``. PCRE2
  remains the next structural migration; the C++17 mechanical sweep
  currently audits clean.
* **In flight, then paused.** Phase 11 (Pandora slim-down to
  ``m4/drizzle.m4``) — what older commit messages call Phase 2. A
  number of build-setup macros have folded into ``m4/drizzle.m4``
  (version, C++ standard, dtrace, platform, optimize, warnings, VC
  info); the headline work (library-presence macros to
  ``PKG_CHECK_MODULES``, killing the last ``AX_PTHREAD`` caller,
  finishing the bzr/svn/hg strip, the ``PANDORA_`` → ``DRIZZLE_``
  rename) is open but **deliberately deferred** until after the LTS
  ratchet reaches 26.04.
* **Next.** Finish Phase 7's PCRE2 migration and final C++17-source
  audit, then re-run the Focal build/test/perf checks after that
  structural slice. The Pandora slim-down (Phase 11) is still held
  back because the existing Pandora layer still works, and the LTS
  ratchet brings in modern pkg-config / Boost / OpenSSL / protobuf
  that make the macro conversion cleaner than fighting the 12.04
  toolchain. After the ratchet reaches 26.04: Phase 11 (Pandora
  slim-down), Phase 12 (constant-fold), Phase 13 (plugin
  enable-by-default sweep), Phase 14 (Sphinx-only docs).
* **Carry-overs from Phase 6.** Two pre-existing items surfaced by
  the Bionic verification but deliberately left for follow-up: the
  ``libdrizzle-1.0/t/`` race over hard-coded port 12399 is currently
  papered over with ``AUTOMAKE_OPTIONS = serial-tests``; the longer
  question is whether ``libdrizzle-1.0`` should stay at all
  (drizzled and ``client/`` link against ``libdrizzle-2.0``; only
  ``unittests/libdrizzle_test.cc`` still pulls in 1.0). And ``arm64``
  verification was skipped on this laptop session — Zuul's arm64
  nodes will pick up the gate.

**Renumber note.** This revision renumbered phases for linear
sequencing. Map: 1.5 → 2, 1.6 → 3, old 3–9 → 4–10, old 2 → 11, old
2.5 → 12, old 10 → 13, old 11 → 14. Commits landed under the old
numbers keep their commit messages; future commits use the new
numbers.


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
* The in-tree plugins are registered via ``config/pandora-plugin.ini``
  and a ``config/pandora-plugin`` Python enumeration script.
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
* Large-file support — don't probe. On LP64 Linux ``off_t`` is
  already 8 bytes by default, so ``-D_FILE_OFFSET_BITS=64`` is a
  no-op; ``config/top.h`` ``#undef``\ s any caller-supplied value as
  deliberate neutralization (an outer build that sets
  ``_FILE_OFFSET_BITS=64`` is fine; one that sets it to ``32`` won't
  silently downgrade us).
* POSIX/glibc-guaranteed functions (``memmove``, ``strerror``,
  ``inet_ntoa``, etc.) — delete the ``AC_CHECK_FUNCS`` probe; either
  delete the corresponding ``#ifdef HAVE_*`` in source or
  ``AC_DEFINE`` the symbol unconditionally.
* Standard C++ headers (``<cstdint>``, ``<unordered_map>``,
  ``<memory>``) — assume present.
* Visibility — don't probe ``gl_VISIBILITY``; hardcode
  ``CFLAG_VISIBILITY="-fvisibility=hidden"`` and apply it per-target
  on the libdrizzle libraries. A build-wide
  ``-fvisibility=hidden -fvisibility-inlines-hidden`` pass needs
  every genuinely-public symbol annotated first and is tracked in
  :ref:`spec-revival-future-work`.
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

Current in-tree violations to clean up (cleanup itself lives under
:ref:`Phase 3 <spec-revival-container-hygiene>`):

* ``configure.ac:47-49`` — describes what ``gl_VISIBILITY`` used to do.
* ``m4/drizzle.m4:35-39`` — explains what ``DRIZZLE_BUILD_SETUP``
  replaces.
* ``m4/drizzle.m4:369-371`` — narrates the prior probe-gated warning
  flags.

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

Listed in execution order. The Pandora slim-down (Phase 11) and the
constant-fold (Phase 12) sit *after* the LTS ratchet by design — see
the Status and next preamble for the rationale.

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
     - Performance baseline harness
     - 12.04
     - M
   * - 3
     - Container hygiene and Phase 0 follow-ups
     - 12.04
     - S
   * - 4
     - LTS bump 14.04
     - 14.04
     - M
   * - 5
     - LTS bump 16.04 (C++11 baseline)
     - 16.04
     - M
   * - 6
     - LTS bump 18.04 (Boost 1.65, OpenSSL 1.1, fs v2→v3)
     - 18.04
     - L
   * - 7
     - LTS bump 20.04 (protobuf 3, C++17, PCRE2)
     - 20.04
     - XL
   * - 8
     - LTS bump 22.04 (OpenSSL 3)
     - 22.04
     - L
   * - 9
     - LTS bump 24.04
     - 24.04
     - M
   * - 10
     - LTS bump 26.04 (multi-arch gating, clean bindep)
     - 26.04
     - M
   * - 11
     - Pandora slim-down to ``m4/drizzle.m4``
     - 26.04
     - M
   * - 12
     - Constant-fold the hardcoded defines into the source
     - 26.04
     - S
   * - 13
     - Plugin enable-by-default sweep
     - 26.04
     - L
   * - 14
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
   podman run --rm drizzle:test

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
  Too slow and/or Python-2 dependent. Revisit in Phase 13 if useful.

Container test runtime needs
----------------------------

* Writable vardir under ``/build`` (the build cache mount).
* ``DTR_BUILD_THREAD=$$`` for port-offset uniqueness within a single
  container. Server and client both live inside the container's
  netns, so default networking is sufficient; no ``--net=host``.
* No "drizzle" UNIX user required (the historical guard has already
  been removed; see ``a82202956``).

Done when
---------

* ``podman build --target=build`` succeeds on amd64 (regression check
  of current behavior).
* ``podman build --target=test`` succeeds on amd64.
* ``podman run --rm drizzle:test`` exits 0
* ``podman build --platform linux/arm64 --target=build`` succeeds
  (configure + compile only; tests not gating until Phase 10).
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
  ``m4/drizzle.m4`` in Phase 11.)
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
  The Phase 1 audit's scope turned out to be narrower than its
  "no hazards found" wording suggested — see the multi-arch
  hazards appendix for the rewritten honest result and the
  remaining queue.

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
``m4/drizzle.m4`` in Phase 11 — writing the macro afresh drops the dead
arms without a throwaway in-place edit first. The vendored m4 files
(``boost.m4``, the gettext set, ``ax_pthread.m4``) keep their
portability code: they are upstream and regenerated, not hand-edited.
The ≥40% ``wc -l m4/*.m4`` reduction is consequently a Phase 11
outcome, measured there.

* Phase 0 tests still pass on amd64.
* ``podman build --platform linux/arm64 --target=build`` still gets
  through ``./configure`` cleanly. Test failures on arm64 are recorded
  in :ref:`spec-revival-multiarch-hazards` but not gating until
  Phase 10.

Risks
-----

* Removing ``gnulib`` may surface latent dependencies. Land that
  removal in its own commit so a revert is cheap.
* ``m4/pandora_extensions.m4`` provides ``AC_USE_SYSTEM_EXTENSIONS``
  wrapping. Verify it isn't load-bearing before deletion.


Phase 2 — Performance baseline harness
======================================

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
server code. It exists so that subsequent phases have a signal.

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
  ``perf/14.04.json`` when Phase 4 lands, ``perf/16.04.json`` for
  Phase 5, and so on. ``perf/baseline.json`` (the 12.04 result) is
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


.. _spec-revival-container-hygiene:

Phase 3 — Container hygiene and Phase 0 follow-ups
==================================================

Objective
---------

Land the parts of the Phase 0 test-image contract that weren't
actually realized (built tree in the image layer, runtime ``CMD``,
per-arch cache isolation, ``m4/drizzle.m4`` in ``EXTRA_DIST``),
tighten dependency hygiene, and mirror this spec's decisions into
the project's orientation docs and source-comment hygiene. The phase
touches only build-system, container, and documentation files — no
C++ source changes.

This phase exists because every subsequent phase's "every commit
green" invariant relies on ``podman run drizzle:test`` actually
running tests against the just-built tree. Today it doesn't.

Tasks
-----

Container hygiene (each item is a candidate commit, ordered):

* Add ``m4/drizzle.m4`` to ``EXTRA_DIST`` in ``Makefile.am``. Lands
  first — protects ``make distcheck`` while the rest of the stack
  reshuffles the container build.
* Make the build cache per-arch:
  ``id=drizzle-build-${TARGETPLATFORM}`` in the three
  ``--mount=type=cache`` lines of ``Containerfile``. amd64 and
  arm64 stop reusing each other's object files and configure
  results.
* Materialize the built tree into the image layer (``cp -au`` out
  of the cache mount inside the ``build`` stage); repoint ``test``
  and ``perf`` stages at the in-image path; add
  ``CMD ["tools/run-tests.sh"]`` to the ``test`` stage so
  ``podman run drizzle:test`` runs tests at runtime; drop the
  build-time ``RUN tools/run-tests.sh``. One commit — the four
  pieces only make sense together.
* Confirm ``tools/regress.sh`` runs the runtime contract end to
  end (``podman run drizzle:regress-test``, no ``--net=host``);
  align help text if needed.
* Move ``rabbitmq-server`` from ``[compile platform:dpkg]`` to
  ``[test platform:dpkg]`` in ``bindep.txt``. Safe only after the
  test image carries its own tree *and* installs the ``test``
  bindep profile.
* Pin the perf-harness CPAN fetch in ``Containerfile`` with
  ``ADD --checksum=sha256:<pin>`` for the ``DBD::drizzle`` tarball.
  Remote fetch + checksum is the preferred pattern — vendoring is
  deliberately avoided.
* Verify the cache reconfigure behavior. The current
  ``[ ! -f Makefile ]`` guard exists so a no-op iteration doesn't
  re-run ``autoreconf -i && ./configure`` (which would churn
  ``config.h`` and discard the build cache on every build). The
  expectation is that the automake-generated ``Makefile`` already
  detects edits to ``configure.ac`` / ``m4/*.m4`` / ``Makefile.am``
  and re-runs the right pieces from inside the cache. Verify
  during the next test pass; only add a smarter cache-bust (hash
  the build-system inputs into a stamp file, compare on entry, run
  ``autoreconf -i && ./configure`` on mismatch) if the self-regen
  turns out to be unreliable across the cache mount. Do **not**
  drop the guard.

Companion doc and convention cleanup (separate sub-stack — mirror
this spec's decisions into the orientation docs and source-comment
hygiene):

* Update ``AGENTS.md`` to match the spec: drop ``--net=host`` from
  the verification example, refresh the test-runtime contract
  line, replace any hardcoded plugin count with phrasing.
* Rewrite ``README.rst`` so the front matter routes contributors to
  the ``Containerfile`` / ``bindep.txt`` / ``tools/regress.sh``
  flow. No Docker, no PPAs, no source-install. Deeper docs pruning
  stays in Phase 14.
* Clean up the gravestone comments listed in the
  Foundational principles "No gravestone comments" violation list
  above — rewrite as forward-looking constraints, or delete.
* ``future-zuul.d/projects.yaml`` currently schedules only
  ``drizzle-build-image`` (amd64). Either add a scheduled
  ``drizzle-build-image-arm64`` per the CI strategy section, or
  drop a TODO comment naming it as a known gap to close at
  activation time.

Done when
---------

* ``podman build --target=test -t drizzle:test .`` followed by
  ``podman run --rm drizzle:test`` runs tests and exits 0; no
  ``podman run`` invocation in the spec, ``AGENTS.md``, or
  ``tools/regress.sh`` uses host networking.
* ``make distcheck`` passes.
* amd64 and arm64 builds reuse nothing from each other's cache.
* ``grep -niE 'docker|dockerfile' README.rst`` returns empty.
* No gravestone comments remain at the three sites listed under
  Foundational principles.

Risks
-----

* The reconfigure-behavior verification may find that automake's
  self-regen doesn't fire reliably across the cache mount, in
  which case we add the stamp-based cache-bust noted above.
  Dropping the ``[ ! -f Makefile ]`` guard outright is *not* the
  fix — it makes the cache useless.
* The ``rabbitmq-server`` profile move must land *after* the test
  image actually installs the ``test`` bindep profile; reordering
  breaks DTR.


.. _spec-revival-lts-template:

Phases 4–10 — LTS bump template
===============================

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

      podman build --platform linux/amd64 --target=build \
        -t drizzle:phaseN-amd64-build .

   Triage compile breakage. Fix code. ``-Wno-xxx`` permitted only as
   last resort, with a written rationale in the commit message.

4. Test on amd64:

   .. code-block:: console

      podman build --platform linux/amd64 --target=test \
        -t drizzle:phaseN-amd64-test .
      podman run --rm drizzle:phaseN-amd64-test

   Fix test failures.

5. Build on arm64 (build-only readiness until Phase 10):

   .. code-block:: console

      podman build --platform linux/arm64 --target=build \
        -t drizzle:phaseN-arm64-build .

   Must succeed. Test runs on arm64 are encouraged for local
   validation but not gating until Phase 10, so no ``--target=test``
   build and no arm64 ``test`` tag exist for Phases 4–9.

6. ``make distcheck`` must pass on amd64.
7. The per-arch tags from steps 3–5 are the artifacts the ``promote``
   pipeline later pushes (re-tagged with the merge SHA + phase name):
   ``drizzle:phaseN-amd64-build``, ``drizzle:phaseN-amd64-test``,
   ``drizzle:phaseN-arm64-build``. Phase 10 adds
   ``drizzle:phase10-arm64-test`` to the set when arm64 becomes
   test-gating.

Phase-specific notes
--------------------

Phase 4 — Ubuntu 14.04
~~~~~~~~~~~~~~~~~~~~~~

Lightest LTS bump. Boost 1.46 → 1.54; protobuf still 2.x; OpenSSL
still 1.0. Mostly warning-flag drift.

Phase 5 — Ubuntu 16.04 (C++11 baseline)
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

Phase 6 — Ubuntu 18.04 (Boost 1.65, OpenSSL 1.1)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

First real friction phase. Sub-stacks:

* Audit ``#include <boost/...>`` across ``drizzled/`` and ``plugin/``.
  Replace ``boost/foreach.hpp`` with C++11 range-for (one commit per
  consumer).
* Migrate ``boost::filesystem`` v2 API to v3. Dedicate this to its
  own contributor; it's the worst single transition of Phase 6.
* OpenSSL 1.1 makes ``SSL_CTX`` and friends opaque. Replace direct
  field access with accessor functions. Audit ``plugin/auth_*``,
  ``client/``, ``drizzled/``.
* Add ``-Wimplicit-fallthrough`` annotations or ``[[fallthrough]];``.

Phase 7 — Ubuntu 20.04 (protobuf 3, C++17, PCRE2)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Hardest phase. Four sub-stacks; the order below is the recommended
sequencing — the compiler-mode flip lands first so the C++17 sweep
has something to compile against.

* **7.0: Enable C++17 in the build.** Set
  ``AX_CXX_COMPILE_STDCXX([17],[noext],[mandatory])`` (or the
  equivalent that replaces ``PANDORA_CHECK_CXX_STANDARD``) and
  confirm ``podman build --target=test`` stays green before any
  C++17-only source change lands. Mandatory: no ad-hoc
  ``-std=c++17`` introduction inside a later patch.
* **7a: protobuf 2 → 3.** Regenerate ``.pb.cc`` / ``.pb.h`` at
  configure time; stop versioning generated code. Update API uses
  (``set_allocated_*`` semantics; ``Reflection`` API churn; arena
  allocation).
* **7b: libpcre1 → libpcre2.** Rewrite ``m4/pandora_have_libpcre.m4``
  (or its replacement in ``m4/drizzle.m4``) to
  ``PKG_CHECK_MODULES([PCRE2],[libpcre2-8])``. Audit
  ``plugin/regex_policy/`` and any other direct PCRE callers.
* **7c: C++17 sweep.** ``std::auto_ptr`` → ``std::unique_ptr``;
  ``std::random_shuffle`` → ``std::shuffle`` + ``std::mt19937``;
  ``register`` keyword removed; ``throw()`` → ``noexcept``.

Bump ``BOOST_REQUIRE([1.46])`` to ``BOOST_REQUIRE([1.71])`` in
``configure.ac``.

Phase 8 — Ubuntu 22.04 (OpenSSL 3)
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

Phase 9 — Ubuntu 24.04
~~~~~~~~~~~~~~~~~~~~~~

Mostly free. GCC 13 / Boost 1.83 ``-Werror`` casualty sweep.

Phase 10 — Ubuntu 26.04 (final landing)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* We should be able to test building directly on the laptop.
* We may consider adding Fedora support to bindep.txt at this point.
  Maybe.
* If we have running zuul jobs:
  * **arm64 becomes fully gating.** ``make test-drizzle`` must pass on
    both architectures. Extend step 5 of the LTS bump template to also^
    build ``--target=test`` on arm64 and to run the resulting
    ``drizzle:phase10-arm64-test`` image; fix arm64-specific test
    failures accumulated during Phases 4–9.
  * Make multi-node jobs using buildset registry for coordiation
    to do native arm64 and amd64 builds, then produce a final
    manifest like:

  .. code-block:: console

     podman manifest create drizzle:26.04
     podman manifest add drizzle:26.04 drizzle:phase10-amd64-test
     podman manifest add drizzle:26.04 drizzle:phase10-arm64-test

.. _spec-revival-pandora-slimdown:

Phase 11 — Pandora slim-down to ``m4/drizzle.m4``
=================================================

Objective
---------

Excise the Pandora macro layer as a *layer* while preserving every
piece of behavior it provides. End state: a single ``m4/drizzle.m4``
(~400 lines) plus a small number of upstream third-party m4 files
(``boost.m4``, the kept-deliberately ``pandora_plugins.m4``,
gettext machinery).

This phase runs on the 26.04 toolchain rather than the 12.04 one
because the LTS ratchet ahead of it brings modern pkg-config, Boost,
OpenSSL, and protobuf — converting the library-presence macros to
``PKG_CHECK_MODULES`` is cleaner against the modern stack than against
the 12.04 readline-without-pc situation that motivated keeping
``pandora_have_libreadline.m4`` around. Partial work landed earlier
(``DRIZZLE_BUILD_SETUP`` skeleton; several macros folded into
``m4/drizzle.m4``) remains; this phase resumes from that state.

Tasks
-----

Several build-setup macros have already folded into
``m4/drizzle.m4`` (version, C++ standard, dtrace, platform, optimize,
warnings, VC info) and ``DRIZZLE_BUILD_SETUP`` is in place at
``configure.ac:38``. The remaining work:

* **Library-presence macros — convert to ``PKG_CHECK_MODULES``,
  one commit each, protobuf first.** ``pandora_have_protobuf.m4``
  ``AC_REQUIRE``\ s ``AX_PTHREAD``, which is the last live caller of
  the pthread probe; replacing it with ``PKG_CHECK_MODULES`` removes
  ``AX_PTHREAD`` from the build entirely. Then ``libz``, ``libssl``,
  ``libpcre`` (each ships a pkg-config file on the 26.04 base; pcre1
  → pcre2 happened in Phase 7). ``libdl`` becomes
  ``AC_SEARCH_LIBS([dlopen],[dl])`` — ``dlopen`` is in glibc and
  there is no ``libdl.pc`` on any release. ``readline`` finally
  converts to ``PKG_CHECK_MODULES`` as well now that ``readline.pc``
  is universally available on the 26.04 base. Each replacement
  preserves the variables the ``Makefile.am`` files consume —
  ``$(LIBZ)``, ``$(LIBSSL)``, ``$(LIBPCRE)``/``$(LTLIBPCRE)``,
  ``$(LIBPROTOBUF)``/``$(LTLIBPROTOBUF)``, ``$(LIBDL_LIBS)`` —
  assigned from the ``*_LIBS`` pkg-config output, plus the
  ``HAVE_LIB*`` ``config.h`` defines.
* **bzr/svn/hg version-control arms.** Commit ``63ebbc28`` claims
  this strip; in reality ``m4/drizzle.m4:492-593`` still defines
  ``PANDORA_TEST_VC_DIR`` and ``PANDORA_BUILDING_FROM_VC`` with all
  four arms and still shells out to ``bzr``. Land the actual
  deletion: keep only the git arm; the ``bzr revno`` / ``bzr nick``
  / ``bzr log`` extraction and the svn/hg branches go.
* **LP64 sizes in top-level ``configure.ac``** are only partially
  hardcoded. Add ``SIZEOF_VOIDP=8`` and ``SIZEOF_LONG=8`` next to
  the existing ``SIZEOF_OFF_T`` / ``SIZEOF_SIZE_T`` /
  ``SIZEOF_LONG_LONG`` ``AC_DEFINE`` lines.
* **``PANDORA_`` → ``DRIZZLE_`` rename**, landed together with
  ``config/pandora-plugin``'s emitted standalone-plugin template
  update so out-of-tree plugin generation keeps working through the
  rename. Macros now living in ``m4/drizzle.m4``
  (``PANDORA_MSG_ERROR``, ``PANDORA_WARNINGS``, ``PANDORA_PLATFORM``,
  ``PANDORA_VERSION``, ``PANDORA_OPTIMIZE``,
  ``PANDORA_VC_INFO_HEADER``, etc.) all rename, with call sites in
  ``configure.ac`` updated; the configure summary at
  ``configure.ac:243`` still prints ``pandora-build version`` —
  fix in the same stack. Land *after* the library-macro
  conversion so the macro set is stable. Skip the deliberately-kept
  ``pandora_plugins.m4`` and the plugin-dependency ``have-lib``
  macros still called by ``plugin/*/plugin.ac``.
* **Revisit ``config/pandora-plugin`` as a generator.** The Python 2
  script still earns its keep during the LTS ratchet because changing
  the plugin enumeration machinery would be a structural rewrite. Once
  Phase 11 owns the Pandora cleanup directly, replace it with a smaller
  maintained generator or a generated-file-free build description
  rather than continuing to carry Python as the default answer.
* **Delete the now-unused ``m4/pandora_*.m4`` files** as each one's
  last caller goes away. One commit per file.
* **InnoDB is an upstream-merge surface — do not touch.** Earlier
  drafts of this phase contemplated stripping
  ``AC_CHECK_SIZEOF`` probes and dead-platform arms from
  ``plugin/innobase/plugin.ac``; that strip is withdrawn. Future
  MySQL / MariaDB cherry-picks depend on InnoDB's cross-platform
  arms (and their attendant configure/source symbol mismatches)
  staying mergeable. The InnoDB issues are recorded in
  :ref:`spec-revival-cxx-debt` as known latent, deliberate
  non-fixes.

Done when
---------

* The Pandora build-setup layer is gone: ``m4/drizzle.m4`` is the only
  orchestration file, and the surviving ``pandora_*.m4`` files are
  ``pandora_plugins.m4`` plus the plugin-dependency ``have-lib``
  macros still called by ``plugin/*/plugin.ac`` (``libaio``,
  ``libcurl``, ``libevent``, ``libgearman``, ``libldap``,
  ``libmemcached``, ``libv8``, flex). Those retire in Phase 13 with
  the plugin sweep — Phase 11 does not reach the original "≤2 files"
  target, and is not meant to.
* ``plugin/innobase/`` is intentionally untouched — its
  cross-platform arms stay so future MySQL / MariaDB cherry-picks
  remain mergeable.
* ``configure.ac`` is under 250 lines.
* ``grep -rnE 'solaris|freebsd|SUNCC|INTELCC|i386|powerpc|sparc'``
  over the first-party m4 (everything but ``boost.m4`` and the
  vendored gettext set) returns empty.
* ``wc -l m4/*.m4`` shows a substantial drop versus the Phase 0
  baseline. The original ≥40% figure assumed the plugin have-lib
  macros also went; with those correctly deferred to Phase 13, report
  the actual figure rather than forcing it.
* Phase 0 tests still pass on amd64.
* ``./configure`` succeeds on arm64.

Risks
-----

* ``pandora_plugins.m4`` is the most opaque file in the layer — it
  generates ``am__plugin_LIST`` and the load-list. Treat it as
  load-bearing infrastructure. Do not rewrite; verify it still works
  after surrounding deletions.


Phase 12 — Constant-fold the hardcoded defines into the source
==============================================================

Objective
---------

Phase 1 replaced a raft of autoconf probes with fixed ``AC_DEFINE``
constants, and Phase 11 adds more as it moves to
``PKG_CHECK_MODULES``. A ``#define`` whose value can no longer vary
makes every ``#ifdef`` and ``#if`` that tests it dead-reckonable: the
preprocessor branch is now always-taken or never-taken, and any C/C++
``if`` written against the value is a constant condition.

Phases 1 and 11 stop at the configure layer. Phase 12 follows each
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
* The ``HAVE_LIB*`` symbols Phase 11's ``PKG_CHECK_MODULES`` switch
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


Phase 13 — Plugin enable-by-default sweep
=========================================

Objective
---------

Every plugin in ``plugin/`` builds on the 26.04 target by default.
``bindep.txt`` covers every plugin's dep unconditionally. No
``build_conditional=`` line survives (modulo the v8 plugin, which
remains opt-out pending Node-based rewrite).

Tasks
-----

* Build every in-tree plugin on 26.04 with the default ``configure``
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

If appetite exists in Phase 13, split the Containerfile into:

* ``production`` stage — ``drizzled`` binary + minimal runtime deps,
  no test harness, no perl.
* ``test-client`` stage — DTR/perl tooling but no ``drizzled``.

Then ``drizzle-dtr-tests`` in CI runs the production image as a
long-running container (``podman run -d``), and the test-client image
drives DTR against it via ``--network=container:<prod>`` or a podman
pod. This gives us the property that **the image we ship is the image
we test**.

Not gating for Phase 13 completion; tracked under
:ref:`spec-revival-future-work`.


Phase 14 — Sphinx-only docs
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
* Sweep the installing/contributor docs for stale install paths
  (distro packages, PPAs, source-install,  ``./bootstrap``) and
  reroute to the container-first
  ``Containerfile`` / ``bindep.txt`` / ``tools/regress.sh`` flow.
  Phase 3 fixes the README front matter; this finishes the rest.


.. _spec-revival-ci:

CI strategy — Zuul on OpenDev
=============================

Activation status
-----------------

The Zuul pipeline files described in this section live under
``future-zuul.d/`` and are not currently active — they are inert
scaffolding waiting on OpenDev Zuul tenant registration and the
referenced playbooks. When activated, the files move to ``zuul.d/``
and the same definitions take effect.

Until then: amd64 build+test gating once activated; arm64 build-only
readiness until Phase 10, at which point arm64 becomes test-gating
too. ``future-zuul.d/projects.yaml`` currently schedules only
``drizzle-build-image`` (amd64); ``drizzle-build-image-arm64`` is a
known gap to close at activation time and is tracked in
:ref:`Phase 3 <spec-revival-container-hygiene>`.

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
``drizzle:phase4-ubuntu1404``) in addition to the SHA. This gives us a
permanent regression archive: any future change can
``podman run drizzle:phaseN make test-drizzle`` to verify it doesn't
regress prior phases.


.. _spec-revival-multiarch-hazards:

Appendix — Multi-arch hazards
=============================

A running list, populated during Phase 1's architecture audit and
extended through Phases 4–9. Each entry describes an x86-specific or
endianness-sensitive construct in the source and a sketch of the
aarch64 fix.

**Phase 1 audit scope (honest restatement).** The original audit
grepped only ``drizzled/``, ``client/``, and ``libdrizzle*`` for the
narrow construct set ``__builtin_ia32_*`` / ``_mm_*`` / SSE-AVX
``*intrin.h`` / ``__asm`` / ``asm volatile`` / ``rdtsc`` / ``cpuid``
and reported "no hazards found." That result was correct *for that
scope*; it was not a sweep of all multi-arch hazards in the tree. The
grep did not cover ``plugin/``, did not check for ``__i386__`` /
``WORDS_BIGENDIAN`` / pthread-yield / ``SIZEOF_*`` conditionals, and
did not look at unaligned-access fast paths or release-store
correctness. Items below were surfaced by a broader pass.

``plugin/innobase/`` is **out of scope** for this appendix per
:ref:`spec-revival-cxx-debt` — InnoDB is treated as an upstream-merge
surface, so its existing cross-platform arms stay untouched and
its arm64 behavior travels with the upstream code we cherry-pick.

Hazards to address (each gets a triage during a Phase that
naturally touches the file, or earlier if a contributor wants
to land it standalone):

* ``drizzled/korr.h:31-58`` — ``__i386__``-gated unaligned-access
  fast path. aarch64 silently drops into the portable byte-by-byte
  branch, which works but loses the optimization. Decision: convert
  to ``__attribute__((aligned(1)))`` / ``__builtin_memcpy``-based
  unaligned load that the compiler emits well on both arches, or
  delete the fast path and rely on the portable branch.
* ``drizzled/korr.h:88-93``, ``plugin/myisam/myisampack.h:28-41``,
  ``libdrizzle-1.0/constants.h:512-523`` — signed byte-unpack
  macros left-shift signed bytes into high bits, which is C++
  undefined behavior. See :ref:`spec-revival-cxx-debt` for the
  rewrite plan; the arm64 angle is that newer compilers on the
  ratchet can optimize around the UB and produce a different
  result per arch.
* ``drizzled/atomics.h`` plus ``drizzled/atomic/gcc_traits.h:81-85``
  — ``store_with_release`` is implemented as a plain assignment
  through a ``volatile`` pointer, which does not provide release
  ordering on aarch64. See :ref:`spec-revival-cxx-debt`.
* ``drizzled/session.h:512`` and ``drizzled/drizzled.cc:231-233``
  — cross-thread kill/shutdown state uses ``volatile`` instead of
  atomics. Often masked on x86; not on arm64. See
  :ref:`spec-revival-cxx-debt`.
* ``drizzled/field/*``, ``libdrizzle/sha1.cc``,
  ``plugin/myisam/*`` — broader pass owed. Grep for
  ``WORDS_BIGENDIAN``, ``__i386__``, ``__x86_64__``, ``SIZEOF_*``
  conditionals, pthread-yield wrappers, byte-swap intrinsics.
  Populate this list as the audit lands.


.. _spec-revival-cxx-debt:

Appendix — C++ and threading correctness debt
=============================================

Items a broader review surfaced that are real but better caught and
fixed when the LTS-bump compiler ratchets (Phases 6, 7, 9) raise
them as warnings or errors. This appendix is the discovery trail,
not a parallel work plan to execute now. A contributor with
appetite can land any of them as a standalone commit; otherwise the
natural ratchet delivers them in context.

* **Signed byte-unpack shift UB** — ``drizzled/korr.h:88-93``,
  ``plugin/myisam/myisampack.h:28-41``,
  ``libdrizzle-1.0/constants.h:512-523``. The unpackers left-shift
  signed (or signed-promoted) byte values into high bits, which is
  C++ undefined behavior. Rewrite as unsigned accumulation with an
  explicit final cast for the signed-result variants; add unit
  coverage for high-bit 2-, 3-, and 4-byte signed and unsigned
  decoders.
* **Cross-thread ``volatile`` state** — ``drizzled/session.h:512``
  (kill state), ``drizzled/drizzled.cc:231-233`` (select-loop and
  shutdown globals). ``volatile`` is not synchronization in C++;
  these are data races that x86 has masked in practice. Convert to
  real atomics or to existing mutex-protected state; add stress
  coverage for concurrent ``KILL`` and shutdown paths.
* **``atomic<T>::operator=`` is not a release store** —
  ``drizzled/atomic/gcc_traits.h:81-85``. ``store_with_release`` is
  implemented as plain assignment through a ``volatile`` pointer,
  which provides no release ordering on aarch64 and races readers
  that expect the wrapper to provide atomic semantics. Use
  ``__atomic_store_n(..., __ATOMIC_RELEASE)`` (with a documented
  fallback for the 12.04 compiler if needed); extend
  ``unittests/atomics_test.cc`` beyond single-thread arithmetic.
* **``Join`` cloned with ``memcpy``** —
  ``drizzled/join.cc:1289-1292``. ``Join`` is noncopyable and owns
  non-trivial members, so the raw ``sizeof(Join)`` copy is
  object-lifetime UB and will trip ``-Wclass-memaccess`` on a
  modern compiler. Replace with an explicit snapshot/restore
  object, or save and restore only the fields needed for
  temporary-table state.
* **``COM_PROCESS_KILL`` payload byte order** — see
  :ref:`spec-revival-investigation`; tracked there because it needs
  a behaviour test before any patch.
* **json_server lifecycle regression test owed** —
  ``plugin/json_server/json_server.cc:697-704``. The pushed fix
  signals once and joins every worker; the design is plausible but
  has no DTR test pinning the behavior. Add a plugin-level test
  that starts ``json_server`` with ``max_threads > 1`` and
  exercises clean shutdown or plugin unload.

InnoDB-related entries below are **deliberate non-fixes** per the
upstream-merge policy (see :ref:`spec-revival-container-hygiene` and
Phase 11 Done-when). They are listed so future contributors recognise
them as known and intentional, not oversights:

* **InnoDB configure/source symbol mismatch.**
  ``plugin/innobase/plugin.ac:91-93`` defines
  ``HAVE_ATOMIC_PTHREAD_T``, but ``plugin/innobase/include/os0sync.h``
  checks ``HAVE_IB_ATOMIC_PTHREAD_T_GCC`` and
  ``HAVE_IB_ATOMIC_PTHREAD_T_SOLARIS``. Similarly,
  ``plugin/innobase/plugin.ac:164-166`` defines
  ``IB_HAVE_PAUSE_INSTRUCTION`` while
  ``plugin/innobase/include/ut0ut.h`` checks
  ``HAVE_PAUSE_INSTRUCTION`` / ``HAVE_FAKE_PAUSE_INSTRUCTION``. The
  configure probes have been silently dead for ~15 years; the
  source already falls through to the portable branch. Do not fix
  in-tree — the cross-platform arms are MySQL-shaped and the right
  fix arrives via the next InnoDB cherry-pick from upstream.


.. _spec-revival-investigation:

Appendix — Investigation backlog
================================

Items that are *probably* bugs but need a test or a protocol-spec
read before any patch is justified. Drive each one to a yes/no
answer; convert to a normal Phase task or close with a note.

* **``COM_PROCESS_KILL`` payload byte order.**
  ``plugin/mysql_protocol/mysql_protocol.cc:243-245`` maps MySQL
  command ``12`` to the internal ``COM_KILL`` without translating
  the payload. ``drizzled/sql_parse.cc:246-258`` reads the internal
  payload as a four-byte value and converts it with ``ntohl``,
  while ``libdrizzle/conn.cc:730-732`` sends native kill ids with
  ``htonl``. MySQL protocol integer payloads are documented as
  little-endian. Native Drizzle clients and MySQL-protocol clients
  therefore appear to disagree about byte order for the same
  internal command. Tasks:

  - Confirm the MySQL protocol spec's payload byte order for
    command ``12``.
  - Write a raw-protocol DTR test that sends ``COM_PROCESS_KILL``
    with a known thread id over the MySQL-protocol port and
    asserts the right thread dies.
  - If the test fails, fix the payload translation in
    ``plugin/mysql_protocol/mysql_protocol.cc:243-245`` (or split
    native vs MySQL kill parsing).
  - If the test passes, write a short explanatory note here and
    close the item.


.. _spec-revival-future-work:

Future work
===========

Items tracked but explicitly out of scope until a named phase picks
them up:

* **v8 plugin rewrite** against modern V8 or Node embedding. The
  current plugin source stays in tree as a placeholder with
  ``build_conditional=false``.
* **Production/test-client Containerfile split.** Described under
  Phase 13. The image we ship is the image we test.
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
