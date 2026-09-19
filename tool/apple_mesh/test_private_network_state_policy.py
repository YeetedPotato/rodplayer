#!/usr/bin/env python3
"""Static contract checks for the duplicated Apple D3 private-network host."""

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
            self.assertIn('appendingPathComponent("metadata.json", isDirectory: false)', source)
            self.assertIn("fileExists(atPath: tailscaledState.path)", source)
            self.assertIn("values.isExcludedFromBackup = true", source)
            self.assertIn("options: .atomic", source)

    def test_stop_reset_and_fail_closed_ordering(self) -> None:
        for path in HOSTS:
            source = private_network_source(path)
            owner = source[source.index("actor ApplePrivateNetworkNodeOwner"):]
            self.assertIn("private var lifecycleLocked = false", owner)
            self.assertIn("private var lifecycleWaiters: [CheckedContinuation<Void, Never>] = []", owner)
            self.assertIn("private func acquireLifecycle() async", owner)
            self.assertIn("private func releaseLifecycle()", owner)
            self.assertIn("func bootstrap(metadata: ApplePrivateNetworkMetadata, authKey: String) async throws", owner)
            self.assertIn("func resume() async throws", owner)
            self.assertIn("private func startLocked(config: TailscaleKit.Configuration) async throws", owner)
            for method, next_marker in (
                ("func bootstrap(metadata: ApplePrivateNetworkMetadata, authKey: String) async throws", "func resume()"),
                ("func resume() async throws", "private func startLocked(config:"),
                ("func stop() async throws", "func reset()"),
                ("func reset() async throws", "private func stopLocked()"),
            ):
                body = owner[owner.index(method):owner.index(next_marker, owner.index(method))]
                self.assertIn("await acquireLifecycle()", body)
                self.assertIn("defer { releaseLifecycle() }", body)
            self.assertIn("private func stopLocked() async throws", owner)
            self.assertIn("private enum ApplePrivateNetworkNodeOwnerError: Error", source)
            self.assertIn("case nodeAlreadyActive", source)
            self.assertIn("case startFailed", source)
            bootstrap = owner[owner.index("func bootstrap(metadata"):owner.index("func resume()")]
            self.assertLess(bootstrap.index("guard !stateStore.hasPersistedIdentity"), bootstrap.index("try stateStore.write(metadata: metadata)"))
            self.assertLess(bootstrap.index("try stateStore.write(metadata: metadata)"), bootstrap.index("try await startLocked"))
            self.assertLess(owner.index("guard activeNode == nil"), owner.index("activeNode = node"))
            self.assertLess(owner.index("activeNode = node"), owner.index("try await node.up()"))
            start = owner[owner.index("private func startLocked"):owner.index("func stop()")]
            self.assertIn("try await node.close()", start)
            self.assertLess(start.index("try await node.close()"), start.index("activeNode = nil"))
            self.assertLess(owner.index("try await activeNode.close()"), owner.index("self.activeNode = nil"))
            self.assertEqual(owner.count("activeNode = nil"), 2)
            reset = owner[owner.index("func reset() async throws"):owner.index("private func stopLocked()")]
            self.assertIn("try await stopLocked()", reset)
            self.assertNotIn("try await stop()", reset)
            self.assertLess(reset.index("try await stopLocked()"), reset.index("try stateStore.reset()"))
            self.assertIn("private_network_operation_failed", source)
            self.assertIn('"state": "stopped"', source)
            self.assertIn('"path": "none"', source)
            self.assertIn('"gatewayUrl": NSNull()', source)
            self.assertIn("for _ in 0 ..< 20", source)
            self.assertIn("Task.sleep(nanoseconds: 50_000_000)", source)
            self.assertIn("guard try await stateStore.waitForPersistedIdentity() else", bootstrap)
            self.assertIn("try await stopLocked()", bootstrap)

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

    def test_bootstrap_resume_use_non_secret_persisted_configuration(self) -> None:
        for path in HOSTS:
            source = private_network_source(path)
            bootstrap = source[source.index('case "bootstrap":'):source.index('case "resume":')]
            resume = source[source.index('case "resume":'):source.index("default:", source.index('case "resume":'))]
            self.assertIn("bootstrap(call.arguments, result: result)", bootstrap)
            self.assertIn("resume(result: result)", resume)
            self.assertIn("private struct ApplePrivateNetworkMetadata: Codable, Sendable", source)
            metadata = source[source.index("private struct ApplePrivateNetworkMetadata"):source.index("private enum ApplePrivateNetworkMetadataError")]
            for field in ("version", "controlUrl", "homeIpv4", "homePort", "nodeHostname"):
                self.assertIn(f"let {field}", metadata)
            self.assertNotIn("authKey", metadata)
            self.assertIn("TailscaleKitNodeFactory()", source)
            self.assertIn("authKey: bootstrap.authKey", source)
            self.assertIn("authKey: nil", source)
            self.assertGreaterEqual(source.count("ephemeral: false"), 1)
            self.assertIn("logFileHandle: Int32? = -1", source)
            sink = source[source.index("private struct RodPlayerTailscaleLogSink"):source.index("private struct TailscaleKitNodeFactory")]
            self.assertIn("func log(_ message: String) {}", sink)
            host_bootstrap = source[source.index("private func bootstrap"):source.index("private func resume")]
            host_resume = source[source.index("private func resume"):source.index("private static func operationFailed")]
            self.assertIn("result(Self.operationFailed())", host_bootstrap)
            self.assertIn("result(Self.operationFailed())", host_resume)
            self.assertNotIn("hasPersistedIdentity", host_bootstrap)
            self.assertNotIn("write(metadata", host_bootstrap)
            self.assertNotIn("nodeOwner.start", host_bootstrap)
            self.assertIn("try await nodeOwner.bootstrap", host_bootstrap)
            self.assertIn("try await nodeOwner.resume()", host_resume)
            self.assertIn("guard stateStore.hasPersistedIdentity else", source)
            self.assertIn('"state": "unavailable"', source)
            self.assertIn('"reason": "no_identity"', source)
            self.assertIn('"state": "stopped"', source)
            self.assertIn('"path": "none"', source)
            self.assertIn('"gatewayUrl": NSNull()', source)
            self.assertNotIn('"state": "ready"', source)
            self.assertNotIn('"path": "direct"', source)
            self.assertNotIn('"path": "relay"', source)
            self.assertNotIn(".down()", source)
            self.assertNotIn(".loopback()", source)
            self.assertNotIn(".statusJSON()", source)
            self.assertNotIn(".addrs()", source)
            self.assertNotIn(".dial(", source)
            self.assertIn("components.path.isEmpty || components.path == \"/\"", source)

    def test_only_adapter_touches_tailscale_node_lifecycle(self) -> None:
        for path in HOSTS:
            source = private_network_source(path)
            adapter = source[
                source.index("private final class TailscaleKitNodeAdapter"):
                source.index("private struct RodPlayerTailscaleLogSink")
            ]
            self.assertIn("try await node.up()", adapter)
            self.assertIn("try await node.close()", adapter)
            self.assertNotIn("TailscaleNode", source[:source.index("private final class TailscaleKitNodeAdapter")])
            self.assertNotRegex(source, r"hskey-auth-[A-Za-z0-9_-]{12}-[A-Za-z0-9_-]{64}")

    def test_apple_hosts_keep_identical_private_network_implementations(self) -> None:
        self.assertEqual(
            private_network_source(HOSTS[0]),
            private_network_source(HOSTS[1]),
        )


if __name__ == "__main__":
    unittest.main()
