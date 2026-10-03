#!/usr/bin/env bash
# fetch.sh - download the upstream release tarball named in upstream.conf into cache/
# and verify its SHA-256 (and GPG signature when the signing key is available).
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
. "$top/upstream.conf"

cache=$top/cache
mkdir -p "$cache"
tarball=$cache/$(basename "$UPSTREAM_URL")

if [ ! -f "$tarball" ]; then
    echo "fetch: downloading $UPSTREAM_URL"
    curl -fsSL -o "$tarball.tmp" "$UPSTREAM_URL"
    mv "$tarball.tmp" "$tarball"
fi
[ -f "$tarball.sig" ] || curl -fsSL -o "$tarball.sig" "$UPSTREAM_URL.sig"

echo "$UPSTREAM_SHA256  $tarball" | sha256sum -c --quiet - ||
    { echo "fetch: SHA-256 mismatch for $tarball" >&2; exit 1; }

# Verify against the GNU project keyring (ftp.gnu.org/gnu/gnu-keyring.gpg).
keyring=$cache/gnu-keyring.gpg
[ -f "$keyring" ] || curl -fsSL -o "$keyring" https://ftp.gnu.org/gnu/gnu-keyring.gpg
status=$(gpg --no-default-keyring --keyring "$keyring" --status-fd 1 \
             --verify "$tarball.sig" "$tarball" 2>/dev/null || true)
echo "$status" | grep -q "^\[GNUPG:\] VALIDSIG $UPSTREAM_GPG_KEY " ||
    { echo "fetch: GPG signature by $UPSTREAM_GPG_KEY not valid for $tarball" >&2; exit 1; }
echo "fetch: signature OK ($UPSTREAM_GPG_KEY)"
echo "fetch: $tarball"
