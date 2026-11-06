#!/bin/sh
# Runs on FreeBSD/OPNsense (pkg + bmake). Builds the os-warpgate package (plugin + bundled warpgate binary)
# with OPNsense's plugin tooling into a flat pkg repository SITE_DIR/<ABI>/ (package + signed catalogue), plus the
# small files for GitHub Pages in SITE_DIR (landing page, repo config, key).
# The repository itself is served from the GitHub release repo-<ABI with ':' -> '-'> (Pages times out on big files).
# Usage: build/repo/build-repo.sh SITE_DIR WARPGATE_BINARY [SIGNING_KEY]   (run by publish-repo.yml)
# WARPGATE_BINARY must have a valid WARPGATE_BINARY.sig made with the signing key (build/signing.pub).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SITE=$1
BIN=$2
KEY=${3:-}
PUB=$ROOT/build/signing.pub
URL=${SITE_URL:-https://leonardoiz.github.io/os-warpgate}
RELEASES=${RELEASES_URL:-https://github.com/LeonardoIz/os-warpgate/releases/download}
PLUGINS_REF=${PLUGINS_REF:-master}

# trust boundary: only package a binary signed with our key
openssl dgst -sha256 -verify "$PUB" -signature "$BIN.sig" "$BIN" >/dev/null ||
    { echo "error: $BIN is not signed with $PUB" >&2; exit 1; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# OPNsense plugin build system (Mk/, Scripts/, Templates/) from opnsense/plugins
fetch -q -o - "https://codeload.github.com/opnsense/plugins/tar.gz/refs/heads/$PLUGINS_REF" |
    tar -xzf - -C "$W" --strip-components 1 "plugins-$PLUGINS_REF/Mk" "plugins-$PLUGINS_REF/Scripts" "plugins-$PLUGINS_REF/Templates"
mkdir -p "$W/security"
cp -R "$ROOT/plugin" "$W/security/warpgate"
mkdir -p "$W/security/warpgate/src/bin"
install -m 0755 "$BIN" "$W/security/warpgate/src/bin/warpgate"
# PLUGIN_DEVEL empty: stable package name (os-warpgate), not os-warpgate-devel
make -C "$W/security/warpgate" package WRKDIR="$W/wrk" PLUGIN_DEVEL=

ABI=$(pkg config abi)
# like any pkg repository, only the current version is served
REPO_URL=$RELEASES/repo-$(echo "$ABI" | tr : -)
rm -rf "${SITE:?}/$ABI"
mkdir -p "$SITE/$ABI"
# flat (no All/): release assets cannot live in subdirectories
cp "$W"/wrk/pkg/*.pkg "$SITE/$ABI/"
if [ -n "$KEY" ]; then
    pkg repo "$SITE/$ABI" "$KEY"
else
    echo "warning: no signing key, repository catalogue is unsigned" >&2
    pkg repo "$SITE/$ABI"
fi

# what the router fetches into /usr/local/etc/pkg/repos/, and the landing page
cp "$PUB" "$SITE/warpgate.pub"
sed "s|@REPO_URL@|$REPO_URL|g" "$HERE/warpgate.conf" > "$SITE/warpgate.conf"
FP=$(openssl pkey -pubin -in "$PUB" -outform DER | sha256)
PKGS=$(cd "$SITE/$ABI" && for f in os-*.pkg; do
    printf '<li><a href="%s/%s">%s</a> <code>%s</code></li>' "$REPO_URL" "$f" "${f%.pkg}" "$ABI"
done)
sed -e "s|@URL@|$URL|g" -e "s|@FINGERPRINT@|$FP|" -e "s|@PACKAGES@|$PKGS|" "$HERE/index.html" > "$SITE/index.html"
ls -l "$SITE/$ABI"
