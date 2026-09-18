import Cocoa
import AVFoundation
import CoreAudio
import FlutterMacOS
import VideoToolbox
import VLCKit

class MainFlutterWindow: NSWindow, FlutterStreamHandler {
  private var events: FlutterEventSink?
  private let applePlayback = ApplePlaybackManager()
  private let compatibilityPlayback = AppleCompatibilityPlaybackManager()
  private let privateNetwork = PrivateNetworkHost()

  override func awakeFromNib() {
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
  private var hasPersistedIdentity = false

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ping":
      result(true)
    case "status":
      result(statusPayload())
    case "stop":
      emitStatus()
      result(nil)
    case "reset":
      hasPersistedIdentity = false
      emitStatus()
      result(nil)
    case "bootstrap", "resume":
      result(FlutterError(code: "private_network_not_ready", message: nil, details: nil))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = eventSink
    emitStatus()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func emitStatus() {
    eventSink?(statusPayload())
  }

  private func statusPayload() -> [String: Any] {
    [
      "state": "stopped",
      "path": "none",
      "hasPersistedIdentity": hasPersistedIdentity,
      "reason": "none",
      "gatewayUrl": NSNull(),
    ]
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
