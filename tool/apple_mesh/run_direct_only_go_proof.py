#!/usr/bin/env python3
"""Apply the experimental transport patch only to a clean pinned checkout and test it."""

import argparse
from contextlib import contextmanager
import os
from pathlib import Path
import subprocess
import tempfile
from typing import Iterator

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


def apply_policy_patch(source: Path, *, check_only: bool) -> None:
    patch = PATCH.read_bytes().replace(b"\r\n", b"\n")
    args = ["git", "apply"]
    if check_only:
        args.append("--check")
    subprocess.run([*args, "--whitespace=error", "-"], input=patch, cwd=source, check=True)


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
    apply_policy_patch(source, check_only=True)


def run_proof(source: Path, go: Path, broader: bool) -> None:
    verify_patch_source(source)
    apply_policy_patch(source, check_only=False)
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
        packages = ["./wgengine/...", "./tsnet"]
    subprocess.run([str(go), "test", *packages, "-count=1"], cwd=source, env=env, check=True)


@contextmanager
def disposable_proof_worktree(
    base: Path, checkout_parent: Path | None = None,
) -> Iterator[Path]:
    parent = (checkout_parent or SOURCE).resolve()
    if not parent.is_relative_to(BUILD_ROOT.resolve()):
        raise SystemExit("Proof worktree must stay inside the ignored build root")
    if not (base / ".git").exists():
        raise SystemExit(f"Not a pinned Git checkout: {base}")
    if Path(command("git", "rev-parse", "--show-toplevel", cwd=base)).resolve() != base.resolve():
        raise SystemExit(f"Unexpected pinned checkout root: {base}")
    verify_checkout(base, TAILSCALE_COMMIT)
    parent.mkdir(parents=True, exist_ok=True)
    try:
        with tempfile.TemporaryDirectory(prefix="direct-only-proof-", dir=parent) as temp:
            temporary_root = Path(temp).resolve()
            if not temporary_root.is_relative_to(BUILD_ROOT.resolve()):
                raise SystemExit("Proof worktree escaped the ignored build root")
            checkout = temporary_root / "tailscale"
            try:
                subprocess.run(
                    ["git", "worktree", "add", "--detach", str(checkout), TAILSCALE_COMMIT],
                    cwd=base, check=True,
                )
                verify_checkout(checkout, TAILSCALE_COMMIT)
                yield checkout
            finally:
                if (checkout / ".git").exists():
                    subprocess.run(["git", "worktree", "remove", "--force", str(checkout)], cwd=base, check=True)
    finally:
        subprocess.run(["git", "worktree", "prune"], cwd=base, check=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, help="An explicit clean pinned base inside the ignored build tree")
    parser.add_argument("--go", type=Path)
    parser.add_argument("--broader", action="store_true")
    args = parser.parse_args()
    go = args.go or local_go(False)
    verify_go(go)
    base = args.source or SOURCE / "tailscale"
    if not base.resolve().is_relative_to(SOURCE.resolve()):
        raise SystemExit("Pinned base must stay inside the ignored proof source root")
    if command("git", "rev-parse", "HEAD", cwd=SOURCE / "libtailscale") != PIN["commit"]:
        raise SystemExit("Base libtailscale checkout is not the pinned commit")
    verify_checkout(SOURCE / "libtailscale", PIN["commit"])
    with disposable_proof_worktree(base) as checkout:
        run_proof(checkout, go, args.broader)


if __name__ == "__main__":
    main()
