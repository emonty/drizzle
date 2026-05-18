# syntax=docker/dockerfile:1.4
FROM quay.io/inaugust/bindep-rs as bindep_rs
FROM docker.io/library/ubuntu:12.04

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

# Build deps (hardcoded until the rust bindep lands)
RUN apt-get update && apt-get install -y --no-install-recommends $(bindep -b compile) \
    && rm -rf /var/lib/apt/lists/*

# Build in a cache mount so artifacts persist across `podman build` runs.
# Source is bind-mounted read-only; cp -au only copies changed files into the
# cache, so make sees only the files that actually changed.
RUN --mount=type=bind,source=.,target=/host-src,readonly \
    --mount=type=cache,target=/build,id=drizzle-build,sharing=locked \
    cp -au /host-src/. /build/ && \
    cd /build && \
    autoreconf -i && ./configure && make -j"$(nproc)"
