#!/bin/sh
set -eu
ROOT=$(cd -P -- "$(dirname "$0")/.." && pwd)
status=0
for f in "$ROOT"/scripts/*.sh; do
  [ -f "$f" ] || continue
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -x "$f" || status=1
  else
    sh -n "$f" || status=1
  fi
done
exit "$status"
