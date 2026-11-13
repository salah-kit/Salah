#!/usr/bin/env python3
"""Check that built bundles carry the identifiers and the App Group they were built with.

usage: check-identity.py <App Group> (<bundle>=<bundle identifier> | <entitlements>)...

A bundle's Info.plist must hold that bundle identifier, and name the App Group in the key
the shared code reads. An entitlements file must grant the App Group.
"""

import plistlib
import sys
from pathlib import Path

GROUPS = "com.apple.security.application-groups"


def load(path):
    with open(path, "rb") as source:
        return plistlib.load(source)


def info_plist(bundle):
    # A Mac bundle keeps its Info.plist in Contents; the other platforms' at the top.
    nested = bundle / "Contents" / "Info.plist"
    return nested if nested.exists() else bundle / "Info.plist"


def problems(group, arguments):
    for argument in arguments:
        bundle, separator, identifier = argument.rpartition("=")
        if not separator:
            if group not in load(argument).get(GROUPS, []):
                yield f"{argument} doesn't grant the App Group {group}."
            continue
        info = load(info_plist(Path(bundle)))
        if info.get("CFBundleIdentifier") != identifier:
            yield f"{bundle} is {info.get('CFBundleIdentifier')}, not {identifier}."
        if info.get("AppGroupIdentifier") != group:
            yield f"{bundle} names the App Group {info.get('AppGroupIdentifier')}, not {group}."


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__.strip())
    try:
        found = list(problems(sys.argv[1], sys.argv[2:]))
    except (OSError, plistlib.InvalidFileException) as error:
        sys.exit(str(error))
    if found:
        sys.exit("\n".join(found))
