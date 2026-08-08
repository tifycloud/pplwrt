#!/bin/sh
# Admin-confirmed OTA wrapper. It deliberately refuses unattended upgrades.
set -eu

usage() { echo "Usage: ota-apply.sh --image FILE --version VERSION --confirm VERSION [--backup DIR]"; }
IMAGE=""
VERSION=""
CONFIRM=""
BACKUP="/etc/companywrt/backups/$(date -u +%Y%m%dT%H%M%SZ)"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --image) IMAGE=${2:-}; shift 2 ;;
    --version) VERSION=${2:-}; shift 2 ;;
    --confirm) CONFIRM=${2:-}; shift 2 ;;
    --backup) BACKUP=${2:-}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[ "$(id -u)" -eq 0 ] || { echo "OTA requires root" >&2; exit 1; }
if [ -z "$IMAGE" ] || [ ! -f "$IMAGE" ]; then
  echo "image not found" >&2
  exit 1
fi
if [ -z "$VERSION" ] || [ "$CONFIRM" != "$VERSION" ]; then
  echo "explicit administrator confirmation is required: --confirm $VERSION" >&2; exit 1;
fi
command -v sysupgrade >/dev/null 2>&1 || { echo "sysupgrade not found; run on OpenWrt" >&2; exit 1; }

mkdir -p "$BACKUP"
for cfg in /etc/config/network /etc/config/firewall /etc/config/pbr /etc/config/wireless /etc/config/company; do
  [ -f "$cfg" ] && cp -p "$cfg" "$BACKUP/"
done
if [ -d /var/log ]; then
  tar -czf "$BACKUP/logs.tgz" -C /var/log . 2>/dev/null || true
fi
sha256sum "$IMAGE" > "$BACKUP/image.SHA256"
printf 'Backup saved at %s\n' "$BACKUP"
echo "Running sysupgrade dry validation; no reboot yet."
sysupgrade -T "$IMAGE"
echo "Validation passed. Re-run only after reviewing the backup and release manifest."
echo "To actually flash, invoke: sysupgrade \"$IMAGE\""
