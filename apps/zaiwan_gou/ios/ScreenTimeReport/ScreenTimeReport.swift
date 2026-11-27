import DeviceActivity
import ExtensionKit
import FamilyControls
import ManagedSettings
import SwiftUI

/// 报告扩展：系统在沙盒里调起它，把今日排行画进主 App 的页面。
/// 这里的数据（每个 App 用了多久）出不了这个扩展：主 App 读不到，也不能上传。
@main
struct ScreenTimeReportExtension: DeviceActivityReportExtension {
  var body: some DeviceActivityReportScene {
    TopAppsReport { TopAppsView(report: $0) }
    TopAppsCompactReport { TopAppsCompactView(report: $0) }
    LimitAdviceReport { LimitAdviceView(advice: $0) }
    LimitAdviceCompactReport { LimitAdviceView(advice: $0, compact: true) }
  }
}

struct TopApps {
  struct Item: Identifiable {
    /// 名次，从 1 开始
    let id: Int
    let token: ApplicationToken?
    let name: String
    let duration: TimeInterval
  }

  var items: [Item] = []
  var total: TimeInterval = 0
  /// 统计了几天（一天一个时间段）：历史统计页看最近 7 天
  var days = 0

  private struct Entry {
    let token: ApplicationToken?
    let name: String
    var duration: TimeInterval
  }

  static func make(from data: DeviceActivityResults<DeviceActivityData>) async -> TopApps {
    var byApp: [String: Entry] = [:]
    var days = 0
    for await device in data {
      for await segment in device.activitySegments {
        days += 1
        for await category in segment.categories {
          for await activity in category.applications {
            let app = activity.application
            let name = app.localizedDisplayName ?? app.bundleIdentifier ?? "未知 App"
            let key = app.bundleIdentifier ?? name
            var entry = byApp[key] ?? Entry(token: app.token, name: name, duration: 0)
            entry.duration += activity.totalActivityDuration
            byApp[key] = entry
          }
        }
      }
    }
    // 和安卓一致：不到 1 分钟的不算，最多列 30 个
    let ranked = byApp.values.filter { $0.duration >= 60 }.sorted { $0.duration > $1.duration }.prefix(30)
    return TopApps(
      items: ranked.enumerated().map {
        TopApps.Item(id: $0.offset + 1, token: $0.element.token, name: $0.element.name, duration: $0.element.duration)
      },
      total: byApp.values.reduce(0) { $0 + $1.duration },
      days: days
    )
  }
}

/// 完整排行（“今日 App 排行”页）
struct TopAppsReport: DeviceActivityReportScene {
  let context: DeviceActivityReport.Context = .topApps
  let content: (TopApps) -> TopAppsView

  func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TopApps {
    await TopApps.make(from: data)
  }
}

/// 超时来电的建议。和 App 里的 LockAdvisor（lib/core/lock_advisor.dart）同一个规则，改动时两边一起改：
/// - 娱乐类（屏幕使用时间的类别是社交、游戏、娱乐）平均每天 20 分钟以上就建议，别的类别要 45 分钟以上；
/// - 聊天、办公、地图、支付这些离不开的不建议，本 App 自己也不建议；
/// - 额度取不超过平均用时七成的最大一档（15 到 180 分钟），至少 15 分钟；最多建议 3 个，娱乐类在前。
struct LimitAdvice {
  struct Item: Identifiable {
    let id: Int
    let token: ApplicationToken?
    let name: String
    let averageMinutes: Int
    let suggestedMinutes: Int
  }

  var items: [Item] = []
  /// 最费时间的前三名（名字）
  var top: [String] = []
  var days = 0

  static let presets = [15, 30, 45, 60, 90, 120, 180]
  static let funCategories: Set<String> = ["社交", "游戏", "娱乐", "Social", "Games", "Entertainment"]
  static let neverSuggest: Set<String> = [
    "com.tencent.xin", "com.tencent.mqq", "com.tencent.ww", "com.laiwang.DingTalk",
    "com.autonavi.amap", "com.baidu.map", "com.alipay.iphoneclient", "com.zwjsg.zwjsgApp",
  ]

  static func suggested(_ average: Int) -> Int {
    presets.last { Double($0) <= Double(average) * 0.7 } ?? presets[0]
  }

  private struct Entry {
    let token: ApplicationToken?
    let name: String
    let bundle: String?
    var fun: Bool
    var duration: TimeInterval
    /// 已经设了限时（这个 App，或者它所在的整个类别）
    var locked: Bool
  }

  /// 已经设了限时的 App 和类别（2026-11-27）：从 App Group 读主 App 存的限时（ScreenTimeStore 的 locks 键，只读），
  /// 建议里跳过它们，和安卓的 LockAdvisor 跳过已经设了的一样。读不到就当没有
  static func lockedTokens() -> (apps: Set<ApplicationToken>, categories: Set<ActivityCategoryToken>) {
    struct Record: Decodable { let selection: Data }
    guard let data = UserDefaults(suiteName: "group.com.zwjsg.zwjsgApp")?.data(forKey: "locks"),
          let records = try? JSONDecoder().decode([Record].self, from: data)
    else { return ([], []) }
    var apps = Set<ApplicationToken>()
    var categories = Set<ActivityCategoryToken>()
    for record in records {
      guard let selection = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: record.selection) else {
        continue
      }
      apps.formUnion(selection.applicationTokens)
      categories.formUnion(selection.categoryTokens)
    }
    return (apps, categories)
  }

  static func make(from data: DeviceActivityResults<DeviceActivityData>) async -> LimitAdvice {
    var byApp: [String: Entry] = [:]
    var days = 0
    let locked = lockedTokens()
    for await device in data {
      for await segment in device.activitySegments {
        days += 1
        for await category in segment.categories {
          let fun = funCategories.contains(category.category.localizedDisplayName ?? "")
          let categoryLocked = category.category.token.map { locked.categories.contains($0) } ?? false
          for await activity in category.applications {
            let app = activity.application
            let name = app.localizedDisplayName ?? app.bundleIdentifier ?? "未知 App"
            let key = app.bundleIdentifier ?? name
            var entry = byApp[key]
              ?? Entry(token: app.token, name: name, bundle: app.bundleIdentifier, fun: fun, duration: 0, locked: false)
            entry.duration += activity.totalActivityDuration
            entry.fun = entry.fun || fun
            entry.locked = entry.locked || categoryLocked || (app.token.map { locked.apps.contains($0) } ?? false)
            byApp[key] = entry
          }
        }
      }
    }
    let ranked = byApp.values.filter { $0.duration >= 60 }.sorted { $0.duration > $1.duration }
    var fun: [(Entry, Int)] = []
    var others: [(Entry, Int)] = []
    // “最费时间的是”照旧列全；建议里跳过离不开的和已经设了限时的
    for entry in ranked where !entry.locked {
      if let bundle = entry.bundle, neverSuggest.contains(bundle) { continue }
      let average = Int((entry.duration / 60 / Double(max(days, 1))).rounded())
      if average < (entry.fun ? 20 : 45) { continue }
      if entry.fun { fun.append((entry, average)) } else { others.append((entry, average)) }
    }
    let picks = Array((fun + others).prefix(3))
    return LimitAdvice(
      items: picks.enumerated().map {
        Item(
          id: $0.offset, token: $0.element.0.token, name: $0.element.0.name,
          averageMinutes: $0.element.1, suggestedMinutes: suggested($0.element.1))
      },
      top: ranked.prefix(3).map(\.name),
      days: days
    )
  }
}

/// 超时来电页的建议卡片里那一块
struct LimitAdviceReport: DeviceActivityReportScene {
  let context: DeviceActivityReport.Context = .limitAdvice
  let content: (LimitAdvice) -> LimitAdviceView

  func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> LimitAdvice {
    await LimitAdvice.make(from: data)
  }
}

/// 编辑页里的精简版：只有那几行，没有上面两句
struct LimitAdviceCompactReport: DeviceActivityReportScene {
  let context: DeviceActivityReport.Context = .limitAdviceCompact
  let content: (LimitAdvice) -> LimitAdviceView

  func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> LimitAdvice {
    await LimitAdvice.make(from: data)
  }
}

/// Flutter 给它留了 232 点高（lib/features/locks/lock_advice_card.dart）；精简版 [compact] 留 126 点高（IosLockService.adviceReference）
struct LimitAdviceView: View {
  let advice: LimitAdvice
  var compact = false

  static let softYellow = Color(red: 1, green: 0xF4 / 255, blue: 0xC2 / 255)

  var body: some View {
    Group {
      if advice.items.isEmpty {
        Text(advice.top.isEmpty ? "最近还没有用满 1 分钟的 App" : "最近 \(advice.days) 天没有特别上头的 App，好狗。想管哪个，就去设限时。")
          .font(.system(size: 14))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else if compact {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(advice.items) { row($0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        VStack(alignment: .leading, spacing: 10) {
          Text("最费时间的是：\(advice.top.joined(separator: "、"))")
            .font(.system(size: 14, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
          Text("建议先给这几个设限时，额度比平时少三成左右：")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
          ForEach(advice.items) { row($0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
    .foregroundStyle(TopAppsView.ink)
    .background(Color.white)
    .environment(\.colorScheme, .light)
  }

  private func row(_ item: LimitAdvice.Item) -> some View {
    HStack(spacing: 10) {
      Group {
        if let token = item.token {
          Label(token).labelStyle(.iconOnly)
        } else {
          Image(systemName: "app.fill").foregroundStyle(.secondary)
        }
      }
      .frame(width: 30, height: 30)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.name).font(.system(size: 15, weight: .bold)).lineLimit(1)
        Text("平均每天 \(TopAppsView.format(TimeInterval(item.averageMinutes * 60)))")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Text("建议每天 \(TopAppsView.format(TimeInterval(item.suggestedMinutes * 60)))")
        .font(.system(size: 13, weight: .black))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Self.softYellow))
        .overlay(Capsule().stroke(TopAppsView.ink, lineWidth: 1.5))
    }
  }
}

/// 精简版（“今天”页的“今天时间去哪了”卡片）
struct TopAppsCompactReport: DeviceActivityReportScene {
  let context: DeviceActivityReport.Context = .topAppsCompact
  let content: (TopApps) -> TopAppsCompactView

  func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TopApps {
    await TopApps.make(from: data)
  }
}

struct TopAppsView: View {
  let report: TopApps

  // 和 Flutter 那边的配色一致（pop_ui 的 Pop）：底色是排行页的奶油色
  static let ink = Color(red: 0x1B / 255, green: 0x1B / 255, blue: 0x1F / 255)
  static let yellow = Color(red: 1, green: 0xD2 / 255, blue: 0x3F / 255)
  static let paper = Color(red: 0xFB / 255, green: 0xF5 / 255, blue: 0xE6 / 255)

  var body: some View {
    Group {
      if report.items.isEmpty {
        Text("今天还没有用满 1 分钟的 App")
          .font(.system(size: 15))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            Text("\(report.days > 1 ? "这 \(report.days) 天" : "今天")一共 \(Self.format(report.total))")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(.secondary)
            ForEach(report.items) { row($0) }
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
        }
      }
    }
    .background(Self.paper)
    // App 只做浅色：手机开了深色模式也按浅色画，不然白底上的字会变成白色
    .environment(\.colorScheme, .light)
  }

  private func row(_ item: TopApps.Item) -> some View {
    let top = max(report.items.first?.duration ?? 1, 1)
    return HStack(spacing: 12) {
      Text("\(item.id)")
        .font(.system(size: 15, weight: .black))
        .frame(width: 24)
      Group {
        if let token = item.token {
          Label(token).labelStyle(.iconOnly)
        } else {
          Image(systemName: "app.fill").foregroundStyle(.secondary)
        }
      }
      .frame(width: 34, height: 34)
      VStack(alignment: .leading, spacing: 6) {
        Text(item.name)
          .font(.system(size: 15, weight: .bold))
          .lineLimit(1)
        GeometryReader { geo in
          Capsule()
            .fill(Self.yellow)
            .overlay(Capsule().stroke(Self.ink, lineWidth: 1.5))
            .frame(width: max(10, geo.size.width * item.duration / top))
        }
        .frame(height: 9)
      }
      Text(Self.format(item.duration))
        .font(.system(size: 14, weight: .bold))
        .monospacedDigit()
    }
    .padding(12)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }

  static func format(_ t: TimeInterval) -> String {
    let minutes = Int(t / 60)
    if minutes < 60 { return "\(minutes) 分钟" }
    return minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes / 60) 小时 \(minutes % 60) 分"
  }
}

/// “今天”页卡片里的精简版：一句话 + 前五名，不滚动。Flutter 那边给它留了 176 点高（today_cards.dart 的 _IosTopApps）。
struct TopAppsCompactView: View {
  let report: TopApps

  var body: some View {
    Group {
      if let first = report.items.first {
        VStack(alignment: .leading, spacing: 8) {
          Text(Self.headline(first, total: report.total))
            .font(.system(size: 14, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
          ForEach(report.items.prefix(5)) { row($0, top: first.duration) }
        }
      } else {
        Text("今天还没有用满 1 分钟的 App")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
      }
    }
    .foregroundStyle(TopAppsView.ink)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color.white)
    .environment(\.colorScheme, .light)
  }

  private func row(_ item: TopApps.Item, top: TimeInterval) -> some View {
    HStack(spacing: 8) {
      Text("\(item.id)")
        .font(.system(size: 13, weight: .black))
        .frame(width: 16, alignment: .leading)
      Group {
        if let token = item.token {
          Label(token).labelStyle(.iconOnly)
        } else {
          Image(systemName: "app.fill").foregroundStyle(.secondary)
        }
      }
      .frame(width: 22, height: 22)
      .clipped()
      Text(item.name)
        .font(.system(size: 13, weight: .bold))
        .lineLimit(1)
        .frame(width: 72, alignment: .leading)
      GeometryReader { geo in
        Capsule()
          .fill(TopAppsView.yellow)
          .overlay(Capsule().stroke(TopAppsView.ink, lineWidth: 1.5))
          .frame(width: max(8, geo.size.width * item.duration / max(top, 1)))
      }
      .frame(height: 8)
      Text(TopAppsView.format(item.duration))
        .font(.system(size: 13, weight: .bold))
        .monospacedDigit()
    }
    .frame(height: 24)
  }

  /// 和 Flutter 那边（安卓，today_cards.dart 的 TimeSpentCard.headline）同一个规则：占四成以上说“一个就占了”
  static func headline(_ top: TopApps.Item, total: TimeInterval) -> String {
    let pct = Int((top.duration * 100 / max(total, 1)).rounded())
    return pct >= 40 ? "“\(top.name)”一个就占了今天的 \(pct)%" : "最费时间的是“\(top.name)”，占今天的 \(pct)%"
  }
}
