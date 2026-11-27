import Flutter
import UIKit
import UserNotifications

/// Bridges the generated (class-method only) registrant to the
/// `FlutterPluginRegistrant` protocol that `FlutterAppDelegate.pluginRegistrant` expects.
class PluginsRegistrant: NSObject, FlutterPluginRegistrant {
  func register(with registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
    // 本 App 自己的原生插件：屏幕使用时间（技术验证）
    if let registrar = registry.registrar(forPlugin: "ScreenTimePlugin") {
      ScreenTimePlugin.register(with: registrar)
    }
    // 超时来电界面：响铃、提示音、狗版的你说话、听狗叫、放行和拒接
    if let registrar = registry.registrar(forPlugin: "CallPlugin") {
      CallPlugin.register(with: registrar)
    }
    // 拍照形象（技术验证）：手机本地卡通化
    if let registrar = registry.registrar(forPlugin: "CartoonLabPlugin") {
      CartoonLabPlugin.register(with: registrar)
    }
    // 桌面小组件
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
    // iOS 27 mandates the UIScene lifecycle (see Info.plist -> UIApplicationSceneManifest).
    // The window is now owned by FlutterSceneDelegate, so `self.window` is still nil here and
    // `GeneratedPluginRegistrant.register(with: self)` hands out a nil registrar, which crashes
    // inside plugins such as shared_preferences. Let the FlutterViewController created from the
    // storyboard do the registration instead.
    pluginRegistrant = PluginsRegistrant()
    // 每晚结算提醒：App 开着时也显示通知（flutter_local_notifications 的要求）
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
