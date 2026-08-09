#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-sbom-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

cat > "$TMP/sbom.json" <<'EOF'
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.6",
  "version": 1,
  "metadata": {},
  "components": [
    {"type": "application", "name": "base-files", "version": "1"},
    {"type": "library", "name": "libfoo", "version": "2"}
  ]
}
EOF
cat > "$TMP/PACKAGE-MANIFEST" <<'EOF'
base-files - 1-r1
libfoo1 - 2-r3
libnghttp2-14 - 1.66.0-r1
EOF
cat > "$TMP/CUSTOM-COMPONENTS.manifest" <<'EOF'
company-test-overlay | 25.12.5-company.2-rc2 | MIT | overlay | tests/fixture
company-test-apk-patch | 0.3-company.1-r1 | GPL-3.0-only | Source patch compiled into luci-theme-liquid APK | tests/theme
EOF

python3 "$ROOT/scripts/augment-sbom.py" \
	--sbom "$TMP/sbom.json" \
	--components "$TMP/CUSTOM-COMPONENTS.manifest" \
	--package-manifest "$TMP/PACKAGE-MANIFEST" \
	--expected-package-count 3

jq -r '.components[].properties[]? | select(.name == "companywrt:package-manifest-name") | .value' \
	"$TMP/sbom.json" | LC_ALL=C sort > "$TMP/covered"
cut -d' ' -f1 "$TMP/PACKAGE-MANIFEST" | LC_ALL=C sort > "$TMP/expected"
cmp "$TMP/expected" "$TMP/covered"
[ "$(jq -r '[.components[].properties[]? | select(.name == "companywrt:package-manifest-name") | .value] | length' "$TMP/sbom.json")" -eq 3 ]
jq -e '.components[] | select(.name == "libnghttp2") |
  any(.properties[]; .name == "companywrt:package-manifest-name" and .value == "libnghttp2-14") and
  any(.licenses[]; .license.name == "NOASSERTION")' "$TMP/sbom.json" >/dev/null
jq -e '.metadata.properties[] | select(.name == "companywrt:package-manifest-coverage" and .value == "COMPLETE_ONE_TO_ONE:3")' \
	"$TMP/sbom.json" >/dev/null
jq -e '.components[] | select(.name == "company-test-overlay")' "$TMP/sbom.json" >/dev/null
jq -e '.components[] | select(.name == "company-test-apk-patch") |
  any(.properties[]; .name == "companywrt:packaging-claim" and .value == "source-patch-compiled-into-apk")' \
	"$TMP/sbom.json" >/dev/null

if python3 "$ROOT/scripts/augment-sbom.py" \
	--sbom "$TMP/sbom.json" \
	--components "$TMP/CUSTOM-COMPONENTS.manifest" \
	--package-manifest "$TMP/PACKAGE-MANIFEST" \
	--expected-package-count 251 > "$TMP/count.out" 2> "$TMP/count.err"; then
	echo 'SBOM reconciliation unexpectedly accepted the wrong package count' >&2
	exit 1
fi
grep -q 'expected 251' "$TMP/count.err"

echo 'CycloneDX exact package coverage, libnghttp2 fallback and NOASSERTION honesty: ok'
