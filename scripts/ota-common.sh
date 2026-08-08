#!/bin/sh
# Shared strict OTA parsing and verification. Callers must set -eu themselves.

ota_die() {
	printf 'companywrt-ota: %s\n' "$*" >&2
	exit 1
}

ota_manifest_value() {
	key=$1
	file=$2
	awk -v wanted="$key" 'index($0, "=") { key = substr($0, 1, index($0, "=") - 1); if (key == wanted) { print substr($0, index($0, "=") + 1); exit } }' "$file"
}

ota_validate_manifest() {
	manifest=$1
	[ -s "$manifest" ] || ota_die "manifest is empty: $manifest"

	LC_ALL=C awk '
		BEGIN {
			required["FORMAT"] = 1; required["VERSION"] = 1; required["OPENWRT_RELEASE"] = 1
			required["PROFILE"] = 1; required["BOARD"] = 1; required["CHANNEL"] = 1
			required["PARTITION_VARIANT"] = 1; required["MIBIB_SHA256"] = 1
			required["APPSBL_SHA256"] = 1; required["MIGRATION_BOARD"] = 1
			required["TAG"] = 1; required["SOURCE_COMMIT"] = 1; required["IMAGE"] = 1
			required["SHA256"] = 1; required["SIZE"] = 1; required["URL"] = 1
			required["SIGNATURE"] = 1; required["SIGNATURE_URL"] = 1; required["USIGN_KEY_ID"] = 1
			hardware["HARDWARE_VALIDATION"] = 1; hardware["PRODUCTION_GATE_SHA256"] = 1
			hardware["HARDWARE_EVIDENCE_ID"] = 1; hardware["SERIAL_EVIDENCE_ID"] = 1
			hardware["TESTED_FIRMWARE_SHA256"] = 1
		}
		/\r/ { print "manifest contains CR characters" > "/dev/stderr"; exit 1 }
		{
			pos = index($0, "=")
			if (pos < 2) { print "manifest line is not KEY=value" > "/dev/stderr"; exit 1 }
			key = substr($0, 1, pos - 1); value = substr($0, pos + 1)
			if (!(key in required) && !(key in hardware)) { print "unknown manifest field: " key > "/dev/stderr"; exit 1 }
			if (seen[key]++) { print "duplicate manifest field: " key > "/dev/stderr"; exit 1 }
			if (value == "") { print "empty manifest field: " key > "/dev/stderr"; exit 1 }
			values[key] = value
		}
		END {
			for (key in required) if (!seen[key]) { print "missing manifest field: " key > "/dev/stderr"; exit 1 }
			if (values["FORMAT"] == "companywrt-darkyun-release-v1") {
				if (NR != 19) { print "Darkyun v1 manifest must contain exactly 19 fields" > "/dev/stderr"; exit 1 }
				for (key in hardware) if (seen[key]) { print "v1 manifest contains stable-only field: " key > "/dev/stderr"; exit 1 }
			} else if (values["FORMAT"] == "companywrt-darkyun-release-v2") {
				if (NR != 24) { print "Darkyun v2 manifest must contain exactly 24 fields" > "/dev/stderr"; exit 1 }
				for (key in hardware) if (!seen[key]) { print "missing v2 manifest field: " key > "/dev/stderr"; exit 1 }
			} else {
				print "unsupported manifest format: " values["FORMAT"] > "/dev/stderr"; exit 1
			}
			}' "$manifest" || ota_die "manifest schema validation failed"

	OTA_FORMAT=$(ota_manifest_value FORMAT "$manifest")
	OTA_VERSION=$(ota_manifest_value VERSION "$manifest")
	OTA_OPENWRT_RELEASE=$(ota_manifest_value OPENWRT_RELEASE "$manifest")
	OTA_PROFILE=$(ota_manifest_value PROFILE "$manifest")
	OTA_BOARD=$(ota_manifest_value BOARD "$manifest")
	OTA_PARTITION_VARIANT=$(ota_manifest_value PARTITION_VARIANT "$manifest")
	OTA_MIBIB_SHA256=$(ota_manifest_value MIBIB_SHA256 "$manifest")
	OTA_APPSBL_SHA256=$(ota_manifest_value APPSBL_SHA256 "$manifest")
	OTA_MIGRATION_BOARD=$(ota_manifest_value MIGRATION_BOARD "$manifest")
	OTA_CHANNEL=$(ota_manifest_value CHANNEL "$manifest")
	OTA_TAG=$(ota_manifest_value TAG "$manifest")
	OTA_SOURCE_COMMIT=$(ota_manifest_value SOURCE_COMMIT "$manifest")
	OTA_IMAGE=$(ota_manifest_value IMAGE "$manifest")
	OTA_SHA256=$(ota_manifest_value SHA256 "$manifest")
	OTA_SIZE=$(ota_manifest_value SIZE "$manifest")
	OTA_URL=$(ota_manifest_value URL "$manifest")
	OTA_SIGNATURE=$(ota_manifest_value SIGNATURE "$manifest")
	OTA_SIGNATURE_URL=$(ota_manifest_value SIGNATURE_URL "$manifest")
	OTA_USIGN_KEY_ID=$(ota_manifest_value USIGN_KEY_ID "$manifest")
	OTA_HARDWARE_VALIDATION=$(ota_manifest_value HARDWARE_VALIDATION "$manifest")
	OTA_PRODUCTION_GATE_SHA256=$(ota_manifest_value PRODUCTION_GATE_SHA256 "$manifest")
	OTA_HARDWARE_EVIDENCE_ID=$(ota_manifest_value HARDWARE_EVIDENCE_ID "$manifest")
	OTA_SERIAL_EVIDENCE_ID=$(ota_manifest_value SERIAL_EVIDENCE_ID "$manifest")
	OTA_TESTED_FIRMWARE_SHA256=$(ota_manifest_value TESTED_FIRMWARE_SHA256 "$manifest")

	case "$OTA_FORMAT" in companywrt-darkyun-release-v1|companywrt-darkyun-release-v2) ;; *) ota_die "unsupported manifest format: $OTA_FORMAT" ;; esac
	printf '%s\n' "$OTA_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-company\.[0-9]+(-(rc|beta)[1-9][0-9]*)?$' || ota_die "invalid VERSION"
	printf '%s\n' "$OTA_OPENWRT_RELEASE" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || ota_die "invalid OPENWRT_RELEASE"
	printf '%s\n' "$OTA_PROFILE" | grep -Eq '^[a-z0-9][a-z0-9_]{0,63}$' || ota_die "invalid PROFILE"
	printf '%s\n' "$OTA_BOARD" | grep -Eq '^[a-z0-9][a-z0-9,._-]{0,63}$' || ota_die "invalid BOARD"
	case "$OTA_CHANNEL" in
		rc) printf '%s\n' "$OTA_VERSION" | grep -Eq -- '-rc[1-9][0-9]*$' || ota_die "rc channel requires an -rcN version" ;;
		beta) printf '%s\n' "$OTA_VERSION" | grep -Eq -- '-beta[1-9][0-9]*$' || ota_die "beta channel requires a -betaN version" ;;
		stable)
			printf '%s\n' "$OTA_VERSION" | grep -Eq -- '-(rc|beta)[1-9][0-9]*$' && ota_die "stable channel cannot use a prerelease version"
			[ "$OTA_FORMAT" = companywrt-darkyun-release-v2 ] || ota_die "stable channel requires a hardware-bound Darkyun v2 manifest"
			;;
		*) ota_die "invalid CHANNEL: $OTA_CHANNEL" ;;
	esac
	[ "$OTA_PROFILE" = xiaomi_ax9000_darkyun ] || ota_die "manifest is not the Darkyun AX9000 profile"
	[ "$OTA_BOARD" = xiaomi,ax9000-darkyun ] || ota_die "manifest is not the Darkyun AX9000 board"
	[ "$OTA_PARTITION_VARIANT" = darkyun-large-ubi-v1 ] || ota_die "unsupported partition variant"
	[ "$OTA_MIBIB_SHA256" = 2d79c1b15b8946af733dba5fff5e33bf3ba18863ed734710bd2a5e48fc469c11 ] || ota_die "MIBIB trust fingerprint mismatch"
	[ "$OTA_APPSBL_SHA256" = 80908e502add45ee6aa7ad83aa16ec2c3c8bf27b572ac0f9c3fe404b94fc0007 ] || ota_die "APPSBL trust fingerprint mismatch"
	[ "$OTA_MIGRATION_BOARD" = xiaomi,ax9000 ] || ota_die "unexpected one-time migration board"
	if [ "$OTA_FORMAT" = companywrt-darkyun-release-v2 ]; then
		[ "$OTA_CHANNEL" = stable ] || ota_die "v2 hardware-bound manifests are stable-only"
		[ "$OTA_HARDWARE_VALIDATION" = VERIFIED ] || ota_die "v2 manifest requires HARDWARE_VALIDATION=VERIFIED"
		printf '%s\n' "$OTA_PRODUCTION_GATE_SHA256" "$OTA_TESTED_FIRMWARE_SHA256" | \
			awk 'length($0) != 64 || $0 !~ /^[0-9a-f]+$/ { exit 1 }' || ota_die "v2 manifest requires 64-hex hardware evidence digests"
		printf '%s\n' "$OTA_HARDWARE_EVIDENCE_ID" "$OTA_SERIAL_EVIDENCE_ID" | \
			awk 'length($0) < 3 || length($0) > 128 || $0 !~ /^[A-Za-z0-9][A-Za-z0-9._:-]+$/ { exit 1 }' || ota_die "v2 manifest requires safe opaque evidence IDs"
		[ "$OTA_TESTED_FIRMWARE_SHA256" = "$OTA_SHA256" ] || ota_die "v2 tested firmware digest must exactly equal SHA256"
	else
		OTA_HARDWARE_VALIDATION=NOT_PERFORMED_RC_ONLY
		OTA_PRODUCTION_GATE_SHA256=NONE
		OTA_HARDWARE_EVIDENCE_ID=NONE
		OTA_SERIAL_EVIDENCE_ID=NONE
		OTA_TESTED_FIRMWARE_SHA256=NONE
	fi
	[ "${OTA_VERSION%%-company.*}" = "$OTA_OPENWRT_RELEASE" ] || ota_die "VERSION base must equal OPENWRT_RELEASE"
	[ "$OTA_TAG" = "v$OTA_VERSION" ] || ota_die "TAG must equal vVERSION"
	printf '%s\n' "$OTA_SOURCE_COMMIT" | grep -Eq '^[0-9a-f]{40}$' || ota_die "SOURCE_COMMIT must be 40 lowercase hex characters"
	printf '%s\n' "$OTA_IMAGE" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,199}-sysupgrade\.bin$' || ota_die "invalid IMAGE basename"
	printf '%s\n' "$OTA_SHA256" | grep -Eq '^[0-9a-f]{64}$' || ota_die "SHA256 must be exactly 64 lowercase hex characters"
	printf '%s\n' "$OTA_SIZE" | grep -Eq '^[1-9][0-9]*$' || ota_die "SIZE must be a positive integer"
	[ "$OTA_SIZE" -le 536870912 ] 2>/dev/null || ota_die "SIZE exceeds the 512 MiB safety bound"
	case "$OTA_URL" in
		https://*) ;;
		*) ota_die "URL must use HTTPS" ;;
	esac
	case "$OTA_URL" in *[!A-Za-z0-9._~:/%-]*) ota_die "URL contains unsupported characters" ;; esac
	[ "${OTA_URL##*/}" = "$OTA_IMAGE" ] || ota_die "URL basename does not match IMAGE"
	[ "$OTA_SIGNATURE" = RELEASE-MANIFEST.sig ] || ota_die "SIGNATURE must be RELEASE-MANIFEST.sig"
	case "$OTA_SIGNATURE_URL" in
		https://*) ;;
		*) ota_die "SIGNATURE_URL must use HTTPS" ;;
	esac
	case "$OTA_SIGNATURE_URL" in *[!A-Za-z0-9._~:/%-]*) ota_die "SIGNATURE_URL contains unsupported characters" ;; esac
	[ "${OTA_SIGNATURE_URL##*/}" = "$OTA_SIGNATURE" ] || ota_die "SIGNATURE_URL basename does not match SIGNATURE"
	printf '%s\n' "$OTA_USIGN_KEY_ID" | grep -Eq '^[0-9a-f]{16}$' || ota_die "USIGN_KEY_ID must be exactly 16 lowercase hex characters"
}

ota_fetch() {
	source=$1
	destination=$2
	max_bytes=$3
	printf '%s\n' "$max_bytes" | grep -Eq '^[1-9][0-9]*$' || ota_die "invalid download size bound"
	if [ -e "$destination" ] || [ -L "$destination" ]; then
		ota_die "refusing to overwrite staged path: $destination"
	fi
	case "$source" in
		https://*)
			command -v curl >/dev/null 2>&1 || ota_die "curl is required for HTTPS downloads"
			curl --fail --silent --show-error --location --retry 2 \
				--proto '=https' --proto-redir '=https' --tlsv1.2 \
				--max-filesize "$max_bytes" \
				--output "$destination" "$source" || ota_die "HTTPS download failed: $source"
			;;
		http://*) ota_die "plain HTTP is forbidden: $source" ;;
		*://*) ota_die "unsupported URL scheme: $source" ;;
		*)
			[ -f "$source" ] || ota_die "local file not found: $source"
			local_size=$(wc -c < "$source" | tr -d '[:space:]')
			[ "$local_size" -le "$max_bytes" ] 2>/dev/null || ota_die "local input exceeds the $max_bytes byte download bound: $source"
			cp -p "$source" "$destination" || ota_die "failed to stage local file: $source"
			;;
	esac
}

ota_verify_signature() {
	manifest=$1
	signature=$2
	public_key=$3
	command -v usign >/dev/null 2>&1 || ota_die "usign is required; unsigned OTA is forbidden"
	[ -s "$public_key" ] || ota_die "release public key not found: $public_key"
	[ -s "$signature" ] || ota_die "manifest signature is empty: $signature"
	actual_key_id=$(usign -F -p "$public_key" 2>/dev/null) || ota_die "invalid usign public key"
	[ "$actual_key_id" = "$OTA_USIGN_KEY_ID" ] || ota_die "manifest key id does not match the trusted public key"
	usign -q -V -p "$public_key" -m "$manifest" -x "$signature" || ota_die "manifest usign signature verification failed"
}

ota_verify_image() {
	image=$1
	[ -f "$image" ] || ota_die "image not found: $image"
	actual_size=$(wc -c < "$image" | tr -d '[:space:]')
	[ "$actual_size" = "$OTA_SIZE" ] || ota_die "image size mismatch: expected $OTA_SIZE, got $actual_size"
	actual_sha=$(sha256sum "$image" | awk '{print $1}') || ota_die "sha256sum failed"
	printf '%s\n' "$actual_sha" | grep -Eq '^[0-9a-f]{64}$' || ota_die "sha256sum returned an invalid digest"
	[ "$actual_sha" = "$OTA_SHA256" ] || ota_die "image SHA256 mismatch: expected $OTA_SHA256, got $actual_sha"
}

ota_stage_and_verify() {
	manifest_source=$1
	signature_source=$2
	image_source=$3
	public_key=$4
	work_dir=$5

	if [ ! -d "$work_dir" ] || [ -L "$work_dir" ]; then
		ota_die "staging directory is missing or is a symlink: $work_dir"
	fi
	chmod 0700 "$work_dir" || ota_die "cannot protect staging directory: $work_dir"
	OTA_STAGED_MANIFEST="$work_dir/RELEASE-MANIFEST"
	ota_fetch "$manifest_source" "$OTA_STAGED_MANIFEST" 65536
	ota_validate_manifest "$OTA_STAGED_MANIFEST"

	[ -n "$signature_source" ] || signature_source=$OTA_SIGNATURE_URL
	OTA_STAGED_SIGNATURE="$work_dir/$OTA_SIGNATURE"
	ota_fetch "$signature_source" "$OTA_STAGED_SIGNATURE" 65536
	ota_verify_signature "$OTA_STAGED_MANIFEST" "$OTA_STAGED_SIGNATURE" "$public_key"

	[ -n "$image_source" ] || image_source=$OTA_URL
	OTA_STAGED_IMAGE="$work_dir/$OTA_IMAGE"
	ota_fetch "$image_source" "$OTA_STAGED_IMAGE" "$OTA_SIZE"
	ota_verify_image "$OTA_STAGED_IMAGE"
}
