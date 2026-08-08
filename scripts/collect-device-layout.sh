#!/bin/sh
# Collect read-only AX9000 partition/boot evidence. This script deliberately
# avoids fw_printenv by default because a wrong fw_env.config can make its
# output misleading. It never writes flash, U-Boot environment, UCI, or MTD.
set -eu

OUTPUT=/tmp/companywrt-device-layout.txt
INCLUDE_BOOTENV=0

usage() {
	cat <<'EOF'
Usage: collect-device-layout.sh [--output FILE] [--include-bootenv]

Run on the target router as root. The default report contains no configuration
backup or credentials. Review it before sharing because vendor tools may still
print device-specific identifiers.

--include-bootenv reads U-Boot environment only when /etc/fw_env.config exists.
It never invokes fw_setenv. Treat the result as evidence only after validating
the fw_env.config offsets against this exact bootloader.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--output)
			[ "$#" -ge 2 ] || { usage >&2; exit 2; }
			OUTPUT=$2
			shift 2
			;;
		--include-bootenv)
			INCLUDE_BOOTENV=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			usage >&2
			exit 2
			;;
	esac
done

case "$OUTPUT" in
	/tmp/*) ;;
	*) echo "output must be below /tmp" >&2; exit 2 ;;
esac

umask 077

section() {
	printf '\n===== %s =====\n' "$1"
}

run_if_present() {
	command_name=$1
	shift
	if command -v "$command_name" >/dev/null 2>&1; then
		"$command_name" "$@" 2>&1 || true
	else
		printf '%s is not installed\n' "$command_name"
	fi
}

{
	section "collection"
	printf 'collected_at_utc='
	date -u '+%Y-%m-%dT%H:%M:%SZ'
	printf 'collector=companywrt-read-only-v1\n'

	section "OpenWrt board"
	run_if_present ubus call system board

	section "device tree"
	for property in model compatible; do
		printf '%s:\n' "$property"
		if [ -r "/sys/firmware/devicetree/base/$property" ]; then
			tr '\000' '\n' < "/sys/firmware/devicetree/base/$property"
		else
			printf 'unavailable\n'
		fi
	done

	section "kernel command line"
	cat /proc/cmdline 2>&1 || true

	section "MTD table"
	cat /proc/mtd 2>&1 || true

	section "block devices"
	cat /proc/partitions 2>&1 || true

	section "UBI mapping"
	for item in /sys/class/ubi/ubi*/mtd_num /sys/class/ubi/ubi*/name /sys/class/ubi/ubi*/data_bytes /sys/class/ubi/ubi*/reserved_ebs; do
		[ -r "$item" ] || continue
		printf '%s=' "$item"
		cat "$item"
	done
	run_if_present ubinfo -a

	section "mounts and capacity"
	mount 2>&1 || true
	df -h 2>&1 || true

	section "running upgrade implementation"
	if [ -r /lib/upgrade/platform.sh ]; then
		sha256sum /lib/upgrade/platform.sh 2>&1 || true
		# Only emit the AX9000-related upgrade selectors, not arbitrary config.
		grep -n -E 'xiaomi,ax9000|CI_(KERN|ROOT|UBI)|nand_do_upgrade|ubi_kernel|rootfs' /lib/upgrade/platform.sh 2>&1 || true
	else
		printf '/lib/upgrade/platform.sh unavailable\n'
	fi

	section "installed release"
	for release_file in /etc/openwrt_release /etc/os-release /etc/companywrt/VERSION /etc/companywrt/build.conf; do
		[ -r "$release_file" ] || continue
		printf '%s:\n' "$release_file"
		cat "$release_file"
	done

	section "boot environment"
	if [ "$INCLUDE_BOOTENV" -eq 1 ]; then
		if [ ! -r /etc/fw_env.config ]; then
			printf 'REFUSED: /etc/fw_env.config is missing or unreadable\n'
		elif command -v fw_printenv >/dev/null 2>&1; then
			printf 'fw_env_config_sha256='
			sha256sum /etc/fw_env.config | awk '{print $1}'
			fw_printenv 2>&1 || true
		else
			printf 'fw_printenv is not installed\n'
		fi
	else
		printf 'SKIPPED: rerun with --include-bootenv only after validating /etc/fw_env.config\n'
	fi

	section "safety declaration"
	printf 'No flash, U-Boot environment, UCI, network, or MTD write command was executed.\n'
} > "$OUTPUT"

chmod 0600 "$OUTPUT"
printf '%s\n' "$OUTPUT"
