# syntax=docker/dockerfile:1.4
FROM quay.io/inaugust/bindep-rs AS bindep_rs

FROM quay.io/inaugust/unsafe-old-distro-danger:12.04 AS base

ENV DEBIAN_FRONTEND=noninteractive

COPY --chmod=0755 --from=bindep_rs /usr/local/bin/bindep-static /usr/local/bin/bindep

WORKDIR /src

# copy bindep.txt seperately to help with layer caching
COPY bindep.txt /src/bindep.txt

# Compile-time deps
RUN apt-get update && apt-get install -y --no-install-recommends $(bindep -b compile) \
    && rm -rf /var/lib/apt/lists/*

FROM base AS build

# Build in a cache mount so artifacts persist across `podman build` runs.
# Source is bind-mounted read-only; cp -au only copies changed files into the
# cache, so make sees only the files that actually changed.
# Final cp -au lifts the build tree into the image layer so downstream stages
# (and `podman run`) can use it without re-mounting the cache.
RUN --mount=type=bind,source=.,target=/host-src,readonly,Z \
    --mount=type=cache,target=/build,id=drizzle-build,sharing=locked \
    cp -au --no-preserve=context /host-src/. /build/ && \
    cd /build && \
    if [ ! -f Makefile ] ; then autoreconf -i && ./configure ; fi && make -j"$(nproc)"

FROM build AS test

# Test-time deps (DTR is Perl; `make unit` is boost.test, already built).
RUN apt-get update && apt-get install -y --no-install-recommends $(bindep -b test) \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN --mount=type=cache,target=/build,id=drizzle-build,sharing=locked \
    tools/run-tests.sh

FROM build AS perf

# Phase 1.5 performance harness. valgrind (callgrind/massif) plus the
# Perl DBI stack used to build DBD::drizzle and drive sql-bench.
RUN apt-get update && apt-get install -y --no-install-recommends $(bindep -b perf) \
    && rm -rf /var/lib/apt/lists/*

# DBD::drizzle (the libdrizzle Perl DBI driver) is not packaged. Fetch
# the pinned CPAN release; tools/perf.sh builds it against libdrizzle.
ADD https://cpan.metacpan.org/authors/id/C/CA/CAPTTOFU/DBD-drizzle-0.304.tar.gz \
    /opt/DBD-drizzle-0.304.tar.gz

WORKDIR /build
RUN --mount=type=cache,target=/build,id=drizzle-build,sharing=locked \
    tools/perf.sh
