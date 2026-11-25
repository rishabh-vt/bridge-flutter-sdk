import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Bridge SDK downloads channel — saves into Documents (Files app via sharing).
    let messenger = engineBridge.applicationRegistrar.messenger()
    FlutterMethodChannel(name: "bridge_flutter_sdk/downloads", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "saveToDownloads" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard
          let args = call.arguments as? [String: Any],
          let fileName = args["fileName"] as? String
        else {
          result(
            FlutterError(code: "bad_args", message: "Missing bytes/fileName", details: nil)
          )
          return
        }

        let data: Data?
        if let typed = args["bytes"] as? FlutterStandardTypedData {
          data = typed.data
        } else if let bytes = args["bytes"] as? [UInt8] {
          data = Data(bytes)
        } else if let bytes = args["bytes"] as? [Int] {
          data = Data(bytes.map { UInt8(truncatingIfNeeded: $0) })
        } else {
          data = nil
        }

        guard let fileData = data else {
          result(
            FlutterError(code: "bad_args", message: "Missing bytes/fileName", details: nil)
          )
          return
        }

        do {
          let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
          let dest = docs.appendingPathComponent(fileName)
          try? FileManager.default.removeItem(at: dest)
          try fileData.write(to: dest)
          result(nil)
        } catch {
          result(
            FlutterError(
              code: "save_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
  }
}
