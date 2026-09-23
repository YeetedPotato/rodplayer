#!/usr/bin/env python3
"""Policy tests for the generated macOS networking entitlements."""

import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "apply_native_hosts", ROOT / "tool" / "apply_native_hosts.py"
)
assert SPEC is not None and SPEC.loader is not None
APPLY_NATIVE_HOSTS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(APPLY_NATIVE_HOSTS)


class MacosEntitlementsPolicyTest(unittest.TestCase):
    def test_network_entitlements_preserve_existing_values_and_are_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runner = Path(temporary) / "macos" / "Runner"
            runner.mkdir(parents=True)
            initial = {
                "com.apple.security.app-sandbox": True,
                "com.apple.security.get-task-allow": True,
                "com.example.existing": "preserved",
            }
            for name in ("DebugProfile.entitlements", "Release.entitlements"):
                with (runner / name).open("wb") as handle:
                    plistlib.dump(initial, handle)

            APPLY_NATIVE_HOSTS.patch_macos_entitlements(Path(temporary))
            first = []
            for name in ("DebugProfile.entitlements", "Release.entitlements"):
                with (runner / name).open("rb") as handle:
                    values = plistlib.load(handle)
                self.assertEqual(values["com.example.existing"], "preserved")
                self.assertTrue(values["com.apple.security.app-sandbox"])
                self.assertTrue(values["com.apple.security.get-task-allow"])
                self.assertTrue(values["com.apple.security.network.client"])
                self.assertTrue(values["com.apple.security.network.server"])
                first.append(values)

            APPLY_NATIVE_HOSTS.patch_macos_entitlements(Path(temporary))
            for name, expected in zip(("DebugProfile.entitlements", "Release.entitlements"), first):
                with (runner / name).open("rb") as handle:
                    self.assertEqual(plistlib.load(handle), expected)


if __name__ == "__main__":
    unittest.main()
