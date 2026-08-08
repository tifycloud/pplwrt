#!/bin/sh
# Print a deterministic feed fallback plan. The active source is not changed
# automatically because changing feeds during a release can alter packages.
set -eu
BASE="https://downloads.openwrt.org/releases/25.12.5"
cat <<EOF
official=$BASE
ustc=https://mirrors.ustc.edu.cn/openwrt/releases/25.12.5
tuna=https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/25.12.5

Use official first. Switch to USTC or TUNA only after checking that the
target/profile path and SHA256/manifest are identical; restore official before
releasing. ImageBuilder's repositories file is the source of truth.
EOF
