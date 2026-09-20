#!/usr/bin/env python3
"""Build the pinned upstream TailscaleKit framework for one Apple platform."""

import argparse
import json
from pathlib import Path
import platform
import re
import shutil
import shlex
import subprocess


ROOT = Path(__file__).resolve().parents[2]
PIN = json.loads(Path(__file__).with_name("libtailscale_pin.json").read_text())
BUILD_ROOT = ROOT / "build" / "apple_mesh"
SOURCE = BUILD_ROOT / "source" / "libtailscale"


def query(*args: str, cwd: Path | None = None) -> str:
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def execute(*args: str, cwd: Path | None = None) -> None:
    print(f"+ {shlex.join(args)}")
    subprocess.run(args, cwd=cwd, check=True)


def require_darwin() -> None:
    if platform.system() != "Darwin":
        raise SystemExit("TailscaleKit Apple artifacts can only be built on macOS.")


def verify_toolchain(xcode_major: int) -> None:
    go_version = query("go", "version")
    if not re.search(rf"\bgo{re.escape(PIN['goVersion'])}\b", go_version):
        raise SystemExit(f"Go {PIN['goVersion']} is required; found: {go_version}")
    xcode_version = query("xcodebuild", "-version")
    match = re.search(r"Xcode\s+(\d+)\.(\d+)", xcode_version)
    if not match or int(match.group(1)) != xcode_major:
        raise SystemExit(f"Xcode {xcode_major} is required; found: {xcode_version}")


def checkout_source() -> None:
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    if SOURCE.exists():
        if not (SOURCE / ".git").is_dir():
            raise SystemExit(f"Refusing to reuse non-Git source directory: {SOURCE}")
    else:
        execute("git", "clone", "--no-checkout", PIN["repository"], str(SOURCE))
    execute("git", "fetch", "--depth", "1", "origin", PIN["commit"], cwd=SOURCE)
    execute("git", "checkout", "--detach", "FETCH_HEAD", cwd=SOURCE)
    revision = query("git", "rev-parse", "HEAD", cwd=SOURCE)
    if revision != PIN["commit"]:
        raise SystemExit(f"Pinned revision mismatch: expected {PIN['commit']}, got {revision}")
    go_mod = (SOURCE / "go.mod").read_text()
    if f"go {PIN['goVersion']}" not in go_mod or f"tailscale.com v{PIN['tailscaleVersion']}" not in go_mod:
        raise SystemExit("Pinned libtailscale dependency versions do not match metadata.")


def _replace_exact(
    text: str,
    original: str,
    patched: str,
    *,
    label: str,
    expected_count: int,
    required: bool = True,
) -> str:
    original_count = text.count(original)
    patched_count = text.count(patched)
    if original_count == expected_count and patched_count == 0:
        return text.replace(original, patched)
    if original_count == 0 and patched_count == expected_count:
        return text
    if not required and original_count == 0 and patched_count == 0:
        return text
    raise SystemExit(f"Unexpected pinned libtailscale {label} source shape.")


def patch_pinned_source(source_root: Path = SOURCE) -> None:
    tailscale_path = source_root / "tailscale.go"
    makefile_path = source_root / "Makefile"
    if not tailscale_path.is_file() or not makefile_path.is_file():
        raise SystemExit("Pinned libtailscale source files are missing.")

    tailscale = tailscale_path.read_text()
    function_start = tailscale.find("func TsnetSetLogFD")
    function_end = tailscale.find("\n//export", function_start + 1)
    if function_start == -1 or function_end == -1:
        raise SystemExit("Pinned libtailscale TsnetSetLogFD source marker is missing.")
    function = tailscale[function_start:function_end]
    original_branch = """if fd == -1 {
\t\ts.s.Logf = logger.Discard
\t\treturn 0
\t}"""
    patched_branch = """if fd == -1 {
\t\ts.s.Logf = logger.Discard
\t\ts.s.UserLogf = logger.Discard
\t\treturn 0
\t}"""
    patched_function = _replace_exact(
        function,
        original_branch,
        patched_branch,
        label="TsnetSetLogFD",
        expected_count=1,
    )
    tailscale_path.write_text(tailscale[:function_start] + patched_function + tailscale[function_end:])

    makefile = makefile_path.read_text()
    makefile = _replace_exact(
        makefile,
        "go build -buildmode=c-archive -o $@",
        "go build -tags=ts_omit_logtail -buildmode=c-archive -o $@",
        label="macOS c-archive",
        expected_count=1,
    )
    makefile = _replace_exact(
        makefile,
        "go build -v -ldflags -w -tags ios -o $@ -buildmode=c-archive",
        "go build -v -ldflags -w -tags=ios,ts_omit_logtail -o $@ -buildmode=c-archive",
        label="iOS c-archive",
        expected_count=3,
    )
    makefile = _replace_exact(
        makefile,
        "go build -v -buildmode=c-shared -o $@",
        "go build -v -tags=ts_omit_logtail -buildmode=c-shared -o $@",
        label="shared-library",
        expected_count=1,
        required=False,
    )
    makefile_path.write_text(makefile)


def create_local_pod(target: str) -> None:
    product = {
        "ios": SOURCE / "swift" / "build" / "Build" / "Products" / "Release-iphoneos" / "TailscaleKit.framework",
        "macos": SOURCE / "swift" / "build" / "Build" / "Products" / "Release" / "TailscaleKit.framework",
    }[target]
    if not product.is_dir():
        raise SystemExit(f"Upstream {target} build did not produce {product}")
    pod_root = BUILD_ROOT / target
    framework = pod_root / "TailscaleKit.framework"
    if framework.exists():
        shutil.rmtree(framework)
    pod_root.mkdir(parents=True, exist_ok=True)
    shutil.copytree(product, framework, symlinks=True)
    template = Path(__file__).with_name(target) / "RodPlayerTailscaleKit.podspec"
    shutil.copyfile(template, pod_root / template.name)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("platform", choices=("ios", "macos"))
    parser.add_argument("--xcode-major", type=int, required=True)
    args = parser.parse_args()
    require_darwin()
    verify_toolchain(args.xcode_major)
    checkout_source()
    patch_pinned_source()
    execute("make", args.platform, cwd=SOURCE / "swift")
    create_local_pod(args.platform)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from error
