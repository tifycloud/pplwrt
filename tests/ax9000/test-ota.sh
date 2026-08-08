#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-ota-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
MOCK="$TMP/mock-bin"
mkdir -p "$MOCK" "$TMP/device/etc/companywrt"

cat > "$MOCK/usign" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = -F ]; then
	echo 444eb53ba66e6d45
	exit 0
fi
[ "${1:-}" = -q ] && shift
[ "${1:-}" = -V ] || exit 2
shift
message=''
signature=''
while [ "$#" -gt 0 ]; do
	case "$1" in
		-p) grep -q 'RWRETrU7pm5t' "$2" || exit 1; shift 2 ;;
		-m) message=$2; shift 2 ;;
		-x) signature=$2; shift 2 ;;
		*) exit 2 ;;
	esac
done
[ -n "$message" ] && [ -n "$signature" ]
[ "$(sha256sum "$message" | awk '{print $1}')" = "$(sed -n '1p' "$signature")" ]
EOF

cat > "$MOCK/id" <<'EOF'
#!/bin/sh
[ "${1:-}" = -u ] && { echo 0; exit 0; }
exec /usr/bin/id "$@"
EOF

cat > "$MOCK/ubus" <<'EOF'
#!/bin/sh
[ "$*" = 'call system board' ] || exit 1
cat <<JSON
{"board_name":"${TEST_BOARD:-xiaomi,ax9000-darkyun}","release":{"version":"25.12.5","target":"qualcommax/ipq807x"}}
JSON
EOF

cat > "$MOCK/jsonfilter" <<'EOF'
#!/bin/sh
[ "${1:-}" = -e ] || exit 2
case "$2" in
	@.board_name) echo "${TEST_BOARD:-xiaomi,ax9000-darkyun}" ;;
	@.release.version) echo 25.12.5 ;;
	@.release.target) echo qualcommax/ipq807x ;;
	*) exit 1 ;;
esac
EOF

cat > "$MOCK/sysupgrade" <<'EOF'
#!/bin/sh
[ "${1:-}" = -T ] && [ -f "${2:-}" ] || exit 1
printf '%s\n' "$*" >> "$SYSUPGRADE_LOG"
EOF
chmod 0755 "$MOCK"/*

printf 'signed firmware fixture\n' > "$TMP/image.bin"
IMAGE_SHA=$(sha256sum "$TMP/image.bin" | awk '{print $1}')
IMAGE_SIZE=$(wc -c < "$TMP/image.bin" | tr -d '[:space:]')
IMAGE_NAME='openwrt-25.12.5-qualcommax-ipq807x-xiaomi_ax9000_darkyun-squashfs-sysupgrade.bin'
cat > "$TMP/manifest" <<EOF
FORMAT=companywrt-darkyun-release-v1
VERSION=25.12.5-company.2-rc1
OPENWRT_RELEASE=25.12.5
PROFILE=xiaomi_ax9000_darkyun
BOARD=xiaomi,ax9000-darkyun
PARTITION_VARIANT=darkyun-large-ubi-v1
MIBIB_SHA256=2d79c1b15b8946af733dba5fff5e33bf3ba18863ed734710bd2a5e48fc469c11
APPSBL_SHA256=80908e502add45ee6aa7ad83aa16ec2c3c8bf27b572ac0f9c3fe404b94fc0007
MIGRATION_BOARD=xiaomi,ax9000
CHANNEL=rc
TAG=v25.12.5-company.2-rc1
SOURCE_COMMIT=0123456789abcdef0123456789abcdef01234567
IMAGE=$IMAGE_NAME
SHA256=$IMAGE_SHA
SIZE=$IMAGE_SIZE
URL=https://github.com/tifycloud/pplwrt/releases/download/v25.12.5-company.2-rc1/$IMAGE_NAME
SIGNATURE=RELEASE-MANIFEST.sig
SIGNATURE_URL=https://github.com/tifycloud/pplwrt/releases/download/v25.12.5-company.2-rc1/RELEASE-MANIFEST.sig
USIGN_KEY_ID=444eb53ba66e6d45
EOF
sha256sum "$TMP/manifest" | awk '{print $1}' > "$TMP/manifest.sig"

PATH="$MOCK:$PATH" "$ROOT/scripts/ota-check.sh" \
	--manifest "$TMP/manifest" --signature "$TMP/manifest.sig" --image "$TMP/image.bin" \
	--public-key "$ROOT/keys/companywrt-release.pub" --download-dir "$TMP/checked" \
	--version 25.12.5-company.2-rc1 --profile xiaomi_ax9000_darkyun --board xiaomi,ax9000-darkyun --channel rc \
	> "$TMP/check.out"
grep -q 'VERIFIED_SHA256='"$IMAGE_SHA" "$TMP/check.out"
grep -q 'No router state was changed' "$TMP/check.out"
cmp "$TMP/image.bin" "$TMP/checked/$IMAGE_NAME"

cat > "$TMP/stable.manifest" <<EOF
FORMAT=companywrt-darkyun-release-v2
VERSION=25.12.5-company.2
OPENWRT_RELEASE=25.12.5
PROFILE=xiaomi_ax9000_darkyun
BOARD=xiaomi,ax9000-darkyun
PARTITION_VARIANT=darkyun-large-ubi-v1
MIBIB_SHA256=2d79c1b15b8946af733dba5fff5e33bf3ba18863ed734710bd2a5e48fc469c11
APPSBL_SHA256=80908e502add45ee6aa7ad83aa16ec2c3c8bf27b572ac0f9c3fe404b94fc0007
MIGRATION_BOARD=xiaomi,ax9000
CHANNEL=stable
TAG=v25.12.5-company.2
SOURCE_COMMIT=0123456789abcdef0123456789abcdef01234567
IMAGE=$IMAGE_NAME
SHA256=$IMAGE_SHA
SIZE=$IMAGE_SIZE
URL=https://github.com/tifycloud/pplwrt/releases/download/v25.12.5-company.2/$IMAGE_NAME
SIGNATURE=RELEASE-MANIFEST.sig
SIGNATURE_URL=https://github.com/tifycloud/pplwrt/releases/download/v25.12.5-company.2/RELEASE-MANIFEST.sig
USIGN_KEY_ID=444eb53ba66e6d45
HARDWARE_VALIDATION=VERIFIED
PRODUCTION_GATE_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
HARDWARE_EVIDENCE_ID=hw-record-fixture-001
SERIAL_EVIDENCE_ID=serial-record-redacted-001
TESTED_FIRMWARE_SHA256=$IMAGE_SHA
EOF
sha256sum "$TMP/stable.manifest" | awk '{print $1}' > "$TMP/stable.sig"
PATH="$MOCK:$PATH" "$ROOT/scripts/ota-check.sh" \
	--manifest "$TMP/stable.manifest" --signature "$TMP/stable.sig" --image "$TMP/image.bin" \
	--public-key "$ROOT/keys/companywrt-release.pub" --download-dir "$TMP/stable-checked" \
	--version 25.12.5-company.2 --profile xiaomi_ax9000_darkyun --board xiaomi,ax9000-darkyun --channel stable \
	> "$TMP/stable.out"
grep -q 'VERIFIED_HARDWARE_VALIDATION=VERIFIED' "$TMP/stable.out"
grep -q 'VERIFIED_PRODUCTION_GATE_SHA256=aaaaaaaa' "$TMP/stable.out"

if PATH="$MOCK:$PATH" "$ROOT/scripts/ota-check.sh" \
	--manifest "$TMP/manifest" --signature "$TMP/manifest.sig" --image "$TMP/image.bin" \
	--public-key "$ROOT/keys/companywrt-release.pub" --download-dir "$TMP/checked" \
	>"$TMP/reused-dir.out" 2>"$TMP/reused-dir.err"; then
	echo 'pre-existing OTA staging directory unexpectedly passed' >&2
	exit 1
fi
grep -q 'directory must not already exist' "$TMP/reused-dir.err"

expect_check_fail() {
	name=$1
	manifest=$2
	signature=$3
	image=$4
	if PATH="$MOCK:$PATH" "$ROOT/scripts/ota-check.sh" \
		--manifest "$manifest" --signature "$signature" --image "$image" \
		--public-key "$ROOT/keys/companywrt-release.pub" --download-dir "$TMP/$name" \
		>"$TMP/$name.out" 2>"$TMP/$name.err"; then
		echo "$name unexpectedly passed" >&2
		exit 1
	fi
}

cp "$TMP/image.bin" "$TMP/tampered.bin"
printf 'tamper\n' >> "$TMP/tampered.bin"
expect_check_fail tampered "$TMP/manifest" "$TMP/manifest.sig" "$TMP/tampered.bin"
grep -Eq 'download bound|size mismatch|SHA256 mismatch' "$TMP/tampered.err"

sed 's/^SHA256=.*/SHA256=0123456789abcdef/' "$TMP/manifest" > "$TMP/short-sha.manifest"
sha256sum "$TMP/short-sha.manifest" | awk '{print $1}' > "$TMP/short-sha.sig"
expect_check_fail short-sha "$TMP/short-sha.manifest" "$TMP/short-sha.sig" "$TMP/image.bin"
grep -q '64 lowercase hex' "$TMP/short-sha.err"

sed 's/^CHANNEL=rc$/CHANNEL=beta/' "$TMP/manifest" > "$TMP/channel-mismatch.manifest"
sha256sum "$TMP/channel-mismatch.manifest" | awk '{print $1}' > "$TMP/channel-mismatch.sig"
expect_check_fail channel-mismatch "$TMP/channel-mismatch.manifest" "$TMP/channel-mismatch.sig" "$TMP/image.bin"
grep -q 'beta channel requires a -betaN version' "$TMP/channel-mismatch.err"

sed 's/^OPENWRT_RELEASE=.*/OPENWRT_RELEASE=25.12.4/' "$TMP/manifest" > "$TMP/release-mismatch.manifest"
sha256sum "$TMP/release-mismatch.manifest" | awk '{print $1}' > "$TMP/release-mismatch.sig"
expect_check_fail release-mismatch "$TMP/release-mismatch.manifest" "$TMP/release-mismatch.sig" "$TMP/image.bin"
grep -q 'VERSION base must equal OPENWRT_RELEASE' "$TMP/release-mismatch.err"

cp "$TMP/manifest" "$TMP/duplicate.manifest"
printf 'VERSION=25.12.5-company.2-rc1\n' >> "$TMP/duplicate.manifest"
sha256sum "$TMP/duplicate.manifest" | awk '{print $1}' > "$TMP/duplicate.sig"
expect_check_fail duplicate "$TMP/duplicate.manifest" "$TMP/duplicate.sig" "$TMP/image.bin"
grep -Eq 'duplicate manifest field|exactly 19 fields' "$TMP/duplicate.err"

cp "$TMP/manifest.sig" "$TMP/bad.sig"
printf 'bad\n' > "$TMP/bad.sig"
expect_check_fail signature "$TMP/manifest" "$TMP/bad.sig" "$TMP/image.bin"
grep -q 'signature verification failed' "$TMP/signature.err"

if PATH="$MOCK:$PATH" "$ROOT/scripts/ota-check.sh" --manifest http://example.invalid/manifest \
	--public-key "$ROOT/keys/companywrt-release.pub" >"$TMP/http.out" 2>"$TMP/http.err"; then
	echo 'plain HTTP manifest unexpectedly passed' >&2
	exit 1
fi
grep -q 'plain HTTP is forbidden' "$TMP/http.err"

cat > "$TMP/device/etc/companywrt/build.conf" <<'EOF'
PROFILE=xiaomi_ax9000_darkyun
BOARD=xiaomi,ax9000-darkyun
PARTITION_VARIANT=darkyun-large-ubi-v1
RELEASE=25.12.5
CHANNEL=rc
EOF
printf '25.12.5-company.1-rc1\n' > "$TMP/device/etc/companywrt/VERSION"
SYSUPGRADE_LOG="$TMP/sysupgrade.log"
export SYSUPGRADE_LOG
"$ROOT/scripts/ota-apply.sh" --help > "$TMP/apply-help.out"
grep -q 'PRODUCTION TRUST ANCHOR IS FIXED' "$TMP/apply-help.out"
grep -q '/etc/companywrt/keys/release.pub' "$TMP/apply-help.out"
if PATH="$MOCK:$PATH" "$ROOT/scripts/ota-apply.sh" \
	--manifest "$TMP/manifest" --signature "$TMP/manifest.sig" --image "$TMP/image.bin" \
	--public-key "$ROOT/keys/companywrt-release.pub" --work-dir "$TMP/production-override" \
	--expected-version 25.12.5-company.2-rc1 --expected-channel rc \
	--confirm-version 25.12.5-company.2-rc1 --confirm-sha256 "$IMAGE_SHA" \
	>"$TMP/production-override.out" 2>"$TMP/production-override.err"; then
	echo 'production ota-apply unexpectedly accepted a public key override' >&2
	exit 1
fi
grep -q -- '--public-key is forbidden in production' "$TMP/production-override.err"
if PATH="$MOCK:$PATH" COMPANYWRT_DEVICE_ROOT="$TMP/device" "$ROOT/scripts/ota-apply.sh" \
	--test-mode --manifest "$TMP/manifest" \
	--expected-version 25.12.5-company.2-rc1 --expected-channel rc \
	--confirm-version 25.12.5-company.2-rc1 --confirm-sha256 "$IMAGE_SHA" \
	>"$TMP/unarmed-test.out" 2>"$TMP/unarmed-test.err"; then
	echo 'ota-apply test mode unexpectedly worked without its environment guard' >&2
	exit 1
fi
grep -q 'requires COMPANYWRT_OTA_TEST_MODE=1' "$TMP/unarmed-test.err"
PATH="$MOCK:$PATH" COMPANYWRT_OTA_TEST_MODE=1 COMPANYWRT_DEVICE_ROOT="$TMP/device" "$ROOT/scripts/ota-apply.sh" \
	--test-mode \
	--manifest "$TMP/manifest" --signature "$TMP/manifest.sig" --image "$TMP/image.bin" \
	--public-key "$ROOT/keys/companywrt-release.pub" --work-dir "$TMP/apply" \
	--expected-version 25.12.5-company.2-rc1 --expected-channel rc \
	--confirm-version 25.12.5-company.2-rc1 --confirm-sha256 "$IMAGE_SHA" > "$TMP/apply.out"
grep -q 'SIGNED OTA CANDIDATE PASSED ALL AUTOMATED CHECKS' "$TMP/apply.out"
grep -q 'Final manual command (NOT executed)' "$TMP/apply.out"
[ "$(wc -l < "$SYSUPGRADE_LOG" | tr -d '[:space:]')" = 1 ]
grep -q '^-T ' "$SYSUPGRADE_LOG"

if PATH="$MOCK:$PATH" COMPANYWRT_OTA_TEST_MODE=1 COMPANYWRT_DEVICE_ROOT="$TMP/device" "$ROOT/scripts/ota-apply.sh" \
	--test-mode \
	--manifest "$TMP/manifest" --signature "$TMP/manifest.sig" --image "$TMP/image.bin" \
	--public-key "$ROOT/keys/companywrt-release.pub" --work-dir "$TMP/bad-confirm" \
	--expected-version 25.12.5-company.2-rc1 --expected-channel rc \
	--confirm-version 25.12.5-company.2-rc1 --confirm-sha256 0000000000000000000000000000000000000000000000000000000000000000 \
	>"$TMP/confirm.out" 2>"$TMP/confirm.err"; then
	echo 'wrong second confirmation unexpectedly passed' >&2
	exit 1
fi
grep -q 'does not match second confirmation' "$TMP/confirm.err"

if TEST_BOARD=xiaomi,wrong PATH="$MOCK:$PATH" COMPANYWRT_OTA_TEST_MODE=1 COMPANYWRT_DEVICE_ROOT="$TMP/device" "$ROOT/scripts/ota-apply.sh" \
	--test-mode \
	--manifest "$TMP/manifest" --signature "$TMP/manifest.sig" --image "$TMP/image.bin" \
	--public-key "$ROOT/keys/companywrt-release.pub" --work-dir "$TMP/bad-board" \
	--expected-version 25.12.5-company.2-rc1 --expected-channel rc \
	--confirm-version 25.12.5-company.2-rc1 --confirm-sha256 "$IMAGE_SHA" \
	>"$TMP/board.out" 2>"$TMP/board.err"; then
	echo 'wrong device board unexpectedly passed' >&2
	exit 1
fi
grep -q 'device board mismatch' "$TMP/board.err"

printf '25.12.5-company.2-rc2\n' > "$TMP/device/etc/companywrt/VERSION"
if PATH="$MOCK:$PATH" COMPANYWRT_OTA_TEST_MODE=1 COMPANYWRT_DEVICE_ROOT="$TMP/device" "$ROOT/scripts/ota-apply.sh" \
	--test-mode \
	--manifest "$TMP/manifest" --signature "$TMP/manifest.sig" --image "$TMP/image.bin" \
	--public-key "$ROOT/keys/companywrt-release.pub" --work-dir "$TMP/downgrade" \
	--expected-version 25.12.5-company.2-rc1 --expected-channel rc \
	--confirm-version 25.12.5-company.2-rc1 --confirm-sha256 "$IMAGE_SHA" \
	>"$TMP/downgrade.out" 2>"$TMP/downgrade.err"; then
	echo 'same-generation prerelease downgrade unexpectedly passed' >&2
	exit 1
fi
grep -q 'candidate is not newer' "$TMP/downgrade.err"

echo 'OTA strict manifest, usign binding, image integrity and device/double-confirm gates: ok'
