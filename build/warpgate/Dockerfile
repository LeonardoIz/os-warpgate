# Cross-compiles warpgate for x86_64-unknown-freebsd from Linux.
FROM node:24-trixie-slim AS node

FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils git make perl cmake pkg-config \
        clang lld llvm build-essential default-jre-headless \
    && rm -rf /var/lib/apt/lists/*

COPY --from=node /usr/local/ /usr/local/

# FreeBSD sysroot (headers + libs) matching the OPNsense base: 26.7 = FreeBSD 15.1 (26.1 was 14.3).
# Hash pinned from the release MANIFEST. Older releases live under
# http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/amd64/
ARG FREEBSD_VERSION=15.1
ARG FREEBSD_BASE_SHA256=3768988b151c20f965679062b065c63a977d6bbb9f47fd83695ec2c40790c18f
ARG FREEBSD_BASE_URL=https://download.freebsd.org/releases/amd64/${FREEBSD_VERSION}-RELEASE/base.txz
RUN curl -fsSL -o /tmp/base.txz "${FREEBSD_BASE_URL}" \
    && echo "${FREEBSD_BASE_SHA256}  /tmp/base.txz" | sha256sum -c - \
    && mkdir /sysroot \
    && tar -xJf /tmp/base.txz -C /sysroot ./lib ./usr/lib ./usr/include ./usr/libdata/pkgconfig \
    && rm /tmp/base.txz

RUN for t in clang clang++; do \
        printf '#!/bin/sh\nexec %s --target=x86_64-unknown-freebsd%s --sysroot=/sysroot -fuse-ld=lld "$@"\n' \
            "$t" "${FREEBSD_VERSION}" > /usr/local/bin/x86_64-unknown-freebsd-$t; \
        chmod +x /usr/local/bin/x86_64-unknown-freebsd-$t; \
    done

# rustup only; the toolchain pinned by upstream's rust-toolchain.toml is installed at build time into the cache.
RUN curl -fsSL -o /tmp/rustup-init https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init \
    && echo "$(curl -fsSL https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init.sha256 | cut -d' ' -f1)  /tmp/rustup-init" | sha256sum -c - \
    && chmod +x /tmp/rustup-init \
    && RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo /tmp/rustup-init -y --no-modify-path --profile minimal --default-toolchain none \
    && rm /tmp/rustup-init

ENV PATH=/opt/cargo/bin:$PATH \
    FREEBSD_VERSION=${FREEBSD_VERSION} \
    RUSTUP_HOME=/cache/rustup \
    CARGO_HOME=/cache/cargo \
    npm_config_cache=/cache/npm \
    HOME=/tmp \
    CC_x86_64_unknown_freebsd=x86_64-unknown-freebsd-clang \
    CXX_x86_64_unknown_freebsd=x86_64-unknown-freebsd-clang++ \
    AR_x86_64_unknown_freebsd=llvm-ar \
    CARGO_TARGET_X86_64_UNKNOWN_FREEBSD_LINKER=x86_64-unknown-freebsd-clang \
    PKG_CONFIG_ALLOW_CROSS=1 \
    PKG_CONFIG_SYSROOT_DIR=/sysroot \
    PKG_CONFIG_LIBDIR=/sysroot/usr/libdata/pkgconfig \
    X86_64_UNKNOWN_FREEBSD_OPENSSL_LIB_DIR=/sysroot/usr/lib \
    X86_64_UNKNOWN_FREEBSD_OPENSSL_INCLUDE_DIR=/sysroot/usr/include

COPY container-build.sh /usr/local/bin/container-build.sh
WORKDIR /src
ENTRYPOINT ["/usr/local/bin/container-build.sh"]
