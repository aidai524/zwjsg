import DeviceActivity
import Foundation

extension DeviceActivityName {
  /// 每天 0 点到 23:59:59 的统计周期
  static let daily = Self("daily")
}

/// 主 App 和监控扩展共用的本机存储（App Group），两个 target 都编译这个文件。
/// 只存今天到了第几阶段、最近每天到过的最高阶段、阈值和调试记录：不存任何 App 名称，也不上传。
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
    // 每天到过的最高阶段也记一份：没打开 App 的日子，历史统计也有真实数据
    var history = stageHistory
    history[day] = max(history[day] ?? 0, stage)
    let keep = Set(history.keys.sorted().suffix(historyDays))
    d.set(history.filter { keep.contains($0.key) }, forKey: Key.history)
  }

  /// 最近每天到过的最高阶段（日期 yyyy-MM-dd → 阶段 0–5）。每天统计周期一开始就记 0，没在统计的日子没有
  static var stageHistory: [String: Int] { defaults?.dictionary(forKey: Key.history) as? [String: Int] ?? [:] }

  /// 留最近多少天
  static let historyDays = 120

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
    static let history = "stageHistory"
    static let locks = "locks"
    static let call = "callRequest"
    static let previewCall = "previewCall"
    static func lockedDay(_ id: String) -> String { "lockedDay.\(id)" }
    static func declinedDay(_ id: String) -> String { "declinedDay.\(id)" }
  }

  // MARK: 超时来电（2026-11-23 起是一个像 FaceTime 的来电界面）
  // 屏蔽页和它的按钮扩展不能放动画、不能出声、不能开麦克风，也打不开 App：
  // 用满时监控扩展记下“有一通来电”、发一条带铃声的通知；在屏蔽页上点“接听”就记下“已接听”。
  // 主 App 打开时看到就弹来电界面（Flutter 的 CallScreen），学会两声狗叫再由主 App 放行。拒接 = 今天锁死

  /// 没接的来电：多久内打开 App 还在响
  static let callRingSeconds: TimeInterval = 10 * 60

  /// 在屏蔽页上点了接听：多久内打开 App 还接着通话
  static let callAnsweredSeconds: TimeInterval = 30 * 60

  /// 来电铃声：主 App 启动时从 Flutter 资源（assets/sounds/ring.caf）拷到 App Group 的 Library/Sounds，
  /// 扩展发的通知也能用（系统只在 App、App Group 的 Library/Sounds 和发通知的那个包里找铃声）
  static let ringSound = "dog_call.caf"

  static func recordCall(_ lockId: String, answered: Bool) {
    defaults?.set(["id": lockId, "at": Date().timeIntervalSince1970, "answered": answered], forKey: Key.call)
  }

  /// 正在打来的电话
  static var pendingCall: (id: String, answered: Bool)? {
    guard let d = defaults?.dictionary(forKey: Key.call), let id = d["id"] as? String,
      let at = d["at"] as? TimeInterval
    else { return nil }
    let answered = d["answered"] as? Bool ?? false
    guard Date().timeIntervalSince1970 - at < (answered ? callAnsweredSeconds : callRingSeconds) else { return nil }
    return (id, answered)
  }

  static func clearCall() { defaults?.removeObject(forKey: Key.call) }

  /// “试一下来电通知”（只在主 App 用）：记下 Flutter 交过来的那通试一下的来电和通知响的时间，
  /// 点通知回到 App 时弹出来。通知响之前回来不算，响了以后 10 分钟内有效，读一次就清掉
  static func recordPreviewCall(_ call: [String: Any], ringsAt: Date) {
    defaults?.set(["call": call, "at": ringsAt.timeIntervalSince1970], forKey: Key.previewCall)
  }

  static func takePreviewCall() -> [String: Any]? {
    guard let d = defaults?.dictionary(forKey: Key.previewCall), let call = d["call"] as? [String: Any],
      let at = d["at"] as? TimeInterval
    else { return nil }
    let now = Date().timeIntervalSince1970
    // 通知还没响：先不弹，也不清掉
    if now < at - 1 { return nil }
    defaults?.removeObject(forKey: Key.previewCall)
    return now - at < callRingSeconds ? call : nil
  }

  /// 今天拒接了这个限时的来电：锁到明天 0 点
  static func isDeclinedToday(_ id: String) -> Bool { defaults?.string(forKey: Key.declinedDay(id)) == today() }

  static func setDeclinedToday(_ id: String) { defaults?.set(today(), forKey: Key.declinedDay(id)) }

  /// 和 DogMeter.formatMinutes 一样
  static func formatMinutes(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    if h == 0 { return "\(m) 分钟" }
    return m == 0 ? "\(h) 小时" : "\(h) 小时 \(m) 分"
  }
}

/// 一个单个 App 限时：选中的 App（系统的不透明令牌，编码后存）每天合计用满 [minutes] 分钟，屏蔽页就“来电”问还玩不玩。
/// 按狗度来的（dogPercent 不为空，2026-11-27）：今天狗度统计的那些 App 一共刷到目标的这么多（%）以后，挡住选中的 App、来电
struct AppLockRecord: Codable {
  let id: String
  var minutes: Int
  /// FamilyActivitySelection 编码后的数据；这个文件不依赖 FamilyControls，解码在 LockShield 里
  var selection: Data
  /// 按狗度来电（%）；按额度的是 nil（以前存的限时没有这一项，解出来也是 nil）
  var dogPercent: Int? = nil

  /// 来电时说的“为什么打来”
  var callReason: String {
    if let dogPercent { return "今天狗度到 \(dogPercent)% 了" }
    return "说好一天 \(ScreenTimeStore.formatMinutes(minutes))，时间到了"
  }
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

  // MARK: 超时来电：用满后屏蔽页上点“再玩 10 分钟”就放行，不限次数，再用满又挡一下（按使用时长算，和安卓一致）

  static let snoozeMinutes = 10

  /// 再玩的那几分钟单独开一个统计周期：再用满 snoozeMinutes 就重新挡上
  static func graceActivity(_ id: String) -> DeviceActivityName { .init("grace.\(id)") }

  static func graceLockId(of activity: DeviceActivityName) -> String? {
    activity.rawValue.hasPrefix("grace.") ? String(activity.rawValue.dropFirst("grace.".count)) : nil
  }

  /// 正在“再玩 10 分钟”的那几分钟里
  static func isGraceActive(_ id: String) -> Bool { defaults?.string(forKey: "graceActive.\(id)") == today() }

  static func setGraceActive(_ id: String, _ active: Bool) {
    defaults?.set(active ? today() : nil, forKey: "graceActive.\(id)")
  }
}
