#!/usr/bin/env python3
"""Static contract checks for the duplicated Apple D3 private-network host."""

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
HOSTS = (
    ROOT / "tool" / "native_hosts" / "ios" / "AppDelegate.swift",
    ROOT / "tool" / "native_hosts" / "macos" / "MainFlutterWindow.swift",
)
GATEWAY = ROOT / "tool" / "native_hosts" / "apple" / "AppleLoopbackGateway.swift"


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
            self.assertIn("func resume(claim: ApplePrivateNetworkIdentityClaim) async throws", owner)
            self.assertIn("private func startLocked(config: TailscaleKit.Configuration) async throws", owner)
            for method, next_marker in (
                ("func bootstrap(metadata: ApplePrivateNetworkMetadata, authKey: String) async throws", "func resume(claim:"),
                ("func resume(claim: ApplePrivateNetworkIdentityClaim) async throws", "private func startLocked(config:"),
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
            bootstrap = owner[owner.index("func bootstrap(metadata"):owner.index("func resume(claim:")]
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
            self.assertIn("resume(call.arguments, result: result)", resume)
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
            self.assertIn("try await nodeOwner.resume(claim: claim)", host_resume)
            self.assertIn("guard stateStore.hasPersistedIdentity else", source)
            self.assertIn('reason: "no_identity"', source)
            self.assertIn('static func ready(gatewayUrl: String)', source)
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

            sample = owner[
                owner.index("private func sampleStatus()"):owner.index("private func publish(")
            ]
            peer_guard = sample[
                sample.index("let homePeers"):sample.index("guard let currentAddress")
            ]
            self.assertIn("homePeers.count == 1", peer_guard)
            self.assertIn("peer.online", peer_guard)
            self.assertIn("peer.peerRelay?.isEmpty != false", peer_guard)
            self.assertNotIn("currentAddress", peer_guard)
            self.assertIn('reason: "direct_path_unavailable"', peer_guard)

            cur_addr_guard = sample[
                sample.index("guard let currentAddress"):sample.index(
                    'return .starting(path: "direct"'
                )
            ]
            self.assertIn("let currentAddress = peer.currentAddress", cur_addr_guard)
            self.assertIn("!currentAddress.isEmpty", cur_addr_guard)
            self.assertIn('return .starting(path: "none"', cur_addr_guard)
            self.assertNotIn('reason: "direct_path_unavailable"', cur_addr_guard)

    def test_status_failures_and_observers_remain_authoritative(self) -> None:
        for path in HOSTS:
            source = private_network_source(path)
            owner = source[source.index("actor ApplePrivateNetworkNodeOwner"):]
            resume = owner[owner.index("func resume(claim: ApplePrivateNetworkIdentityClaim) async throws"):owner.index("private func startLocked")]
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
                source.index("private func resume(_ arguments:"):
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

    def test_fixed_loopback_gateway_and_byte_stream_cleanup(self) -> None:
        gateway = GATEWAY.read_text()
        self.assertIn('"127.0.0.1".withCString', gateway)
        self.assertIn("address.sin_port = 0", gateway)
        self.assertIn("Darwin.bind(fd, $0, length)", gateway)
        self.assertIn("Darwin.listen(fd, 16)", gateway)
        self.assertIn("flags | O_NONBLOCK", gateway)
        self.assertIn("clientFlags & ~O_NONBLOCK", gateway)
        self.assertIn('baseURL = "http://127.0.0.1:', gateway)
        self.assertNotIn('"0.0.0.0"', gateway)
        self.assertNotIn('"::1"', gateway)
        self.assertIn('destination = "\\(metadata.homeIpv4):\\(metadata.homePort)"', gateway)
        self.assertIn("node.dialTCP(destination)", gateway)
        self.assertNotIn("CONNECT", gateway)
        self.assertNotIn("SOCKS", gateway)
        self.assertIn("connections.count < 32", gateway)
        self.assertIn("SO_NOSIGPIPE", gateway)
        self.assertIn("Darwin.read(source", gateway)
        self.assertIn("Darwin.write(destination", gateway)
        self.assertIn("while offset < received", gateway)
        self.assertIn("if errno == EINTR", gateway)
        self.assertIn("SHUT_WR", gateway)
        self.assertIn("pumps.wait()", gateway)
        self.assertIn("func close()", gateway)
        self.assertIn("deinit { close() }", gateway)
        close = gateway[gateway.index("  func close() {"):gateway.index("  func drain() async {")]
        accept = gateway[gateway.index("  private func acceptLoop() {"):gateway.index("  private func removeConnection(")]
        self.assertIn("closing = true", close)
        self.assertIn("connection.cancel()", close)
        self.assertNotIn("Darwin.close(", close)
        self.assertIn("if shouldStop { return }", accept)
        self.assertIn("Darwin.close(ownedFD)", accept)
        self.assertIn("acceptGroup.leave()", accept)
        self.assertIn("workers.enter()", accept)
        self.assertIn("if removed != nil { workers.leave() }", gateway)
        self.assertIn("acceptGroup.notify", gateway)
        self.assertIn("self.workers.notify", gateway)

    def test_generation_appends_same_gateway_to_both_apple_hosts(self) -> None:
        spec = importlib.util.spec_from_file_location("apply_native_hosts", ROOT / "tool" / "apply_native_hosts.py")
        assert spec and spec.loader
        generator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(generator)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with patch.object(generator, "ROOT", root):
                for platform, name in (("ios", "AppDelegate.swift"), ("macos", "MainFlutterWindow.swift")):
                    target = root / platform / "Runner" / name
                    target.parent.mkdir(parents=True)
                    target.write_text("// generated host\n")
                    generator.append_apple_gateway(f"{platform}/Runner/{name}")
                    self.assertEqual(target.read_text(), "// generated host\n\n" + GATEWAY.read_text())
        generator_source = (ROOT / "tool" / "apply_native_hosts.py").read_text()
        self.assertIn('append_apple_gateway("ios/Runner/AppDelegate.swift")', generator_source)
        self.assertIn('append_apple_gateway("macos/Runner/MainFlutterWindow.swift")', generator_source)

    def test_ready_requires_current_direct_peer_and_lifecycle_owned_listener(self) -> None:
        for path in HOSTS:
            source = private_network_source(path)
            owner = source[source.index("actor ApplePrivateNetworkNodeOwner"):]
            status = source[source.index("private struct ApplePrivateNetworkStatus"):source.index("private struct ApplePrivateNetworkStateStore")]
            self.assertIn("let gatewayUrl: String?", status)
            self.assertIn('state: "ready", path: "direct", hasPersistedIdentity: true, reason: "none"', status)
            self.assertIn('"gatewayUrl": gatewayUrl.map { $0 as Any } ?? NSNull()', status)
            self.assertIn("private var gateway: AppleLoopbackGateway?", owner)
            self.assertIn("gateway = try AppleLoopbackGateway(node: activeNode, metadata: metadata)", owner)
            stop = owner[owner.index("private func stopLocked()"):owner.index("private func startMonitorLocked()")]
            self.assertLess(stop.index("retiringGateway?.close()"), stop.index("try await activeNode.close()"))
            self.assertLess(stop.index("try await activeNode.close()"), stop.index("await retiringGateway?.drain()", stop.index("try await activeNode.close()")))
            self.assertLess(stop.index("await retiringGateway?.drain()", stop.index("try await activeNode.close()")), stop.index("self.activeNode = nil"))
            self.assertIn("await retiringWarmup?.value", stop)
            self.assertIn('publish(.starting(path: "none"', stop)
            reset = owner[owner.index("func reset() async throws"):owner.index("private func stopLocked()")]
            self.assertLess(reset.index("try await stopLocked()"), reset.index("try stateStore.reset()"))
            sample = owner[owner.index("private func sampleStatus()"):owner.index("private func startWarmupIfNeeded")]
            self.assertLess(sample.index('backend.backendState == "Running"'), sample.index("homePeers.count == 1"))
            self.assertLess(sample.index("peer.peerRelay?.isEmpty != false"), sample.index("guard let currentAddress"))
            self.assertLess(sample.index("!currentAddress.isEmpty"), sample.index("verifiedAddress == currentAddress"))
            self.assertLess(sample.index("verifiedAddress == currentAddress"), sample.index("gateway.isListening"))
            self.assertIn("if warmupSucceeded { verifiedAddress = currentAddress }", sample)
            self.assertIn("startWarmupIfNeeded(node: activeNode, metadata: metadata)", sample)
            self.assertIn("invalidateUpstreamVerification()", sample)
            self.assertIn("if lastDirectAddress != currentAddress", sample)
            self.assertIn('return .starting(path: "none"', sample)
            self.assertIn('return .starting(path: "direct"', sample)
            self.assertIn("stateStore.hasPersistedIdentity, let gateway, gateway.isListening", sample)
            self.assertIn("return .ready(gatewayUrl: gateway.baseURL)", sample)
            self.assertIn('reason: "direct_path_unavailable"', sample)
            self.assertIn('reason: "transport_failure"', sample)
            warmup = owner[owner.index("private func startWarmupIfNeeded"):owner.index("private func publish(")]
            self.assertIn("guard !stopping, warmupTask == nil", warmup)
            self.assertIn('let destination = "\\(metadata.homeIpv4):\\(metadata.homePort)"', warmup)
            self.assertIn("Task.detached(priority: .utility)", warmup)
            self.assertIn("Darwin.close(connection)", warmup)
            self.assertIn("succeeded: connection != nil && !Task.isCancelled", warmup)
            self.assertIn("guard !stopping, generation == warmupGeneration else { return }", warmup)
            self.assertIn("warmupSucceeded = succeeded", warmup)
            invalidate = sample[sample.index("private func invalidateUpstreamVerification()"):]
            for cleared in ("lastDirectAddress = nil", "verifiedAddress = nil", "warmupSucceeded = false"):
                self.assertIn(cleared, invalidate)
            self.assertIn("warmupGeneration += 1", owner)
            self.assertIn("warmupTask?.cancel()", owner)
            self.assertIn("directOnlyData: true", owner)
            adapter = source[source.index("private final class TailscaleKitNodeAdapter"):source.index("private struct AppleTsnetStatus")]
            self.assertIn("guard let handle = await node.tailscale", adapter)
            self.assertEqual(adapter.count("node.tailscale"), 1)
            self.assertIn("try cacheHandle(handle)", adapter)
            self.assertIn("private var cachedHandle: Int32?", adapter)
            self.assertIn("guard !closing, let handle = cachedHandle", adapter)
            self.assertIn("inFlightDials.enter()", adapter)
            self.assertIn("defer { inFlightDials.leave() }", adapter)
            self.assertLess(adapter.index("beginClosing()"), adapter.index("try await node.close()"))
            self.assertLess(adapter.index("try await node.close()"), adapter.index("inFlightDials.notify"))
            self.assertIn('tailscale_dial(handle, "tcp", destination, &connection)', adapter)
            self.assertNotIn(".loopback()", source)

    def test_apple_hosts_keep_identical_private_network_implementations(self) -> None:
        self.assertEqual(
            private_network_source(HOSTS[0]),
            private_network_source(HOSTS[1]),
        )

    def test_retained_identity_is_bound_before_node_start(self) -> None:
        for path in HOSTS:
            source = private_network_source(path)
            owner = source[source.index("actor ApplePrivateNetworkNodeOwner"):]
            resume = owner[owner.index("func resume(claim:"):owner.index("private func startGatewayLocked")]
            self.assertLess(resume.index("let metadata = try retained.claimed(by: claim)"),
                            resume.index("try await startLocked"))
            self.assertIn("_ = try activeMetadata.claimed(by: claim)", resume)
            self.assertIn("if retained.version == 1 { try stateStore.write(metadata: metadata) }", resume)
            metadata = source[source.index("private struct ApplePrivateNetworkMetadata: Codab"):
                              source.index("private enum ApplePrivateNetworkMetadataError")]
            self.assertIn("let profileId: String?", metadata)
            self.assertIn("version == 1 && profileId == nil", metadata)
            self.assertIn("version == 2 && profileId.map(ApplePrivateNetworkValidation.isProfileId) == true", metadata)
            claim = metadata[metadata.index("func claimed(by claim:"):]
            self.assertIn("ApplePrivateNetworkValidation.sameControlEndpoint(controlUrl, claim.controlUrl)", claim)
            self.assertNotIn("controlUrl == claim.controlUrl", claim)
            validation = source[source.index("private enum ApplePrivateNetworkValidation"):]
            comparison = validation[validation.index("static func sameControlEndpoint"):
                                    validation.index("static func isProfileId")]
            self.assertIn("isControlUrl(left), isControlUrl(right)", comparison)
            self.assertIn("lhsHost.caseInsensitiveCompare(rhsHost) == .orderedSame", comparison)
            self.assertIn("(lhs.port ?? 443) == (rhs.port ?? 443)", comparison)
            self.assertIn("components.path.isEmpty || components.path == \"/\"", validation)
            for field in ("homeIpv4", "homePort"):
                self.assertIn(f"{field} == claim.{field}", claim)
            self.assertIn("profileId == claim.profileId : claim.allowLegacyClaim", claim)
            self.assertIn("if version == 2 { return self }", claim)
            self.assertIn("nodeHostname: nodeHostname", claim)
            self.assertNotIn("stateStore.reset()", resume)
            host_resume = source[source.index("private func resume(_ arguments:"):
                                 source.index("private static func operationFailed")]
            self.assertLess(host_resume.index("ApplePrivateNetworkIdentityClaim(arguments:"),
                            host_resume.index("nodeOwner.resume(claim:"))
            self.assertNotIn("authKey", metadata)


if __name__ == "__main__":
    unittest.main()
