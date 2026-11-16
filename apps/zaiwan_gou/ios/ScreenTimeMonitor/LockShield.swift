import FamilyControls
import Foundation
import ManagedSettings

/// App 时间锁的屏蔽。主 App 和监控扩展都编译这个文件。
/// 每个锁用一个单独命名的设置存储，解开一个锁不会影响别的锁。
enum LockShield {
  static func store(_ id: String) -> ManagedSettingsStore { ManagedSettingsStore(named: .init("lock.\(id)")) }

  static func selection(of lock: AppLockRecord) -> FamilyActivitySelection? {
    try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: lock.selection)
  }

  static func encode(_ selection: FamilyActivitySelection) -> Data? {
    try? PropertyListEncoder().encode(selection)
  }

  /// 用满了：挡住这个锁里的 App、类别和网站，直到 0 点
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
}
