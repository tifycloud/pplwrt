#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
VERSION=$(sed -n '1p' "$ROOT/VERSION")
TMP=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-build-layout.XXXXXX")
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT INT TERM

DEFAULT=$("$ROOT/scripts/build-imagebuilder.sh" --print-output)
[ "$DEFAULT" = "$ROOT/artifacts/rc/$VERSION" ]
if "$ROOT/scripts/build-imagebuilder.sh" --channel beta --print-output > /dev/null 2>&1; then
	echo 'beta output accepted an rc VERSION' >&2
	exit 1
fi
mkdir -p "$TMP/scripts"
cp "$ROOT/scripts/build-imagebuilder.sh" "$TMP/scripts/build-imagebuilder.sh"
printf '25.12.5-company.2-beta1\n' > "$TMP/VERSION"
BETA=$("$TMP/scripts/build-imagebuilder.sh" --channel beta --print-output)
[ "$BETA" = "$TMP/artifacts/beta/25.12.5-company.2-beta1" ]
CUSTOM=$("$ROOT/scripts/build-imagebuilder.sh" --channel rc --output /tmp/companywrt-custom-output --print-output)
[ "$CUSTOM" = /tmp/companywrt-custom-output ]
RELATIVE=$(cd "$ROOT" && ./scripts/build-imagebuilder.sh --channel rc --output artifacts/relative-output --print-output)
[ "$RELATIVE" = "$ROOT/artifacts/relative-output" ]
if "$ROOT/scripts/build-imagebuilder.sh" --channel stable --print-output > /dev/null 2>&1; then
	echo 'stable output accepted a prerelease VERSION' >&2
	exit 1
fi
echo 'versioned rc/beta output resolution and stable version gate: ok'
