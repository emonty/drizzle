# syntax=docker/dockerfile:1.4
FROM quay.io/inaugust/bindep-rs AS bindep_rs

FROM docker.io/library/ubuntu:12.04 AS base

ENV DEBIAN_FRONTEND=noninteractive

# Precise is EOL; archive + security mirrors live at old-releases now
RUN sed -i \
        -e 's|archive.ubuntu.com|old-releases.ubuntu.com|g' \
        -e 's|security.ubuntu.com|old-releases.ubuntu.com|g' \
        /etc/apt/sources.list

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
RUN --mount=type=bind,source=.,target=/host-src,readonly \
    --mount=type=cache,target=/build,id=drizzle-build,sharing=locked \
    cp -au /host-src/. /build/ && \
    cd /build && \
    autoreconf -i && ./configure && make -j"$(nproc)" && \
    mkdir -p /opt/drizzle && \
    cp -au /build/. /opt/drizzle/

# Libtool bakes rpaths to the build dir into the wrappers and binaries;
# the symlink makes those resolve to /opt/drizzle in the final image.
RUN ln -s /opt/drizzle /build

FROM build AS test

# Test-time deps (DTR is Perl; `make unit` is boost.test, already built).
RUN apt-get update && apt-get install -y --no-install-recommends $(bindep -b test) \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/drizzle
CMD ["/opt/drizzle/support-files/docker/run-tests.sh"]
