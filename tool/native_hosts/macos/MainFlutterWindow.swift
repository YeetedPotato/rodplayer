import Cocoa
import AVFoundation
import CoreAudio
import Darwin
import Foundation
import FlutterMacOS
import VideoToolbox
import VLCKit
import TailscaleKit

class MainFlutterWindow: NSWindow, FlutterStreamHandler {
  private var events: FlutterEventSink?
  private let applePlayback = ApplePlaybackManager()
  private let compatibilityPlayback = AppleCompatibilityPlaybackManager()
  private let privateNetwork = PrivateNetworkHost()
  private let tailscaleKitLinkProof: TailscaleNode.Type = TailscaleNode.self

  override func awakeFromNib() {
    _ = tailscaleKitLinkProof
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let messenger = flutterViewController.engine.binaryMessenger
    FlutterMethodChannel(name: "rodplayer/playback_capabilities", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "ping": result(true)
        case "probeCompute": result(self.probeCompute())
        case "probeDisplay": result(self.probeDisplay())
        case "probeAudio": result(self.probeAudio())
        default: result(FlutterMethodNotImplemented)
        }
      }
    FlutterEventChannel(name: "rodplayer/playback_capability_events", binaryMessenger: messenger)
      .setStreamHandler(self)
    FlutterMethodChannel(name: "rodplayer/private_network", binaryMessenger: messenger)
      .setMethodCallHandler(privateNetwork.handle)
    FlutterEventChannel(name: "rodplayer/private_network_events", binaryMessenger: messenger)
      .setStreamHandler(privateNetwork)
    FlutterMethodChannel(name: "rodplayer/apple_playback", binaryMessenger: messenger)
      .setMethodCallHandler(applePlayback.handle)
    FlutterEventChannel(name: "rodplayer/apple_playback_events", binaryMessenger: messenger)
      .setStreamHandler(applePlayback)
    flutterViewController.registrar(forPlugin: "RodPlayerApplePlayback")
      .register(ApplePlaybackViewFactory(manager: applePlayback), withId: "rodplayer/apple_playback_view")
    FlutterMethodChannel(name: "rodplayer/apple_compatibility_playback", binaryMessenger: messenger)
      .setMethodCallHandler(compatibilityPlayback.handle)
    FlutterEventChannel(name: "rodplayer/apple_compatibility_playback_events", binaryMessenger: messenger)
      .setStreamHandler(compatibilityPlayback)
    flutterViewController.registrar(forPlugin: "RodPlayerAppleCompatibilityPlayback")
      .register(AppleCompatibilityPlaybackViewFactory(manager: compatibilityPlayback), withId: "rodplayer/apple_compatibility_playback_view")

    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }

  func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
    events = eventSink
    NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(appActive), name: NSApplication.didBecomeActiveNotification, object: nil)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
    NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
    events = nil
    return nil
  }

  @objc private func displayChanged() { events?("displayChanged") }
  @objc private func appActive() { events?("resume") }

  private func probeCompute() -> [String: Any] {
    var decoders: [[String: Any]] = []
    if VTIsHardwareDecodeSupported(kCMVideoCodecType_H264) {
      decoders.append(["codec": "h264", "support": "supported", "hardwareAccelerated": "supported"])
    }
    if VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) {
      decoders.append(["codec": "hevc", "support": "supported", "hardwareAccelerated": "supported"])
    }
    return [
      "hardwareVideoDecoding": decoders.isEmpty ? "unknown" : "supported",
      "videoDecoders": decoders,
    ]
  }

  private func probeDisplay() -> [String: Any] {
    guard let screen = NSScreen.main else { return [:] }
    let frame = screen.frame
    let displayId = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    let mode = displayId == nil ? nil : CGDisplayCopyDisplayMode(displayId!)
    var payload: [String: Any] = [
      "width": Int(frame.width * screen.backingScaleFactor),
      "height": Int(frame.height * screen.backingScaleFactor),
      "pixelRatio": screen.backingScaleFactor,
      "refreshRate": mode?.refreshRate ?? 0,
      "displayName": screen.localizedName,
      "genericHdrOutput": screen.maximumExtendedDynamicRangeColorComponentValue > 1.0 ? "supported" : "unknown",
    ]
    if let displayId = displayId { payload["displayId"] = "\(displayId)" }
    return payload
  }

  private func probeAudio() -> [String: Any] {
    var deviceId = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceId) == noErr else {
      return [:]
    }
    return [
      "routeName": audioString(deviceId, kAudioObjectPropertyName) as Any,
      "sinkName": audioString(deviceId, kAudioObjectPropertyName) as Any,
      "pcmOutput": "supported",
      "sampleRates": sampleRate(deviceId).map { [Int($0)] } ?? [],
    ]
  }

  private func audioString(_ deviceId: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(deviceId, &address, 0, nil, &size, &value) == noErr else { return nil }
    return value as String
  }

  private func sampleRate(_ deviceId: AudioDeviceID) -> Double? {
    var value = Float64(0)
    var size = UInt32(MemoryLayout<Float64>.size)
    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(deviceId, &address, 0, nil, &size, &value) == noErr else { return nil }
    return value
  }
}

private final class PrivateNetworkHost: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private let stateStore: ApplePrivateNetworkStateStore?
  private let nodeOwner: ApplePrivateNetworkNodeOwner?
  private var cachedStatus: ApplePrivateNetworkStatus

  override init() {
    do {
      let stateStore = try ApplePrivateNetworkStateStore()
      try stateStore.prepare()
      self.stateStore = stateStore
      nodeOwner = ApplePrivateNetworkNodeOwner(stateStore: stateStore)
      cachedStatus = .stopped(hasPersistedIdentity: stateStore.hasPersistedIdentity)
    } catch {
      stateStore = nil
      nodeOwner = nil
      cachedStatus = .stopped(hasPersistedIdentity: false)
    }
    super.init()
    if let nodeOwner {
      Task { [weak self, nodeOwner] in
        await nodeOwner.setStatusObserver { [weak self] status in
          Task { @MainActor [weak self] in self?.receiveStatus(status) }
        }
      }
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ping":
      result(true)
    case "status":
      status(result: result)
    case "stop":
      stop(result: result)
    case "reset":
      reset(result: result)
    case "bootstrap":
      bootstrap(call.arguments, result: result)
    case "resume":
      resume(call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = eventSink
    guard stateStore != nil else {
      eventSink(Self.operationFailed())
      return nil
    }
    emitStatus()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func emitStatus() {
    guard stateStore != nil else {
      eventSink?(Self.operationFailed())
      return
    }
    eventSink?(cachedStatus.payload)
  }

  private func receiveStatus(_ status: ApplePrivateNetworkStatus) {
    guard cachedStatus != status else { return }
    cachedStatus = status
    eventSink?(status.payload)
  }

  private func status(result: @escaping FlutterResult) {
    guard let nodeOwner else {
      result(Self.operationFailed())
      return
    }
    Task { @MainActor [weak self] in
      let status = await nodeOwner.currentStatus()
      self?.receiveStatus(status)
      result(status.payload)
    }
  }

  private func stop(result: @escaping FlutterResult) {
    guard let nodeOwner else {
      result(Self.operationFailed())
      return
    }
    Task { @MainActor [weak self] in
      do {
        try await nodeOwner.stop()
        self?.receiveStatus(await nodeOwner.currentStatus())
        result(nil)
      } catch {
        result(Self.operationFailed())
      }
    }
  }

  private func reset(result: @escaping FlutterResult) {
    guard let nodeOwner else {
      result(Self.operationFailed())
      return
    }
    Task { @MainActor [weak self] in
      do {
        try await nodeOwner.reset()
        self?.receiveStatus(await nodeOwner.currentStatus())
        result(nil)
      } catch {
        result(Self.operationFailed())
      }
    }
  }

  private func bootstrap(_ arguments: Any?, result: @escaping FlutterResult) {
    Task { @MainActor [weak self] in
      guard let self, self.stateStore != nil, let nodeOwner = self.nodeOwner else {
        result(Self.operationFailed())
        return
      }
      do {
        let bootstrap = try ApplePrivateNetworkBootstrap(arguments: arguments)
        let metadata = ApplePrivateNetworkMetadata.from(bootstrap: bootstrap)
        let status = try await nodeOwner.bootstrap(metadata: metadata, authKey: bootstrap.authKey)
        receiveStatus(status)
        result(status.payload)
      } catch {
        result(Self.operationFailed())
      }
    }
  }

  private func resume(_ arguments: Any?, result: @escaping FlutterResult) {
    Task { @MainActor [weak self] in
      guard let self, self.stateStore != nil, let nodeOwner = self.nodeOwner else {
        result(Self.operationFailed())
        return
      }
      do {
        let claim = try ApplePrivateNetworkIdentityClaim(arguments: arguments)
        let status = try await nodeOwner.resume(claim: claim)
        receiveStatus(status)
        result(status.payload)
      } catch ApplePrivateNetworkNodeOwnerError.noIdentity {
        let status = await nodeOwner.currentStatus()
        receiveStatus(status)
        result(status.payload)
      } catch {
        result(Self.operationFailed())
      }
    }
  }

  private static func operationFailed() -> FlutterError {
    FlutterError(code: "private_network_operation_failed", message: nil, details: nil)
  }

}

private struct ApplePrivateNetworkStatus: Equatable, Sendable {
  let state: String
  let path: String
  let hasPersistedIdentity: Bool
  let reason: String
  let gatewayUrl: String?

  init(state: String, path: String, hasPersistedIdentity: Bool, reason: String, gatewayUrl: String? = nil) {
    self.state = state
    self.path = path
    self.hasPersistedIdentity = hasPersistedIdentity
    self.reason = reason
    self.gatewayUrl = gatewayUrl
  }

  static func stopped(hasPersistedIdentity: Bool) -> ApplePrivateNetworkStatus {
    ApplePrivateNetworkStatus(state: "stopped", path: "none", hasPersistedIdentity: hasPersistedIdentity, reason: "none")
  }

  static func starting(path: String, hasPersistedIdentity: Bool) -> ApplePrivateNetworkStatus {
    ApplePrivateNetworkStatus(state: "starting", path: path, hasPersistedIdentity: hasPersistedIdentity, reason: "none")
  }

  static func unavailable(reason: String, hasPersistedIdentity: Bool) -> ApplePrivateNetworkStatus {
    ApplePrivateNetworkStatus(state: "unavailable", path: "none", hasPersistedIdentity: hasPersistedIdentity, reason: reason)
  }

  static func ready(gatewayUrl: String) -> ApplePrivateNetworkStatus {
    ApplePrivateNetworkStatus(state: "ready", path: "direct", hasPersistedIdentity: true, reason: "none", gatewayUrl: gatewayUrl)
  }

  var payload: [String: Any] {
    [
      "state": state,
      "path": path,
      "hasPersistedIdentity": hasPersistedIdentity,
      "reason": reason,
      "gatewayUrl": gatewayUrl.map { $0 as Any } ?? NSNull(),
    ]
  }
}

private struct ApplePrivateNetworkStateStore: Sendable {
  let privateNetworkRoot: URL
  let nodeStateDirectory: URL
  let tailscaledState: URL
  let metadataFile: URL

  init(fileManager: FileManager = .default) throws {
    let applicationSupport = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    privateNetworkRoot = applicationSupport
      .appendingPathComponent("RodPlayer", isDirectory: true)
      .appendingPathComponent("PrivateNetwork", isDirectory: true)
    nodeStateDirectory = privateNetworkRoot.appendingPathComponent("node", isDirectory: true)
    tailscaledState = nodeStateDirectory.appendingPathComponent("tailscaled.state", isDirectory: false)
    metadataFile = privateNetworkRoot.appendingPathComponent("metadata.json", isDirectory: false)
  }

  func prepare(fileManager: FileManager = .default) throws {
    try fileManager.createDirectory(at: nodeStateDirectory, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var root = privateNetworkRoot
    try root.setResourceValues(values)
  }

  var hasPersistedIdentity: Bool {
    FileManager.default.fileExists(atPath: tailscaledState.path)
  }

  func write(metadata: ApplePrivateNetworkMetadata) throws {
    try JSONEncoder().encode(metadata).write(to: metadataFile, options: .atomic)
  }

  func loadMetadata() throws -> ApplePrivateNetworkMetadata {
    try ApplePrivateNetworkMetadata.decodeAndValidate(from: Data(contentsOf: metadataFile))
  }

  func waitForPersistedIdentity() async throws -> Bool {
    if hasPersistedIdentity { return true }
    for _ in 0 ..< 20 {
      try await Task.sleep(nanoseconds: 50_000_000)
      if hasPersistedIdentity { return true }
    }
    return false
  }

  func reset(fileManager: FileManager = .default) throws {
    guard fileManager.fileExists(atPath: privateNetworkRoot.path) else { return }
    try fileManager.removeItem(at: privateNetworkRoot)
  }
}

private protocol ApplePrivateNetworkNode: AnyObject, Sendable {
  func up() async throws
  func close() async throws
  func statusJSON() async throws -> Data
  func dialTCP(_ destination: String) throws -> Int32
}

private protocol ApplePrivateNetworkNodeFactory: Sendable {
  func make(config: TailscaleKit.Configuration) throws -> any ApplePrivateNetworkNode
}

private enum ApplePrivateNetworkNodeOwnerError: Error {
  case nodeAlreadyActive
  case existingIdentity
  case noIdentity
  case startFailed
}

private actor ApplePrivateNetworkNodeOwner {
  private let stateStore: ApplePrivateNetworkStateStore
  private let factory: any ApplePrivateNetworkNodeFactory
  private var activeNode: (any ApplePrivateNetworkNode)?
  private var activeMetadata: ApplePrivateNetworkMetadata?
  private var gateway: AppleLoopbackGateway?
  private var cachedStatus: ApplePrivateNetworkStatus
  private var statusObserver: (@Sendable (ApplePrivateNetworkStatus) -> Void)?
  private var monitorTask: Task<Void, Never>?
  private var warmupTask: Task<Void, Never>?
  private var warmupGeneration = 0
  private var lastDirectAddress: String?
  private var verifiedAddress: String?
  private var warmupSucceeded = false
  private var nextWarmupAt = Date.distantPast
  private var stopping = false
  private var lifecycleLocked = false
  private var lifecycleWaiters: [CheckedContinuation<Void, Never>] = []

  init(
    stateStore: ApplePrivateNetworkStateStore,
    factory: any ApplePrivateNetworkNodeFactory = TailscaleKitNodeFactory()
  ) {
    self.stateStore = stateStore
    self.factory = factory
    cachedStatus = .stopped(hasPersistedIdentity: stateStore.hasPersistedIdentity)
  }

  func setStatusObserver(_ observer: @escaping @Sendable (ApplePrivateNetworkStatus) -> Void) {
    statusObserver = observer
    observer(cachedStatus)
  }

  func currentStatus() -> ApplePrivateNetworkStatus { cachedStatus }

  func bootstrap(metadata: ApplePrivateNetworkMetadata, authKey: String) async throws -> ApplePrivateNetworkStatus {
    await acquireLifecycle()
    defer { releaseLifecycle() }
    guard activeNode == nil else {
      throw ApplePrivateNetworkNodeOwnerError.nodeAlreadyActive
    }
    guard !stateStore.hasPersistedIdentity else {
      throw ApplePrivateNetworkNodeOwnerError.existingIdentity
    }
    try stateStore.prepare()
    try stateStore.write(metadata: metadata)
    try await startLocked(config: configuration(metadata: metadata, authKey: authKey))
    guard try await stateStore.waitForPersistedIdentity() else {
      try await stopLocked()
      throw ApplePrivateNetworkNodeOwnerError.startFailed
    }
    activeMetadata = metadata
    do {
      try startGatewayLocked(metadata: metadata)
    } catch {
      try? await stopLocked()
      throw ApplePrivateNetworkNodeOwnerError.startFailed
    }
    return await startMonitorLocked()
  }

  func resume(claim: ApplePrivateNetworkIdentityClaim) async throws -> ApplePrivateNetworkStatus {
    await acquireLifecycle()
    defer { releaseLifecycle() }
    if activeNode != nil {
      guard let activeMetadata else { throw ApplePrivateNetworkMetadataError.invalid }
      _ = try activeMetadata.claimed(by: claim)
      return cachedStatus
    }
    guard stateStore.hasPersistedIdentity else {
      publish(.unavailable(reason: "no_identity", hasPersistedIdentity: false))
      throw ApplePrivateNetworkNodeOwnerError.noIdentity
    }
    try stateStore.prepare()
    let retained = try stateStore.loadMetadata()
    let metadata = try retained.claimed(by: claim)
    if retained.version == 1 { try stateStore.write(metadata: metadata) }
    try await startLocked(config: configuration(metadata: metadata, authKey: nil))
    activeMetadata = metadata
    do {
      try startGatewayLocked(metadata: metadata)
    } catch {
      try? await stopLocked()
      throw ApplePrivateNetworkNodeOwnerError.startFailed
    }
    return await startMonitorLocked()
  }

  private func startGatewayLocked(metadata: ApplePrivateNetworkMetadata) throws {
    guard let activeNode else { throw ApplePrivateNetworkNodeOwnerError.startFailed }
    gateway = try AppleLoopbackGateway(node: activeNode, metadata: metadata)
  }

  private func startLocked(config: TailscaleKit.Configuration) async throws {
    let node: any ApplePrivateNetworkNode
    do {
      node = try factory.make(config: config)
    } catch {
      throw ApplePrivateNetworkNodeOwnerError.startFailed
    }
    activeNode = node
    do {
      try await node.up()
    } catch {
      do {
        try await node.close()
        activeNode = nil
      } catch {
        // Retain ownership when cleanup fails; reset must not delete its state.
      }
      throw ApplePrivateNetworkNodeOwnerError.startFailed
    }
  }

  private func configuration(
    metadata: ApplePrivateNetworkMetadata,
    authKey: String?
  ) -> TailscaleKit.Configuration {
    TailscaleKit.Configuration(
      hostName: metadata.nodeHostname,
      path: stateStore.nodeStateDirectory.path,
      authKey: authKey,
      controlURL: metadata.controlUrl,
      ephemeral: false,
      directOnlyData: true
    )
  }

  func stop() async throws {
    await acquireLifecycle()
    defer { releaseLifecycle() }
    await stopMonitorLocked()
    do {
      try await stopLocked()
    } catch {
      publish(.unavailable(reason: "transport_failure", hasPersistedIdentity: stateStore.hasPersistedIdentity))
      throw error
    }
    publish(.stopped(hasPersistedIdentity: stateStore.hasPersistedIdentity))
  }

  func reset() async throws {
    await acquireLifecycle()
    defer { releaseLifecycle() }
    await stopMonitorLocked()
    do {
      try await stopLocked()
    } catch {
      publish(.unavailable(reason: "transport_failure", hasPersistedIdentity: stateStore.hasPersistedIdentity))
      throw error
    }
    try stateStore.reset()
    publish(.stopped(hasPersistedIdentity: false))
  }

  private func stopLocked() async throws {
    stopping = true
    warmupGeneration += 1
    warmupTask?.cancel()
    let retiringWarmup = warmupTask
    let retiringGateway = gateway
    retiringGateway?.close()
    publish(.starting(path: "none", hasPersistedIdentity: stateStore.hasPersistedIdentity))
    guard let activeNode else {
      await retiringGateway?.drain()
      await retiringWarmup?.value
      gateway = nil
      warmupTask = nil
      stopping = false
      return
    }
    try await activeNode.close()
    await retiringGateway?.drain()
    await retiringWarmup?.value
    gateway = nil
    warmupTask = nil
    self.activeNode = nil
    activeMetadata = nil
    lastDirectAddress = nil
    verifiedAddress = nil
    warmupSucceeded = false
    nextWarmupAt = .distantPast
    stopping = false
  }

  private func startMonitorLocked() async -> ApplePrivateNetworkStatus {
    await stopMonitorLocked()
    let status = await sampleStatus()
    publish(status)
    monitorTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
          return
        }
        guard !Task.isCancelled, let self else { return }
        await self.pollStatus()
      }
    }
    return status
  }

  private func stopMonitorLocked() async {
    let task = monitorTask
    monitorTask = nil
    task?.cancel()
    await task?.value
  }

  private func pollStatus() async {
    guard monitorTask != nil else { return }
    let status = await sampleStatus()
    guard monitorTask != nil else { return }
    publish(status)
  }

  private func sampleStatus() async -> ApplePrivateNetworkStatus {
    guard let activeNode, let metadata = activeMetadata else {
      return .stopped(hasPersistedIdentity: stateStore.hasPersistedIdentity)
    }
    do {
      let backend = try JSONDecoder().decode(AppleTsnetStatus.self, from: await activeNode.statusJSON())
      guard let currentNode = self.activeNode, currentNode === activeNode else { return cachedStatus }
      guard !stopping else { return .starting(path: "none", hasPersistedIdentity: stateStore.hasPersistedIdentity) }
      guard backend.backendState == "Running" else {
        invalidateUpstreamVerification()
        return .starting(path: "none", hasPersistedIdentity: stateStore.hasPersistedIdentity)
      }
      let homePeers = backend.peer.values.filter { $0.tailscaleIPs.contains(metadata.homeIpv4) }
      guard
        homePeers.count == 1,
        let peer = homePeers.first,
        peer.online,
        peer.peerRelay?.isEmpty != false
      else {
        invalidateUpstreamVerification()
        return .unavailable(reason: "direct_path_unavailable", hasPersistedIdentity: stateStore.hasPersistedIdentity)
      }
      guard let currentAddress = peer.currentAddress, !currentAddress.isEmpty else {
        if lastDirectAddress != nil || verifiedAddress != nil || warmupSucceeded {
          invalidateUpstreamVerification()
        }
        startWarmupIfNeeded(node: activeNode, metadata: metadata)
        return .starting(path: "none", hasPersistedIdentity: stateStore.hasPersistedIdentity)
      }
      if lastDirectAddress != currentAddress {
        if lastDirectAddress != nil { invalidateUpstreamVerification() }
        lastDirectAddress = currentAddress
      }
      if warmupSucceeded { verifiedAddress = currentAddress }
      guard verifiedAddress == currentAddress else {
        startWarmupIfNeeded(node: activeNode, metadata: metadata)
        return .starting(path: "direct", hasPersistedIdentity: stateStore.hasPersistedIdentity)
      }
      if stateStore.hasPersistedIdentity, let gateway, gateway.isListening {
        return .ready(gatewayUrl: gateway.baseURL)
      }
      return .starting(path: "direct", hasPersistedIdentity: stateStore.hasPersistedIdentity)
    } catch {
      guard let currentNode = self.activeNode, currentNode === activeNode else { return cachedStatus }
      guard !stopping else { return .starting(path: "none", hasPersistedIdentity: stateStore.hasPersistedIdentity) }
      invalidateUpstreamVerification()
      return .unavailable(reason: "transport_failure", hasPersistedIdentity: stateStore.hasPersistedIdentity)
    }
  }

  private func invalidateUpstreamVerification() {
    lastDirectAddress = nil
    verifiedAddress = nil
    warmupSucceeded = false
    if warmupTask != nil {
      warmupGeneration += 1
      warmupTask?.cancel()
    }
  }

  private func startWarmupIfNeeded(node: any ApplePrivateNetworkNode, metadata: ApplePrivateNetworkMetadata) {
    guard !stopping, warmupTask == nil, Date() >= nextWarmupAt else { return }
    nextWarmupAt = Date().addingTimeInterval(5)
    let generation = warmupGeneration
    let destination = "\(metadata.homeIpv4):\(metadata.homePort)"
    warmupTask = Task.detached(priority: .utility) { [weak self] in
      // tailscale_dial is blocking; node closure invalidates this attempt on stop/reset.
      let connection = try? node.dialTCP(destination)
      if let connection { Darwin.close(connection) }
      await self?.warmupFinished(generation: generation, succeeded: connection != nil && !Task.isCancelled)
    }
  }

  private func warmupFinished(generation: Int, succeeded: Bool) {
    warmupTask = nil
    guard !stopping, generation == warmupGeneration else { return }
    warmupSucceeded = succeeded
    Task { [weak self] in await self?.pollStatus() }
  }

  private func publish(_ status: ApplePrivateNetworkStatus) {
    guard cachedStatus != status else { return }
    cachedStatus = status
    statusObserver?(status)
  }

  private func acquireLifecycle() async {
    guard lifecycleLocked else {
      lifecycleLocked = true
      return
    }
    await withCheckedContinuation { lifecycleWaiters.append($0) }
  }

  private func releaseLifecycle() {
    guard !lifecycleWaiters.isEmpty else {
      lifecycleLocked = false
      return
    }
    lifecycleWaiters.removeFirst().resume()
  }
}

private final class TailscaleKitNodeAdapter: ApplePrivateNetworkNode, @unchecked Sendable {
  private let node: TailscaleNode
  private let lock = NSLock()
  private let inFlightDials = DispatchGroup()
  private var cachedHandle: Int32?
  private var closing = false

  init(node: TailscaleNode) {
    self.node = node
  }

  func up() async throws {
    try await node.up()
    guard let handle = await node.tailscale else { throw AppleGatewayError.dialFailure }
    try cacheHandle(handle)
  }

  func close() async throws {
    beginClosing()
    try await node.close()
    await withCheckedContinuation { continuation in
      inFlightDials.notify(queue: .global(qos: .utility)) { continuation.resume() }
    }
  }

  private func beginClosing() {
    lock.lock()
    closing = true
    cachedHandle = nil
    lock.unlock()
  }

  func statusJSON() async throws -> Data {
    try await node.statusJSON()
  }

  func dialTCP(_ destination: String) throws -> Int32 {
    lock.lock()
    guard !closing, let handle = cachedHandle else {
      lock.unlock()
      throw AppleGatewayError.dialFailure
    }
    inFlightDials.enter()
    lock.unlock()
    defer { inFlightDials.leave() }
    var connection: Int32 = -1
    guard tailscale_dial(handle, "tcp", destination, &connection) == 0, connection >= 0 else {
      throw AppleGatewayError.dialFailure
    }
    return connection
  }

  private func cacheHandle(_ handle: Int32) throws {
    lock.lock()
    defer { lock.unlock() }
    guard !closing else { throw AppleGatewayError.dialFailure }
    cachedHandle = handle
  }
}

private struct AppleTsnetStatus: Decodable {
  let backendState: String
  let peer: [String: AppleTsnetPeer]

  enum CodingKeys: String, CodingKey {
    case backendState = "BackendState"
    case peer = "Peer"
  }
}

private struct AppleTsnetPeer: Decodable {
  let tailscaleIPs: [String]
  let currentAddress: String?
  let peerRelay: String?
  let online: Bool

  enum CodingKeys: String, CodingKey {
    case tailscaleIPs = "TailscaleIPs"
    case currentAddress = "CurAddr"
    case peerRelay = "PeerRelay"
    case online = "Online"
  }
}

private struct RodPlayerTailscaleLogSink: TailscaleKit.LogSink {
  let logFileHandle: Int32? = -1

  func log(_ message: String) {}
}

private struct TailscaleKitNodeFactory: ApplePrivateNetworkNodeFactory {
  func make(config: TailscaleKit.Configuration) throws -> any ApplePrivateNetworkNode {
    TailscaleKitNodeAdapter(
      node: try TailscaleNode(config: config, logger: RodPlayerTailscaleLogSink())
    )
  }
}

private struct ApplePrivateNetworkBootstrap: Sendable {
  let version: Int
  let profileId: String
  let controlUrl: String
  let authKey: String
  let homeIpv4: String
  let homePort: Int

  init(arguments: Any?) throws {
    guard
      let values = arguments as? [String: Any],
      let version = values["version"] as? Int,
      version == 1,
      let profileId = values["profileId"] as? String,
      let controlUrl = values["controlUrl"] as? String,
      let authKey = values["authKey"] as? String,
      let homeIpv4 = values["homeIpv4"] as? String,
      let homePort = values["homePort"] as? Int
    else {
      throw ApplePrivateNetworkMetadataError.invalid
    }
    let metadata = ApplePrivateNetworkMetadata(
      version: 2,
      profileId: profileId,
      controlUrl: controlUrl,
      homeIpv4: homeIpv4,
      homePort: homePort,
      nodeHostname: "rodplayer-validation"
    )
    try metadata.validated()
    guard ApplePrivateNetworkValidation.isAuthKey(authKey) else {
      throw ApplePrivateNetworkMetadataError.invalid
    }
    self.version = version
    self.profileId = profileId
    self.controlUrl = controlUrl
    self.authKey = authKey
    self.homeIpv4 = homeIpv4
    self.homePort = homePort
  }
}

private struct ApplePrivateNetworkIdentityClaim: Sendable {
  let profileId: String
  let controlUrl: String
  let homeIpv4: String
  let homePort: Int
  let allowLegacyClaim: Bool

  init(arguments: Any?) throws {
    guard let values = arguments as? [String: Any],
      let profileId = values["profileId"] as? String,
      let controlUrl = values["controlUrl"] as? String,
      let homeIpv4 = values["homeIpv4"] as? String,
      let homePort = values["homePort"] as? Int,
      let allowLegacyClaim = values["allowLegacyClaim"] as? Bool
    else { throw ApplePrivateNetworkMetadataError.invalid }
    let candidate = ApplePrivateNetworkMetadata(
      version: 2, profileId: profileId, controlUrl: controlUrl,
      homeIpv4: homeIpv4, homePort: homePort, nodeHostname: "rodplayer-validation"
    )
    try candidate.validated()
    self.profileId = profileId
    self.controlUrl = controlUrl
    self.homeIpv4 = homeIpv4
    self.homePort = homePort
    self.allowLegacyClaim = allowLegacyClaim
  }
}

private struct ApplePrivateNetworkMetadata: Codable, Sendable {
  let version: Int
  let profileId: String?
  let controlUrl: String
  let homeIpv4: String
  let homePort: Int
  let nodeHostname: String

  static func from(bootstrap: ApplePrivateNetworkBootstrap) -> ApplePrivateNetworkMetadata {
    let suffix = UUID().uuidString
      .replacingOccurrences(of: "-", with: "")
      .lowercased()
      .prefix(16)
    return ApplePrivateNetworkMetadata(
      version: 2,
      profileId: bootstrap.profileId,
      controlUrl: bootstrap.controlUrl,
      homeIpv4: bootstrap.homeIpv4,
      homePort: bootstrap.homePort,
      nodeHostname: "rodplayer-\(suffix)"
    )
  }

  static func decodeAndValidate(from data: Data) throws -> ApplePrivateNetworkMetadata {
    let metadata = try JSONDecoder().decode(ApplePrivateNetworkMetadata.self, from: data)
    try metadata.validated()
    return metadata
  }

  func validated() throws {
    guard
      (version == 1 && profileId == nil) ||
        (version == 2 && profileId.map(ApplePrivateNetworkValidation.isProfileId) == true),
      ApplePrivateNetworkValidation.isControlUrl(controlUrl),
      ApplePrivateNetworkValidation.isIpv4(homeIpv4),
      (1 ... 65_535).contains(homePort),
      ApplePrivateNetworkValidation.isHostname(nodeHostname)
    else {
      throw ApplePrivateNetworkMetadataError.invalid
    }
  }

  func claimed(by claim: ApplePrivateNetworkIdentityClaim) throws -> ApplePrivateNetworkMetadata {
    guard ApplePrivateNetworkValidation.sameControlEndpoint(controlUrl, claim.controlUrl),
      homeIpv4 == claim.homeIpv4,
      homePort == claim.homePort,
      (version == 2 ? profileId == claim.profileId : claim.allowLegacyClaim)
    else { throw ApplePrivateNetworkMetadataError.invalid }
    if version == 2 { return self }
    return ApplePrivateNetworkMetadata(
      version: 2, profileId: claim.profileId, controlUrl: controlUrl,
      homeIpv4: homeIpv4, homePort: homePort, nodeHostname: nodeHostname
    )
  }
}

private enum ApplePrivateNetworkMetadataError: Error {
  case invalid
}

private enum ApplePrivateNetworkValidation {
  // Same identity rule as Dart: HTTPS host plus effective port; root slash is ignored.
  static func sameControlEndpoint(_ left: String, _ right: String) -> Bool {
    guard isControlUrl(left), isControlUrl(right),
      let lhs = URLComponents(string: left), let rhs = URLComponents(string: right),
      let lhsHost = lhs.host, let rhsHost = rhs.host
    else { return false }
    return lhsHost.caseInsensitiveCompare(rhsHost) == .orderedSame &&
      (lhs.port ?? 443) == (rhs.port ?? 443)
  }

  static func isProfileId(_ value: String) -> Bool {
    value.range(of: "^[A-Za-z0-9][A-Za-z0-9:_-]{0,127}$", options: .regularExpression) != nil
  }

  static func isControlUrl(_ value: String) -> Bool {
    guard
      let components = URLComponents(string: value),
      components.scheme?.lowercased() == "https",
      components.host?.isEmpty == false,
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil,
      components.port.map({ (1 ... 65_535).contains($0) }) ?? true,
      components.path.isEmpty || components.path == "/"
    else {
      return false
    }
    return true
  }

  static func isAuthKey(_ value: String) -> Bool {
    value.range(
      of: "^hskey-auth-[A-Za-z0-9_-]{12}-[A-Za-z0-9_-]{64}$",
      options: .regularExpression
    ) != nil
  }

  static func isIpv4(_ value: String) -> Bool {
    let components = value.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count == 4 else { return false }
    return components.allSatisfy { component in
      guard let number = Int(component), (0 ... 255).contains(number) else { return false }
      return String(number) == component
    }
  }

  static func isHostname(_ value: String) -> Bool {
    value.range(
      of: "^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$",
      options: .regularExpression
    ) != nil
  }
}

private final class AppleCompatibilityPlaybackManager: NSObject, FlutterStreamHandler {
  private var players: [String: AppleCompatibilityPlaybackSession] = [:]
  private var eventSink: FlutterEventSink?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ping":
      result(true)
    case "create":
      guard let args = call.arguments as? [String: Any], let text = args["url"] as? String, let url = URL(string: text) else {
        result(FlutterError(code: "bad_url", message: "Missing playback URL", details: nil))
        return
      }
      let handle = UUID().uuidString
      players[handle] = AppleCompatibilityPlaybackSession(handle: handle, url: url) { [weak self] payload in self?.eventSink?(payload) }
      result(handle)
    case "play": command(call, result) { $0.play() }
    case "pause": command(call, result) { $0.pause() }
    case "seek": command(call, result) { session in
      let millis = ((call.arguments as? [String: Any])?["positionMillis"] as? NSNumber)?.int32Value ?? 0
      session.seek(milliseconds: millis)
    }
    case "stop": command(call, result) { $0.stop() }
    case "volume": command(call, result) { session in
      let volume = ((call.arguments as? [String: Any])?["volume"] as? NSNumber)?.floatValue ?? 100
      session.setVolume(volume / 100)
    }
    case "mute": command(call, result) { session in
      let muted = ((call.arguments as? [String: Any])?["muted"] as? Bool) ?? false
      session.setMuted(muted)
    }
    case "dispose":
      guard let handle = (call.arguments as? [String: Any])?["handle"] as? String else {
        result(FlutterError(code: "bad_handle", message: "Missing player handle", details: nil))
        return
      }
      players.removeValue(forKey: handle)?.dispose()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func attach(handle: String?, view: NSView?) {
    guard let handle = handle else { return }
    players[handle]?.player.drawable = view
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func command(_ call: FlutterMethodCall, _ result: @escaping FlutterResult, _ action: (AppleCompatibilityPlaybackSession) -> Void) {
    guard let handle = (call.arguments as? [String: Any])?["handle"] as? String, let session = players[handle] else {
      result(FlutterError(code: "bad_handle", message: "Unknown player handle", details: nil))
      return
    }
    action(session)
    result(nil)
  }
}

private final class AppleCompatibilityPlaybackSession: NSObject, VLCMediaPlayerDelegate {
  let handle: String
  let player = VLCMediaPlayer()
  private let emit: ([String: Any]) -> Void
  private var disposed = false
  private var muted = false
  private var desiredVolume: Float = 1

  init(handle: String, url: URL, emit: @escaping ([String: Any]) -> Void) {
    self.handle = handle
    self.emit = emit
    super.init()
    player.delegate = self
    player.media = VLCMedia(url: url)
    player.play()
    sendState()
  }

  func play() { player.play(); sendState() }
  func pause() { player.pause(); sendState() }
  func stop() { player.stop(); sendState() }
  func seek(milliseconds: Int32) { player.time = VLCTime(int: milliseconds); sendState() }
  func setVolume(_ value: Float) { desiredVolume = min(max(value, 0), 1); if !muted { player.audio?.volume = Int32(desiredVolume * 100) }; sendState() }
  func setMuted(_ value: Bool) { muted = value; player.audio?.isMuted = muted; if !muted { player.audio?.volume = Int32(desiredVolume * 100) }; sendState() }

  func mediaPlayerStateChanged(_ aNotification: Notification!) { sendState(error: player.state == .error ? "VLCKit playback failed" : nil, ended: player.state == .ended) }
  func mediaPlayerTimeChanged(_ aNotification: Notification!) { sendState() }

  private func sendState(error: String? = nil, ended: Bool = false) {
    guard !disposed else { return }
    emit([
      "handle": handle,
      "playing": player.isPlaying,
      "buffering": player.state == .buffering,
      "positionMillis": player.time.intValue,
      "durationMillis": player.media?.length.intValue ?? 0,
      "volume": Double(desiredVolume * 100),
      "muted": muted,
      "error": error as Any,
      "ended": ended,
    ])
  }

  func dispose() {
    guard !disposed else { return }
    disposed = true
    player.stop()
    player.delegate = nil
    player.drawable = nil
  }
}

private final class AppleCompatibilityPlaybackPlatformView: NSView {
  init(frame: CGRect, handle: String?, manager: AppleCompatibilityPlaybackManager) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
    manager.attach(handle: handle, view: self)
  }

  required init?(coder: NSCoder) { nil }
}

private final class AppleCompatibilityPlaybackViewFactory: NSObject, FlutterPlatformViewFactory {
  private let manager: AppleCompatibilityPlaybackManager

  init(manager: AppleCompatibilityPlaybackManager) {
    self.manager = manager
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let handle = (args as? [String: Any])?["handle"] as? String
    return AppleCompatibilityPlaybackPlatformView(frame: .zero, handle: handle, manager: manager)
  }
}

private final class ApplePlaybackManager: NSObject, FlutterStreamHandler {
  private var players: [String: ApplePlaybackSession] = [:]
  private var eventSink: FlutterEventSink?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ping":
      result(true)
    case "create":
      guard let args = call.arguments as? [String: Any], let text = args["url"] as? String, let url = URL(string: text) else {
        result(FlutterError(code: "bad_url", message: "Missing playback URL", details: nil))
        return
      }
      let handle = UUID().uuidString
      players[handle] = ApplePlaybackSession(handle: handle, url: url) { [weak self] payload in self?.eventSink?(payload) }
      result(handle)
    case "play": command(call, result) { $0.play() }
    case "pause": command(call, result) { $0.pause() }
    case "seek": command(call, result) { session in
      let millis = ((call.arguments as? [String: Any])?["positionMillis"] as? NSNumber)?.doubleValue ?? 0
      session.seek(milliseconds: millis)
    }
    case "stop": command(call, result) { $0.stop() }
    case "volume": command(call, result) { session in
      let volume = ((call.arguments as? [String: Any])?["volume"] as? NSNumber)?.floatValue ?? 100
      session.setVolume(volume / 100)
    }
    case "mute": command(call, result) { session in
      let muted = ((call.arguments as? [String: Any])?["muted"] as? Bool) ?? false
      session.setMuted(muted)
    }
    case "dispose":
      guard let handle = (call.arguments as? [String: Any])?["handle"] as? String else {
        result(FlutterError(code: "bad_handle", message: "Missing player handle", details: nil))
        return
      }
      players.removeValue(forKey: handle)?.dispose()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func player(for handle: String) -> AVPlayer? { players[handle]?.player }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func command(_ call: FlutterMethodCall, _ result: @escaping FlutterResult, _ action: (ApplePlaybackSession) -> Void) {
    guard let handle = (call.arguments as? [String: Any])?["handle"] as? String, let session = players[handle] else {
      result(FlutterError(code: "bad_handle", message: "Unknown player handle", details: nil))
      return
    }
    action(session)
    result(nil)
  }
}

private final class ApplePlaybackSession {
  let handle: String
  let player: AVPlayer
  private let emit: ([String: Any]) -> Void
  private var timeObserver: Any?
  private var statusObservation: NSKeyValueObservation?
  private var timeControlObservation: NSKeyValueObservation?
  private var durationObservation: NSKeyValueObservation?
  private var disposed = false

  init(handle: String, url: URL, emit: @escaping ([String: Any]) -> Void) {
    self.handle = handle
    self.emit = emit
    let item = AVPlayerItem(url: url)
    player = AVPlayer(playerItem: item)
    statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in self?.statusChanged(item) }
    durationObservation = item.observe(\.duration, options: [.new]) { [weak self] _, _ in self?.sendState() }
    timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in self?.sendState() }
    timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 2), queue: .main) { [weak self] _ in self?.sendState() }
    NotificationCenter.default.addObserver(self, selector: #selector(ended), name: .AVPlayerItemDidPlayToEndTime, object: item)
    sendState()
  }

  func play() { player.play(); sendState() }
  func pause() { player.pause(); sendState() }
  func stop() { player.pause(); player.seek(to: .zero); sendState() }
  func seek(milliseconds: Double) { player.seek(to: CMTime(seconds: milliseconds / 1000, preferredTimescale: 600)); sendState() }
  func setVolume(_ value: Float) { player.volume = min(max(value, 0), 1); sendState() }
  func setMuted(_ value: Bool) { player.isMuted = value; sendState() }

  @objc private func ended() {
    sendState(ended: true)
  }

  private func statusChanged(_ item: AVPlayerItem) {
    if item.status == .failed {
      sendState(error: item.error?.localizedDescription ?? "AVPlayer item failed")
    } else {
      sendState()
    }
  }

  private func sendState(error: String? = nil, ended: Bool = false) {
    guard !disposed else { return }
    let duration = player.currentItem?.duration.seconds ?? 0
    emit([
      "handle": handle,
      "playing": player.rate != 0,
      "buffering": player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
      "positionMillis": milliseconds(player.currentTime().seconds),
      "durationMillis": milliseconds(duration),
      "volume": Double(player.volume * 100),
      "muted": player.isMuted,
      "error": error as Any,
      "ended": ended,
    ])
  }

  private func milliseconds(_ seconds: Double) -> Int {
    return seconds.isFinite ? max(0, Int(seconds * 1000)) : 0
  }

  func dispose() {
    guard !disposed else { return }
    disposed = true
    player.pause()
    if let observer = timeObserver { player.removeTimeObserver(observer) }
    statusObservation?.invalidate()
    timeControlObservation?.invalidate()
    durationObservation?.invalidate()
    NotificationCenter.default.removeObserver(self)
    player.replaceCurrentItem(with: nil)
  }
}

private final class ApplePlaybackPlatformView: NSView {
  private let playerLayer = AVPlayerLayer()

  init(frame: CGRect, handle: String?, manager: ApplePlaybackManager) {
    super.init(frame: frame)
    wantsLayer = true
    layer = playerLayer
    playerLayer.videoGravity = .resizeAspect
    if let handle = handle { playerLayer.player = manager.player(for: handle) }
  }

  required init?(coder: NSCoder) { nil }

}

private final class ApplePlaybackViewFactory: NSObject, FlutterPlatformViewFactory {
  private let manager: ApplePlaybackManager

  init(manager: ApplePlaybackManager) {
    self.manager = manager
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let handle = (args as? [String: Any])?["handle"] as? String
    return ApplePlaybackPlatformView(frame: .zero, handle: handle, manager: manager)
  }
}
