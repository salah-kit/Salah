#!/usr/bin/env python3
"""Select an installed iOS runtime and compatible iPhone or iPad type."""

import json
import sys


def version(value):
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def select_simulator(inventory, family):
    if family not in ("iPhone", "iPad"):
        raise ValueError("The simulator family must be iPhone or iPad.")
    runtimes = sorted(
        (
            item
            for item in inventory["runtimes"]
            if item.get("isAvailable")
            and item.get("platform") == "iOS"
            and version(item["version"]) >= (26, 0)
        ),
        key=lambda item: version(item["version"]),
        reverse=True,
    )
    for runtime in runtimes:
        supported = {
            item["identifier"] for item in runtime.get("supportedDeviceTypes", [])
        }
        candidates = [
            item
            for item in inventory["devicetypes"]
            if item.get("productFamily") == family
            and (not supported or item["identifier"] in supported)
            and version(item["minRuntimeVersionString"]) <= version(runtime["version"])
            and version(runtime["version"]) <= version(item["maxRuntimeVersionString"])
        ]
        if candidates:
            preferred = (
                "iPhone 17 Pro" if family == "iPhone" else "iPad Pro 11-inch (M4)"
            )
            device = next(
                (item for item in candidates if item["name"] == preferred), candidates[0]
            )
            return runtime["identifier"], device["identifier"]
    raise ValueError(f"Install an iOS 26 or later simulator runtime for {family}.")


if __name__ == "__main__":
    try:
        selected = select_simulator(json.load(sys.stdin), sys.argv[1])
        print("\t".join(selected))
    except (ValueError, KeyError, IndexError) as error:
        sys.exit(str(error))
