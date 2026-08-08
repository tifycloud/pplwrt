#!/bin/sh
# Generate or apply an explicit two-WAN policy. No credentials are accepted on
# the command line; DHCP is the safe default and UCI remains the source of truth.
set -eu

usage() {
  cat <<'EOF'
Usage:
  company-network.sh generate --wan1 IFACE --wan2 IFACE [options]
  company-network.sh apply --wan1 IFACE --wan2 IFACE [options]

Options:
  --lan-cidr CIDR       LAN IPv4 subnet (default 192.168.50.1/24)
  --wan1-gateway IP     Optional static gateway for WAN1
  --wan2-gateway IP     Optional static gateway for WAN2
  --output DIR          Output directory for generated UCI files
  --yes                 Required for apply; still creates a backup first
  --rollback FILE       Restore a backup created by apply

The generated PBR policy is intentionally conservative: source subnet and
destination port can choose WAN1/WAN2; established flows stay on one mark.
Review files in the output directory before applying to a live router.
EOF
}

die() { echo "company-network: $*" >&2; exit 2; }

MODE=""
WAN1=""
WAN2=""
LAN_CIDR="192.168.50.1/24"
GATEWAY1=""
GATEWAY2=""
OUTPUT=""
YES=0
ROLLBACK=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    generate|apply) MODE="$1"; shift ;;
    --wan1) WAN1=${2:-}; shift 2 ;;
    --wan2) WAN2=${2:-}; shift 2 ;;
    --lan-cidr) LAN_CIDR=${2:-}; shift 2 ;;
    --wan1-gateway) GATEWAY1=${2:-}; shift 2 ;;
    --wan2-gateway) GATEWAY2=${2:-}; shift 2 ;;
    --output) OUTPUT=${2:-}; shift 2 ;;
    --yes) YES=1; shift ;;
    --rollback) ROLLBACK=${2:-}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

if [ -n "$ROLLBACK" ]; then
  [ "$MODE" = apply ] || die "--rollback is only valid with apply"
  [ "$YES" -eq 1 ] || die "--yes is required for rollback"
  [ -d "$ROLLBACK" ] || die "backup directory not found: $ROLLBACK"
  command -v uci >/dev/null 2>&1 || die "uci is required on the router"
  for f in network firewall pbr; do
    [ -f "$ROLLBACK/$f" ] || continue
    cp -p "$ROLLBACK/$f" "/etc/config/$f"
    uci -q revert "$f" || true
  done
  uci commit
  /etc/init.d/network reload 2>/dev/null || true
  /etc/init.d/firewall reload 2>/dev/null || true
  /etc/init.d/pbr restart 2>/dev/null || true
  echo "rolled back from $ROLLBACK"
  exit 0
fi

[ -n "$MODE" ] || { usage >&2; exit 2; }
[ -n "$WAN1" ] || die "--wan1 is required"
[ -n "$WAN2" ] || die "--wan2 is required"
case "$LAN_CIDR" in */*) : ;; *) die "--lan-cidr must contain a prefix" ;; esac
LAN_PREFIX=${LAN_CIDR#*/}
LAN_IP=${LAN_CIDR%/*}
[ "$LAN_PREFIX" = 24 ] || die "--lan-cidr currently requires an IPv4 /24"
LAN_NETWORK="$LAN_CIDR"
if [ "$LAN_PREFIX" = 24 ]; then
  LAN_NETWORK=$(printf '%s\n' "$LAN_IP" | awk -F. 'NF==4 {printf "%d.%d.%d.0/24",$1,$2,$3}')
fi

if [ -z "$OUTPUT" ]; then
  OUTPUT=$(mktemp -d /tmp/company-network.XXXXXX)
else
  mkdir -p "$OUTPUT"
fi

WAN1_PROTO=dhcp
WAN2_PROTO=dhcp
[ -n "$GATEWAY1" ] && WAN1_PROTO=static
[ -n "$GATEWAY2" ] && WAN2_PROTO=static

cat > "$OUTPUT/network" <<EOF
config interface 'lan'
        option device 'br-lan'
        option proto 'static'
        option ipaddr '$LAN_IP'
        option netmask '255.255.255.0'

config interface 'wan1'
        option device '$WAN1'
        option proto '$WAN1_PROTO'
$( [ -n "$GATEWAY1" ] && printf "        option gateway '%s'\n" "$GATEWAY1" )

config interface 'wan2'
        option device '$WAN2'
        option proto '$WAN2_PROTO'
$( [ -n "$GATEWAY2" ] && printf "        option gateway '%s'\n" "$GATEWAY2" )
EOF

cat > "$OUTPUT/firewall" <<'EOF'
config defaults
        option input 'REJECT'
        option output 'ACCEPT'
        option forward 'REJECT'
        option synflood_protect '1'

config zone
        option name 'lan'
        list network 'lan'
        option input 'ACCEPT'
        option output 'ACCEPT'
        option forward 'ACCEPT'

config zone
        option name 'wan'
        list network 'wan1'
        list network 'wan2'
        option input 'REJECT'
        option output 'ACCEPT'
        option forward 'REJECT'
        option masq '1'
        option mtu_fix '1'

config forwarding
        option src 'lan'
        option dest 'wan'
EOF

cat > "$OUTPUT/pbr" <<EOF
config pbr 'config'
        option enabled '1'
        option strict_enforcement '1'
        option resolver_set 'none'
        option ipv6_enabled '0'
        option nft_file '/etc/pbr.d/company.nft'

config policy
        option name 'Corporate LAN to WAN1'
        option src_addr '$LAN_NETWORK'
        option interface 'wan1'

# Add explicit destination/port policies here. Do not overlap OpenClash's
# mark/table; reserve fwmark 0x100/0x200 for PBR and document any exception.
EOF

cat > "$OUTPUT/README" <<EOF
Generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
WAN1=$WAN1 WAN2=$WAN2 LAN=$LAN_CIDR

Review before importing. This output contains no PPPoE credentials. The PBR
policy must be extended with intentional source/destination/port rules and a
mark/table allocation that does not collide with OpenClash.
EOF

if [ "$MODE" = generate ]; then
  echo "$OUTPUT"
  exit 0
fi

[ "$YES" -eq 1 ] || die "apply changes live router state; repeat with --yes after review"
command -v uci >/dev/null 2>&1 || die "uci is required for apply"
BACKUP="${OUTPUT}.backup.$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP"
for f in network firewall pbr; do
  if [ -f "/etc/config/$f" ]; then
    cp -p "/etc/config/$f" "$BACKUP/$f" || true
  fi
  uci import "$f" < "$OUTPUT/$f"
done
uci commit
/etc/init.d/network reload
/etc/init.d/firewall reload
/etc/init.d/pbr restart 2>/dev/null || true
echo "applied; backup=$BACKUP"
