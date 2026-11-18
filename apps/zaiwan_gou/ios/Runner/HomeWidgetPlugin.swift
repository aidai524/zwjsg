import Flutter
import WidgetKit

/// 桌面小组件的通道（Flutter 那边是 lib/core/home_widget.dart）：
/// 把狗度规则、目标和数据来源交给小组件；告诉 Flutter 形象图放在哪个共享目录；形象图换了、狗度变了让小组件重画。
class HomeWidgetPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "zwjsg/home_widget", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(HomeWidgetPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "directory":
      guard let dir = GouWidgetShared.avatarDirectory else { return result(nil) }
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      result(dir.path)
    case "configure":
      GouWidgetShared.saveConfig(call.arguments)
      WidgetCenter.shared.reloadTimelines(ofKind: GouWidgetShared.kind)
      result(nil)
    case "reload":
      WidgetCenter.shared.reloadTimelines(ofKind: GouWidgetShared.kind)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
