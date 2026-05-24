# syntax=docker/dockerfile:1.4
ARG UBUNTU=12.04

FROM quay.io/inaugust/bindep-rs AS bindep_rs

FROM quay.io/inaugust/unsafe-old-distro-danger:${UBUNTU} AS base

ENV DEBIAN_FRONTEND=noninteractive

COPY --chmod=0755 --from=bindep_rs /usr/local/bin/bindep-static /usr/local/bin/bindep

WORKDIR /src

# copy bindep.txt seperately to help with layer caching
COPY bindep.txt /src/bindep.txt

# Compile-time deps
RUN apt-get update && apt-get install -y --no-install-recommends $(bindep -b compile) \
    && rm -rf /var/lib/apt/lists/*

FROM base AS build
ARG TARGETPLATFORM
ARG UBUNTU

# Build in a per-arch cache mount for incremental rebuilds, then cp the
# tree out of the cache into the image layer so the test and perf stages
# — and `podman run drizzle:test` — work against a self-contained tree.
RUN --mount=type=bind,source=.,target=/host-src,readonly,Z \
    --mount=type=cache,target=/build,id=drizzle-build-${TARGETPLATFORM}-${UBUNTU},sharing=locked \
    cp -au --no-preserve=context /host-src/. /build/ && \
    cd /build && \
    if [ ! -f Makefile ] ; then autoreconf -i && ./configure ; fi && \
    make -j"$(nproc)" && \
    mkdir -p /opt/drizzle-build && \
    cp -au /build/. /opt/drizzle-build/

# libtool bakes -Wl,-rpath=/build/... into the test binaries at link
# time; alias /build to the image-layer copy so the dynamic linker
# resolves at runtime without requiring `make install`.
RUN ln -s /opt/drizzle-build /build

WORKDIR /opt/drizzle-build

FROM build AS test

# Test-time deps (DTR is Perl; `make unit` is boost.test, already built).
RUN apt-get update && apt-get install -y --no-install-recommends $(bindep -b test) \
    && rm -rf /var/lib/apt/lists/*

CMD ["tools/run-tests.sh"]

FROM build AS perf
ARG TARGETPLATFORM
ARG UBUNTU

# Phase 2 performance harness. valgrind (callgrind/massif) plus the
# Perl DBI stack used to build DBD::drizzle and drive sql-bench.
RUN apt-get update && apt-get install -y --no-install-recommends $(bindep -b perf) \
    && rm -rf /var/lib/apt/lists/*

# DBD::drizzle (the libdrizzle Perl DBI driver) is not packaged. Fetch
# the pinned CPAN release; tools/perf.sh builds it against libdrizzle.
# Checksum pins the artifact so a silent upstream re-tag would fail loud.
ADD --checksum=sha256:ab0513eb4429a56ba07a1f76528577cb3caf70ae42149441d6041c204b0e8929 \
    https://cpan.metacpan.org/authors/id/C/CA/CAPTTOFU/DBD-drizzle-0.304.tar.gz \
    /opt/DBD-drizzle-0.304.tar.gz

RUN tools/perf.sh
