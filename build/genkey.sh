#!/bin/sh
# Create the signing key pair (once). The private key signs the pkg repo and the warpgate binaries;
# the public key (build/signing.pub) is served with the pkg repository and installed on the router. Never commit keys/. Usually via `make genkey`.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KEY=$ROOT/keys/signing.key
PUB=$ROOT/build/signing.pub
[ -e "$KEY" ] && { echo "$KEY already exists"; exit 1; }
mkdir -p "$ROOT/keys" "$(dirname "$PUB")"
(umask 077; openssl genrsa -out "$KEY" 4096 2>/dev/null)
openssl rsa -in "$KEY" -pubout -out "$PUB" 2>/dev/null
echo "private: $KEY (keep offline / GitHub secret SIGNING_KEY)"
echo "public:  $PUB (commit it)"
