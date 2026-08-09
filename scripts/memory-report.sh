#!/bin/sh
# Reclaim-aware memory and largest resident process report. Read-only.
set -eu

MODE=report
MIN_AVAILABLE_PERCENT=70
case "${1:-}" in
	'') ;;
	--check-idle) MODE=check ;;
	*) echo "usage: $0 [--check-idle]" >&2; exit 2 ;;
esac

mem_kib() {
	awk -v key="$1:" '$1 == key { print $2; exit }' /proc/meminfo
}

total=$(mem_kib MemTotal)
available=$(mem_kib MemAvailable)
free=$(mem_kib MemFree)
cached=$(mem_kib Cached)
buffers=$(mem_kib Buffers)
reclaimable=$(mem_kib SReclaimable)
shmem=$(mem_kib Shmem)
used=$((total - available))
used_percent=$((used * 100 / total))
available_percent=$((available * 100 / total))

printf 'CompanyWrt memory report\n'
printf '  total:              %8s KiB\n' "$total"
printf '  available:          %8s KiB (%s%%)\n' "$available" "$available_percent"
printf '  unreclaimable-used: %8s KiB (%s%%)\n' "$used" "$used_percent"
printf '  free:               %8s KiB\n' "$free"
printf '  file-cache:         %8s KiB\n' "$cached"
printf '  buffers:            %8s KiB\n' "$buffers"
printf '  slab-reclaimable:   %8s KiB\n' "$reclaimable"
printf '  shared-memory:      %8s KiB\n' "$shmem"
printf '\nLargest resident processes (KiB RSS):\n'

for status in /proc/[0-9]*/status; do
	[ -r "$status" ] || continue
	pid=${status#/proc/}; pid=${pid%/status}
	name=$(awk '$1 == "Name:" { print $2; exit }' "$status")
	rss=$(awk '$1 == "VmRSS:" { print $2; exit }' "$status")
	[ -n "$rss" ] || rss=0
	printf '%10s %7s %s\n' "$rss" "$pid" "$name"
done | sort -nr | awk 'NR <= 15 { printf "  %8s KiB  pid %-7s %s\n", $1, $2, $3 }'

if [ "$MODE" = check ]; then
	uptime_seconds=$(cut -d. -f1 /proc/uptime)
	if [ "$uptime_seconds" -lt 600 ]; then
		echo "FAIL: idle baseline requires at least 600 seconds uptime (now ${uptime_seconds}s)" >&2
		exit 1
	fi
	if [ "$available_percent" -lt "$MIN_AVAILABLE_PERCENT" ]; then
		echo "FAIL: MemAvailable ${available_percent}% is below the ${MIN_AVAILABLE_PERCENT}% lean-base gate" >&2
		exit 1
	fi
	if command -v pidof >/dev/null 2>&1 && pidof collectd >/dev/null 2>&1; then
		echo 'FAIL: collectd is running in the lean-base idle baseline' >&2
		exit 1
	fi
	echo "PASS: idle MemAvailable ${available_percent}% >= ${MIN_AVAILABLE_PERCENT}%"
fi
