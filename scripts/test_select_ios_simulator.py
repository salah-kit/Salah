"""Tests for select-ios-simulator.py against the runtimes Xcode 27.1 installs.

Run from the repository root (-B keeps Python from writing a __pycache__ folder here):

    python3 -B -m unittest discover -s scripts
"""
import json
import subprocess
import sys
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "select-ios-simulator.py"


def device(name, family, minimum="26.0.0"):
    return {
        "name": name,
        "identifier": "com.apple.CoreSimulator.SimDeviceType." + name.replace(" ", "-"),
        "productFamily": family,
        "minRuntimeVersionString": minimum,
        "maxRuntimeVersionString": "65535.255.255",
    }


def runtime(version, *devices):
    return {
        "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-" + version.replace(".", "-"),
        "version": version,
        "platform": "iOS",
        "isAvailable": True,
        "supportedDeviceTypes": devices,
    }


IPHONE = device("iPhone 17 Pro", "iPhone")
OTHER_IPHONE = device("iPhone 18 Pro", "iPhone")
IPAD = device("iPad Pro 11-inch (M4)", "iPad", "17.4.0")
DUO = device("iPhone Duo", "iPhone", "27.1.0")
IOS_27_0 = runtime("27.0", OTHER_IPHONE, IPHONE, IPAD)
IOS_27_1 = runtime("27.1", DUO)

# iOS 27.1 is newer than 27.0 but runs iPhone Duo alone.
HOSTED = {"runtimes": [IOS_27_0, IOS_27_1], "devicetypes": [DUO, OTHER_IPHONE, IPHONE, IPAD]}


class SelectSimulatorTests(unittest.TestCase):
    def select(self, inventory, family):
        result = subprocess.run(
            [sys.executable, "-B", "-I", str(SCRIPT), family],
            input=json.dumps(inventory), capture_output=True, text=True)
        return result.returncode, result.stdout.strip(), result.stderr.strip()

    def assertSelects(self, inventory, family, runtime, device):
        self.assertEqual(
            self.select(inventory, family),
            (0, f"{runtime['identifier']}\t{device['identifier']}", ""))

    def test_iphone_skips_a_newer_runtime_that_only_runs_iphone_duo(self):
        self.assertSelects(HOSTED, "iPhone", IOS_27_0, IPHONE)

    def test_ipad_selects_its_preferred_device(self):
        self.assertSelects(HOSTED, "iPad", IOS_27_0, IPAD)

    def test_duo_selects_iphone_duo_on_its_runtime(self):
        self.assertSelects(HOSTED, "Duo", IOS_27_1, DUO)

    def test_iphone_falls_back_to_another_iphone_but_never_to_iphone_duo(self):
        inventory = {
            "runtimes": [runtime("27.0", OTHER_IPHONE), IOS_27_1],
            "devicetypes": [DUO, OTHER_IPHONE],
        }
        self.assertSelects(inventory, "iPhone", inventory["runtimes"][0], OTHER_IPHONE)

    def test_duo_asks_for_its_runtime_instead_of_another_iphone(self):
        code, output, error = self.select({"runtimes": [IOS_27_0], "devicetypes": [DUO, IPHONE]}, "Duo")
        self.assertNotEqual(code, 0)
        self.assertEqual(output, "")
        self.assertIn("iPhone Duo", error)


if __name__ == "__main__":
    unittest.main()
