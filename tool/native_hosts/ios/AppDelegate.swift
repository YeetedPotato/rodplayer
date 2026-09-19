import AVFoundation
import Foundation
import Flutter
import MobileVLCKit
import TailscaleKit
import UIKit
import VideoToolbox

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterStreamHandler {
  private var events: FlutterEventSink?
  private let applePlayback = ApplePlaybackManager()
  private let compatibilityPlayback = AppleCompatibilityPlaybackManager()
  private let privateNetwork = PrivateNetworkHost()
  private let tailscaleKitLinkProof: TailscaleNode.Type = TailscaleNode.self

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    _ = tailscaleKitLinkProof
    let controller = window?.rootViewController as! FlutterViewController
    FlutterMethodChannel(name: "rodplayer/playback_capabilities", binaryMessenger: controller.binaryMessenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "ping": result(true)
        case "probeCompute": result(self.probeCompute())
        case "probeDisplay": result(self.probeDisplay())
        case "probeAudio": result(self.probeAudio())
        default: result(FlutterMethodNotImplemented)
        }
      }
    FlutterEventChannel(name: "rodplayer/playback_capability_events", binaryMessenger: controller.binaryMessenger)
      .setStreamHandler(self)
    FlutterMethodChannel(name: "rodplayer/private_network", binaryMessenger: controller.binaryMessenger)
      .setMethodCallHandler(privateNetwork.handle)
    FlutterEventChannel(name: "rodplayer/private_network_events", binaryMessenger: controller.binaryMessenger)
      .setStreamHandler(privateNetwork)
    FlutterMethodChannel(name: "rodplayer/apple_playback", binaryMessenger: controller.binaryMessenger)
      .setMethodCallHandler(applePlayback.handle)
    FlutterEventChannel(name: "rodplayer/apple_playback_events", binaryMessenger: controller.binaryMessenger)
      .setStreamHandler(applePlayback)
    registrar(forPlugin: "RodPlayerApplePlayback")
      .register(ApplePlaybackViewFactory(manager: applePlayback), withId: "rodplayer/apple_playback_view")
    FlutterMethodChannel(name: "rodplayer/apple_compatibility_playback", binaryMessenger: controller.binaryMessenger)
      .setMethodCallHandler(compatibilityPlayback.handle)
    FlutterEventChannel(name: "rodplayer/apple_compatibility_playback_events", binaryMessenger: controller.binaryMessenger)
      .setStreamHandler(compatibilityPlayback)
    registrar(forPlugin: "RodPlayerAppleCompatibilityPlayback")
      .register(AppleCompatibilityPlaybackViewFactory(manager: compatibilityPlayback), withId: "rodplayer/apple_compatibility_playback_view")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    events?("resume")
  }

  func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
    events = eventSink
    NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChanged), name: AVAudioSession.routeChangeNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: UIScreen.didConnectNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: UIScreen.didDisconnectNotification, object: nil)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
    NotificationCenter.default.removeObserver(self, name: UIScreen.didConnectNotification, object: nil)
    NotificationCenter.default.removeObserver(self, name: UIScreen.didDisconnectNotification, object: nil)
    events = nil
    return nil
  }

  @objc private func audioRouteChanged() { events?("audioRouteChanged") }
  @objc private func screenChanged() { events?("displayChanged") }

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
    let screen = UIScreen.main
    return [
      "width": Int((screen.bounds.width * screen.scale).rounded()),
      "height": Int((screen.bounds.height * screen.scale).rounded()),
      "pixelRatio": screen.scale,
      "refreshRate": Double(screen.maximumFramesPerSecond),
      "genericHdrOutput": screen.traitCollection.displayGamut == .P3 ? "supported" : "unknown",
    ]
  }

  private func probeAudio() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    let route = session.currentRoute.outputs.first
    return [
      "routeName": route?.portName as Any,
      "sinkName": route?.portName as Any,
      "pcmOutput": route == nil ? "unknown" : "supported",
      "maxChannels": route?.channels?.count as Any,
      "sampleRates": [Int(session.sampleRate)].filter { $0 > 0 },
    ]
  }
}

private final class PrivateNetworkHost: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private let stateStore: ApplePrivateNetworkStateStore?
  private let nodeOwner: ApplePrivateNetworkNodeOwner?

  override init() {
    do {
      let stateStore = try ApplePrivateNetworkStateStore()
      try stateStore.prepare()
      self.stateStore = stateStore
      nodeOwner = ApplePrivateNetworkNodeOwner(stateStore: stateStore)
    } catch {
      stateStore = nil
      nodeOwner = nil
    }
    super.init()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ping":
      result(true)
    case "status":
      guard stateStore != nil else {
        result(Self.operationFailed())
        return
      }
      result(statusPayload())
    case "stop":
      stop(result: result)
    case "reset":
      reset(result: result)
    case "bootstrap", "resume":
      result(FlutterError(code: "private_network_not_ready", message: nil, details: nil))
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
    eventSink?(statusPayload())
  }

  private func stop(result: @escaping FlutterResult) {
    guard let nodeOwner else {
      result(Self.operationFailed())
      return
    }
    Task { @MainActor [weak self] in
      do {
        try await nodeOwner.stop()
        self?.emitStatus()
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
        self?.emitStatus()
        result(nil)
      } catch {
        result(Self.operationFailed())
      }
    }
  }

  private static func operationFailed() -> FlutterError {
    FlutterError(code: "private_network_operation_failed", message: nil, details: nil)
  }

  private func statusPayload() -> [String: Any] {
    [
      "state": "stopped",
      "path": "none",
      "hasPersistedIdentity": stateStore?.hasPersistedIdentity ?? false,
      "reason": "none",
      "gatewayUrl": NSNull(),
    ]
  }
}

struct ApplePrivateNetworkStateStore: Sendable {
  let privateNetworkRoot: URL
  let nodeStateDirectory: URL
  let tailscaledState: URL

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

  func reset(fileManager: FileManager = .default) throws {
    guard fileManager.fileExists(atPath: privateNetworkRoot.path) else { return }
    try fileManager.removeItem(at: privateNetworkRoot)
  }
}

protocol ApplePrivateNetworkNode: AnyObject, Sendable {
  func close() async throws
}

private enum ApplePrivateNetworkNodeOwnerError: Error {
  case nodeAlreadyActive
}

actor ApplePrivateNetworkNodeOwner {
  private let stateStore: ApplePrivateNetworkStateStore
  private var activeNode: (any ApplePrivateNetworkNode)?
  private var lifecycleLocked = false
  private var lifecycleWaiters: [CheckedContinuation<Void, Never>] = []

  init(stateStore: ApplePrivateNetworkStateStore) {
    self.stateStore = stateStore
  }

  func install(_ node: any ApplePrivateNetworkNode) async throws {
    await acquireLifecycle()
    defer { releaseLifecycle() }
    guard activeNode == nil else {
      throw ApplePrivateNetworkNodeOwnerError.nodeAlreadyActive
    }
    activeNode = node
  }

  func stop() async throws {
    await acquireLifecycle()
    defer { releaseLifecycle() }
    try await stopLocked()
  }

  func reset() async throws {
    await acquireLifecycle()
    defer { releaseLifecycle() }
    try await stopLocked()
    try stateStore.reset()
  }

  private func stopLocked() async throws {
    guard let activeNode else { return }
    try await activeNode.close()
    self.activeNode = nil
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

  init(node: TailscaleNode) {
    self.node = node
  }

  func close() async throws {
    try await node.close()
  }
}

private struct TailscaleKitNodeFactory {
  func make(config: TailscaleKit.Configuration) throws -> any ApplePrivateNetworkNode {
    TailscaleKitNodeAdapter(node: try TailscaleNode(config: config, logger: nil))
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

  func attach(handle: String?, view: UIView?) {
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

private final class AppleCompatibilityPlaybackPlatformView: NSObject, FlutterPlatformView {
  private let playerView = UIView()

  init(frame: CGRect, handle: String?, manager: AppleCompatibilityPlaybackManager) {
    super.init()
    playerView.backgroundColor = .black
    manager.attach(handle: handle, view: playerView)
  }

  func view() -> UIView { playerView }
}

private final class AppleCompatibilityPlaybackViewFactory: NSObject, FlutterPlatformViewFactory {
  private let manager: AppleCompatibilityPlaybackManager

  init(manager: AppleCompatibilityPlaybackManager) {
    self.manager = manager
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let handle = (args as? [String: Any])?["handle"] as? String
    return AppleCompatibilityPlaybackPlatformView(frame: frame, handle: handle, manager: manager)
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

private final class ApplePlaybackView: UIView {
  override static var layerClass: AnyClass { AVPlayerLayer.self }
  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private final class ApplePlaybackPlatformView: NSObject, FlutterPlatformView {
  private let playerView = ApplePlaybackView()

  init(frame: CGRect, handle: String?, manager: ApplePlaybackManager) {
    super.init()
    playerView.playerLayer.videoGravity = .resizeAspect
    if let handle = handle { playerView.playerLayer.player = manager.player(for: handle) }
  }

  func view() -> UIView { playerView }
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

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let handle = (args as? [String: Any])?["handle"] as? String
    return ApplePlaybackPlatformView(frame: frame, handle: handle, manager: manager)
  }
}
