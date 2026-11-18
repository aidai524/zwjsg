import Foundation

/// App 和桌面小组件共用的东西，两边的 target 都编进这个文件。
///
/// 都放在 App Group 的共享目录里，用普通文件，不用 UserDefaults（省得在隐私清单里申报）：
/// - `config.json`：App 写，小组件读。查哪个城市、什么温度单位、后端地址；还没选城市时没有这个文件。
/// - `avatars/`：App 预先画好的 61 张形象图（见 Flutter 的 HomeWidgetSync），小组件按后端给的衣服档和天气状态挑一张。
/// - `last.json`：小组件写，上一次取到的天气，取不到新的时先显示它。
enum WidgetShared {
  static let appGroup = "group.com.zwjsg.shenmeTianqi"

  /// 小组件的 kind，App 让小组件刷新时用
  static let kind = "WeatherWidget"

  struct Config: Codable, Equatable {
    let apiBase: String
    let locationId: String
    let city: String
    let adm: String?
    let unit: String
  }

  static var container: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
  }

  static var avatarDirectory: URL? { container?.appendingPathComponent("avatars", isDirectory: true) }

  private static var configFile: URL? { container?.appendingPathComponent("config.json") }

  static var lastFile: URL? { container?.appendingPathComponent("last.json") }

  /// App 传来的配置（Flutter 的 HomeWidgetConfig.toMap）；nil 表示还没选城市或还没同意隐私政策，连同旧天气一起删掉
  static func saveConfig(_ args: [String: Any]?) {
    guard let file = configFile else { return }
    guard let args,
          let apiBase = args["api_base"] as? String,
          let locationId = args["location_id"] as? String,
          let city = args["city"] as? String,
          let unit = args["unit"] as? String
    else {
      try? FileManager.default.removeItem(at: file)
      if let last = lastFile { try? FileManager.default.removeItem(at: last) }
      return
    }
    let config = Config(apiBase: apiBase, locationId: locationId, city: city, adm: args["adm"] as? String, unit: unit)
    if let data = try? JSONEncoder().encode(config) {
      try? data.write(to: file, options: .atomic)
    }
  }

  static func loadConfig() -> Config? {
    guard let file = configFile, let data = try? Data(contentsOf: file) else { return nil }
    return try? JSONDecoder().decode(Config.self, from: data)
  }
}
