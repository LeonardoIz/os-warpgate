#!/bin/sh
# Runs inside the builder image with upstream source mounted at /src.
set -eu
TARGET=x86_64-unknown-freebsd

toolchain=$(sed -n 's/^channel *= *"\(.*\)"/\1/p' rust-toolchain.toml)
rustup toolchain install "$toolchain" --profile minimal --target "$TARGET"

(cd warpgate-web && npm ci && npm run build)

# separate target dir per sysroot so objects built against another FreeBSD release are never reused
export CARGO_TARGET_DIR="target/freebsd-$FREEBSD_VERSION"
# --locked: build exactly upstream's Cargo.lock, fail instead of silently updating it
SOURCE_DATE_EPOCH=0 cargo build --locked --all-features --release --target "$TARGET"
mkdir -p out && cp "$CARGO_TARGET_DIR/$TARGET/release/warpgate" out/warpgate
echo "$FREEBSD_VERSION" > out/freebsd-version
