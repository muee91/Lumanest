import Flutter
import AVFoundation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var feedbackController: LumaNestFeedbackController?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LumaNestFeedback") {
      let controller = LumaNestFeedbackController(registrar: registrar)
      feedbackController = controller
      controller.register()
    }
  }
}

private final class LumaNestFeedbackController {
  private let registrar: FlutterPluginRegistrar
  private var players: [String: AVAudioPlayer] = [:]
  private var soundEnabled = true
  private var hapticEnabled = true

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  func register() {
    let channel = FlutterMethodChannel(
      name: "com.lumanest/feedback",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "preload":
      let sounds = arguments?["sounds"] as? [String] ?? []
      sounds.forEach { _ = player(for: $0) }
      result(nil)
    case "setEnabled":
      soundEnabled = arguments?["soundEnabled"] as? Bool ?? true
      hapticEnabled = arguments?["hapticEnabled"] as? Bool ?? true
      result(nil)
    case "play":
      guard soundEnabled, let sound = arguments?["sound"] as? String else {
        result(nil)
        return
      }
      let volume = Float(arguments?["volume"] as? Double ?? 1).clamped(to: 0...1)
      if let player = player(for: sound) {
        player.currentTime = 0
        player.volume = volume
        player.play()
      }
      result(nil)
    case "stop":
      if let sound = arguments?["sound"] as? String {
        players[sound]?.stop()
        players[sound]?.currentTime = 0
      }
      result(nil)
    case "haptic":
      if hapticEnabled {
        let type = arguments?["type"] as? String
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type == "warning" ? .warning : .success)
      }
      result(nil)
    case "dispose":
      players.values.forEach { $0.stop() }
      players.removeAll()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func player(for sound: String) -> AVAudioPlayer? {
    if let player = players[sound] { return player }
    let asset = registrar.lookupKey(forAsset: "assets/audio/\(sound)")
    guard let path = Bundle.main.path(forResource: asset, ofType: nil) else { return nil }
    do {
      let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
      player.prepareToPlay()
      players[sound] = player
      return player
    } catch {
      return nil
    }
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
