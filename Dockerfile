# Define the base image and tag for AdGuard Home
ARG FRM='adguard/adguardhome'
ARG TAG='latest'

# Stage for building Unbound (this remains unchanged)
FROM debian:bullseye as unbound

ARG UNBOUND_VERSION=1.20.0
ARG UNBOUND_SHA256=56b4ceed33639522000fd96775576ddf8782bb3617610715d7f1e777c5ec1dbf
ARG UNBOUND_DOWNLOAD_URL=https://nlnetlabs.nl/downloads/unbound/unbound-1.20.0.tar.gz

WORKDIR /tmp/src

RUN build_deps="curl gcc libc-dev libevent-dev libexpat1-dev libnghttp2-dev make libssl-dev" && \
    set -x && \
    DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends \
      $build_deps \
      bsdmainutils \
      ca-certificates \
      ldnsutils \
      libevent-2.1-7 \
      libexpat1 \
      libprotobuf-c-dev \
      protobuf-c-compiler && \
    curl -sSL $UNBOUND_DOWNLOAD_URL -o unbound.tar.gz && \
    echo "${UNBOUND_SHA256} *unbound.tar.gz" | sha256sum -c - && \
    tar xzf unbound.tar.gz && \
    rm -f unbound.tar.gz && \
    cd unbound-${UNBOUND_VERSION} && \
    groupadd unbound && \
    useradd -g unbound -s /dev/null -d /etc unbound && \
    ./configure \
        --disable-dependency-tracking \
        --with-pthreads \
        --with-username=unbound \
        --with-libevent \
        --with-libnghttp2 \
        --enable-dnstap \
        --enable-tfo-server \
        --enable-tfo-client \
        --enable-event-api \
        --enable-subnet && \
    make -j$(nproc) install && \
    apt-get purge -y --auto-remove \
      $build_deps && \
    rm -rf \
        /tmp/* \
        /var/tmp/* \
        /var/lib/apt/lists/*

# Intermediate stage to setup Unbound files and directories
FROM debian:bullseye as setup-unbound

RUN mkdir -p /usr/local/etc/unbound

COPY --from=unbound /usr/local/sbin/unbound* /usr/local/sbin/
COPY --from=unbound /usr/local/lib/libunbound* /usr/local/lib/
COPY --from=unbound /usr/local/etc/unbound/* /usr/local/etc/unbound/

# Install necessary packages and setup AdGuard Home
FROM setup-unbound as setup-adguard

RUN apt-get update && \
    apt-get install -y bash nano curl wget stubby libssl-dev && \
    rm -rf /var/lib/apt/lists/*

ADD scripts /temp

RUN groupadd unbound \
    && useradd -g unbound unbound \
    && /bin/bash /temp/install.sh \
    && rm -rf /temp/install.sh 

# Main stage for AdGuard Home
FROM ${FRM}:${TAG}
ARG FRM
ARG TAG
ARG TARGETPLATFORM

VOLUME ["/config"]

RUN echo "$(date "+%d.%m.%Y %T") Built from ${FRM} with tag ${TAG}" >> /build_date.info
