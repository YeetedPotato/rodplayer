#!/usr/bin/env python3
"""Build the pinned upstream TailscaleKit framework for one Apple platform."""

import argparse
import json
import os
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


def execute(
    *args: str,
    cwd: Path | None = None,
    environment: dict[str, str] | None = None,
) -> None:
    print(f"+ {shlex.join(args)}")
    subprocess.run(
        args,
        cwd=cwd,
        check=True,
        env={**os.environ, **(environment or {})},
    )


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


def build_macos_framework(architecture: str, derived_data: Path) -> Path:
    go_architecture = {"arm64": "arm64", "x86_64": "amd64"}[architecture]
    environment = {
        "GOARCH": go_architecture,
        "CGO_CFLAGS": f"-arch {architecture}",
        "CGO_LDFLAGS": f"-arch {architecture}",
    }
    execute("make", "-B", "c-archive", cwd=SOURCE, environment=environment)
    if derived_data.exists():
        shutil.rmtree(derived_data)
    execute(
        "xcodebuild",
        "build",
        "-scheme",
        "TailscaleKit (macOS)",
        "-derivedDataPath",
        str(derived_data),
        "-configuration",
        "Release",
        "-destination",
        f"platform=macOS,arch={architecture}",
        "MACOSX_DEPLOYMENT_TARGET=15.0",
        "CODE_SIGNING_ALLOWED=NO",
        cwd=SOURCE / "swift",
    )
    framework = derived_data / "Build" / "Products" / "Release" / "TailscaleKit.framework"
    if not framework.is_dir():
        raise SystemExit(f"Upstream macOS {architecture} build did not produce {framework}")
    return framework


def resolve_framework_entry(
    framework: Path,
    relative_path: Path,
    *,
    directory: bool,
) -> tuple[Path, Path, bool]:
    entry = framework / relative_path
    try:
        resolved = entry.resolve(strict=True)
    except FileNotFoundError as error:
        raise SystemExit(f"Missing macOS TailscaleKit framework entry: {entry}") from error
    if directory != resolved.is_dir():
        kind = "directory" if directory else "file"
        raise SystemExit(f"Expected macOS TailscaleKit {kind}: {entry}")
    return entry, resolved, entry.is_symlink()


def merge_macos_frameworks(arm64: Path, x86_64: Path) -> None:
    binary, arm64_binary, binary_was_symlink = resolve_framework_entry(
        arm64,
        Path("TailscaleKit"),
        directory=False,
    )
    _, x86_64_binary, _ = resolve_framework_entry(
        x86_64,
        Path("TailscaleKit"),
        directory=False,
    )
    modules, arm64_modules_root, modules_were_symlink = resolve_framework_entry(
        arm64,
        Path("Modules"),
        directory=True,
    )
    _, x86_64_modules_root, _ = resolve_framework_entry(
        x86_64,
        Path("Modules"),
        directory=True,
    )
    arm64_modules = arm64_modules_root / "TailscaleKit.swiftmodule"
    x86_64_modules = x86_64_modules_root / "TailscaleKit.swiftmodule"
    if not arm64_modules.is_dir() or not x86_64_modules.is_dir():
        raise SystemExit("Upstream macOS build did not produce architecture-specific Swift modules.")

    universal = arm64_binary.with_name(f".{arm64_binary.name}.universal")
    if universal.exists() or universal.is_symlink():
        universal.unlink()
    execute("lipo", "-create", str(arm64_binary), str(x86_64_binary), "-output", str(universal))
    universal.replace(arm64_binary)
    for module in x86_64_modules.glob("x86_64-apple-macos.*"):
        shutil.copy2(module, arm64_modules / module.name)

    architectures = set(query("lipo", "-archs", str(binary)).split())
    if architectures != {"arm64", "x86_64"}:
        raise SystemExit(f"Expected universal macOS TailscaleKit, found: {' '.join(sorted(architectures))}")
    for architecture in ("arm64", "x86_64"):
        if not (arm64_modules / f"{architecture}-apple-macos.swiftmodule").is_file():
            raise SystemExit(f"Missing {architecture} macOS TailscaleKit Swift module.")
    if binary.is_symlink() != binary_was_symlink or modules.is_symlink() != modules_were_symlink:
        raise SystemExit("macOS TailscaleKit framework symlink structure changed during universal merge.")


def build_macos_universal_framework() -> None:
    swift_build = SOURCE / "swift" / "build"
    arm64 = build_macos_framework("arm64", swift_build)
    x86_64 = build_macos_framework("x86_64", SOURCE / "swift" / "build-x86_64")
    merge_macos_frameworks(arm64, x86_64)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("platform", choices=("ios", "macos"))
    parser.add_argument("--xcode-major", type=int, required=True)
    args = parser.parse_args()
    require_darwin()
    verify_toolchain(args.xcode_major)
    checkout_source()
    patch_pinned_source()
    if args.platform == "macos":
        build_macos_universal_framework()
    else:
        execute("make", args.platform, cwd=SOURCE / "swift")
    create_local_pod(args.platform)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from error
