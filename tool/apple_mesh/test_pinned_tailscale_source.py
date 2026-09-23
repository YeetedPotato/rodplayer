#!/usr/bin/env python3
"""Offline checks for the pinned Go proof workspace guards."""

from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build_tailscalekit
from prepare_pinned_tailscale_source import BUILD_ROOT, PIN, SOURCE, TAILSCALE_COMMIT, verify_checkout
from run_direct_only_go_proof import verify_go, verify_patch_source


class PinnedSourceTests(unittest.TestCase):
    def test_proof_workspace_cannot_parent_production_builder(self) -> None:
        self.assertEqual(BUILD_ROOT.name, "direct_only_proof")
        self.assertEqual(SOURCE, BUILD_ROOT / "source")
        self.assertNotIn(SOURCE / "go.work", build_tailscalekit.SOURCE.parents)
        self.assertNotIn(SOURCE, build_tailscalekit.SOURCE.parents)

    def test_exact_pins(self) -> None:
        self.assertEqual(PIN["commit"], "59d4bb82744915815178e0f0776d60026a397ee7")
        self.assertEqual(PIN["goVersion"], "1.25.5")
        self.assertEqual(PIN["tailscaleVersion"], "1.94.1")
        self.assertEqual(TAILSCALE_COMMIT, "d885b34776cd2e96f1f368a4d31729e37ff8b59b")

    def test_checkout_refuses_wrong_revision_and_dirty_source(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp)
            subprocess.run(["git", "init", "--quiet", str(repo)], check=True)
            (repo / "proof.txt").write_text("pinned\n")
            subprocess.run(["git", "add", "proof.txt"], cwd=repo, check=True)
            subprocess.run(
                ["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--quiet", "-m", "pin"],
                cwd=repo,
                check=True,
            )
            revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
            verify_checkout(repo, revision)
            with self.assertRaises(SystemExit):
                verify_checkout(repo, "0" * 40)
            (repo / "proof.txt").write_text("changed\n")
            with self.assertRaises(SystemExit):
                verify_checkout(repo, revision)

    def test_go_version_refuses_wrong_binary(self) -> None:
        with patch("run_direct_only_go_proof.command", return_value="go version go1.17.5 windows/amd64"):
            with self.assertRaises(SystemExit):
                verify_go(Path("go"))

    def test_patch_refuses_source_outside_ignored_build_tree(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(SystemExit):
                verify_patch_source(Path(temp))


if __name__ == "__main__":
    unittest.main()
