#!/bin/sh
# Run the same pinned build in a reproducible Linux x86_64 container.
set -eu
ROOT=$(cd -P -- "$(dirname "$0")/.." && pwd)
command -v docker >/dev/null 2>&1 || { echo "Docker is required for container build" >&2; exit 3; }
docker info >/dev/null 2>&1 || {
  echo "Docker CLI is installed but the daemon is unavailable." >&2
  echo "Start Docker/OrbStack/Colima, then rerun this command or use CI." >&2
  exit 3
}
VOLUME="companywrt-build-$$"
mkdir -p "$ROOT/artifacts"
docker volume create "$VOLUME" >/dev/null
cleanup() { docker volume rm "$VOLUME" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
docker run --rm --platform linux/amd64 \
  -e DEBIAN_FRONTEND=noninteractive \
  --mount "type=volume,src=$VOLUME,dst=/work" \
  --mount "type=bind,src=$ROOT,dst=/src,readonly" \
  --mount "type=bind,src=$ROOT/artifacts,dst=/src/artifacts" \
  ubuntu:24.04 sh -euxc '
    mkdir -p /work
    tar --exclude=.git --exclude=.build --exclude=.cache --exclude=artifacts -cf - -C /src . | tar -xf - -C /work
    mkdir -p /work/.build
    if [ -f /src/.cache/imagebuilder.tar.zst ]; then
      cp /src/.cache/imagebuilder.tar.zst /work/.build/openwrt-imagebuilder-25.12.5-qualcommax-ipq807x.Linux-x86_64.tar.zst
    fi
    apt-get update
    apt-get install -y --no-install-recommends bzip2 ca-certificates curl file gawk make patch perl python3 tar unzip wget zstd coreutils
    cd /work
    ./scripts/build-imagebuilder.sh "$@"
    mkdir -p /src/artifacts
    cp -a /work/artifacts/. /src/artifacts/
  ' -- "$@"
