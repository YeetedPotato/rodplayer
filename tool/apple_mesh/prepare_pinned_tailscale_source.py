#!/usr/bin/env python3
"""Prepare an isolated, exact-version Go workspace for Tailscale policy tests."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import urllib.request
import zipfile


ROOT = Path(__file__).resolve().parents[2]
PIN = json.loads(Path(__file__).with_name("libtailscale_pin.json").read_text())
BUILD_ROOT = ROOT / "build" / "apple_mesh"
SOURCE = BUILD_ROOT / "source"
TAILSCALE_REPO = "https://github.com/tailscale/tailscale.git"
TAILSCALE_COMMIT = "d885b34776cd2e96f1f368a4d31729e37ff8b59b"
GO_WINDOWS_SHA256 = "ae756cce1cb80c819b4fe01b0353807178f532211b47f72d7fa77949de054ebb"


def command(*args: str, cwd: Path | None = None, env: dict | None = None) -> str:
    return subprocess.check_output(args, cwd=cwd, env=env, text=True).strip()


def verify_checkout(path: Path, revision: str) -> None:
    if command("git", "rev-parse", "HEAD", cwd=path) != revision:
        raise SystemExit(f"Wrong pinned revision: {path}")
    if command("git", "status", "--porcelain", cwd=path):
        raise SystemExit(f"Pinned source is dirty; refusing to overwrite: {path}")


def checkout(path: Path, repository: str, revision: str) -> None:
    if not path.exists():
        subprocess.run(["git", "clone", "--filter=blob:none", repository, str(path)], check=True)
    if not (path / ".git").is_dir():
        raise SystemExit(f"Not a Git checkout: {path}")
    current = command("git", "rev-parse", "HEAD", cwd=path)
    if current != revision:
        if command("git", "status", "--porcelain", cwd=path):
            raise SystemExit(f"Pinned source is dirty; refusing checkout: {path}")
        subprocess.run(["git", "fetch", "--depth", "1", "origin", revision], cwd=path, check=True)
        subprocess.run(["git", "checkout", "--detach", revision], cwd=path, check=True)
    verify_checkout(path, revision)


def local_go(provision: bool) -> Path:
    version = PIN["goVersion"]
    binary = BUILD_ROOT / "toolchains" / f"go{version}" / "go" / "bin" / "go.exe"
    if not binary.exists() and provision:
        if platform.system() != "Windows":
            raise SystemExit("Automatic isolated Go provisioning is Windows-only; pass --go on other hosts.")
        archive = BUILD_ROOT / "toolchains" / f"go{version}.windows-amd64.zip"
        archive.parent.mkdir(parents=True, exist_ok=True)
        if not archive.exists():
            urllib.request.urlretrieve(f"https://go.dev/dl/go{version}.windows-amd64.zip", archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != GO_WINDOWS_SHA256:
            raise SystemExit("Official Go archive SHA-256 mismatch")
        with zipfile.ZipFile(archive) as zipped:
            zipped.extractall(binary.parents[2])
    if not binary.exists():
        raise SystemExit(f"Exact Go toolchain missing: {binary}; use --provision-go or --go")
    return binary


def prepare(go: Path) -> None:
    env = {**os.environ, "GOTOOLCHAIN": "local"}
    version = command(str(go), "version", env=env)
    if not version.startswith(f"go version go{PIN['goVersion']} "):
        raise SystemExit(f"Go {PIN['goVersion']} required; found {version}")
    SOURCE.mkdir(parents=True, exist_ok=True)
    lib = SOURCE / "libtailscale"
    ts = SOURCE / "tailscale"
    checkout(lib, PIN["repository"], PIN["commit"])
    checkout(ts, TAILSCALE_REPO, TAILSCALE_COMMIT)
    if command("git", "rev-parse", f"v{PIN['tailscaleVersion']}^{{commit}}", cwd=ts) != TAILSCALE_COMMIT:
        raise SystemExit("Tailscale tag does not resolve to the pinned commit")
    lib_mod = (lib / "go.mod").read_text()
    ts_mod = (ts / "go.mod").read_text()
    if f"go {PIN['goVersion']}" not in lib_mod or f"tailscale.com v{PIN['tailscaleVersion']}" not in lib_mod:
        raise SystemExit("libtailscale go.mod differs from the pin")
    if "module tailscale.com" not in ts_mod:
        raise SystemExit("Pinned Tailscale module name differs")
    workspace = SOURCE / "go.work"
    workspace.write_text(
        f"go {PIN['goVersion']}\n\nuse ./libtailscale\n\n"
        f"replace tailscale.com v{PIN['tailscaleVersion']} => ./tailscale\n"
    )
    cache = BUILD_ROOT / "go-cache"
    cache.mkdir(exist_ok=True)
    print(f"Go: {go}\nlibtailscale: {PIN['commit']}\nTailscale: {TAILSCALE_COMMIT}\nGOWORK: {workspace}\nGOMODCACHE: {cache / 'mod'}\nGOCACHE: {cache / 'build'}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--go", type=Path)
    parser.add_argument("--provision-go", action="store_true")
    args = parser.parse_args()
    prepare(args.go or local_go(args.provision_go))


if __name__ == "__main__":
    main()
