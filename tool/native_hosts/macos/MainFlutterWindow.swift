import Cocoa
import CoreAudio
import FlutterMacOS
import VideoToolbox

class MainFlutterWindow: NSWindow, FlutterStreamHandler {
  private var events: FlutterEventSink?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let messenger = flutterViewController.engine.binaryMessenger
    FlutterMethodChannel(name: "rodplayer/playback_capabilities", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "probeCompute": result(self.probeCompute())
        case "probeDisplay": result(self.probeDisplay())
        case "probeAudio": result(self.probeAudio())
        default: result(FlutterMethodNotImplemented)
        }
      }
    FlutterEventChannel(name: "rodplayer/playback_capability_events", binaryMessenger: messenger)
      .setStreamHandler(self)

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
