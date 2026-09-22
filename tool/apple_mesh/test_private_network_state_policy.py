#!/usr/bin/env python3
"""Static contract checks for the duplicated Apple D3 private-network host."""

import re
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


def without_p5e_live_proof_diagnostics(source: str) -> str:
    return re.sub(
        r"\n?\s*// P5E_LIVE_PROOF_DIAGNOSTIC_BEGIN.*?// P5E_LIVE_PROOF_DIAGNOSTIC_END\n?",
        "\n",
        source,
        flags=re.DOTALL,
    )


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
            self.assertIn("status(result: result)", status)
            self.assertIn("private func status(result:", source)
            self.assertIn("await nodeOwner.currentStatus()", source)
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
            self.assertIn('reason: "no_identity"', source)
            self.assertNotIn('"state": "ready"', source)
            self.assertNotIn('"path": "relay"', source)
            self.assertNotIn(".down()", source)
            self.assertNotIn(".loopback()", source)
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
            self.assertIn("try await node.statusJSON()", adapter)
            self.assertNotIn("TailscaleNode", source[:source.index("private final class TailscaleKitNodeAdapter")])
            self.assertNotRegex(source, r"hskey-auth-[A-Za-z0-9_-]{12}-[A-Za-z0-9_-]{64}")

    def test_status_monitor_is_direct_only_and_lifecycle_owned(self) -> None:
        for path in HOSTS:
            source = private_network_source(path)
            owner = source[source.index("actor ApplePrivateNetworkNodeOwner"):]
            self.assertIn("func statusJSON() async throws -> Data", source)
            self.assertIn("private struct AppleTsnetStatus: Decodable", source)
            self.assertIn('case backendState = "BackendState"', source)
            self.assertIn('case peer = "Peer"', source)
            for field in ("TailscaleIPs", "Online", "CurAddr", "PeerRelay"):
                self.assertIn(f'"{field}"', source)
            self.assertIn("$0.tailscaleIPs.contains(metadata.homeIpv4)", owner)
            self.assertIn('backend.backendState == "Running"', owner)
            self.assertIn("peer.online", owner)
            self.assertIn("let currentAddress = peer.currentAddress", owner)
            self.assertIn("!currentAddress.isEmpty", owner)
            self.assertIn("peer.peerRelay?.isEmpty != false", owner)
            self.assertIn('return .starting(path: "direct"', owner)
            self.assertIn('reason: "direct_path_unavailable"', owner)
            self.assertIn('reason: "transport_failure"', owner)
            self.assertIn("private var monitorTask: Task<Void, Never>?", owner)
            self.assertIn("private func startMonitorLocked()", owner)
            self.assertIn("private func stopMonitorLocked()", owner)
            self.assertIn("Task.sleep(nanoseconds: 1_000_000_000)", owner)
            self.assertIn("guard cachedStatus != status else { return }", owner)
            stop = owner[owner.index("func stop() async throws"):owner.index("func reset()")]
            reset = owner[owner.index("func reset() async throws"):owner.index("private func stopLocked()")]
            self.assertLess(stop.index("await stopMonitorLocked()"), stop.index("try await stopLocked()"))
            self.assertLess(reset.index("await stopMonitorLocked()"), reset.index("try await stopLocked()"))
            self.assertIn("return await startMonitorLocked()", owner)
            self.assertIn("func onListen", source)
            self.assertNotIn("startMonitorLocked()", source[source.index("func onListen"):source.index("func onCancel")])

    def test_status_failures_and_observers_remain_authoritative(self) -> None:
        for path in HOSTS:
            source = private_network_source(path)
            owner = source[source.index("actor ApplePrivateNetworkNodeOwner"):]
            resume = owner[owner.index("func resume() async throws"):owner.index("private func startLocked")]
            self.assertLess(
                resume.index('publish(.unavailable(reason: "no_identity"'),
                resume.index("throw ApplePrivateNetworkNodeOwnerError.noIdentity"),
            )
            observer = owner[
                owner.index("func setStatusObserver"):
                owner.index("func currentStatus()")
            ]
            self.assertLess(
                observer.index("statusObserver = observer"),
                observer.index("observer(cachedStatus)"),
            )
            host_resume = source[
                source.index("private func resume(result:"):
                source.index("private static func operationFailed")
            ]
            no_identity = host_resume[
                host_resume.index("catch ApplePrivateNetworkNodeOwnerError.noIdentity"):
                host_resume.index("catch {", host_resume.index("catch ApplePrivateNetworkNodeOwnerError.noIdentity"))
            ]
            self.assertIn("await nodeOwner.currentStatus()", no_identity)
            self.assertIn("result(status.payload)", no_identity)
            self.assertNotIn("noIdentityPayload", source)

            stop = owner[owner.index("func stop() async throws"):owner.index("func reset()")]
            reset = owner[owner.index("func reset() async throws"):owner.index("private func stopLocked()")]
            for operation in (stop, reset):
                self.assertIn("await stopMonitorLocked()", operation)
                self.assertIn("catch {", operation)
                self.assertIn('publish(.unavailable(reason: "transport_failure"', operation)
                self.assertIn("throw error", operation)
            self.assertLess(
                reset.index('publish(.unavailable(reason: "transport_failure"'),
                reset.index("try stateStore.reset()"),
            )
            stop_locked = owner[
                owner.index("private func stopLocked()"):
                owner.index("private func startMonitorLocked()")
            ]
            self.assertLess(
                stop_locked.index("try await activeNode.close()"),
                stop_locked.index("self.activeNode = nil"),
            )
            monitor = owner[
                owner.index("private func startMonitorLocked()"):
                owner.index("private func stopMonitorLocked()")
            ]
            self.assertIn("guard !Task.isCancelled, let self else { return }", monitor)

    def test_relay_is_not_a_directness_input(self) -> None:
        for path in HOSTS:
            source = private_network_source(path)
            status = source[source.index("private struct AppleTsnetStatus"):source.index("private struct RodPlayerTailscaleLogSink")]
            self.assertIn('case peerRelay = "PeerRelay"', status)
            self.assertNotIn('case relay = "Relay"', status)
            self.assertNotIn('"Relay"', status)

    def test_macos_live_proof_diagnostic_is_allowlisted(self) -> None:
        source = private_network_source(HOSTS[1])
        blocks = re.findall(
            r"// P5E_LIVE_PROOF_DIAGNOSTIC_BEGIN(.*?)// P5E_LIVE_PROOF_DIAGNOSTIC_END",
            source,
            flags=re.DOTALL,
        )
        self.assertEqual(len(blocks), 4)
        diagnostic = "\n".join(blocks)
        self.assertIn('case "p5eDebugStatus"', diagnostic)
        self.assertIn("activeNode.statusJSON()", diagnostic)
        for field in (
            "backendState",
            "totalPeerCount",
            "homePeerMatchCount",
            "homePeerOnline",
            "homePeerHasCurAddr",
            "homePeerHasPeerRelay",
            "persistedIdentity",
        ):
            self.assertIn(f'"{field}"', diagnostic)
        for forbidden in (
            "gatewayUrl",
            "controlUrl",
            "authKey",
            "tailscaleIPs:",
            "currentAddress:",
            "peerRelay:",
        ):
            self.assertNotIn(forbidden, diagnostic)

    def test_apple_hosts_keep_identical_private_network_implementations(self) -> None:
        self.assertEqual(
            private_network_source(HOSTS[0]),
            without_p5e_live_proof_diagnostics(private_network_source(HOSTS[1])),
        )


if __name__ == "__main__":
    unittest.main()
