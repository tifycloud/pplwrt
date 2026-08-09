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
VOLUME=${COMPANYWRT_DOCKER_CACHE_VOLUME:-companywrt-buildroot-cache}
mkdir -p "$ROOT/artifacts"
SOURCE_COMMIT=${COMPANYWRT_SOURCE_COMMIT:-$(git -C "$ROOT" rev-parse HEAD)}
printf '%s\n' "$SOURCE_COMMIT" | grep -Eq '^[0-9a-f]{40}$' || { echo 'invalid source commit' >&2; exit 1; }
[ "$(git -C "$ROOT" rev-parse HEAD)" = "$SOURCE_COMMIT" ] || { echo 'source commit does not match repository HEAD' >&2; exit 1; }
[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ] || { echo 'refusing a dirty worktree container build' >&2; exit 1; }
ignored_inputs=$(git -C "$ROOT" ls-files --others --ignored --exclude-standard -- configs/overlay packages/luci-app-company/root packages/luci-theme-liquid | grep -v '/\.DS_Store$' || true)
[ -z "$ignored_inputs" ] || { echo 'ignored files exist in firmware input directories; refusing possible secret leakage' >&2; exit 1; }
case " $* " in *' --compile-only '*) ;; *) echo 'container compiler requires --compile-only; sign the verified bundle separately' >&2; exit 1 ;; esac
docker volume create "$VOLUME" >/dev/null
docker run --rm --platform linux/amd64 \
  -e DEBIAN_FRONTEND=noninteractive \
  -e COMPANYWRT_SOURCE_COMMIT="$SOURCE_COMMIT" \
  -e COMPANYWRT_SOURCE_VERIFIED=1 \
  --mount "type=volume,src=$VOLUME,dst=/work" \
  --mount "type=bind,src=$ROOT,dst=/src,readonly" \
  --mount "type=bind,src=$ROOT/artifacts,dst=/src/artifacts" \
  ubuntu:24.04 sh -euxc '
    rm -rf /work/project
    mkdir -p /work/project /work/cache
    tar --exclude=.git --exclude=.build --exclude=.cache --exclude=artifacts --exclude=.DS_Store -cf - -C /src . | tar -xf - -C /work/project
    apt-get update
    apt-get install -y --no-install-recommends build-essential bzip2 ca-certificates clang curl file flex bison g++ gawk gcc-multilib gettext git libncurses-dev libssl-dev patch perl python3 python3-setuptools rsync squashfs-tools subversion swig tar unzip wget zlib1g-dev zstd
    mkdir -p /tmp/companywrt-builder
    chown -R 10001:10001 /work /tmp/companywrt-builder
    cd /work/project
    HOME=/tmp/companywrt-builder setpriv --reuid=10001 --regid=10001 --clear-groups ./scripts/build-buildroot.sh --build-root /work/cache "$@"
    mkdir -p /src/artifacts
    cp -a /work/project/artifacts/. /src/artifacts/
  ' -- "$@"
