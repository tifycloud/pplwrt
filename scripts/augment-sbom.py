#!/usr/bin/env python3
"""Add explicitly overlaid CompanyWrt components to ImageBuilder CycloneDX."""

import argparse
import json
from pathlib import Path


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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sbom", required=True, type=Path)
    parser.add_argument("--components", required=True, type=Path)
    args = parser.parse_args()

    document = json.loads(args.sbom.read_text(encoding="utf-8"))
    if document.get("bomFormat") != "CycloneDX" or not isinstance(document.get("components"), list):
        raise SystemExit("ImageBuilder SBOM is not a supported CycloneDX document")

    incoming = list(parse_components(args.components))
    existing = {component.get("name") for component in document["components"]}
    duplicate = existing.intersection(component["name"] for component in incoming)
    if duplicate:
        raise SystemExit(f"custom component already exists in SBOM: {sorted(duplicate)}")
    document["components"].extend(incoming)
    document["components"].sort(key=lambda component: (component.get("name", ""), component.get("version", "")))

    args.sbom.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
