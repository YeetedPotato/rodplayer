#!/usr/bin/env python3
"""Apply the experimental transport patch only to a clean pinned checkout and test it."""

import argparse
import os
from pathlib import Path
import subprocess
import tempfile

from prepare_pinned_tailscale_source import (
    BUILD_ROOT,
    PIN,
    SOURCE,
    TAILSCALE_COMMIT,
    command,
    local_go,
    verify_checkout,
)


PATCH = Path(__file__).with_name("patches") / "tailscale-v1.94.1-direct-only-data.patch"


def verify_go(go: Path) -> None:
    version = command(str(go), "version", env={**os.environ, "GOTOOLCHAIN": "local"})
    if not version.startswith(f"go version go{PIN['goVersion']} "):
        raise SystemExit(f"Go {PIN['goVersion']} required; found {version}")


def verify_patch_source(source: Path) -> None:
    if not source.resolve().is_relative_to((BUILD_ROOT / "source").resolve()):
        raise SystemExit("Patch source must be inside the ignored Apple mesh build workspace")
    verify_checkout(source, TAILSCALE_COMMIT)
    if not PATCH.is_file():
        raise SystemExit(f"Missing policy patch: {PATCH}")
    subprocess.run(["git", "apply", "--check", "--whitespace=error", str(PATCH)], cwd=source, check=True)


def run_proof(source: Path, go: Path, broader: bool) -> None:
    verify_patch_source(source)
    subprocess.run(["git", "apply", "--whitespace=error", str(PATCH)], cwd=source, check=True)
    cache = BUILD_ROOT / "go-cache"
    env = {
        **os.environ,
        "GOTOOLCHAIN": "local",
        "GOWORK": "off",
        "GOMODCACHE": str(cache / "mod"),
        "GOCACHE": str(cache / "build"),
    }
    packages = ["./wgengine/magicsock"]
    if broader:
        packages = ["./wgengine/..."]
    subprocess.run([str(go), "test", *packages, "-count=1"], cwd=source, env=env, check=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, help="An explicit clean checkout inside the ignored build tree")
    parser.add_argument("--go", type=Path)
    parser.add_argument("--broader", action="store_true")
    args = parser.parse_args()
    go = args.go or local_go(False)
    verify_go(go)
    if args.source:
        run_proof(args.source, go, args.broader)
        return
    base = SOURCE / "tailscale"
    if command("git", "rev-parse", "HEAD", cwd=base) != TAILSCALE_COMMIT:
        raise SystemExit("Base checkout is not the pinned Tailscale commit")
    if command("git", "rev-parse", "HEAD", cwd=SOURCE / "libtailscale") != PIN["commit"]:
        raise SystemExit("Base libtailscale checkout is not the pinned commit")
    with tempfile.TemporaryDirectory(prefix="direct-only-proof-", dir=SOURCE) as temp:
        temporary_root = Path(temp).resolve()
        if not temporary_root.is_relative_to(SOURCE.resolve()):
            raise SystemExit("Temporary checkout escaped the ignored build tree")
        checkout = temporary_root / "tailscale"
        subprocess.run(["git", "clone", "--quiet", "--local", "--no-hardlinks", str(base), str(checkout)], check=True)
        run_proof(checkout, go, args.broader)


if __name__ == "__main__":
    main()
