#!/usr/bin/env python3
"""Select an installed watchOS runtime and a compatible Apple Watch type."""

import json
import sys

# The journeys measure a 46 mm watch, the size the design draws. Its default text size is
# xLarge, a step past the 40 to 42 mm watches' Large.
PREFERRED = ("Apple Watch Series 12 (46mm)", "Apple Watch Series 11 (46mm)")


def version(value):
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def select_simulator(inventory):
    runtimes = sorted(
        (
            item
            for item in inventory["runtimes"]
            if item.get("isAvailable")
            and item.get("platform") == "watchOS"
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
            if item.get("productFamily") == "Apple Watch"
            and (not supported or item["identifier"] in supported)
            and version(item["minRuntimeVersionString"]) <= version(runtime["version"])
            and version(runtime["version"]) <= version(item["maxRuntimeVersionString"])
        ]
        if candidates:
            device = next(
                (
                    item
                    for name in PREFERRED
                    for item in candidates
                    if item["name"] == name
                ),
                candidates[0],
            )
            return runtime["identifier"], device["identifier"]
    raise ValueError("Install a watchOS 26 or later simulator runtime.")


if __name__ == "__main__":
    try:
        print("\t".join(select_simulator(json.load(sys.stdin))))
    except (ValueError, KeyError, IndexError) as error:
        sys.exit(str(error))
