"""Tests for select-watchos-simulator.py: each one feeds it a simctl inventory and checks its
pick.

Run from the repository root (-B keeps Python from writing a __pycache__ folder here):

    python3 -B -m unittest discover -s scripts
"""
import json
import subprocess
import sys
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "select-watchos-simulator.py"
MISSING = "Install a watchOS 26 or later simulator runtime."


def runtime(version, platform="watchOS", available=True, supported=()):
    return {
        "identifier": f"com.apple.CoreSimulator.SimRuntime.{platform}-{version.replace('.', '-')}",
        "version": version,
        "platform": platform,
        "isAvailable": available,
        "supportedDeviceTypes": [{"identifier": item["identifier"]} for item in supported],
    }


def device_type(name, slug, family="Apple Watch", minimum="11.0.0", maximum="65535.255.255"):
    return {
        "name": name,
        "identifier": f"com.apple.CoreSimulator.SimDeviceType.{slug}",
        "productFamily": family,
        "minRuntimeVersionString": minimum,
        "maxRuntimeVersionString": maximum,
    }


SERIES_12 = device_type("Apple Watch Series 12 (46mm)", "Apple-Watch-Series-12-46mm")
SERIES_11 = device_type("Apple Watch Series 11 (46mm)", "Apple-Watch-Series-11-46mm")
SMALL = device_type("Apple Watch SE 3 (40mm)", "Apple-Watch-SE-3-40mm")
OLD = device_type("Apple Watch Series 7 (45mm)", "Apple-Watch-Series-7-45mm", maximum="26.99.0")
IPHONE = device_type("iPhone 17 Pro", "iPhone-17-Pro", family="iPhone", minimum="26.0.0")


class SelectWatchOSSimulatorTests(unittest.TestCase):
    def select(self, runtimes, device_types):
        result = subprocess.run(
            [sys.executable, "-B", "-I", str(SCRIPT)],
            input=json.dumps({"runtimes": runtimes, "devicetypes": device_types}),
            capture_output=True,
            text=True,
        )
        return result.returncode, result.stdout.strip(), result.stderr.strip()

    def assert_picks(self, runtimes, device_types, picked_runtime, picked_type):
        self.assertEqual(
            self.select(runtimes, device_types),
            (0, f"{picked_runtime['identifier']}\t{picked_type['identifier']}", ""),
        )

    def test_the_newest_runtime_and_the_46mm_series_12(self):
        newest = runtime("27.0")
        self.assert_picks(
            [runtime("26.0"), newest], [SMALL, IPHONE, SERIES_11, SERIES_12], newest, SERIES_12
        )

    def test_the_series_11_when_the_series_12_is_missing(self):
        newest = runtime("27.0")
        self.assert_picks([newest], [SMALL, SERIES_11], newest, SERIES_11)

    def test_another_watch_when_neither_46mm_type_is_there(self):
        newest = runtime("27.0")
        self.assert_picks([newest], [IPHONE, SMALL], newest, SMALL)

    def test_a_type_the_runtime_doesnt_list_is_skipped(self):
        newest = runtime("27.0", supported=[SMALL])
        self.assert_picks([newest], [SERIES_12, SMALL], newest, SMALL)

    def test_a_type_past_its_last_runtime_falls_back_to_an_older_runtime(self):
        older = runtime("26.0")
        self.assert_picks([older, runtime("27.0")], [OLD], older, OLD)

    def test_unavailable_old_and_ios_runtimes_are_missing(self):
        runtimes = [runtime("27.0", available=False), runtime("11.0"), runtime("27.0", "iOS")]
        self.assertEqual(self.select(runtimes, [SERIES_12, IPHONE]), (1, "", MISSING))


if __name__ == "__main__":
    unittest.main()
