import Foundation

/// 主 App 和桌面小组件共用的东西，两个 target 都编进这个文件。都在 App Group 里：
/// - `widget/config.json`：App 写，小组件读。狗度阈值和文案（照搬 dog_meter.dart）、每日目标、数据来源
/// - `widget/avatars/`：App 预先画好的 6 张形象图（变狗阶段 0–5，见 Flutter 的 HomeWidgetSync）
/// - 今天到了第几阶段、各阶段的分钟数：监控扩展写在 UserDefaults 里（ScreenTimeStore），小组件只读
/// 只有狗度和阶段，没有任何 App 名称，也不上传。
enum GouWidgetShared {
  static let appGroup = "group.com.zwjsg.zwjsgApp"

  /// 小组件的 kind，App 和监控扩展叫小组件刷新时用
  static let kind = "GouWidget"

  /// Flutter 的 DogWidgetConfig.toMap
  struct Config: Codable {
    /// 同意了隐私政策、做完了引导
    let ready: Bool
    /// usage（安卓按分钟算）/ screenTime（iOS 读阶段）/ none（还拿不到真实数据）
    let source: String
    let goalMinutes: Int
    /// 阶段 1–5 的狗度阈值（百分比）
    let thresholds: [Int]
    let stageNames: [String]
    let quips: [String]
    let nextChange: [String]
  }

  private static var root: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
      .appendingPathComponent("widget", isDirectory: true)
  }

  static var avatarDirectory: URL? { root?.appendingPathComponent("avatars", isDirectory: true) }

  private static var configFile: URL? { root?.appendingPathComponent("config.json") }

  /// App 传来的配置，原样存成 JSON
  static func saveConfig(_ args: Any?) {
    guard let file = configFile, let args, JSONSerialization.isValidJSONObject(args),
          let data = try? JSONSerialization.data(withJSONObject: args)
    else { return }
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: file, options: .atomic)
  }

  static func loadConfig() -> Config? {
    guard let file = configFile, let data = try? Data(contentsOf: file) else { return nil }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try? decoder.decode(Config.self, from: data)
  }

  // MARK: 监控扩展记下的数据（键名和 ScreenTimeStore 一致）

  private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

  /// 今天到了第几阶段。记录还停在前一天（过了 0 点还没重置）时按 0 算，和 ScreenTimeStore.stageToday 一样
  static func screenTimeStageToday() -> Int {
    guard let d = defaults, d.string(forKey: "day") == today() else { return 0 }
    return d.integer(forKey: "stage")
  }

  /// 各阶段的分钟数阈值（ScreenTimeStore.thresholds）
  static func screenTimeThresholds() -> [Int] {
    defaults?.array(forKey: "thresholds") as? [Int] ?? []
  }

  static func today() -> String {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
  }
}
