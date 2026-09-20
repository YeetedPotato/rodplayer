#!/usr/bin/env python3
"""Static pinned-source tests for the RodPlayer libtailscale logging patch."""

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "build_tailscalekit", ROOT / "tool" / "apple_mesh" / "build_tailscalekit.py"
)
assert SPEC is not None and SPEC.loader is not None
BUILD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD)

TAILSCALE_GO = """package main

//export TsnetSetLogFD
func TsnetSetLogFD(handle C.uintptr_t, fd C.int) C.int {
	if fd == -1 {
		s.s.Logf = logger.Discard
		return 0
	}
	return 0
}

//export TsnetUp
"""

MAKEFILE = """# unrelated source text must remain unchanged

libtailscale.so:
	go build -v -buildmode=c-shared -o $@

libtailscale.a:
	go build -buildmode=c-archive -o $@

libtailscale_ios.a:
	GOOS=ios GOARCH=arm64 go build -v -ldflags -w -tags ios -o $@ -buildmode=c-archive

libtailscale_ios_sim_arm64.a:
	GOOS=ios GOARCH=arm64 go build -v -ldflags -w -tags ios -o $@ -buildmode=c-archive

libtailscale_ios_sim_x86_64.a:
	GOOS=ios GOARCH=amd64 go build -v -ldflags -w -tags ios -o $@ -buildmode=c-archive
"""


class LibtailscaleLoggingPolicyTest(unittest.TestCase):
    def _source(self) -> tempfile.TemporaryDirectory[str]:
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        (root / "tailscale.go").write_text(TAILSCALE_GO)
        (root / "Makefile").write_text(MAKEFILE)
        return temporary

    def test_patches_logging_and_apple_build_tags_idempotently(self) -> None:
        with self._source() as temporary:
            root = Path(temporary)
            BUILD.patch_pinned_source(root)
            first_go = (root / "tailscale.go").read_text()
            first_makefile = (root / "Makefile").read_text()
            self.assertIn("s.s.Logf = logger.Discard\n\t\ts.s.UserLogf = logger.Discard", first_go)
            self.assertIn("go build -tags=ts_omit_logtail -buildmode=c-archive -o $@", first_makefile)
            self.assertIn("go build -v -tags=ts_omit_logtail -buildmode=c-shared -o $@", first_makefile)
            self.assertEqual(first_makefile.count("-tags=ios,ts_omit_logtail"), 3)
            self.assertIn("GOOS=ios GOARCH=arm64", first_makefile)
            self.assertIn("GOOS=ios GOARCH=amd64", first_makefile)
            self.assertIn("# unrelated source text must remain unchanged", first_makefile)

            BUILD.patch_pinned_source(root)
            self.assertEqual((root / "tailscale.go").read_text(), first_go)
            self.assertEqual((root / "Makefile").read_text(), first_makefile)

    def test_unexpected_source_shape_fails_closed(self) -> None:
        with self._source() as temporary:
            root = Path(temporary)
            (root / "tailscale.go").write_text("package main\n")
            with self.assertRaises(SystemExit):
                BUILD.patch_pinned_source(root)

        with self._source() as temporary:
            root = Path(temporary)
            (root / "Makefile").write_text("libtailscale.a:\n\tgo build -o $@\n")
            with self.assertRaises(SystemExit):
                BUILD.patch_pinned_source(root)


if __name__ == "__main__":
    unittest.main()
