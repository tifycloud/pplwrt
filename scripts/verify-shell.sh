#!/bin/sh
set -eu
ROOT=$(cd -P -- "$(dirname "$0")/.." && pwd)
status=0
if command -v shellcheck >/dev/null 2>&1; then
	find "$ROOT/scripts" "$ROOT/tests" -type f -name '*.sh' -exec shellcheck -S info -x {} + || status=1
else
	find "$ROOT/scripts" "$ROOT/tests" -type f -name '*.sh' -exec sh -n {} \; || status=1
fi
exit "$status"
