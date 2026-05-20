# AGENTS.md — Drizzle Lay of the Land

Quick orientation for any agent or new contributor joining the Drizzle
revival. Read this first; then read the spec.

## What this is

Drizzle is a MySQL fork last actively developed around 2013. We are
reviving the project in 2026 as a **container-first** database server
with a single OS target and a single build system.

The revival is described in detail in
[`docs/specs/revival.rst`](docs/specs/revival.rst). That spec is the
load-bearing roadmap — every active workstream is a phase or sub-stack
of it. Read it before opening a PR.

## Current state

- Branch model: `drizzle-7.2` is the stable / default branch. Active
  revival work happens on `main`.
- Revival phase: **Phase 0** (tests in container, Zuul CI wiring)
  See the spec's Phase Map for what's next.
- Build target: Ubuntu 12.04 (Precise). We will ratchet LTS-by-LTS to
  26.04 as Phases 3–9 land.
- Base image: pulled from quay.io, never docker.io, so Zuul CI does
  not hit docker.io's pull rate limits. EOL releases use
  `quay.io/inaugust/unsafe-old-distro-danger:X.04` (apt sources
  pre-pointed at old-releases); Ubuntu 22.04 onward switches to
  `quay.io/opendevmirror/ubuntu`. See the spec's LTS-bump template.
- Architectures: `linux/amd64` and `linux/arm64`. amd64 is gating now;
  arm64 becomes gating in Phase 9.

## How to build and test

Inner loop — fast iteration, build only:

```console
podman build --platform linux/amd64 --target=build -t drizzle:build .
```

Verification — build + tests:

```console
podman build --platform linux/amd64 --target=test -t drizzle:test .
podman run --rm --net=host drizzle:test
```

arm64 readiness check (configure + compile, no tests yet):

```console
podman build --platform linux/arm64 --target=build -t drizzle:build-arm64 .
```

Local mirror of CI:

```console
./tools/regress.sh
```

Build deps live in `bindep.txt` (consumed by `bindep-rs` in the
Containerfile). Use `[compile platform:dpkg]` for build-time deps and
`[test platform:dpkg]` for DTR/test deps.

## Repo layout

- `Containerfile` — three named stages: `base` (apt + bindep), `build`
  (autoreconf/configure/make), `test` (DTR runtime + entrypoint).
- `bindep.txt` — build/test/runtime package list.
- `configure.ac` + `m4/` — autotools build. **Stay autotools.** Pandora
  macro layer is being slimmed in Phase 2; do not add new Pandora
  files.
- `drizzled/` — server source.
- `plugin/` — 82 plugins, each with a `plugin.ini`. Per-plugin
  `build_conditional` lines are being deleted in Phase 10; do not add
  new ones.
- `tests/` — DTR (`test-run.pl`) harness and suites.
- `unittests/` — boost.test unit tests. `make unit` runs them.
- `tools/run-tests.sh` — test stage entrypoint.
- `tools/regress.sh` — local CI mirror.
- `zuul.d/` — Zuul pipeline + job definitions.
- `docs/` — Sphinx documentation. `docs/specs/` for engineering
  specifications.

## Working norms (from the spec — these are not optional)

### Strip the check, hardcode the answer

When excising an autoconf probe (Phases 1 and 2), preserve the flag /
define / behavior the probe would have set on amd64/arm64 Linux. The
goal is a `configure.ac` that does almost no probing but produces the
same `config.h` as the old one would have on our target. See the spec
for examples.

### Aggressive commit splitting; every commit green

- Deep stacks of small commits are loved. One semantic change per
  commit. Removing the haildb plugin is one commit; removing the
  tokyocabinet plugin is a separate commit.
- **Every commit must be fully green.** `podman build --target=build`
  succeeds, `podman build --target=test` succeeds, `make unit` exits
  0, `make test-drizzle` exits 0. No commit may knowingly break tests,
  even transiently.
- Bisect-load-bearing: future debugging walks dozens of small commits
  with `git bisect`. A "broken in the middle" commit defeats bisect
  for the rest of the stack.
- Zuul's `vouched` and `gate` pipelines run on every commit in a
  stack, not just the tip.
- Commit messages describe **why**, not what. The diff shows what.

### No gravestone comments

When code is removed, it is gone. Git log is the breadcrumb. Do not
leave `// removed X`, `/* was: ... */`, or `# this used to ...`
comments anywhere — source, m4, Makefile.am, plugin.ini, none.

### Multi-arch readiness

- Both targets (amd64, arm64) are 64-bit, little-endian, 8-byte
  pointer. Safe to hardcode.
- No x86-only intrinsics (SSE/AVX) or inline asm without aarch64
  fallback. Note any findings in the spec's "Multi-arch hazards"
  appendix.

## CI

CI runs on OpenDev Zuul. Pipelines:

- **check** — lint only (autoreconf syntax, configure dry-run, docs
  build). Runs on every patchset, unreviewed.
- **vouched** — full build + DTR + distcheck on both arches. Runs
  only after the OpenDev AI review agent has reviewed.
- **gate** — same jobs as vouched, re-run at merge time.
- **promote** — pushes the merged image to the permanent registry,
  tagged with the merge SHA, `latest`, and the phase name.

Everything must always pass. Flaky tests get fixed.

## Quick links

- [Revival spec](docs/specs/revival.rst) — the roadmap.
- [README.rst](README.rst) — top-level project description.
- [`docs/`](docs/) — Sphinx documentation tree.
- [Drizzle on OpenDev](https://opendev.org/inaugust/drizzle) — repo.
