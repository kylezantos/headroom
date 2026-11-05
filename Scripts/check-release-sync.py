#!/usr/bin/env python3
"""Read-only cross-repository release gate, run before the website PR and after promotion."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET


def check(source, site):
    latest = json.loads((site / "public/latest.json").read_text())
    version, build = str(latest["version"]), str(latest["build"])
    project = (source / "project.yml").read_text()
    # A macOS-only release (1.5.2, 1.6.1) leaves the iOS marketing version alone while every
    # target shares the build number, so only the macOS targets must match the website's version.
    targets = re.split(r"^  (?=\w+:\s*$)", project, flags=re.M)
    mac = [block for block in targets if re.search(r"^\s+platform:\s*macOS\s*$", block, re.M)]
    versions = re.findall(r'MARKETING_VERSION:\s*["\']?([\d.]+)', "".join(mac) or project)
    builds = re.findall(r'CURRENT_PROJECT_VERSION:\s*["\']?(\d+)', project)
    if not versions or set(versions) != {version} or not builds or set(builds) != {build}:
        raise ValueError("App versions and website latest.json disagree")
    note = f"Headroom-{version}-{build}.html"
    if (source / "docs/release/sparkle" / note).read_bytes() != (site / "public" / note).read_bytes():
        raise ValueError("Website notes differ from canonical Sparkle notes")
    ns = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    item = ET.parse(site / "public/appcast.xml").find("./channel/item")
    if item is None or item.findtext(ns + "version") != build or item.findtext(ns + "shortVersionString") != version:
        raise ValueError("Latest appcast item disagrees with latest.json")
    if item.findtext(ns + "releaseNotesLink") != f"https://headroom.zantos.co/{note}":
        raise ValueError("Latest appcast notes link disagrees with canonical notes")
    providers = set(re.findall(r'public static let \w+ = ProviderID\("(\w+)"\)', (source / "Sources/HeadroomCore/Models/ProviderID.swift").read_text()))
    demo = (site / "lib/headroom-demo/usage-model.ts").read_text()
    order = re.search(r'export const PROVIDER_ORDER[^=]*=\s*\[([^]]+)\]', demo)
    shown = set(re.findall(r'"(\w+)"', order[1])) if order else set()
    if not providers or shown != providers:
        raise ValueError(f"Website demo provider drift: app={sorted(providers)}, website={sorted(shown)}")
    metadata = (site / "lib/site-metadata.ts").read_text()
    description = re.search(r'export const SITE_DESCRIPTION = "([^"]+)"', metadata)
    if not description or any(provider.casefold() not in description[1].casefold() for provider in providers):
        raise ValueError("Website description omits a supported provider")
    print(f"PASS: {version} ({build}), canonical notes, latest appcast, {len(providers)} demo/metadata providers")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site", type=Path, required=True)
    args = parser.parse_args()
    check(Path(__file__).resolve().parents[1], args.site)
