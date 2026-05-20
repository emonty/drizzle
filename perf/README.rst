Performance baseline
====================

Phase 1.5 of the revival (see ``docs/specs/revival.rst``) tracks
performance with synthetic, hardware-independent counters so that every
later phase can be judged against a frozen baseline. Wall-clock time is
not used — CI runs on shared hardware.

Contents
--------

``baseline.json``
   The Phase 1 reference numbers — Ubuntu 12.04. ``tools/perf.sh``
   diffs every run against this file, so a per-commit run shows how
   far the tree has moved from the 12.04 starting point. It is **never
   overwritten**.

``<release>.json`` (``14.04.json``, ``16.04.json``, …)
   A phase result, recorded at the close of each LTS phase and never
   modified afterwards. The growing set of these files is the
   performance time series — every distro release's numbers in one
   place. Once the revival reaches 26.04 we revisit how to
   re-baseline and measure going forward.

``last-run.json``
   Written by ``tools/perf.sh`` on every run. Not committed.

DBD::drizzle (the libdrizzle Perl DBI driver that sql-bench needs) is
not packaged. The ``perf`` Containerfile stage fetches the pinned CPAN
release with an ``ADD`` instruction; ``tools/perf.sh`` builds it
against the freshly installed libdrizzle.

How the numbers are produced
----------------------------

``tools/perf.sh`` (the ``perf`` Containerfile stage entrypoint) runs a
fixed subset of sql-bench against an installed ``drizzled``:

* once under **callgrind** — instruction count (``ir``) is the headline
  metric; ``estimated_cycles`` folds in simulated cache misses and
  branch mispredicts;
* once under **massif** — peak heap;
* plus ``size(1)`` on ``drizzled`` and the plugin ``.so`` files.

The workload itself is deterministic: sql-bench's "random" keys are a
fixed shuffle, ``--loop-count`` is pinned, and no ``NOW()``/``RAND()``
is used. Changing the workload parameters in ``tools/perf.sh``
invalidates the baseline — rebaseline in the same commit.

The *instruction count* still carries a **~2% run-to-run noise
floor**: drizzled is multithreaded and callgrind sums every thread, so
background-thread work (InnoDB and friends) varies between runs. Read
the diff accordingly — sub-~3% movement is noise; the harness is for
catching the larger shifts an LTS bump or a real refactor produces.
``size`` is bit-exact and ``peak_heap`` is near-stable.

Recording a phase result
------------------------

At the end of a phase::

    podman build --platform linux/amd64 --target=perf .

Take the JSON between the ``PERF METRICS BEGIN/END`` markers in the
build output and commit it as ``perf/<release>.json`` — e.g.
``perf/14.04.json`` when Phase 3 lands. Do **not** overwrite
``baseline.json``: each release's file is kept so the whole series
stays visible together.
