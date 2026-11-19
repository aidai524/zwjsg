import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

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

  /// 屏蔽页上点了“再玩 10 分钟”：先放行，单独统计这几分钟，用满了监控扩展再挡上。不限次数。
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
