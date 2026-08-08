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
SOURCE_COMMIT=${COMPANYWRT_SOURCE_COMMIT:-$(git -C "$ROOT" rev-parse HEAD)}
printf '%s\n' "$SOURCE_COMMIT" | grep -Eq '^[0-9a-f]{40}$' || { echo 'invalid source commit' >&2; exit 1; }
[ "$(git -C "$ROOT" rev-parse HEAD)" = "$SOURCE_COMMIT" ] || { echo 'source commit does not match repository HEAD' >&2; exit 1; }
[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ] || { echo 'refusing a dirty worktree container build' >&2; exit 1; }
ignored_inputs=$(git -C "$ROOT" ls-files --others --ignored --exclude-standard -- configs/overlay packages/luci-app-company/root packages/luci-theme-company/root | grep -v '/\.DS_Store$' || true)
[ -z "$ignored_inputs" ] || { echo 'ignored files exist in firmware input directories; refusing possible secret leakage' >&2; exit 1; }
if [ -z "${USIGN_SECRET_KEY_FILE:-}" ] || [ ! -s "$USIGN_SECRET_KEY_FILE" ]; then
  echo 'USIGN_SECRET_KEY_FILE is required for a signed container build' >&2
  exit 1
fi
SECRET_KEY_REAL=$(realpath "$USIGN_SECRET_KEY_FILE")
case "$SECRET_KEY_REAL" in "$(realpath "$ROOT")"/*) echo 'signing key must be outside the repository' >&2; exit 1 ;; esac
CURRENT_SECRET_KEY_REAL=""
TRANSITION_VERSION=$(sed -n 's/^TRANSITION_VERSION=//p' "$ROOT/keys/ROTATION.env")
if [ "$(sed -n '1p' "$ROOT/VERSION")" = "$TRANSITION_VERSION" ]; then
  if [ -z "${USIGN_CURRENT_SECRET_KEY_FILE:-}" ] || [ ! -s "$USIGN_CURRENT_SECRET_KEY_FILE" ]; then
    echo 'USIGN_CURRENT_SECRET_KEY_FILE is required for the declared key-transition build' >&2
    exit 1
  fi
  CURRENT_SECRET_KEY_REAL=$(realpath "$USIGN_CURRENT_SECRET_KEY_FILE")
  case "$CURRENT_SECRET_KEY_REAL" in "$(realpath "$ROOT")"/*) echo 'current signing key must be outside the repository' >&2; exit 1 ;; esac
elif [ -n "${USIGN_CURRENT_SECRET_KEY_FILE:-}" ]; then
  echo 'USIGN_CURRENT_SECRET_KEY_FILE is valid only for the declared transition version' >&2
  exit 1
fi
docker volume create "$VOLUME" >/dev/null
cleanup() { docker volume rm "$VOLUME" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
run_container() {
  if [ -n "$CURRENT_SECRET_KEY_REAL" ]; then
    docker run --rm --platform linux/amd64 \
      -e DEBIAN_FRONTEND=noninteractive \
      -e COMPANYWRT_SOURCE_COMMIT="$SOURCE_COMMIT" \
      -e COMPANYWRT_SOURCE_VERIFIED=1 \
      -e USIGN_SECRET_KEY_FILE=/run/secrets/companywrt-usign-previous.key \
      -e USIGN_CURRENT_SECRET_KEY_FILE=/run/secrets/companywrt-usign-current.key \
      --mount "type=bind,src=$SECRET_KEY_REAL,dst=/run/secrets/companywrt-usign-previous.key,readonly" \
      --mount "type=bind,src=$CURRENT_SECRET_KEY_REAL,dst=/run/secrets/companywrt-usign-current.key,readonly" \
      --mount "type=volume,src=$VOLUME,dst=/work" \
      --mount "type=bind,src=$ROOT,dst=/src,readonly" \
      --mount "type=bind,src=$ROOT/artifacts,dst=/src/artifacts" \
      ubuntu:24.04 sh -euxc '
    mkdir -p /work
    tar --exclude=.git --exclude=.build --exclude=.cache --exclude=artifacts --exclude=.DS_Store -cf - -C /src . | tar -xf - -C /work
    mkdir -p /work/.build
    if [ -f /src/.cache/imagebuilder.tar.zst ]; then
      cp /src/.cache/imagebuilder.tar.zst /work/.build/openwrt-imagebuilder-25.12.5-qualcommax-ipq807x.Linux-x86_64.tar.zst
    fi
    apt-get update
    apt-get install -y --no-install-recommends bzip2 ca-certificates curl file gawk make patch perl python3 squashfs-tools tar unzip wget zstd coreutils
    cd /work
    ./scripts/build-imagebuilder.sh "$@"
    mkdir -p /src/artifacts
    cp -a /work/artifacts/. /src/artifacts/
  ' -- "$@"
  else
    docker run --rm --platform linux/amd64 \
      -e DEBIAN_FRONTEND=noninteractive \
      -e COMPANYWRT_SOURCE_COMMIT="$SOURCE_COMMIT" \
      -e COMPANYWRT_SOURCE_VERIFIED=1 \
      -e USIGN_SECRET_KEY_FILE=/run/secrets/companywrt-usign.key \
      --mount "type=bind,src=$SECRET_KEY_REAL,dst=/run/secrets/companywrt-usign.key,readonly" \
      --mount "type=volume,src=$VOLUME,dst=/work" \
      --mount "type=bind,src=$ROOT,dst=/src,readonly" \
      --mount "type=bind,src=$ROOT/artifacts,dst=/src/artifacts" \
      ubuntu:24.04 sh -euxc '
    mkdir -p /work
    tar --exclude=.git --exclude=.build --exclude=.cache --exclude=artifacts --exclude=.DS_Store -cf - -C /src . | tar -xf - -C /work
    mkdir -p /work/.build
    if [ -f /src/.cache/imagebuilder.tar.zst ]; then
      cp /src/.cache/imagebuilder.tar.zst /work/.build/openwrt-imagebuilder-25.12.5-qualcommax-ipq807x.Linux-x86_64.tar.zst
    fi
    apt-get update
    apt-get install -y --no-install-recommends bzip2 ca-certificates curl file gawk make patch perl python3 squashfs-tools tar unzip wget zstd coreutils
    cd /work
    ./scripts/build-imagebuilder.sh "$@"
    mkdir -p /src/artifacts
    cp -a /work/artifacts/. /src/artifacts/
  ' -- "$@"
  fi
}
run_container "$@"
