#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
binary="$(mktemp "${TMPDIR:-/tmp}/rodplayer-bootstrap-ownership.XXXXXX")"
trap 'rm -f "$binary"' EXIT
swiftc -parse-as-library \
  "$root/tool/native_hosts/apple/ApplePrivateNetworkBootstrapOwnership.swift" \
  "$root/tool/apple_mesh/test_bootstrap_ownership.swift" \
  -o "$binary"
"$binary"
