#!/usr/bin/env python3
"""Static contract checks for the duplicated Apple D2 private-network host."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HOSTS = (
    ROOT / "tool" / "native_hosts" / "ios" / "AppDelegate.swift",
    ROOT / "tool" / "native_hosts" / "macos" / "MainFlutterWindow.swift",
)


def private_network_source(path: Path) -> str:
    source = path.read_text()
    start = source.index("private final class PrivateNetworkHost")
    end = source.index("private final class AppleCompatibilityPlaybackManager", start)
    return source[start:end]


class PrivateNetworkStatePolicyTest(unittest.TestCase):
    def test_disk_backed_identity_and_backup_exclusion(self) -> None:
        for path in HOSTS:
            source = private_network_source(path)
            self.assertIn('appendingPathComponent("RodPlayer", isDirectory: true)', source)
            self.assertIn('appendingPathComponent("PrivateNetwork", isDirectory: true)', source)
            self.assertIn('appendingPathComponent("node", isDirectory: true)', source)
            self.assertIn('appendingPathComponent("tailscaled.state", isDirectory: false)', source)
            self.assertIn("fileExists(atPath: tailscaledState.path)", source)
            self.assertIn("values.isExcludedFromBackup = true", source)

    def test_stop_reset_and_fail_closed_ordering(self) -> None:
        for path in HOSTS:
            source = private_network_source(path)
            owner = source[source.index("actor ApplePrivateNetworkNodeOwner"):]
            self.assertIn("private var lifecycleLocked = false", owner)
            self.assertIn("private var lifecycleWaiters: [CheckedContinuation<Void, Never>] = []", owner)
            self.assertIn("private func acquireLifecycle() async", owner)
            self.assertIn("private func releaseLifecycle()", owner)
            self.assertIn("func install(_ node: any ApplePrivateNetworkNode) async throws", owner)
            for method, next_marker in (
                ("func install(_ node: any ApplePrivateNetworkNode) async throws", "func stop()"),
                ("func stop() async throws", "func reset()"),
                ("func reset() async throws", "private func stopLocked()"),
            ):
                body = owner[owner.index(method):owner.index(next_marker, owner.index(method))]
                self.assertIn("await acquireLifecycle()", body)
                self.assertIn("defer { releaseLifecycle() }", body)
            self.assertIn("private func stopLocked() async throws", owner)
            self.assertIn("private enum ApplePrivateNetworkNodeOwnerError: Error", source)
            self.assertIn("case nodeAlreadyActive", source)
            self.assertLess(owner.index("guard activeNode == nil"), owner.index("activeNode = node"))
            self.assertLess(owner.index("try await activeNode.close()"), owner.index("self.activeNode = nil"))
            self.assertEqual(owner.count("self.activeNode = nil"), 1)
            reset = owner[owner.index("func reset() async throws"):owner.index("private func stopLocked()")]
            self.assertIn("try await stopLocked()", reset)
            self.assertNotIn("try await stop()", reset)
            self.assertLess(reset.index("try await stopLocked()"), reset.index("try stateStore.reset()"))
            self.assertIn("private_network_operation_failed", source)
            self.assertIn('"state": "stopped"', source)
            self.assertIn('"path": "none"', source)
            self.assertIn('"gatewayUrl": NSNull()', source)

    def test_configuration_and_initialization_failure_are_truthful(self) -> None:
        for path in HOSTS:
            source = private_network_source(path)
            self.assertNotIn("TailscaleNode.Configuration", source)
            self.assertIn("TailscaleKit.Configuration", source)
            self.assertIn("private static func operationFailed() -> FlutterError", source)
            self.assertGreaterEqual(source.count("Self.operationFailed()"), 6)
            self.assertNotIn("result(operationFailed())", source)
            self.assertNotIn("eventSink(operationFailed())", source)
            status = source[source.index('case "status":'):source.index('case "stop":')]
            self.assertLess(status.index("guard stateStore != nil"), status.index("result(statusPayload())"))
            listen = source[source.index("func onListen"):source.index("func onCancel")]
            self.assertIn("eventSink(Self.operationFailed())", listen)

    def test_bootstrap_resume_remain_inert(self) -> None:
        for path in HOSTS:
            source = private_network_source(path)
            unavailable = source[source.index('case "bootstrap", "resume"'):source.index("default:", source.index('case "bootstrap", "resume"'))]
            self.assertIn("private_network_not_ready", unavailable)
            self.assertNotIn("call.arguments", unavailable)
            self.assertNotIn("TailscaleKitNodeFactory()", source)
            self.assertNotIn(".up()", source)
            self.assertNotIn(".down()", source)
            self.assertNotIn(".loopback()", source)
            self.assertNotIn(".statusJSON()", source)
            self.assertNotIn(".addrs()", source)

    def test_apple_hosts_keep_identical_private_network_implementations(self) -> None:
        self.assertEqual(
            private_network_source(HOSTS[0]),
            private_network_source(HOSTS[1]),
        )


if __name__ == "__main__":
    unittest.main()
