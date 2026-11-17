import DeviceActivity
import FamilyControls
import Flutter
import ManagedSettings
import SwiftUI
import UIKit

/// iOS 屏幕使用时间（技术验证）。交给 Flutter 的只有授权状态、选了几个 App 和类别、今天到了第几阶段。
/// 选中的 App 是系统给的不透明令牌，只存在本机 App Group 里：拿不到名字，也不上传。
final class ScreenTimePlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "zwjsg/screen_time", binaryMessenger: registrar.messenger())
    let plugin = ScreenTimePlugin()
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.register(ScreenTimeReportFactory(), withId: "zwjsg/screen_time_report")
    registrar.register(LockSelectionFactory(plugin: plugin), withId: "zwjsg/lock_selection")
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result(status())
    case "requestAuthorization":
      requestAuthorization(result)
    case "pickActivities":
      presentPicker(result)
    case "startMonitoring":
      startMonitoring(call.arguments as? [String: Any] ?? [:], result)
    case "stopMonitoring":
      DeviceActivityCenter().stopMonitoring([.daily])
      ScreenTimeStore.append("停止监控")
      result(status())
    case "listLocks":
      result(locksPayload())
    case "pickLockApps":
      pickLockApps(call.arguments as? [String: Any] ?? [:], result)
    case "discardLockDraft":
      draftSelection = nil
      result(nil)
    case "saveLock":
      saveLock(call.arguments as? [String: Any] ?? [:], result)
    case "deleteLock":
      deleteLock(call.arguments as? [String: Any] ?? [:], result)
    case "grantGrace":
      grantGrace(call.arguments as? [String: Any] ?? [:], result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - App 时间锁

  /// 新建或修改时间锁时选好、还没保存的 App（选中项视图也要读，所以是 fileprivate）
  fileprivate var draftSelection: FamilyActivitySelection?

  /// 交给 Flutter 的只有数量和状态，App 令牌留在本机
  private func locksPayload() -> [[String: Any]] {
    ScreenTimeStore.locks.map { lock in
      let s = LockShield.selection(of: lock)
      return [
        "id": lock.id,
        "minutes": lock.minutes,
        "apps": s?.applicationTokens.count ?? 0,
        "categories": s?.categoryTokens.count ?? 0,
        "webDomains": s?.webDomainTokens.count ?? 0,
        "locked": ScreenTimeStore.isLockedToday(lock.id),
        "graceLeft": ScreenTimeStore.graceLeft(lock.id),
        "graceActive": ScreenTimeStore.isGraceActive(lock.id),
      ]
    }
  }

  /// 紧急解锁：先撤掉屏蔽，再单独监控“再用几分钟”，用满由监控扩展重新锁上
  private func grantGrace(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["id"] as? String, let lock = ScreenTimeStore.lock(id),
          let selection = LockShield.selection(of: lock)
    else {
      return result(FlutterError(code: "bad_args", message: "这个时间锁已经不在了", details: nil))
    }
    guard ScreenTimeStore.graceLeft(id) > 0 else {
      return result(FlutterError(code: "no_grace", message: "今天的临时解锁用完了", details: nil))
    }
    ScreenTimeStore.useGrace(id)
    ScreenTimeStore.setGraceActive(id, true)
    LockShield.clear(id)

    let center = DeviceActivityCenter()
    let name = ScreenTimeStore.graceActivity(id)
    center.stopMonitoring([name])
    let now = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
    let schedule = DeviceActivitySchedule(
      intervalStart: now, intervalEnd: DateComponents(hour: 23, minute: 59, second: 59), repeats: false)
    let event = DeviceActivityEvent(
      applications: selection.applicationTokens, categories: selection.categoryTokens,
      webDomains: selection.webDomainTokens, threshold: DateComponents(minute: ScreenTimeStore.graceMinutes))
    do {
      try center.startMonitoring(name, during: schedule, events: [ScreenTimeStore.lockEvent: event])
      ScreenTimeStore.append("时间锁 \(id.prefix(4))：临时解锁 \(ScreenTimeStore.graceMinutes) 分钟")
    } catch {
      // 快到 0 点时统计周期太短（系统要求至少 15 分钟），就解开到 0 点
      ScreenTimeStore.append("时间锁 \(id.prefix(4))：快到 0 点了，解开到明天")
    }
    result(locksPayload())
  }

  private func pickLockApps(_ args: [String: Any], _ result: @escaping FlutterResult) {
    let saved = (args["id"] as? String).flatMap(ScreenTimeStore.lock).flatMap(LockShield.selection)
    let initial = draftSelection ?? saved ?? FamilyActivitySelection()
    presentActivityPicker(initial: initial, title: "选要锁的 App", result: result) { picked in
      guard let picked else { return result(nil) }
      self.draftSelection = picked
      result([
        "apps": picked.applicationTokens.count,
        "categories": picked.categoryTokens.count,
        "webDomains": picked.webDomainTokens.count,
      ])
    }
  }

  private func saveLock(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard authorized else {
      return result(FlutterError(code: "not_authorized", message: "先授权屏幕使用时间", details: nil))
    }
    guard let minutes = args["minutes"] as? Int, minutes > 0 else {
      return result(FlutterError(code: "bad_args", message: "参数不对", details: nil))
    }
    var locks = ScreenTimeStore.locks
    let id = (args["id"] as? String) ?? String(UUID().uuidString.prefix(8)).lowercased()
    let index = locks.firstIndex { $0.id == id }
    if index == nil && locks.count >= ScreenTimeStore.maxLocks {
      return result(FlutterError(code: "too_many", message: "最多 \(ScreenTimeStore.maxLocks) 个时间锁", details: nil))
    }
    let selection = draftSelection ?? index.flatMap { LockShield.selection(of: locks[$0]) }
    guard let selection,
          !(selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty && selection.webDomainTokens.isEmpty),
          let data = LockShield.encode(selection)
    else {
      return result(FlutterError(code: "no_selection", message: "先选要锁的 App", details: nil))
    }
    let lock = AppLockRecord(id: id, minutes: minutes, selection: data)
    if let index { locks[index] = lock } else { locks.append(lock) }
    ScreenTimeStore.locks = locks
    draftSelection = nil
    // 改过的锁先解开，按新的设置重新算
    LockShield.clear(id)
    ScreenTimeStore.setGraceActive(id, false)
    let center = DeviceActivityCenter()
    let name = ScreenTimeStore.lockActivity(id)
    center.stopMonitoring([name, ScreenTimeStore.graceActivity(id)])
    do {
      let threshold = DateComponents(hour: minutes / 60, minute: minutes % 60)
      try center.startMonitoring(name, during: Self.dailySchedule, events: [ScreenTimeStore.lockEvent: Self.event(selection, threshold)])
      ScreenTimeStore.append("时间锁 \(id.prefix(4))：每天 \(minutes) 分钟")
      result(locksPayload())
    } catch {
      ScreenTimeStore.append("时间锁没开起来：\(error.localizedDescription)")
      result(FlutterError(code: "monitor_failed", message: "时间锁没开起来", details: error.localizedDescription))
    }
  }

  private func deleteLock(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["id"] as? String else {
      return result(FlutterError(code: "bad_args", message: "参数不对", details: nil))
    }
    DeviceActivityCenter().stopMonitoring([ScreenTimeStore.lockActivity(id), ScreenTimeStore.graceActivity(id)])
    LockShield.clear(id)
    ScreenTimeStore.setGraceActive(id, false)
    ScreenTimeStore.locks.removeAll { $0.id == id }
    ScreenTimeStore.append("时间锁 \(id.prefix(4))：删除")
    result(locksPayload())
  }

  /// 每天 0 点到 23:59:59，每天重复
  private static let dailySchedule = DeviceActivitySchedule(
    intervalStart: DateComponents(hour: 0, minute: 0),
    intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
    repeats: true
  )

  private var authorized: Bool { AuthorizationCenter.shared.authorizationStatus == .approved }

  private func status() -> [String: Any] {
    let selection = SelectionStore.value
    return [
      "authorization": Self.authorizationName(AuthorizationCenter.shared.authorizationStatus),
      "apps": selection?.applicationTokens.count ?? 0,
      "categories": selection?.categoryTokens.count ?? 0,
      "webDomains": selection?.webDomainTokens.count ?? 0,
      "monitoring": DeviceActivityCenter().activities.contains(.daily),
      "goalMinutes": ScreenTimeStore.goalMinutes,
      "thresholds": ScreenTimeStore.thresholds,
      "stage": ScreenTimeStore.stageToday,
      "log": ScreenTimeStore.log,
    ]
  }

  private static func authorizationName(_ status: FamilyControls.AuthorizationStatus) -> String {
    switch status {
    case .approved: return "approved"
    case .denied: return "denied"
    case .notDetermined: return "notDetermined"
    @unknown default: return "unknown"
    }
  }

  private func requestAuthorization(_ result: @escaping FlutterResult) {
    Task { @MainActor in
      do {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        ScreenTimeStore.append("授权成功")
        result(self.status())
      } catch {
        ScreenTimeStore.append("授权失败：\(error.localizedDescription)")
        result(FlutterError(code: "auth_failed", message: "没有拿到屏幕使用时间授权", details: error.localizedDescription))
      }
    }
  }

  /// 狗度统计要算哪些 App
  private func presentPicker(_ result: @escaping FlutterResult) {
    let initial = SelectionStore.value ?? FamilyActivitySelection()
    presentActivityPicker(initial: initial, title: "选要统计的 App", result: result) { picked in
      if let picked {
        SelectionStore.value = picked
        ScreenTimeStore.append(
          "选了 \(picked.applicationTokens.count) 个 App、\(picked.categoryTokens.count) 个类别、\(picked.webDomainTokens.count) 个网站")
      }
      result(self.status())
    }
  }

  /// 弹出系统的 App 选择页。用户点“取消”时 [onFinish] 收到 nil；弹不出来时直接用 [result] 报错
  private func presentActivityPicker(
    initial: FamilyActivitySelection, title: String, result: @escaping FlutterResult,
    onFinish: @escaping (FamilyActivitySelection?) -> Void
  ) {
    guard authorized else {
      return result(FlutterError(code: "not_authorized", message: "先授权屏幕使用时间", details: nil))
    }
    guard let presenter = Self.topViewController() else {
      return result(FlutterError(code: "no_window", message: "现在弹不出选择页，稍后再试", details: nil))
    }
    // 先建好页面再换上真正的回调：回调里要用弱引用关掉这个页面
    let host = UIHostingController(rootView: ActivityPicker(initial: initial, title: title, onFinish: { _ in }))
    var finished = false
    host.rootView = ActivityPicker(initial: initial, title: title) { [weak host] picked in
      guard !finished else { return }
      finished = true
      host?.dismiss(animated: true)
      onFinish(picked)
    }
    // 只能点“取消”或“完成”关掉，保证 Flutter 那边一定能收到结果
    host.isModalInPresentation = true
    presenter.present(host, animated: true)
  }

  private func startMonitoring(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let goal = args["goalMinutes"] as? Int, let thresholds = args["thresholds"] as? [Int], !thresholds.isEmpty else {
      result(FlutterError(code: "bad_args", message: "参数不对", details: nil))
      return
    }
    guard authorized else {
      result(FlutterError(code: "not_authorized", message: "先授权屏幕使用时间", details: nil))
      return
    }
    guard let selection = SelectionStore.value,
          !(selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty && selection.webDomainTokens.isEmpty)
    else {
      result(FlutterError(code: "no_selection", message: "先选要统计的 App", details: nil))
      return
    }

    var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
    for (index, minutes) in thresholds.enumerated() {
      let threshold = DateComponents(hour: minutes / 60, minute: minutes % 60)
      events[ScreenTimeStore.eventName(stage: index + 1)] = Self.event(selection, threshold)
    }
    let center = DeviceActivityCenter()
    center.stopMonitoring([.daily])
    ScreenTimeStore.goalMinutes = goal
    ScreenTimeStore.thresholds = thresholds
    ScreenTimeStore.resetToday()
    do {
      try center.startMonitoring(.daily, during: Self.dailySchedule, events: events)
      ScreenTimeStore.append("开始监控：目标 \(goal) 分钟，阈值 \(thresholds.map(String.init).joined(separator: "/")) 分钟")
      result(status())
    } catch {
      ScreenTimeStore.append("监控没开起来：\(error.localizedDescription)")
      result(FlutterError(code: "monitor_failed", message: "监控没开起来", details: error.localizedDescription))
    }
  }

  /// 中途改目标重新开始监控时，今天已经用掉的时间也要算进去（iOS 17.4 起才能指定）
  private static func event(_ s: FamilyActivitySelection, _ threshold: DateComponents) -> DeviceActivityEvent {
    if #available(iOS 17.4, *) {
      return DeviceActivityEvent(
        applications: s.applicationTokens, categories: s.categoryTokens, webDomains: s.webDomainTokens,
        threshold: threshold, includesPastActivity: true)
    }
    return DeviceActivityEvent(
      applications: s.applicationTokens, categories: s.categoryTokens, webDomains: s.webDomainTokens,
      threshold: threshold)
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}

/// 今日排行：把系统的报告视图嵌进 Flutter 页面（UiKitView）。
/// 排行由报告扩展 ios/ScreenTimeReport/ 画出来，主 App 读不到里面的数字。
/// Flutter 传 {"compact": true} 时画“今天”页卡片里的精简版（一句话 + 前三名），不传是完整排行。
final class ScreenTimeReportFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let today = DateInterval(start: Calendar.current.startOfDay(for: Date()), end: Date())
    let filter = DeviceActivityFilter(segment: .daily(during: today), users: .all, devices: .all)
    let compact = (args as? [String: Any])?["compact"] as? Bool == true
    return HostedSwiftUIView(
      frame: frame, root: AnyView(DeviceActivityReport(compact ? .topAppsCompact : .topApps, filter: filter)))
  }
}

/// 时间锁里选了哪些 App 和类别：用系统的 Label 画图标和名字。令牌是不透明的，Flutter 拿不到名字。
/// Flutter 传 {"draft": true} 显示刚选好、还没保存的，传 {"lockId": "..."} 显示已保存的锁。
final class LockSelectionFactory: NSObject, FlutterPlatformViewFactory {
  private weak var plugin: ScreenTimePlugin?

  init(plugin: ScreenTimePlugin) {
    self.plugin = plugin
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let params = args as? [String: Any] ?? [:]
    let selection = params["draft"] as? Bool == true
      ? plugin?.draftSelection
      : (params["lockId"] as? String).flatMap(ScreenTimeStore.lock).flatMap(LockShield.selection)
    return HostedSwiftUIView(frame: frame, root: AnyView(SelectionChips(selection: selection ?? FamilyActivitySelection())))
  }
}

/// 把 SwiftUI 视图嵌进 Flutter 页面（UiKitView）
final class HostedSwiftUIView: NSObject, FlutterPlatformView {
  private let host: UIHostingController<AnyView>

  init(frame: CGRect, root: AnyView) {
    host = UIHostingController(rootView: root)
    // App 只做浅色，嵌进来的系统视图也按浅色画
    host.overrideUserInterfaceStyle = .light
    host.view.frame = frame
    host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    host.view.backgroundColor = .clear
    super.init()
  }

  func view() -> UIView { host.view }
}

/// 一排小标签：单个 App、整个类别（标“整类”）、网站
private struct SelectionChips: View {
  let selection: FamilyActivitySelection

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(Array(selection.applicationTokens), id: \.self) { token in
          chip(icon: Label(token), title: Label(token), tag: nil)
        }
        ForEach(Array(selection.categoryTokens), id: \.self) { token in
          chip(icon: Label(token), title: Label(token), tag: "整类")
        }
        ForEach(Array(selection.webDomainTokens), id: \.self) { token in
          chip(icon: Label(token), title: Label(token), tag: nil)
        }
      }
      .padding(.vertical, 2)
    }
  }

  private func chip<L: View>(icon: L, title: L, tag: String?) -> some View {
    HStack(spacing: 6) {
      icon.labelStyle(.iconOnly).frame(width: 20, height: 20).clipped()
      title.labelStyle(.titleOnly).font(.system(size: 14, weight: .semibold)).lineLimit(1)
      if let tag {
        Text(tag)
          .font(.system(size: 11, weight: .bold))
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(Capsule().fill(Color(red: 1, green: 0xD2 / 255, blue: 0x3F / 255)))
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 30)
    .background(Capsule().fill(Color(red: 0xF3 / 255, green: 0xF4 / 255, blue: 0xF6 / 255)))
  }
}

/// 选中的 App、类别和网站（不透明令牌），只存在本机
private enum SelectionStore {
  static var value: FamilyActivitySelection? {
    get {
      guard let data = ScreenTimeStore.defaults?.data(forKey: "selection") else { return nil }
      return try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
    }
    set {
      ScreenTimeStore.defaults?.set(newValue.flatMap { try? PropertyListEncoder().encode($0) }, forKey: "selection")
    }
  }
}

private struct ActivityPicker: View {
  @State private var selection: FamilyActivitySelection
  let title: String
  let onFinish: (FamilyActivitySelection?) -> Void

  init(initial: FamilyActivitySelection, title: String, onFinish: @escaping (FamilyActivitySelection?) -> Void) {
    _selection = State(initialValue: initial)
    self.title = title
    self.onFinish = onFinish
  }

  var body: some View {
    NavigationStack {
      FamilyActivityPicker(selection: $selection)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("取消") { onFinish(nil) } }
          ToolbarItem(placement: .confirmationAction) { Button("完成") { onFinish(selection) } }
        }
    }
  }
}
