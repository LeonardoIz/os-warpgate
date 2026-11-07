#!/bin/sh
# Behaviour tests for the plugin (what lint cannot catch): template file modes and secrets, the certificate
# exporter against link attacks, model validation, the rc.d bootstrap, wgctl.py safeguards.
# Usage: tests/run.sh [vX.Y.Z]   (warpgate version to test against; default: PLUGIN_VERSION)
# Needs: docker, python3 with jinja2/jsonschema/pyyaml, openssl, gh (authenticated), git, curl.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEPS=$ROOT/out/test
TAG=${1:-v$(sed -n 's/^PLUGIN_VERSION=[[:space:]]*//p' "$ROOT/plugin/Makefile")}
# OPNsense core the plugin targets (stable/26.7 on 2026-11-07): template engine and MVC framework
CORE_REF=1d8668f1b495fcf1c9b7a4deb5794ace2e6845ed
mkdir -p "$DEPS"

if [ ! -d "$DEPS/core-$CORE_REF" ]; then
    git clone -q --filter=blob:none --no-checkout https://github.com/opnsense/core "$DEPS/core-$CORE_REF"
    git -C "$DEPS/core-$CORE_REF" sparse-checkout set --no-cone /src/opnsense/service/modules /src/opnsense/mvc
    git -C "$DEPS/core-$CORE_REF" checkout -q "$CORE_REF"
fi
WG=$DEPS/warpgate-$TAG-linux
if [ ! -x "$WG" ]; then
    asset="warpgate-$TAG-x86_64-linux"
    want=$(gh api "repos/warp-tech/warpgate/releases/tags/$TAG" --jq ".assets[] | select(.name == \"$asset\") | .digest")
    curl -fsSL -o "$WG.tmp" "https://github.com/warp-tech/warpgate/releases/download/$TAG/$asset"
    [ "sha256:$(sha256sum "$WG.tmp" | cut -d' ' -f1)" = "$want" ] || { echo "digest mismatch for $asset"; exit 1; }
    chmod +x "$WG.tmp" && mv "$WG.tmp" "$WG"
fi
SCHEMA=$DEPS/config-schema-$TAG.json
[ -s "$SCHEMA" ] || curl -fsSL -o "$SCHEMA" "https://raw.githubusercontent.com/warp-tech/warpgate/$TAG/config-schema.json"

export ROOT WG SCHEMA CORE="$DEPS/core-$CORE_REF/src/opnsense" PYTHONDONTWRITEBYTECODE=1
fail=0
for t in "$ROOT"/tests/test_*; do
    echo "== $(basename "$t")"
    case "$t" in
    *.py) python3 "$t" || fail=1 ;;
    *.sh) sh "$t" || fail=1 ;;
    esac
done
if [ "$fail" != 0 ]; then
    echo "TESTS FAILED"
    exit 1
fi
echo "all tests passed"
