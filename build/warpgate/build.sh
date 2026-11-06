#!/bin/sh
# Cross-build an upstream warpgate release for FreeBSD (Docker). Usually run via `make binary`.
# Usage: build/warpgate/build.sh [vX.Y.Z]   (default: latest upstream tag)
# Output: out/dist/warpgate-<tag>-x86_64-freebsd<ver> + .sha256 + .sig (if the signing key is present)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUTDIR=$ROOT/out
REPO=https://github.com/warp-tech/warpgate.git

TAG=${1:-$(git ls-remote --tags --refs --sort=-v:refname "$REPO" 'v*' | head -1 | sed 's|.*refs/tags/||')}
SRC=$OUTDIR/src/$TAG
DIST=$OUTDIR/dist
mkdir -p "$OUTDIR/cache" "$DIST"

[ -d "$SRC" ] || git clone --depth 1 --branch "$TAG" --recurse-submodules --shallow-submodules "$REPO" "$SRC"

# FreeBSD fixes not (yet) upstream; skip any patch that is already applied
for p in "$HERE"/patches/*.patch; do
    [ -e "$p" ] || continue
    git -C "$SRC" apply --reverse --check "$p" 2>/dev/null || git -C "$SRC" apply "$p"
done

docker build -t warpgate-freebsd-builder "$HERE"
docker run --rm --user "$(id -u):$(id -g)" \
    -v "$SRC:/src" -v "$OUTDIR/cache:/cache" \
    warpgate-freebsd-builder

OUT="$DIST/warpgate-$TAG-x86_64-freebsd$(cat "$SRC/out/freebsd-version")"
cp "$SRC/out/warpgate" "$OUT"
(cd "$DIST" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256")
cp "$SRC/LICENSE" "$DIST/warpgate-LICENSE"

# the plugin refuses unsigned binaries; without a key the build is only usable for inspection
KEY=${SIGNING_KEY:-$ROOT/keys/signing.key}
if [ -r "$KEY" ]; then
    openssl dgst -sha256 -sign "$KEY" -out "$OUT.sig" "$OUT"
else
    echo "warning: $KEY not found, $OUT is unsigned" >&2
fi
file "$OUT"
