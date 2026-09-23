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
import run_direct_only_go_proof as go_proof


ROOT = Path(__file__).resolve().parents[2]
TAILSCALE_PATCH = build.PATCHES / "tailscale-v1.94.1-direct-only-data.patch"
LIBTAILSCALE_PATCH = build.PATCHES / "libtailscale-59d4bb-direct-only-data.patch"


class DirectOnlyIntegrationPolicyTest(unittest.TestCase):
    def _shallow_proof_base(self, root: Path) -> tuple[Path, Path, Path, str]:
        seed = root / "seed"
        subprocess.run(["git", "init", "--quiet", str(seed)], check=True)
        (seed / "pin.txt").write_text("pinned\n")
        subprocess.run(["git", "add", "pin.txt"], cwd=seed, check=True)
        subprocess.run(
            ["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
             "commit", "--quiet", "-m", "pin"], cwd=seed, check=True,
        )
        revision = build.query("git", "rev-parse", "HEAD", cwd=seed)
        proof_root = root / "direct_only_proof"
        source = proof_root / "source"
        source.mkdir(parents=True)
        base = source / "tailscale"
        subprocess.run(["git", "clone", "--quiet", "--depth", "1", seed.as_uri(), str(base)], check=True)
        self.assertEqual(build.query("git", "rev-parse", "--is-shallow-repository", cwd=base), "true")
        return proof_root, source, base, revision

    def test_proof_worktree_repeats_from_shallow_pin_and_cleans_on_failure(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            proof_root, source, base, revision = self._shallow_proof_base(Path(temporary))
            with (patch.object(go_proof, "BUILD_ROOT", proof_root),
                  patch.object(go_proof, "SOURCE", source),
                  patch.object(go_proof, "TAILSCALE_COMMIT", revision)):
                for _ in range(2):
                    with go_proof.disposable_proof_worktree(base) as checkout:
                        self.assertEqual(build.query("git", "rev-parse", "HEAD", cwd=checkout), revision)
                        self.assertTrue(checkout.resolve().is_relative_to(proof_root.resolve()))
                        self.assertEqual((checkout / "pin.txt").read_text(), "pinned\n")
                        (checkout / "pin.txt").write_text("patched\n")
                        (checkout / "generated.txt").write_text("build output\n")
                    self.assertFalse(checkout.exists())
                    self.assertEqual((base / "pin.txt").read_text(), "pinned\n")
                    proof.verify_checkout(base, revision)
                with self.assertRaisesRegex(RuntimeError, "injected proof failure"):
                    with go_proof.disposable_proof_worktree(base) as checkout:
                        raise RuntimeError("injected proof failure")
                self.assertFalse(checkout.exists())
                worktrees = build.query("git", "worktree", "list", "--porcelain", cwd=base).splitlines()
                self.assertEqual(sum(line.startswith("worktree ") for line in worktrees), 1)
                proof.verify_checkout(base, revision)

    def test_proof_worktree_rejects_wrong_or_dirty_base_and_outside_path(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            proof_root, source, base, revision = self._shallow_proof_base(root)
            with (patch.object(go_proof, "BUILD_ROOT", proof_root),
                  patch.object(go_proof, "SOURCE", source)):
                with patch.object(go_proof, "TAILSCALE_COMMIT", "0" * 40):
                    with self.assertRaises(SystemExit):
                        with go_proof.disposable_proof_worktree(base):
                            self.fail("Wrong revision was accepted")
                with patch.object(go_proof, "TAILSCALE_COMMIT", revision):
                    (base / "pin.txt").write_text("dirty\n")
                    with self.assertRaises(SystemExit):
                        with go_proof.disposable_proof_worktree(base):
                            self.fail("Dirty base was accepted")
                    (base / "pin.txt").write_text("pinned\n")
                    with self.assertRaises(SystemExit):
                        with go_proof.disposable_proof_worktree(base, checkout_parent=root / "outside"):
                            self.fail("Outside worktree was accepted")
                proof.verify_checkout(base, revision)

    def test_proof_applies_crlf_checked_out_patch_only_to_worktree(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            proof_root, source, base, revision = self._shallow_proof_base(root)
            patch_file = root / "policy.patch"
            patch_file.write_bytes(
                b"diff --git a/pin.txt b/pin.txt\r\n"
                b"--- a/pin.txt\r\n+++ b/pin.txt\r\n@@ -1 +1 @@\r\n"
                b"-pinned\r\n+patched\r\n"
            )
            with (patch.object(go_proof, "BUILD_ROOT", proof_root),
                  patch.object(go_proof, "SOURCE", source),
                  patch.object(go_proof, "TAILSCALE_COMMIT", revision),
                  patch.object(go_proof, "PATCH", patch_file)):
                with go_proof.disposable_proof_worktree(base) as checkout:
                    go_proof.verify_patch_source(checkout)
                    go_proof.apply_policy_patch(checkout, check_only=False)
                    self.assertEqual((checkout / "pin.txt").read_text(), "patched\n")
                self.assertEqual((base / "pin.txt").read_text(), "pinned\n")
                self.assertIn(b"\r\n", patch_file.read_bytes())
                proof.verify_checkout(base, revision)

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
            subprocess.run(["git", "remote", "add", "origin", "https://example.invalid/repository.git"], cwd=source, check=True)
            with self.assertRaises(SystemExit):
                build.verify_clean_checkout(source, revision, "https://wrong.example/repository.git")
            (source / "file").write_text("dirty\n")
            with self.assertRaises(SystemExit):
                build.verify_clean_checkout(source, revision)

    def test_two_preparations_start_from_clean_exact_pins(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            base = root / "base"
            base.mkdir()

            def repository(name: str, origin: str) -> tuple[Path, str]:
                source = base / name
                subprocess.run(["git", "init", "--quiet", str(source)], check=True)
                (source / "pin.txt").write_text(f"{name}\n")
                subprocess.run(["git", "add", "pin.txt"], cwd=source, check=True)
                subprocess.run(
                    ["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                     "commit", "--quiet", "-m", "pin"], cwd=source, check=True,
                )
                subprocess.run(["git", "remote", "add", "origin", origin], cwd=source, check=True)
                return source, build.query("git", "rev-parse", "HEAD", cwd=source)

            lib, lib_commit = repository("libtailscale", build.PIN["repository"])
            tailscale, ts_commit = repository("tailscale", build.TAILSCALE_REPOSITORY)
            patches = root / "patches"
            patches.mkdir()
            for name, filename in (
                ("libtailscale", LIBTAILSCALE_PATCH.name),
                ("tailscale", TAILSCALE_PATCH.name),
            ):
                (patches / filename).write_text(
                    "diff --git a/pin.txt b/pin.txt\n"
                    "--- a/pin.txt\n+++ b/pin.txt\n@@ -1 +1 @@\n"
                    f"-{name}\n+patched-{name}\n"
                )
            with (patch.object(build, "BUILD_ROOT", root / "runs"),
                  patch.object(build, "SOURCE", lib),
                  patch.object(build, "TAILSCALE_SOURCE", tailscale),
                  patch.object(build, "PATCHES", patches),
                  patch.dict(build.PIN, {"commit": lib_commit}),
                  patch.object(build, "TAILSCALE_COMMIT", ts_commit)):
                for _ in range(2):
                    with build.disposable_build_sources() as (run, lib_worktree, ts_worktree):
                        for worktree, commit, origin, name in (
                            (lib_worktree, lib_commit, build.PIN["repository"], "libtailscale"),
                            (ts_worktree, ts_commit, build.TAILSCALE_REPOSITORY, "tailscale"),
                        ):
                            build.verify_clean_checkout(worktree, commit, origin)
                            self.assertEqual((worktree / "pin.txt").read_text(), f"{name}\n")
                        build.apply_direct_only_patches(lib_worktree, ts_worktree)
                        for worktree, name in ((lib_worktree, "libtailscale"), (ts_worktree, "tailscale")):
                            self.assertEqual((worktree / "pin.txt").read_text(), f"patched-{name}\n")
                            (worktree / "generated.txt").write_text("build output\n")
                        environment = build.build_workspace_environment(run)
                        self.assertEqual(Path(environment["GOWORK"]).parent, run)
                    build.verify_clean_checkout(lib, lib_commit, build.PIN["repository"])
                    build.verify_clean_checkout(tailscale, ts_commit, build.TAILSCALE_REPOSITORY)

    def test_patches_are_ordered_and_source_checked(self) -> None:
        calls = []
        with patch.object(build, "execute", side_effect=lambda *a, **k: calls.append((a, k))):
            build.apply_direct_only_patches(build.SOURCE, build.TAILSCALE_SOURCE)
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
        self.assertLess(main.index("checkout_source()"), main.index("with disposable_build_sources()"))
        self.assertLess(main.index("with disposable_build_sources()"), main.index("apply_direct_only_patches("))
        self.assertLess(main.index("apply_direct_only_patches("), main.index("patch_pinned_source("))
        self.assertLess(main.index("patch_pinned_source("), main.index("build_workspace_environment("))

    def test_build_explicitly_selects_patched_local_dependency(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            environment = build.build_workspace_environment(Path(temporary))
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

    def test_ci_runs_substantive_go_proof_and_patched_bridge_tests(self) -> None:
        workflow = (ROOT / ".github/workflows/build-multiplatform.yml").read_text()
        proof_job = workflow[workflow.index("  direct-only-proof:"):workflow.index("  test:")]
        self.assertIn("actions/setup-go@v5", proof_job)
        self.assertIn("go-version: '1.25.5'", proof_job)
        self.assertIn("prepare_pinned_tailscale_source.py --go", proof_job)
        self.assertIn("run_direct_only_go_proof.py --go", proof_job)
        self.assertIn("--broader", proof_job)
        self.assertIn('packages = ["./wgengine/...", "./tsnet"]', inspect.getsource(go_proof.run_proof))
        macos_job = workflow[workflow.index("  macos:"):workflow.index("  windows:")]
        self.assertIn("build_tailscalekit.py macos", macos_job)
        self.assertIn("--run-bridge-tests", macos_job)
        builder = inspect.getsource(build.main)
        self.assertLess(builder.index("apply_direct_only_patches("), builder.index("if args.run_bridge_tests:"))
        self.assertIn('"^(TestDirectOnlyDataConfiguration|TestConn)$"', builder)
        self.assertIn("cwd=lib_source, environment=build_env", builder)

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
