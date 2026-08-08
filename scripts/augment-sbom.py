#!/usr/bin/env python3
"""Reconcile OpenWrt CycloneDX with the exact resolved package inventory."""

import argparse
import json
import re
from pathlib import Path
from typing import Optional


PACKAGE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+_.@-]*$")
ABI_SUFFIX = re.compile(r"-?[0-9]+(?:\.[0-9]+)*$")
APK_REVISION = re.compile(r"-r[0-9]+$")


def parse_components(path: Path):
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [part.strip() for part in line.split("|")]
        if len(parts) != 5 or not all(parts):
            raise SystemExit(f"invalid custom component line: {raw}")
        name, version, license_id, install_method, source_path = parts
        yield {
            "type": "application",
            "name": name,
            "version": version,
            "bom-ref": f"pkg:generic/{name}@{version}",
            "licenses": [{"license": {"id": license_id}}],
            "properties": [
                {"name": "companywrt:install-method", "value": install_method},
                {"name": "companywrt:source-path", "value": source_path},
                {"name": "companywrt:packaging-claim", "value": "overlay-not-apk"},
            ],
        }


def parse_package_manifest(path: Path, expected_count: Optional[int]) -> dict[str, str]:
    packages: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        if " - " not in raw:
            raise SystemExit(f"invalid PACKAGE-MANIFEST line: {raw}")
        name, version = raw.split(" - ", 1)
        if not PACKAGE_NAME.fullmatch(name) or not version or any(character.isspace() for character in version):
            raise SystemExit(f"invalid PACKAGE-MANIFEST package/version: {raw}")
        if name in packages:
            raise SystemExit(f"duplicate PACKAGE-MANIFEST package: {name}")
        packages[name] = version
    if expected_count is not None and len(packages) != expected_count:
        raise SystemExit(
            f"PACKAGE-MANIFEST contains {len(packages)} unique packages; expected {expected_count}"
        )
    return packages


def component_property(component: dict, name: str, value: str) -> None:
    properties = component.setdefault("properties", [])
    if not isinstance(properties, list):
        raise SystemExit(f"SBOM component has invalid properties: {component.get('name')}")
    if any(item.get("name") == name for item in properties if isinstance(item, dict)):
        raise SystemExit(f"SBOM component property already exists: {component.get('name')} {name}")
    properties.append({"name": name, "value": value})
    properties.sort(key=lambda item: (item.get("name", ""), item.get("value", "")))


def reconcile_packages(document: dict, packages: dict[str, str]) -> None:
    components = document["components"]
    by_name: dict[str, list[dict]] = {}
    for component in components:
        if not isinstance(component, dict) or not isinstance(component.get("name"), str):
            raise SystemExit("OpenWrt SBOM contains an invalid component")
        by_name.setdefault(component["name"], []).append(component)

    claimed_components: set[int] = set()
    for package_name, package_version in sorted(packages.items()):
        source_name = package_name
        candidates = [candidate for candidate in by_name.get(source_name, []) if id(candidate) not in claimed_components]
        if not candidates:
            source_name = ABI_SUFFIX.sub("", package_name)
            candidates = [candidate for candidate in by_name.get(source_name, []) if id(candidate) not in claimed_components]
        if len(candidates) > 1:
            raise SystemExit(
                f"PACKAGE-MANIFEST package {package_name} maps ambiguously to SBOM component {source_name}"
            )
        if candidates:
            component = candidates[0]
        else:
            # OpenWrt 25.12.5 may omit the libnghttp2 source component even
            # though libnghttp2-14 is in the resolved APK manifest. Synthesize
            # an honest inventory record and make no unverified license claim.
            component = {
                "type": "library" if package_name.startswith("lib") else "application",
                "name": source_name or package_name,
                "version": APK_REVISION.sub("", package_version),
                "licenses": [{"license": {"name": "NOASSERTION"}}],
            }
            component_property(component, "companywrt:component-origin", "synthesized-from-PACKAGE-MANIFEST")
            component_property(component, "companywrt:license-claim", "NOASSERTION")
            components.append(component)
            by_name.setdefault(component["name"], []).append(component)
        claimed_components.add(id(component))
        component_property(component, "companywrt:package-manifest-name", package_name)
        component_property(component, "companywrt:package-manifest-version", package_version)

    coverage: dict[str, int] = {}
    for component in components:
        for item in component.get("properties", []):
            if item.get("name") == "companywrt:package-manifest-name":
                package_name = item.get("value")
                coverage[package_name] = coverage.get(package_name, 0) + 1
    missing = sorted(set(packages) - set(coverage))
    extra = sorted(set(coverage) - set(packages))
    duplicates = sorted(name for name, count in coverage.items() if count != 1)
    if missing or extra or duplicates:
        raise SystemExit(
            f"SBOM/PACKAGE-MANIFEST one-to-one coverage failed: "
            f"missing={missing} extra={extra} duplicates={duplicates}"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sbom", required=True, type=Path)
    parser.add_argument("--components", required=True, type=Path)
    parser.add_argument("--package-manifest", required=True, type=Path)
    parser.add_argument("--expected-package-count", type=int)
    args = parser.parse_args()

    document = json.loads(args.sbom.read_text(encoding="utf-8"))
    if document.get("bomFormat") != "CycloneDX" or not isinstance(document.get("components"), list):
        raise SystemExit("OpenWrt SBOM is not a supported CycloneDX document")

    packages = parse_package_manifest(args.package_manifest, args.expected_package_count)
    reconcile_packages(document, packages)

    incoming = list(parse_components(args.components))
    existing = {component.get("name") for component in document["components"]}
    duplicate = existing.intersection(component["name"] for component in incoming)
    if duplicate:
        raise SystemExit(f"custom component already exists in SBOM: {sorted(duplicate)}")
    document["components"].extend(incoming)
    document["components"].sort(key=lambda component: (component.get("name", ""), component.get("version", "")))

    metadata = document.setdefault("metadata", {})
    properties = metadata.setdefault("properties", [])
    properties.extend(
        [
            {
                "name": "companywrt:package-manifest-coverage",
                "value": f"COMPLETE_ONE_TO_ONE:{len(packages)}",
            },
            {
                "name": "companywrt:license-coverage",
                "value": "BEST_EFFORT_UPSTREAM_METADATA_WITH_NOASSERTION_FALLBACK",
            },
        ]
    )
    properties.sort(key=lambda item: (item.get("name", ""), item.get("value", "")))

    args.sbom.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
