#!/usr/bin/env python3
"""Offline guards for the pinned direct-only Apple framework integration."""

import inspect
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build_tailscalekit as build
import prepare_pinned_tailscale_source as proof


ROOT = Path(__file__).resolve().parents[2]
TAILSCALE_PATCH = build.PATCHES / "tailscale-v1.94.1-direct-only-data.patch"
LIBTAILSCALE_PATCH = build.PATCHES / "libtailscale-59d4bb-direct-only-data.patch"


class DirectOnlyIntegrationPolicyTest(unittest.TestCase):
    def test_exact_pins_and_isolated_workspaces(self) -> None:
        self.assertEqual(build.PIN["commit"], "59d4bb82744915815178e0f0776d60026a397ee7")
        self.assertEqual(build.TAILSCALE_COMMIT, "d885b34776cd2e96f1f368a4d31729e37ff8b59b")
        self.assertEqual(build.PIN["tailscaleVersion"], "1.94.1")
        self.assertEqual(build.PIN["goVersion"], "1.25.5")
        self.assertEqual(proof.BUILD_ROOT.name, "direct_only_proof")
        self.assertNotIn(proof.SOURCE, build.SOURCE.parents)
        self.assertNotIn(proof.SOURCE, build.TAILSCALE_SOURCE.parents)
        self.assertEqual(build.SOURCE.parent, build.TAILSCALE_SOURCE.parent)

    def test_wrong_or_dirty_revision_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            subprocess.run(["git", "init", "--quiet", str(source)], check=True)
            (source / "file").write_text("clean\n")
            subprocess.run(["git", "add", "file"], cwd=source, check=True)
            subprocess.run(
                ["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--quiet", "-m", "pin"],
                cwd=source, check=True,
            )
            revision = build.query("git", "rev-parse", "HEAD", cwd=source)
            build.verify_clean_checkout(source, revision)
            with self.assertRaises(SystemExit):
                build.verify_clean_checkout(source, "0" * 40)
            (source / "file").write_text("dirty\n")
            with self.assertRaises(SystemExit):
                build.verify_clean_checkout(source, revision)

    def test_patches_are_ordered_and_source_checked(self) -> None:
        calls = []
        with patch.object(build, "execute", side_effect=lambda *a, **k: calls.append((a, k))):
            build.apply_direct_only_patches()
        self.assertEqual(len(calls), 4)
        for index, (source, patch_file) in enumerate(
            ((build.TAILSCALE_SOURCE, TAILSCALE_PATCH), (build.SOURCE, LIBTAILSCALE_PATCH))
        ):
            check, apply = calls[index * 2:index * 2 + 2]
            self.assertEqual(check[0][:4], ("git", "apply", "--check", "--whitespace=error"))
            self.assertEqual(apply[0][:3], ("git", "apply", "--whitespace=error"))
            self.assertEqual(check[0][-1], str(patch_file))
            self.assertEqual(apply[0][-1], str(patch_file))
            self.assertEqual(check[1]["cwd"], source)
            self.assertEqual(apply[1]["cwd"], source)
        main = inspect.getsource(build.main)
        self.assertLess(main.index("checkout_source()"), main.index("apply_direct_only_patches()"))
        self.assertLess(main.index("apply_direct_only_patches()"), main.index("patch_pinned_source()"))
        self.assertLess(main.index("patch_pinned_source()"), main.index("build_workspace_environment()"))

    def test_build_explicitly_selects_patched_local_dependency(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(build, "BUILD_SOURCE", Path(temporary)):
                environment = build.build_workspace_environment()
                work = Path(environment["GOWORK"])
                self.assertEqual(work.parent, Path(temporary))
                self.assertEqual(environment["GOTOOLCHAIN"], "local")
                self.assertIn("use ./libtailscale", work.read_text())
                self.assertIn("replace tailscale.com v1.94.1 => ./tailscale", work.read_text())
        macos_build = inspect.getsource(build.build_macos_framework)
        self.assertIn("**build_env", macos_build)
        self.assertEqual(macos_build.count("environment=environment"), 2)
        self.assertIn("environment=build_env", inspect.getsource(build.main))

    def test_patch_contains_complete_per_node_transport_path(self) -> None:
        transport = TAILSCALE_PATCH.read_text()
        for text in (
            "+\t\tDirectOnlyData: s.DirectOnlyData,",
            "+\t\tDirectOnlyData: conf.DirectOnlyData,",
            "+\tc.directOnlyData = opts.DirectOnlyData",
            "TestDirectOnlyDataOutbound",
            "TestDirectOnlyDataPathLossAndFallback",
            "TestDirectOnlyDataCookieAndInbound",
            "TestDirectOnlyDataDiscoViaDERP",
            "TestDirectOnlyDataIsPerServer",
        ):
            self.assertIn(text, transport)

    def test_bridge_and_swift_contract(self) -> None:
        bridge = LIBTAILSCALE_PATCH.read_text()
        for text in (
            "tailscale_set_direct_only_data(tailscale sd, int enabled)",
            "TsnetSetDirectOnlyData(sd, enabled)",
            "if !s.setDirectOnlyData(enabled != 0)",
            "return C.EBUSY",
            "directOnlyData: Bool = false",
            "TestDirectOnlyDataConfiguration",
            "late direct-only setter did not return EBUSY",
            "new independent node rejected direct-only configuration",
        ):
            self.assertIn(text, bridge)
        swift = bridge.index("tailscale_set_direct_only_data(tailscale, config.directOnlyData ? 1 : 0)")
        self.assertLess(swift, bridge.index("let res = tailscale_start(tailscale)"))
        self.assertIn("guard directOnlyResult == 0 else", bridge)
        for host in ("macos/MainFlutterWindow.swift", "ios/AppDelegate.swift"):
            source = (ROOT / "tool/native_hosts" / host).read_text()
            config = source[source.index("private func configuration("):source.index("func stop() async throws")]
            for text in ("hostName: metadata.nodeHostname", "path: stateStore.nodeStateDirectory.path",
                         "authKey: authKey", "controlURL: metadata.controlUrl", "ephemeral: false",
                         "directOnlyData: true"):
                self.assertIn(text, config)
            self.assertIn("configuration(metadata: metadata, authKey: authKey)", source)
            self.assertIn("configuration(metadata: metadata, authKey: nil)", source)


if __name__ == "__main__":
    unittest.main()
