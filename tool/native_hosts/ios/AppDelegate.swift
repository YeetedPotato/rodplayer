import AVFoundation
import Flutter
import UIKit
import VideoToolbox

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterStreamHandler {
  private var events: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    FlutterMethodChannel(name: "rodplayer/playback_capabilities", binaryMessenger: controller.binaryMessenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "probeCompute": result(self.probeCompute())
        case "probeDisplay": result(self.probeDisplay())
        case "probeAudio": result(self.probeAudio())
        default: result(FlutterMethodNotImplemented)
        }
      }
    FlutterEventChannel(name: "rodplayer/playback_capability_events", binaryMessenger: controller.binaryMessenger)
      .setStreamHandler(self)
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
