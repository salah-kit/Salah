"""Tests for select-tvos-simulator.py: each one feeds it a simctl inventory and checks its pick.

Run from the repository root (-B keeps Python from writing a __pycache__ folder here):

    python3 -B -m unittest discover -s scripts
"""
import json
import subprocess
import sys
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "select-tvos-simulator.py"
MISSING = "Install a tvOS 26 or later simulator runtime."


def runtime(version, platform="tvOS", available=True, supported=()):
    return {
        "identifier": f"com.apple.CoreSimulator.SimRuntime.{platform}-{version.replace('.', '-')}",
        "version": version,
        "platform": platform,
        "isAvailable": available,
        "supportedDeviceTypes": [{"identifier": item["identifier"]} for item in supported],
    }


def device_type(name, slug, family="Apple TV", minimum="16.1.0", maximum="65535.255.255"):
    return {
        "name": name,
        "identifier": f"com.apple.CoreSimulator.SimDeviceType.{slug}",
        "productFamily": family,
        "minRuntimeVersionString": minimum,
        "maxRuntimeVersionString": maximum,
    }


TV_1080P = device_type(
    "Apple TV 4K (3rd generation) (at 1080p)", "Apple-TV-4K-3rd-generation-1080p"
)
TV_4K = device_type("Apple TV 4K (3rd generation)", "Apple-TV-4K-3rd-generation-4K")
OLD_TV = device_type("Apple TV", "Apple-TV-1080p", minimum="9.0.0", maximum="26.99.0")
IPHONE = device_type("iPhone 17 Pro", "iPhone-17-Pro", family="iPhone", minimum="26.0.0")


class SelectTVOSSimulatorTests(unittest.TestCase):
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

    def test_the_newest_runtime_and_the_1080p_apple_tv(self):
        newest = runtime("27.0")
        self.assert_picks([runtime("26.0"), newest], [TV_4K, IPHONE, TV_1080P], newest, TV_1080P)

    def test_another_apple_tv_when_the_1080p_type_is_missing(self):
        newest = runtime("27.0")
        self.assert_picks([newest], [IPHONE, TV_4K], newest, TV_4K)

    def test_a_type_the_runtime_doesnt_list_is_skipped(self):
        newest = runtime("27.0", supported=[TV_4K])
        self.assert_picks([newest], [TV_1080P, TV_4K], newest, TV_4K)

    def test_a_type_past_its_last_runtime_falls_back_to_an_older_runtime(self):
        older = runtime("26.0")
        self.assert_picks([older, runtime("27.0")], [OLD_TV], older, OLD_TV)

    def test_unavailable_old_and_ios_runtimes_are_missing(self):
        runtimes = [runtime("27.0", available=False), runtime("18.0"), runtime("27.0", "iOS")]
        self.assertEqual(self.select(runtimes, [TV_1080P, IPHONE]), (1, "", MISSING))


if __name__ == "__main__":
    unittest.main()
