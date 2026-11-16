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
}

struct TopAppsReport: DeviceActivityReportScene {
  let context: DeviceActivityReport.Context = .topApps
  let content: (TopApps) -> TopAppsView

  private struct Entry {
    let token: ApplicationToken?
    let name: String
    var duration: TimeInterval
  }

  func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TopApps {
    var byApp: [String: Entry] = [:]
    for await device in data {
      for await segment in device.activitySegments {
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
      total: byApp.values.reduce(0) { $0 + $1.duration }
    )
  }
}

struct TopAppsView: View {
  let report: TopApps

  // 和 Flutter 那边的黄黑波普配色一致
  private static let ink = Color(red: 0x1B / 255, green: 0x1B / 255, blue: 0x1F / 255)
  private static let yellow = Color(red: 1, green: 0xD2 / 255, blue: 0x3F / 255)
  private static let gray = Color(red: 0xF3 / 255, green: 0xF4 / 255, blue: 0xF6 / 255)

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
            Text("今天一共 \(Self.format(report.total))")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(.secondary)
            ForEach(report.items) { row($0) }
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
        }
      }
    }
    .background(Self.gray)
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
