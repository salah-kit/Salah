#!/usr/bin/env python3
"""Check that built bundles carry the identifiers and the App Group they were built with.

usage: check-identity.py <App Group> (<bundle>=<bundle identifier> | <entitlements>)...

A bundle's Info.plist must hold that bundle identifier, and name the App Group in the key
the shared code reads. An entitlements file must grant the App Group.
"""

import plistlib
import sys
from pathlib import Path
from xml.parsers.expat import ExpatError

GROUPS = "com.apple.security.application-groups"


def load(path):
    try:
        with open(path, "rb") as source:
            content = plistlib.load(source)
    except (ValueError, ExpatError) as error:
        sys.exit(f"{path} isn't a property list: {error}")
    if not isinstance(content, dict):
        sys.exit(f"{path} isn't a property list dictionary.")
    return content


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
        built = info.get("CFBundleIdentifier")
        if built != identifier:
            yield f"{bundle} is {built}, not {identifier}." if built else (
                f"{bundle} has no bundle identifier, not {identifier}."
            )
        named = info.get("AppGroupIdentifier")
        if named != group:
            yield f"{bundle} names the App Group {named}, not {group}." if named else (
                f"{bundle} names no App Group, not {group}."
            )


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__.strip())
    try:
        found = list(problems(sys.argv[1], sys.argv[2:]))
    except OSError as error:
        sys.exit(str(error))
    if found:
        sys.exit("\n".join(found))
