import Flutter
import UIKit

/// 把生成的插件注册（只有类方法）接到 `FlutterAppDelegate.pluginRegistrant` 要的 `FlutterPluginRegistrant` 协议上
class PluginsRegistrant: NSObject, FlutterPluginRegistrant {
  func register(with registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
    // 本 App 自己的原生插件：桌面小组件
    if let registrar = registry.registrar(forPlugin: "HomeWidgetPlugin") {
      HomeWidgetPlugin.register(with: registrar)
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // iOS 27 要求用 UIScene 生命周期（见 Info.plist 的 UIApplicationSceneManifest），和“再玩我是狗”一样：
    // 窗口归 FlutterSceneDelegate 管，这里 self.window 还是 nil，直接 `GeneratedPluginRegistrant.register(with: self)`
    // 拿到的 registrar 是空的，shared_preferences 这类插件会崩。改成让故事板建出来的 FlutterViewController 来注册。
    pluginRegistrant = PluginsRegistrant()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
