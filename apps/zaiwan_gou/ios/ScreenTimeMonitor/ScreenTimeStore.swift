import DeviceActivity
import Foundation

extension DeviceActivityName {
  /// 每天 0 点到 23:59:59 的统计周期
  static let daily = Self("daily")
}

/// 主 App 和监控扩展共用的本机存储（App Group），两个 target 都编译这个文件。
/// 只存今天到了第几阶段、阈值和调试记录：不存任何 App 名称，也不上传。
enum ScreenTimeStore {
  static let appGroup = "group.com.zwjsg.zwjsgApp"

  static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

  /// 阶段 n 的阈值事件叫 stage<n>
  static func eventName(stage: Int) -> DeviceActivityEvent.Name { .init("stage\(stage)") }

  static func stage(of event: DeviceActivityEvent.Name) -> Int? {
    guard event.rawValue.hasPrefix("stage") else { return nil }
    return Int(event.rawValue.dropFirst("stage".count))
  }

  /// 今天到了第几阶段。记录还停在前一天（过了 0 点还没重置）时按 0 算。
  static var stageToday: Int {
    guard let d = defaults, d.string(forKey: Key.day) == today() else { return 0 }
    return d.integer(forKey: Key.stage)
  }

  /// 阶段只升不降：同一天收到较低阶段的通知，不会把阶段拉回去
  static func recordStage(_ stage: Int) {
    guard let d = defaults else { return }
    let day = today()
    let current = d.string(forKey: Key.day) == day ? d.integer(forKey: Key.stage) : 0
    d.set(day, forKey: Key.day)
    d.set(max(current, stage), forKey: Key.stage)
  }

  /// 主 App 重新开始监控时调用：今天从阶段 0 重新算
  static func resetToday() {
    defaults?.set(today(), forKey: Key.day)
    defaults?.set(0, forKey: Key.stage)
  }

  /// 统计周期开始时调用：跨天才归零，免得冲掉刚开始监控时补发的阈值通知
  static func startDayIfNeeded() {
    guard defaults?.string(forKey: Key.day) != today() else { return }
    resetToday()
  }

  static var goalMinutes: Int {
    get { defaults?.integer(forKey: Key.goal) ?? 0 }
    set { defaults?.set(newValue, forKey: Key.goal) }
  }

  /// 各阶段的分钟数阈值，由 Flutter 按 dog_meter.dart 的规则算好传进来
  static var thresholds: [Int] {
    get { defaults?.array(forKey: Key.thresholds) as? [Int] ?? [] }
    set { defaults?.set(newValue, forKey: Key.thresholds) }
  }

  /// 调试记录，最多留 60 条，用来在真机上核对阈值通知来得准不准
  static var log: [String] { defaults?.stringArray(forKey: Key.log) ?? [] }

  static func append(_ message: String) {
    guard let d = defaults else { return }
    let lines = (d.stringArray(forKey: Key.log) ?? []) + ["\(format("MM-dd HH:mm:ss")) \(message)"]
    d.set(Array(lines.suffix(60)), forKey: Key.log)
  }

  static func today() -> String { format("yyyy-MM-dd") }

  private static func format(_ pattern: String) -> String {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = pattern
    return f.string(from: Date())
  }

  private enum Key {
    static let day = "day"
    static let stage = "stage"
    static let goal = "goalMinutes"
    static let thresholds = "thresholds"
    static let log = "log"
    static let locks = "locks"
    static func lockedDay(_ id: String) -> String { "lockedDay.\(id)" }
  }
}

/// 一个 App 时间锁：选中的 App（系统的不透明令牌，编码后存）每天合计用满 [minutes] 分钟就锁到 0 点
struct AppLockRecord: Codable {
  let id: String
  var minutes: Int
  /// FamilyActivitySelection 编码后的数据；这个文件不依赖 FamilyControls，解码在 LockShield 里
  var selection: Data
}

extension ScreenTimeStore {
  static let maxLocks = 10

  /// 每个锁单独一个统计周期，改锁不影响狗度的监控
  static func lockActivity(_ id: String) -> DeviceActivityName { .init("lock.\(id)") }

  static func lockId(of activity: DeviceActivityName) -> String? {
    activity.rawValue.hasPrefix("lock.") ? String(activity.rawValue.dropFirst("lock.".count)) : nil
  }

  static let lockEvent = DeviceActivityEvent.Name("limit")

  static var locks: [AppLockRecord] {
    get {
      guard let data = defaults?.data(forKey: Key.locks) else { return [] }
      return (try? JSONDecoder().decode([AppLockRecord].self, from: data)) ?? []
    }
    set { defaults?.set(try? JSONEncoder().encode(newValue), forKey: Key.locks) }
  }

  static func lock(_ id: String) -> AppLockRecord? { locks.first { $0.id == id } }

  /// 这个锁今天是不是已经锁上了
  static func isLockedToday(_ id: String) -> Bool { defaults?.string(forKey: Key.lockedDay(id)) == today() }

  static func setLockedToday(_ id: String, _ locked: Bool) {
    defaults?.set(locked ? today() : nil, forKey: Key.lockedDay(id))
  }

  // MARK: 紧急解锁：每个锁每天 gracesPerDay 次，每次再用 graceMinutes 分钟（按使用时长算，和安卓一致）

  static let gracesPerDay = 3
  static let graceMinutes = 5

  /// 临时解锁时单独开一个统计周期：再用满 graceMinutes 就重新锁上
  static func graceActivity(_ id: String) -> DeviceActivityName { .init("grace.\(id)") }

  static func graceLockId(of activity: DeviceActivityName) -> String? {
    activity.rawValue.hasPrefix("grace.") ? String(activity.rawValue.dropFirst("grace.".count)) : nil
  }

  private static func usedGracesToday(_ id: String) -> Int {
    guard let d = defaults, d.string(forKey: "graceDay.\(id)") == today() else { return 0 }
    return d.integer(forKey: "graceCount.\(id)")
  }

  /// 今天还能紧急解锁几次
  static func graceLeft(_ id: String) -> Int { max(0, gracesPerDay - usedGracesToday(id)) }

  static func useGrace(_ id: String) {
    let used = usedGracesToday(id)
    defaults?.set(today(), forKey: "graceDay.\(id)")
    defaults?.set(used + 1, forKey: "graceCount.\(id)")
  }

  /// 正在临时解锁的那几分钟里
  static func isGraceActive(_ id: String) -> Bool { defaults?.string(forKey: "graceActive.\(id)") == today() }

  static func setGraceActive(_ id: String, _ active: Bool) {
    defaults?.set(active ? today() : nil, forKey: "graceActive.\(id)")
  }
}
