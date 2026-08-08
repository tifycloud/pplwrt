#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
PROFILE="$ROOT/devices/ax9000/profile.json"
command -v jq >/dev/null 2>&1 || { echo "jq is required for profile test" >&2; exit 1; }
[ "$(jq -r .release "$PROFILE")" = 25.12.5 ]
[ "$(jq -r .profile "$PROFILE")" = xiaomi_ax9000 ]
[ "$(jq -r '.supported_devices[0]' "$PROFILE")" = xiaomi,ax9000 ]
[ "$(jq -r .imagebuilder.filename "$PROFILE")" = openwrt-imagebuilder-25.12.5-qualcommax-ipq807x.Linux-x86_64.tar.zst ]
[ "$(jq -r .imagebuilder.sha256 "$PROFILE")" = 81faa256975900d1d5f07d57c06881996802ef09f3d7ee27e74cb99136e7a6b5 ]
if grep -q '^mwan3$' "$ROOT/configs/ax9000/packages.txt"; then
  echo 'mwan3 must not be in base packages' >&2
  exit 1
fi
echo 'profile metadata: ok'
