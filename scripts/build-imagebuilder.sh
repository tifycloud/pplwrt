#!/bin/sh
set -eu

cat >&2 <<'EOF'
The official AX9000 ImageBuilder uses the standard split-UBI device tree and
is intentionally disabled for this Darkyun large-UBI repository target.
Use scripts/build-buildroot.sh; it builds the pinned OpenWrt source plus the
reviewed xiaomi_ax9000_darkyun device patch.
EOF
exit 1
