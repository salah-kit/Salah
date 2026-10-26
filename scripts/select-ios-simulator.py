#!/usr/bin/env python3
"""Select an installed iOS runtime and compatible iPhone, iPad or iPhone Duo type."""

import json
import sys

# Each family's journeys are written for its preferred device. iPhone Duo has its own
# displays, bars and journeys, so an iPhone run never falls back to it.
PREFERRED = {"iPhone": "iPhone 17 Pro", "iPad": "iPad Pro 11-inch (M4)", "Duo": "iPhone Duo"}
PRODUCT_FAMILY = {"iPhone": "iPhone", "iPad": "iPad", "Duo": "iPhone"}


def version(value):
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def runs_on(item, runtime):
    supported = {entry["identifier"] for entry in runtime.get("supportedDeviceTypes", [])}
    return (
        (not supported or item["identifier"] in supported)
        and version(item["minRuntimeVersionString"]) <= version(runtime["version"])
        and version(runtime["version"]) <= version(item["maxRuntimeVersionString"])
    )


def select_simulator(inventory, family):
    if family not in PREFERRED:
        raise ValueError("The simulator family must be iPhone, iPad or Duo.")
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
    devices = [
        item
        for item in inventory["devicetypes"]
        if item.get("productFamily") == PRODUCT_FAMILY[family]
        and (family == "Duo") == (item["name"] == PREFERRED["Duo"])
    ]
    # A newer runtime can exist for one device alone, as iOS 27.1 does for iPhone Duo, so
    # the preferred device on any runtime wins over another device on the newest one.
    for runtime in runtimes:
        for item in devices:
            if item["name"] == PREFERRED[family] and runs_on(item, runtime):
                return runtime["identifier"], item["identifier"]
    for runtime in runtimes:
        for item in devices:
            if runs_on(item, runtime):
                return runtime["identifier"], item["identifier"]
    if family == "Duo":
        raise ValueError("Install the iOS 27.1 or later simulator runtime for iPhone Duo.")
    raise ValueError(f"Install an iOS 26 or later simulator runtime for {family}.")


if __name__ == "__main__":
    try:
        selected = select_simulator(json.load(sys.stdin), sys.argv[1])
        print("\t".join(selected))
    except (ValueError, KeyError, IndexError) as error:
        sys.exit(str(error))
