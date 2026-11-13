"""Tests for check-identity.py: each one builds bundles and entitlements in a scratch folder.

Run from the repository root (-B keeps Python from writing a __pycache__ folder here):

    python3 -B -m unittest discover -s scripts
"""
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "check-identity.py"
GROUP = "group.com.example.Salah"
APP = "com.example.Salah"


class CheckIdentityTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)

    def bundle(self, name, identifier, group=GROUP, mac=False):
        info = self.root / name / ("Contents/Info.plist" if mac else "Info.plist")
        info.parent.mkdir(parents=True)
        values = {"CFBundleIdentifier": identifier}
        if group:
            values["AppGroupIdentifier"] = group
        # Xcode writes a device bundle's Info.plist in the binary format.
        info.write_bytes(plistlib.dumps(values, fmt=plistlib.FMT_BINARY))
        return self.root / name

    def entitlements(self, name, groups):
        path = self.root / name
        path.write_bytes(plistlib.dumps({"com.apple.security.application-groups": groups}))
        return path

    def check(self, *arguments):
        result = subprocess.run(
            [sys.executable, "-B", "-I", str(SCRIPT), GROUP, *map(str, arguments)],
            capture_output=True,
            text=True,
        )
        return result.returncode, result.stdout.strip(), result.stderr.strip()

    def test_bundles_and_entitlements_that_agree_pass(self):
        app = self.bundle("Salah.app", APP, mac=True)
        widgets = self.bundle("Widgets.appex", f"{APP}.iOS.Widgets")
        granted = self.entitlements("App.xcent", [GROUP])
        self.assertEqual(
            self.check(f"{app}={APP}", f"{widgets}={APP}.iOS.Widgets", granted), (0, "", "")
        )

    def test_another_bundle_identifier_fails(self):
        app = self.bundle("Salah.app", "io.github.salah-kit.Salah")
        self.assertEqual(
            self.check(f"{app}={APP}"), (1, "", f"{app} is io.github.salah-kit.Salah, not {APP}.")
        )

    def test_a_bundle_that_names_another_group_or_none_fails(self):
        other = self.bundle("Other.app", APP, group="group.io.github.salah-kit.Salah.shared")
        none = self.bundle("None.app", APP, group=None)
        self.assertEqual(
            self.check(f"{other}={APP}", f"{none}={APP}"),
            (
                1,
                "",
                f"{other} names the App Group group.io.github.salah-kit.Salah.shared, not {GROUP}.\n"
                f"{none} names the App Group None, not {GROUP}.",
            ),
        )

    def test_entitlements_without_the_group_fail(self):
        missing = self.entitlements("Missing.xcent", ["group.com.example.Other"])
        self.assertEqual(
            self.check(missing), (1, "", f"{missing} doesn't grant the App Group {GROUP}.")
        )

    def test_a_missing_bundle_is_an_error(self):
        code, output, error = self.check(f"{self.root / 'Gone.app'}={APP}")
        self.assertEqual((code, output), (1, ""))
        self.assertIn("Gone.app", error)


if __name__ == "__main__":
    unittest.main()
