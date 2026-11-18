import Flutter
import WidgetKit

/// 桌面小组件的通道（Flutter 那边是 lib/core/home_widget.dart）：
/// 把常驻城市、温度单位交给小组件；告诉 Flutter 形象图放在哪个共享目录；形象图换了让小组件重画。
class HomeWidgetPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "shenmetianqi/home_widget", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(HomeWidgetPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "directory":
      guard let dir = WidgetShared.avatarDirectory else { return result(nil) }
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      result(dir.path)
    case "configure":
      WidgetShared.saveConfig(call.arguments as? [String: Any])
      reload()
      result(nil)
    case "reload":
      reload()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func reload() {
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.kind)
    }
  }
}
