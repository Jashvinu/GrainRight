import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureConfigChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func configureConfigChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "grainright.wrkfarm/config",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "mapTilerApiKey":
        result(Self.infoString("MapTilerApiKey"))
      case "offlineTileUrlTemplate":
        result(Self.infoString("OfflineTileUrlTemplate"))
      case "offlineTileSourceLabel":
        result(Self.infoString("OfflineTileSourceLabel"))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func infoString(_ key: String) -> String {
    let value = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    return value.hasPrefix("$(") ? "" : value
  }
}
