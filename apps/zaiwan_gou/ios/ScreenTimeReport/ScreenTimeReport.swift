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

/// “今天”页卡片里的精简版：一句话 + 前三名，不滚动。Flutter 那边给它留了 116 点高。
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
          ForEach(report.items.prefix(3)) { row($0, top: first.duration) }
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
