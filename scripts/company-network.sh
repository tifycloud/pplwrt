#!/bin/sh
# Produce a review-only, incremental UCI plan for the two enterprise uplinks.
# This program intentionally has no live apply or rollback mode: changing WAN
# and firewall state safely requires an operator, an out-of-band path and a
# hardware-specific maintenance window.
set -eu
LC_ALL=C
export LC_ALL
umask 077

usage() {
	cat <<'EOF'
Usage:
  company-network.sh plan \
    --unicom-device IFACE --mobile-device IFACE [options]

Required role mapping:
  unicom  1 Gbit/s primary/default office uplink
  mobile  100 Mbit/s uplink preferred for stable uploads

Options:
  --office-cidr CIDR          Office IPv4 source (default 192.168.50.0/24)
  --unicom-address CIDR       Static address; omit for DHCP
  --unicom-gateway IP         Required with --unicom-address
  --mobile-address CIDR       Static address; omit for DHCP
  --mobile-gateway IP         Required with --mobile-address
  --server IP|CIDR            Route a server source through mobile (repeatable)
  --employee IP|CIDR          Route an employee source through mobile (repeatable)
  --mobile-dest DOMAIN|CIDR   Route an office destination through mobile (repeatable)
  --unicom-dest DOMAIN|CIDR   Route an office destination through unicom (repeatable)
  --mobile-port PROTO:PORT    Route an office destination port through mobile
  --unicom-port PROTO:PORT    Route an office destination port through unicom
                              PROTO is tcp or udp; PORT may be 443 or 1000-2000
  --output DIR                Plan directory (default: secure /tmp directory)

The output is an uncommitted UCI batch plus a human review checklist. It never
imports a whole UCI package, commits, reloads services or changes the router.
Use only from an isolated wired LAN during an approved maintenance window.
EOF
}

die() {
	printf 'company-network: %s\n' "$*" >&2
	exit 2
}

valid_iface() {
	value=$1
	if [ -z "$value" ] || [ "${#value}" -gt 15 ]; then
		return 1
	fi
	case "$value" in
		[-.]*|*[!A-Za-z0-9_.-]*) return 1 ;;
	esac
}

valid_ipv4() {
	printf '%s\n' "$1" | awk -F. '
		NF != 4 { exit 1 }
		{
			for (i = 1; i <= 4; i++) {
				if ($i !~ /^[0-9]+$/ || $i > 255 || (length($i) > 1 && substr($i, 1, 1) == "0"))
					exit 1
			}
		}'
}

valid_cidr() {
	value=$1
	case "$value" in
		*/*/*|/*|*/|'') return 1 ;;
	esac
	ip=${value%/*}
	prefix=${value#*/}
	valid_ipv4 "$ip" || return 1
	case "$prefix" in
		''|*[!0-9]*|0[0-9]*) return 1 ;;
	esac
	[ "$prefix" -ge 1 ] 2>/dev/null && [ "$prefix" -le 32 ]
}

canonical_cidr() {
	printf '%s\n' "$1" | awk -F'[./]' '
		{
			addr = (((($1 * 256) + $2) * 256 + $3) * 256) + $4
			block = 1
			for (i = $5; i < 32; i++) block *= 2
			net = int(addr / block) * block
			a = int(net / 16777216); net -= a * 16777216
			b = int(net / 65536); net -= b * 65536
			c = int(net / 256); d = net - c * 256
			printf "%d.%d.%d.%d/%d\n", a, b, c, d, $5
		}'
}

valid_host_cidr() {
	valid_cidr "$1" || return 1
	prefix=${1#*/}
	[ "$prefix" -le 30 ] || return 1
	printf '%s\n' "$1" | awk -F'[./]' '
		{
			addr = (((($1 * 256) + $2) * 256 + $3) * 256) + $4
			block = 1
			for (i = $5; i < 32; i++) block *= 2
			net = int(addr / block) * block
			exit (addr == net || addr == net + block - 1)
		}'
}

cidr_contains_ip() {
	printf '%s %s\n' "$1" "$2" | awk '
		function asint(ip, p) {
			split(ip, p, ".")
			return ((((p[1] * 256) + p[2]) * 256 + p[3]) * 256) + p[4]
		}
		{
			split($1, c, "/")
			block = 1
			for (i = c[2]; i < 32; i++) block *= 2
			net = int(asint(c[1]) / block) * block
			candidate = asint($2)
			exit !(candidate > net && candidate < net + block - 1)
		}'
}

cidr_overlaps() {
	printf '%s %s\n' "$1" "$2" | awk '
		function asint(ip, p) {
			split(ip, p, ".")
			return ((((p[1] * 256) + p[2]) * 256 + p[3]) * 256) + p[4]
		}
		function start(cidr, c, block) {
			split(cidr, c, "/")
			block = 2 ^ (32 - c[2])
			return int(asint(c[1]) / block) * block
		}
		function finish(cidr, c, block, first) {
			split(cidr, c, "/")
			block = 2 ^ (32 - c[2]); first = int(asint(c[1]) / block) * block
			return first + block - 1
		}
		{ exit !(start($1) <= finish($2) && start($2) <= finish($1)) }'
}

valid_domain() {
	value=$1
	if [ -z "$value" ] || [ "${#value}" -gt 253 ]; then
		return 1
	fi
	case "$value" in
		.*|*.|*[!A-Za-z0-9.-]*) return 1 ;;
	esac
	printf '%s\n' "$value" | awk -F. '
		NF < 2 { exit 1 }
		{
			for (i = 1; i <= NF; i++) {
				if (length($i) < 1 || length($i) > 63 || $i ~ /^-/ || $i ~ /-$/)
					exit 1
			}
		}'
}

valid_destination() {
	case "$1" in
		*/*) valid_cidr "$1" ;;
		*) valid_ipv4 "$1" || valid_domain "$1" ;;
	esac
}

valid_port_policy() {
	printf '%s\n' "$1" | awk -F: '
		NF != 2 || ($1 != "tcp" && $1 != "udp") { exit 1 }
		{
			n = split($2, p, "-")
			if (n < 1 || n > 2) exit 1
			for (i = 1; i <= n; i++) {
				if (p[i] !~ /^[0-9]+$/ || p[i] < 1 || p[i] > 65535 || (length(p[i]) > 1 && substr(p[i], 1, 1) == "0"))
					exit 1
			}
			if (n == 2 && p[1] > p[2]) exit 1
		}'
}

MODE=""
UNICOM_DEVICE=""
MOBILE_DEVICE=""
OFFICE_CIDR="192.168.50.0/24"
UNICOM_ADDRESS=""
UNICOM_GATEWAY=""
MOBILE_ADDRESS=""
MOBILE_GATEWAY=""
SERVER_SOURCES=""
EMPLOYEE_SOURCES=""
MOBILE_DESTS=""
UNICOM_DESTS=""
MOBILE_PORTS=""
UNICOM_PORTS=""
OUTPUT=""

while [ "$#" -gt 0 ]; do
	case "$1" in
		plan|generate)
			[ -z "$MODE" ] || die "mode may be specified only once"
			MODE=plan
			shift
			;;
		apply|rollback)
			die "live apply/rollback is disabled; generate a plan for manual LuCI/maintenance-window review"
			;;
		--unicom-device) [ "$#" -ge 2 ] || die "missing value for $1"; UNICOM_DEVICE=$2; shift 2 ;;
		--mobile-device) [ "$#" -ge 2 ] || die "missing value for $1"; MOBILE_DEVICE=$2; shift 2 ;;
		--office-cidr) [ "$#" -ge 2 ] || die "missing value for $1"; OFFICE_CIDR=$2; shift 2 ;;
		--unicom-address) [ "$#" -ge 2 ] || die "missing value for $1"; UNICOM_ADDRESS=$2; shift 2 ;;
		--unicom-gateway) [ "$#" -ge 2 ] || die "missing value for $1"; UNICOM_GATEWAY=$2; shift 2 ;;
		--mobile-address) [ "$#" -ge 2 ] || die "missing value for $1"; MOBILE_ADDRESS=$2; shift 2 ;;
		--mobile-gateway) [ "$#" -ge 2 ] || die "missing value for $1"; MOBILE_GATEWAY=$2; shift 2 ;;
		--server)
			[ "$#" -ge 2 ] || die "missing value for $1"
			valid_ipv4 "$2" || valid_cidr "$2" || die "invalid --server IPv4/CIDR: $2"
			SERVER_SOURCES="$SERVER_SOURCES $2"; shift 2
			;;
		--employee)
			[ "$#" -ge 2 ] || die "missing value for $1"
			valid_ipv4 "$2" || valid_cidr "$2" || die "invalid --employee IPv4/CIDR: $2"
			EMPLOYEE_SOURCES="$EMPLOYEE_SOURCES $2"; shift 2
			;;
		--mobile-dest)
			[ "$#" -ge 2 ] || die "missing value for $1"
			valid_destination "$2" || die "invalid --mobile-dest domain/IPv4/CIDR: $2"
			MOBILE_DESTS="$MOBILE_DESTS $2"; shift 2
			;;
		--unicom-dest)
			[ "$#" -ge 2 ] || die "missing value for $1"
			valid_destination "$2" || die "invalid --unicom-dest domain/IPv4/CIDR: $2"
			UNICOM_DESTS="$UNICOM_DESTS $2"; shift 2
			;;
		--mobile-port)
			[ "$#" -ge 2 ] || die "missing value for $1"
			valid_port_policy "$2" || die "invalid --mobile-port protocol/port: $2"
			MOBILE_PORTS="$MOBILE_PORTS $2"; shift 2
			;;
		--unicom-port)
			[ "$#" -ge 2 ] || die "missing value for $1"
			valid_port_policy "$2" || die "invalid --unicom-port protocol/port: $2"
			UNICOM_PORTS="$UNICOM_PORTS $2"; shift 2
			;;
		--output) [ "$#" -ge 2 ] || die "missing value for $1"; OUTPUT=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown argument: $1" ;;
	esac
done

[ "$MODE" = plan ] || { usage >&2; exit 2; }
valid_iface "$UNICOM_DEVICE" || die "invalid --unicom-device (1-15 safe interface characters required)"
valid_iface "$MOBILE_DEVICE" || die "invalid --mobile-device (1-15 safe interface characters required)"
[ "$UNICOM_DEVICE" != "$MOBILE_DEVICE" ] || die "duplicate WAN device: unicom and mobile must be different"
valid_cidr "$OFFICE_CIDR" || die "invalid --office-cidr IPv4 CIDR"
OFFICE_CIDR=$(canonical_cidr "$OFFICE_CIDR")

if [ -n "$UNICOM_ADDRESS$UNICOM_GATEWAY" ]; then
	if [ -z "$UNICOM_ADDRESS" ] || [ -z "$UNICOM_GATEWAY" ]; then
		die "unicom static address and gateway must be supplied together"
	fi
	valid_host_cidr "$UNICOM_ADDRESS" || die "invalid --unicom-address host CIDR (prefix /1 through /30)"
	valid_ipv4 "$UNICOM_GATEWAY" || die "invalid --unicom-gateway IPv4 address"
	[ "${UNICOM_ADDRESS%/*}" != "$UNICOM_GATEWAY" ] || die "unicom gateway duplicates its interface address"
	cidr_contains_ip "$UNICOM_ADDRESS" "$UNICOM_GATEWAY" || die "unicom gateway is outside its address subnet or is network/broadcast"
	cidr_overlaps "$UNICOM_ADDRESS" "$OFFICE_CIDR" && die "unicom WAN subnet overlaps the office source subnet"
fi
if [ -n "$MOBILE_ADDRESS$MOBILE_GATEWAY" ]; then
	if [ -z "$MOBILE_ADDRESS" ] || [ -z "$MOBILE_GATEWAY" ]; then
		die "mobile static address and gateway must be supplied together"
	fi
	valid_host_cidr "$MOBILE_ADDRESS" || die "invalid --mobile-address host CIDR (prefix /1 through /30)"
	valid_ipv4 "$MOBILE_GATEWAY" || die "invalid --mobile-gateway IPv4 address"
	[ "${MOBILE_ADDRESS%/*}" != "$MOBILE_GATEWAY" ] || die "mobile gateway duplicates its interface address"
	cidr_contains_ip "$MOBILE_ADDRESS" "$MOBILE_GATEWAY" || die "mobile gateway is outside its address subnet or is network/broadcast"
	cidr_overlaps "$MOBILE_ADDRESS" "$OFFICE_CIDR" && die "mobile WAN subnet overlaps the office source subnet"
fi
if [ -n "$UNICOM_ADDRESS" ] && [ -n "$MOBILE_ADDRESS" ]; then
	[ "${UNICOM_ADDRESS%/*}" != "${MOBILE_ADDRESS%/*}" ] || die "duplicate WAN static address"
	cidr_overlaps "$UNICOM_ADDRESS" "$MOBILE_ADDRESS" && die "overlapping WAN static subnets are ambiguous"
fi

if [ -z "$OUTPUT" ]; then
	OUTPUT=$(mktemp -d "${TMPDIR:-/tmp}/company-network-plan.XXXXXX")
else
	case "$OUTPUT" in *[![:print:]]*) die "output path contains control characters" ;; esac
	if [ -e "$OUTPUT" ] || [ -L "$OUTPUT" ]; then
		die "output directory must not already exist"
	fi
	mkdir -m 0700 -- "$OUTPUT" || die "cannot create output directory: $OUTPUT"
fi
if [ -e "$OUTPUT/uci.batch" ] || [ -L "$OUTPUT/uci.batch" ]; then
	die "refusing to overwrite existing uci.batch"
fi
if [ -e "$OUTPUT/REVIEW.md" ] || [ -L "$OUTPUT/REVIEW.md" ]; then
	die "refusing to overwrite existing REVIEW.md"
fi
BATCH="$OUTPUT/uci.batch"
: > "$BATCH"

emit_interface() {
	role=$1
	device=$2
	address=$3
	gateway=$4
	metric=$5
	{
		printf "set network.%s=interface\n" "$role"
		printf "set network.%s.device='%s'\n" "$role" "$device"
		if [ -n "$address" ]; then
			printf "set network.%s.proto='static'\n" "$role"
			printf "set network.%s.ipaddr='%s'\n" "$role" "$address"
			printf "set network.%s.gateway='%s'\n" "$role" "$gateway"
		else
			printf "set network.%s.proto='dhcp'\n" "$role"
		fi
		printf "set network.%s.metric='%s'\n" "$role" "$metric"
		printf "set network.%s.peerdns='1'\n" "$role"
	} >> "$BATCH"
}

emit_policy() {
	section=$1
	name=$2
	source=$3
	destination=$4
	protocol=$5
	port=$6
	interface=$7
	{
		printf "set pbr.%s=policy\n" "$section"
		printf "set pbr.%s.name='%s'\n" "$section" "$name"
		[ -z "$source" ] || printf "set pbr.%s.src_addr='%s'\n" "$section" "$source"
		[ -z "$destination" ] || printf "set pbr.%s.dest_addr='%s'\n" "$section" "$destination"
		[ -z "$protocol" ] || printf "set pbr.%s.proto='%s'\n" "$section" "$protocol"
		[ -z "$port" ] || printf "set pbr.%s.dest_port='%s'\n" "$section" "$port"
		printf "set pbr.%s.interface='%s'\n" "$section" "$interface"
		printf "set pbr.%s.enabled='1'\n" "$section"
	} >> "$BATCH"
}

{
	printf '# CompanyWrt review-only incremental UCI plan\n'
	printf '# Roles: unicom=1G office default, mobile=100M stable upload\n'
	printf '# No delete/import/commit/reload commands are present.\n'
} >> "$BATCH"
emit_interface unicom "$UNICOM_DEVICE" "$UNICOM_ADDRESS" "$UNICOM_GATEWAY" 10
emit_interface mobile "$MOBILE_DEVICE" "$MOBILE_ADDRESS" "$MOBILE_GATEWAY" 20

cat >> "$BATCH" <<'EOF'
set firewall.company_unicom=zone
set firewall.company_unicom.name='company_unicom'
set firewall.company_unicom.network='unicom'
set firewall.company_unicom.input='REJECT'
set firewall.company_unicom.output='ACCEPT'
set firewall.company_unicom.forward='REJECT'
set firewall.company_unicom.masq='1'
set firewall.company_unicom.mtu_fix='1'
set firewall.company_mobile=zone
set firewall.company_mobile.name='company_mobile'
set firewall.company_mobile.network='mobile'
set firewall.company_mobile.input='REJECT'
set firewall.company_mobile.output='ACCEPT'
set firewall.company_mobile.forward='REJECT'
set firewall.company_mobile.masq='1'
set firewall.company_mobile.mtu_fix='1'
set firewall.company_lan_unicom=forwarding
set firewall.company_lan_unicom.src='lan'
set firewall.company_lan_unicom.dest='company_unicom'
set firewall.company_lan_mobile=forwarding
set firewall.company_lan_mobile.src='lan'
set firewall.company_lan_mobile.dest='company_mobile'
set pbr.config=pbr
set pbr.config.enabled='1'
set pbr.config.strict_enforcement='1'
set pbr.config.resolver_set='dnsmasq.nftset'
EOF

index=0
for source in $SERVER_SOURCES; do
	index=$((index + 1))
	emit_policy "company_server_$index" "Server $index via mobile" "$source" "" "" "" mobile
done
index=0
for source in $EMPLOYEE_SOURCES; do
	index=$((index + 1))
	emit_policy "company_employee_$index" "Employee $index via mobile" "$source" "" "" "" mobile
done
index=0
for destination in $MOBILE_DESTS; do
	index=$((index + 1))
	emit_policy "company_mobile_dest_$index" "Destination $index via mobile" "$OFFICE_CIDR" "$destination" "" "" mobile
done
index=0
for destination in $UNICOM_DESTS; do
	index=$((index + 1))
	emit_policy "company_unicom_dest_$index" "Destination $index via unicom" "$OFFICE_CIDR" "$destination" "" "" unicom
done
index=0
for spec in $MOBILE_PORTS; do
	index=$((index + 1))
	protocol=${spec%%:*}
	port=${spec#*:}
	emit_policy "company_mobile_port_$index" "$protocol/$port via mobile" "$OFFICE_CIDR" "" "$protocol" "$port" mobile
done
index=0
for spec in $UNICOM_PORTS; do
	index=$((index + 1))
	protocol=${spec%%:*}
	port=${spec#*:}
	emit_policy "company_unicom_port_$index" "$protocol/$port via unicom" "$OFFICE_CIDR" "" "$protocol" "$port" unicom
done
emit_policy company_office_default "Office default via unicom" "$OFFICE_CIDR" "" "" "" unicom

cat > "$OUTPUT/REVIEW.md" <<EOF
# CompanyWrt network change plan

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

- Role **unicom**: device \`$UNICOM_DEVICE\`, 1 Gbit/s primary/default office path, metric 10.
- Role **mobile**: device \`$MOBILE_DEVICE\`, 100 Mbit/s stable-upload path, metric 20.
- Office source: \`$OFFICE_CIDR\`.

This directory is a plan, not an installer. It intentionally contains no
\`uci import\`, package-wide delete, commit, service reload, live apply or
automatic rollback. Existing loopback, DSA bridge/ports, default WAN/WAN6,
firewall defaults and built-in rules are left untouched.

## Required human gate

1. Use an isolated wired LAN and confirm an out-of-band/vendor recovery path.
2. Record \`ubus call system board\`, \`ip -br link\`, \`uci export network\`,
   \`uci export firewall\`, \`uci export pbr\`, IPv6 and OpenClash mark/table state.
3. Review every line in \`uci.batch\`; confirm named sections do not collide.
4. In the maintenance window, stage with \`uci -q batch < uci.batch\`. Inspect
   \`uci changes network\`, \`uci changes firewall\` and \`uci changes pbr\`.
   Use \`uci revert <package>\` if the staged diff is wrong.
5. Only an on-site administrator may commit/reload through LuCI/CLI after the
   staged diff is approved. Verify HTTPS management before changing uplinks.
6. Test unicom/mobile independently, WAN rejection, DNS, IPv4/IPv6, PBR source,
   domain/address/port policies and OpenClash ownership. Archive redacted evidence.

Because a reliable hardware-independent automatic rollback cannot be proven,
this project does not provide a live-apply command.
EOF

printf '%s\n' "$OUTPUT"
