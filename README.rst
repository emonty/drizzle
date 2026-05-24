=======
Drizzle
=======

A Lightweight SQL Database for Cloud and Web

.. epigraph::

  What, this again?

Drizzle is a community-driven open source project that is forked from the
popular MySQL database.

The Drizzle team has removed non-essential code, re-factored the remaining
code and modernized the code base moving to C++.

Charter
=======

* A database optimized for Cloud infrastructure and Web applications
* Design for massive concurrency on modern multi-cpu architecture
* Optimize memory for increased performance and parallelism
* Open source, open community, open design
* Container-first approach

Scope
=====

* Re-designed modular architecture providing plugins with defined APIs
* Simple design for ease of use and administration
* Reliable, ACID transactional

Getting Drizzle running
=======================

Drizzle is container-first. The repo ships a ``Containerfile`` and a
``bindep.txt`` package list; every documented build and test invocation
is a ``podman`` command against that container. The revival is still
forward-porting from Ubuntu Precise, so a host build is not supported.

Inner loop — build only, fast iteration::

    podman build --platform linux/amd64 --target=build -t drizzle:build .

Verification — build then run tests::

    podman build --platform linux/amd64 --target=test -t drizzle:test .
    podman run --rm drizzle:test

arm64 readiness check (configure + compile, tests not gating yet)::

    podman build --platform linux/arm64 --target=build -t drizzle:build-arm64 .

Local mirror of CI::

    ./tools/regress.sh

Build, test, and perf dependencies live in ``bindep.txt`` (consumed by
``bindep-rs`` inside the ``Containerfile``). For the full revival
roadmap and contributor conventions, see ``AGENTS.md`` and
``docs/specs/revival.rst``.

Cheers!

  - The Drizzle team
