#!/usr/bin/env python3
"""Verify the selected Apple toolchain without changing deployment targets."""

import argparse
import re
import subprocess


def run(*args: str) -> str:
    output = subprocess.check_output(args, text=True).strip()
    print(output)
    return output


def major(label: str, output: str) -> int:
    match = re.search(r"(\d+)(?:\.\d+)?", output)
    if not match:
        raise SystemExit(f"Could not determine {label} version: {output}")
    return int(match.group(1))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--xcode-major", type=int, required=True)
    parser.add_argument("--ios-sdk-major", type=int, required=True)
    parser.add_argument("--macos-sdk-major", type=int, required=True)
    parser.add_argument("--go-version", required=True)
    args = parser.parse_args()

    run("sw_vers")
    architecture = run("uname", "-m")
    xcode = run("xcodebuild", "-version")
    ios_sdk = run("xcrun", "--sdk", "iphoneos", "--show-sdk-version")
    macos_sdk = run("xcrun", "--sdk", "macosx", "--show-sdk-version")
    go = run("go", "version")

    if architecture != "arm64":
        raise SystemExit(f"Apple proof requires arm64, found {architecture}")
    if major("Xcode", xcode) != args.xcode_major:
        raise SystemExit(f"Expected Xcode {args.xcode_major}, found: {xcode}")
    if major("iOS SDK", ios_sdk) != args.ios_sdk_major:
        raise SystemExit(f"Expected iOS SDK {args.ios_sdk_major}, found: {ios_sdk}")
    if major("macOS SDK", macos_sdk) != args.macos_sdk_major:
        raise SystemExit(f"Expected macOS SDK {args.macos_sdk_major}, found: {macos_sdk}")
    if f"go{args.go_version}" not in go:
        raise SystemExit(f"Expected Go {args.go_version}, found: {go}")


if __name__ == "__main__":
    main()
