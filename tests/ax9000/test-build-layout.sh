#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
VERSION=$(sed -n '1p' "$ROOT/VERSION")
TMP=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-build-layout.XXXXXX")
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT INT TERM

DEFAULT=$("$ROOT/scripts/build-buildroot.sh" --compile-only --print-output)
[ "$DEFAULT" = "$ROOT/artifacts/preflight/$VERSION" ]
if "$ROOT/scripts/build-buildroot.sh" --channel rc --source-commit 0000000000000000000000000000000000000000 > /dev/null 2>&1; then
	echo 'Buildroot accepted a build without --compile-only' >&2
	exit 1
fi
if "$ROOT/scripts/build-buildroot.sh" --channel beta --print-output > /dev/null 2>&1; then
	echo 'beta output accepted an rc VERSION' >&2
	exit 1
fi
mkdir -p "$TMP/scripts"
cp "$ROOT/scripts/build-buildroot.sh" "$TMP/scripts/build-buildroot.sh"
printf '25.12.5-company.2-beta1\n' > "$TMP/VERSION"
BETA=$("$TMP/scripts/build-buildroot.sh" --channel beta --compile-only --print-output)
[ "$BETA" = "$TMP/artifacts/preflight/25.12.5-company.2-beta1" ]
CUSTOM=$("$ROOT/scripts/build-buildroot.sh" --channel rc --compile-only --output /tmp/companywrt-custom-output --print-output)
[ "$CUSTOM" = /tmp/companywrt-custom-output ]
RELATIVE=$(cd "$ROOT" && ./scripts/build-buildroot.sh --channel rc --compile-only --output artifacts/relative-output --print-output)
[ "$RELATIVE" = "$ROOT/artifacts/relative-output" ]
if "$ROOT/scripts/build-buildroot.sh" --channel stable --print-output > /dev/null 2>&1; then
	echo 'stable output accepted a prerelease VERSION' >&2
	exit 1
fi
grep -Fq 'OpenWrt source checkout failed after 3 attempts' "$ROOT/scripts/build-buildroot.sh"
grep -Fq 'refusing full Buildroot compilation as root' "$ROOT/scripts/build-buildroot.sh"
grep -Fq 'setpriv --reuid=10001 --regid=10001 --clear-groups' "$ROOT/scripts/build-in-container.sh"
if grep -q 'FORCE_UNSAFE_CONFIGURE' "$ROOT/scripts/build-buildroot.sh" "$ROOT/scripts/build-in-container.sh"; then
	echo 'container bypasses an upstream root-build safety check' >&2
	exit 1
fi
if grep -Eq -- '--signing-key|USIGN_SECRET_KEY_FILE|USIGN_CURRENT_SECRET_KEY_FILE' "$ROOT/scripts/build-buildroot.sh" "$ROOT/scripts/build-in-container.sh"; then
	echo 'compiler entrypoint still accepts release signing secrets' >&2
	exit 1
fi
echo 'compile-only preflight output resolution and stable version gate: ok'
