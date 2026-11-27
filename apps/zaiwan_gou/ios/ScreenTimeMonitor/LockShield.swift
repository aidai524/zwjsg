import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import UserNotifications

/// 单个 App 限时的屏蔽（超时来电）。主 App、监控扩展、屏蔽页和屏蔽页按钮扩展都编译这个文件。
/// 每个限时用一个单独命名的设置存储，放行一个不会影响别的。
enum LockShield {
  static func store(_ id: String) -> ManagedSettingsStore { ManagedSettingsStore(named: .init("lock.\(id)")) }

  static func selection(of lock: AppLockRecord) -> FamilyActivitySelection? {
    try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: lock.selection)
  }

  static func encode(_ selection: FamilyActivitySelection) -> Data? {
    try? PropertyListEncoder().encode(selection)
  }

  /// 用满了：挡住这个限时里的 App、类别和网站，屏蔽页做成来电的样子问还玩不玩
  static func apply(_ lock: AppLockRecord) {
    guard let s = selection(of: lock) else { return }
    let store = store(lock.id)
    store.shield.applications = s.applicationTokens.isEmpty ? nil : s.applicationTokens
    store.shield.applicationCategories = s.categoryTokens.isEmpty ? nil : .specific(s.categoryTokens)
    store.shield.webDomains = s.webDomainTokens.isEmpty ? nil : s.webDomainTokens
    store.shield.webDomainCategories = s.categoryTokens.isEmpty ? nil : .specific(s.categoryTokens)
    ScreenTimeStore.setLockedToday(lock.id, true)
  }

  static func clear(_ id: String) {
    store(id).clearAllSettings()
    ScreenTimeStore.setLockedToday(id, false)
  }

  /// 学会两声狗叫以后（主 App 调用，2026-11-23 起）：先放行，单独统计这几分钟，用满了监控扩展再挡上。不限次数。
  /// 快到 0 点时统计周期太短（系统要求至少 15 分钟），就放行到明天。
  static func snooze(_ lock: AppLockRecord) {
    guard let s = selection(of: lock) else { return }
    ScreenTimeStore.setGraceActive(lock.id, true)
    clear(lock.id)
    let center = DeviceActivityCenter()
    let name = ScreenTimeStore.graceActivity(lock.id)
    center.stopMonitoring([name])
    let now = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
    let schedule = DeviceActivitySchedule(
      intervalStart: now, intervalEnd: DateComponents(hour: 23, minute: 59, second: 59), repeats: false)
    let event = DeviceActivityEvent(
      applications: s.applicationTokens, categories: s.categoryTokens, webDomains: s.webDomainTokens,
      threshold: DateComponents(minute: ScreenTimeStore.snoozeMinutes))
    do {
      try center.startMonitoring(name, during: schedule, events: [ScreenTimeStore.lockEvent: event])
      ScreenTimeStore.append("限时 \(lock.id.prefix(4))：再玩 \(ScreenTimeStore.snoozeMinutes) 分钟")
    } catch {
      ScreenTimeStore.append("限时 \(lock.id.prefix(4))：快到 0 点了，放行到明天")
    }
  }

  /// 被挡住的 App / 网站 / 类别属于哪个限时
  static func lock(containing app: ApplicationToken) -> AppLockRecord? {
    ScreenTimeStore.locks.first { selection(of: $0)?.applicationTokens.contains(app) == true }
  }

  static func lock(containing domain: WebDomainToken) -> AppLockRecord? {
    ScreenTimeStore.locks.first { selection(of: $0)?.webDomainTokens.contains(domain) == true }
  }

  static func lock(containing category: ActivityCategoryToken) -> AppLockRecord? {
    ScreenTimeStore.locks.first { selection(of: $0)?.categoryTokens.contains(category) == true }
  }
}

/// 超时来电的通知（监控扩展、屏蔽页按钮扩展、主 App 都用）。扩展只拿得到 App 的令牌，通知里不写 App 名称
enum CallNotice {
  static let id = "call"

  /// “试一下来电通知”用单独的编号，不顶掉真的来电
  static let previewId = "call.preview"

  /// 响铃：用满了（或者狗度到了），狗版的你打来电话。铃声是 App Group 里的原创铃声（约 26 秒）；静音模式下跟系统一样只震动
  static func ring(_ lock: AppLockRecord) { ring(reason: lock.callReason) }

  /// [reason] 是为什么打来（“说好一天 1 小时，时间到了”“今天狗度到 100% 了”）；
  /// [delay] 秒以后响（0 = 马上）；[preview] 是“试一下来电通知”，通知里写明是试一下
  static func ring(reason: String, after delay: TimeInterval = 0, preview: Bool = false, _ done: ((Error?) -> Void)? = nil) {
    let content = UNMutableNotificationContent()
    content.title = "狗版的你打来电话…"
    content.body = "\(reason)。点这里接听；拒接今天就锁死。" + (preview ? "（试一下，不会真的锁）" : "")
    content.sound = UNNotificationSound(named: UNNotificationSoundName(ScreenTimeStore.ringSound))
    content.threadIdentifier = id
    let trigger = delay > 0 ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false) : nil
    let request = UNNotificationRequest(identifier: preview ? previewId : id, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request) { error in done?(error) }
  }

  /// 在屏蔽页上点了接听：屏蔽页按钮扩展打不开 App，发一条通知把人带回「再玩我是狗」接着通话
  static func answered(_ done: @escaping () -> Void) {
    let content = UNMutableNotificationContent()
    content.title = "接通了，狗版的你在等你"
    content.body = "点这里听它说两句；想再玩 \(ScreenTimeStore.snoozeMinutes) 分钟，就学两声狗叫"
    content.sound = .default
    content.threadIdentifier = id
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { _ in
      done()
    }
  }

  /// 来电处理完了（放行、拒接、挂断）：收起通知
  static func cancel() {
    let center = UNUserNotificationCenter.current()
    center.removeDeliveredNotifications(withIdentifiers: [id])
    center.removePendingNotificationRequests(withIdentifiers: [id])
  }
}
