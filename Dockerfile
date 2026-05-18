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

COPY . /src
RUN cd /src && \
    autoreconf -i && ./configure && make
