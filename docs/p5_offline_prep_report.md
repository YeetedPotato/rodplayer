# Phase 5 Offline Preparation Report

## Initial State

- Production starting branch: `phase-5-family-beta`.
- Starting commit: `09e542098a9494e99bff8204df3e9ea3f621fd2f` (`Treat idle direct path as starting`).
- Starting worktree exception: the intentionally untracked `docs/p5f_architecture_audit.md`.
- Offline work branch: `codex/p5-offline-prep-20260922`.

No live service, Headscale node, Mac, enrollment endpoint, setup code, auth key, or persisted node-state file was accessed by this work.

## P5-E Startup Wiring Finding

**Confirmed gap:** normal application startup did not instantiate or invoke the private-network runtime.

Evidence at the starting commit:

- `lib/main.dart` restored Jellyfin credentials and constructed `JellyfinApiClient`, but had no `PrivateNetworkRuntime`, `MethodChannelPrivateNetworkRuntime`, `confirmHostAvailable`, `status`, `resume`, or status-stream use.
- `lib/platform/network/method_channel_private_network_runtime.dart` implemented the runtime boundary, but `rg` found it only in its implementation and tests.
- `tool/native_hosts/ios/AppDelegate.swift` and `tool/native_hosts/macos/MainFlutterWindow.swift` expose bootstrap/resume only through the MethodChannel. Their native hosts do not auto-resume an identity at app launch.

Therefore a persisted P5-E identity could remain stopped in ordinary production startup unless explicit Dart/proof-harness code called `resume()`.

## Offline Integration Implemented

`PrivateNetworkSessionController` is application-scoped and owns exactly one `PrivateNetworkRuntime` subscription for the lifetime of `RodPlayerShell`.

Startup behavior:

1. Call `confirmHostAvailable()` safely.
2. Subscribe to status events before requesting the current status.
3. Read current status.
4. Resume exactly once only when the host is present, identity is persisted, and current state is `stopped`.
5. Never bootstrap/enroll automatically.
6. Ignore runtime failures so Jellyfin/UI startup remains available.

The controller has a revision guard so a delayed startup/status/resume result cannot overwrite a newer event. Its `close()` cancels the Dart stream subscription. It is deliberately not tied to Jellyfin logout, profile switching, or Jellyfin client recreation; those operations do not call private-network reset/stop.

This adds no listener, gateway URL, ready state, `canProxy`, endpoint rewrite, mesh dial, proxy, or P5-F traffic behavior.

## Files Changed

- `docs/p5f_architecture_audit.md`: reviewed P5-F audit and future direct-only gateway/security design.
- `lib/core/network/private_network_session_controller.dart`: application-scoped persisted-identity resume controller.
- `lib/main.dart`: creates/disposes the controller once per application shell and injects a runtime factory for tests.
- `test/private_network_session_controller_test.dart`: deterministic startup, failure, stale-result, and subscription tests.
- `test/private_network_runtime_test.dart`: malformed gateway and ready/non-ready parser rejection coverage.
- `test/root_session_test.dart`: shell startup injection and logout/profile-switch non-reset coverage.

## Security Regression Coverage

The runtime parser remains fail-closed for gateway URLs. Added cases reject HTTPS, hostnames, wildcard/external/IPv6 addresses, missing/invalid ports, userinfo, query, fragment, unexpected path, and malformed URI. Tests also reject invalid ready state combinations and non-ready gateway publication.

The production startup path does not acquire enrollment material, read/write setup codes, bootstrap a node, or reset persisted private identity.

## P5-F Preparation

The architecture audit was rechecked against current source. Its recommendations remain explicitly proposed/unresolved where a Mac live proof is needed. The key P5-F gate remains unchanged: a direct P5-E path must be live-proven before any loopback listener or data-plane implementation begins.

## Unresolved Live Requirements

1. Use the disposable Mac proof harness only to identify the failing P5-E direct-predicate clause and to prove a repeatable direct state for node 6.
2. Confirm resume after an ordinary production app restart with no auth key and no setup code.
3. Verify iOS/macOS lifecycle behavior and status transitions on real devices.
4. Capture sanitized, representative Jellyfin/Remux behavior for redirects, HLS manifests, image authentication, range seeking, and any subtitle URL behavior before P5-F routing design is implemented.

These require the Mac/Home/Headscale environment and were intentionally not attempted offline.

## Recommended Next Steps

1. Complete the sanitized P5-E live proof; do not weaken the exact direct predicate to obtain a result.
2. If direct proof succeeds, review the P5-F audit and implement P5-F0 only: a pure approved-origin endpoint-routing contract with tests, no native gateway.
3. Keep a native fixed-destination, direct-only streaming gateway as a separately reviewed later change.

## Local Commits and Final Status

Local commits, if any, are intentionally not pushed. Update this section after final local validation and commit inspection. The production branch and live proof state remain untouched.
