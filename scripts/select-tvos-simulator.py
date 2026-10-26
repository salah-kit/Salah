#!/usr/bin/env python3
"""Select an installed tvOS runtime and a compatible Apple TV type."""

import json
import sys

# The journeys measure the 1920 x 1080 point screen every Apple TV has; the 1080p type
# renders it at 1x, which keeps screenshots small.
PREFERRED = "Apple TV 4K (3rd generation) (at 1080p)"


def version(value):
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def select_simulator(inventory):
    runtimes = sorted(
        (
            item
            for item in inventory["runtimes"]
            if item.get("isAvailable")
            and item.get("platform") == "tvOS"
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
            if item.get("productFamily") == "Apple TV"
            and (not supported or item["identifier"] in supported)
            and version(item["minRuntimeVersionString"]) <= version(runtime["version"])
            and version(runtime["version"]) <= version(item["maxRuntimeVersionString"])
        ]
        if candidates:
            device = next(
                (item for item in candidates if item["name"] == PREFERRED), candidates[0]
            )
            return runtime["identifier"], device["identifier"]
    raise ValueError("Install a tvOS 26 or later simulator runtime.")


if __name__ == "__main__":
    try:
        print("\t".join(select_simulator(json.load(sys.stdin))))
    except (ValueError, KeyError, IndexError) as error:
        sys.exit(str(error))
