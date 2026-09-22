#!/usr/bin/env python3
"""Static policy checks for generated macOS compatibility build repairs."""

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


APPLY = load_module("apply_native_hosts", ROOT / "tool" / "apply_native_hosts.py")
BUILD = load_module("build_tailscalekit", ROOT / "tool" / "apple_mesh" / "build_tailscalekit.py")


class MacOSBuildCompatibilityPolicyTest(unittest.TestCase):
    def test_vlckit_header_patch_is_exact_and_idempotent(self) -> None:
        podfile = """platform :osx, '15.0'
target 'Runner' do
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
  end
end
"""
        patched = APPLY.patch_macos_vlckit_podfile(podfile)
        self.assertIn("def rodplayer_patch_vlckit_coregraphics(installer)", patched)
        self.assertIn("VLCMediaThumbnailer.h", patched)
        self.assertIn("contents.scan(original).length == 1", patched)
        self.assertIn("rodplayer_patch_vlckit_coregraphics(installer)", patched)
        self.assertEqual(patched, APPLY.patch_macos_vlckit_podfile(patched))

    def test_vlckit_header_patch_requires_generated_post_install_block(self) -> None:
        with self.assertRaises(RuntimeError):
            APPLY.patch_macos_vlckit_podfile("target 'Runner' do\nend\n")

    def test_tailscalekit_build_requires_universal_macos_artifact(self) -> None:
        source = Path(BUILD.__file__).read_text()
        self.assertIn('build_macos_framework("arm64"', source)
        self.assertIn('build_macos_framework("x86_64"', source)
        self.assertIn('"MACOSX_DEPLOYMENT_TARGET=15.0"', source)
        self.assertIn('execute("lipo", "-create"', source)
        self.assertIn('{"arm64", "x86_64"}', source)
        self.assertIn('f"{architecture}-apple-macos.swiftmodule"', source)
        self.assertIn("resolve_framework_entry", source)
        self.assertIn("binary_was_symlink", source)
        self.assertIn("modules_were_symlink", source)

    def test_universal_merge_preserves_framework_symlinks(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            try:
                arm64 = self._framework(root / "arm64", "arm64")
                x86_64 = self._framework(root / "x86_64", "x86_64")
            except OSError as error:
                self.skipTest(f"symlink creation unavailable: {error}")

            def lipo(*args: str, **_: object) -> None:
                output = Path(args[-1])
                output.write_bytes(Path(args[2]).read_bytes() + Path(args[3]).read_bytes())

            with mock.patch.object(BUILD, "execute", side_effect=lipo), mock.patch.object(
                BUILD,
                "query",
                return_value="arm64 x86_64",
            ):
                BUILD.merge_macos_frameworks(arm64, x86_64)

            binary = arm64 / "TailscaleKit"
            modules = arm64 / "Modules"
            self.assertTrue(binary.is_symlink())
            self.assertTrue(modules.is_symlink())
            self.assertEqual(binary.resolve().read_bytes(), b"arm64x86_64")
            swift_modules = modules.resolve() / "TailscaleKit.swiftmodule"
            self.assertTrue((swift_modules / "arm64-apple-macos.swiftmodule").is_file())
            self.assertTrue((swift_modules / "x86_64-apple-macos.swiftmodule").is_file())

    @staticmethod
    def _framework(root: Path, architecture: str) -> Path:
        version = root / "Versions" / "A"
        modules = version / "Modules" / "TailscaleKit.swiftmodule"
        modules.mkdir(parents=True)
        (version / "TailscaleKit").write_bytes(architecture.encode())
        (modules / f"{architecture}-apple-macos.swiftmodule").write_bytes(b"module")
        current = root / "Versions" / "Current"
        current.symlink_to("A", target_is_directory=True)
        (root / "TailscaleKit").symlink_to("Versions/Current/TailscaleKit")
        (root / "Modules").symlink_to("Versions/Current/Modules", target_is_directory=True)
        return root


if __name__ == "__main__":
    unittest.main()
