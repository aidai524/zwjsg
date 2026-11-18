import SwiftUI
import WidgetKit

// 什么鬼天气的桌面小组件：常驻城市的温度、形象和一句话结论（小号：伞、秋裤两张决策卡；中号：一句话 + 四张决策卡）。
// 小组件大约每 30 分钟自己向后端取一次精简天气（GET /widget/{locationId}），温度和句子后端按单位写好了，这里原样显示；
// 结论全部是后端算的，这里不做判断。严肃模式（黄色及以上预警）只显示预警标题原文、发布单位和时间，不显示决策卡。

// MARK: - 数据

/// 后端 GET /widget/{locationId} 返回的精简天气
struct WidgetWeather: Codable {
  struct Decision: Codable {
    let key: String
    let title: String
    let label: String
    let action: Bool
  }

  struct Warning: Codable {
    let title: String
    let sender: String
    let pubTime: String
    let color: String
  }

  let locationId: String
  let unit: String
  let temp: String
  let text: String
  let range: String?
  let cond: String
  let outfit: String
  let serious: Bool
  let line: String?
  let decisions: [Decision]
  let warning: Warning?
  let warningsCount: Int
  let obsTime: String?
  let credit: String

  static let sample = WidgetWeather(
    locationId: "", unit: "c", temp: "20°", text: "多云", range: "14°～24°", cond: "cloudy", outfit: "mild",
    serious: false, line: "体感 19°，长袖/薄外套",
    decisions: [
      Decision(key: "umbrella", title: "伞", label: "不带", action: false),
      Decision(key: "long_johns", title: "秋裤", label: "不用", action: false),
      Decision(key: "car_wash", title: "洗车", label: "洗", action: true),
      Decision(key: "laundry", title: "晾衣", label: "晾", action: true),
    ],
    warning: nil, warningsCount: 0, obsTime: nil, credit: "天气服务由和风天气驱动")
}

struct WeatherEntry: TimelineEntry {
  enum Content {
    case weather(city: String, weather: WidgetWeather)
    /// 还没在 App 里选城市
    case setup
    /// 取不到天气，也没有能用的旧数据
    case unavailable(city: String)
  }

  let date: Date
  let content: Content
}

// MARK: - 取数据

enum WeatherLoader {
  /// 旧数据最多显示 3 小时，再久就说取不到，免得把过时的天气当成现在的
  static let maxStale: TimeInterval = 3 * 3600

  private struct Envelope: Codable { let data: WidgetWeather }

  /// 存在共享目录里的上一次结果
  private struct Cached: Codable {
    let at: Date
    let weather: WidgetWeather
  }

  static func entry(fetch allowed: Bool) async -> WeatherEntry {
    guard let config = WidgetShared.loadConfig() else { return WeatherEntry(date: .now, content: .setup) }
    if allowed, let fresh = await fetch(config) {
      return WeatherEntry(date: .now, content: .weather(city: config.city, weather: fresh))
    }
    if let cached = cached(for: config) {
      return WeatherEntry(date: .now, content: .weather(city: config.city, weather: cached))
    }
    return WeatherEntry(date: .now, content: .unavailable(city: config.city))
  }

  private static func fetch(_ config: WidgetShared.Config) async -> WidgetWeather? {
    guard var components = URLComponents(string: "\(config.apiBase)/widget/\(config.locationId)") else { return nil }
    components.queryItems = [URLQueryItem(name: "unit", value: config.unit)]
    if let adm = config.adm { components.queryItems?.append(URLQueryItem(name: "adm", value: adm)) }
    guard let url = components.url else { return nil }

    var request = URLRequest(url: url, timeoutInterval: 15)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      let weather = try decoder.decode(Envelope.self, from: data).data
      if let file = WidgetShared.lastFile, let cached = try? JSONEncoder().encode(Cached(at: .now, weather: weather)) {
        try? cached.write(to: file, options: .atomic)
      }
      return weather
    } catch {
      return nil
    }
  }

  /// 同一个城市、同一个单位、3 小时内的旧数据才用
  private static func cached(for config: WidgetShared.Config) -> WidgetWeather? {
    guard let file = WidgetShared.lastFile,
          let data = try? Data(contentsOf: file),
          let cached = try? JSONDecoder().decode(Cached.self, from: data),
          Date.now.timeIntervalSince(cached.at) < maxStale,
          cached.weather.locationId == config.locationId,
          cached.weather.unit == config.unit
    else { return nil }
    return cached.weather
  }
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> WeatherEntry {
    WeatherEntry(date: .now, content: .weather(city: "北京", weather: .sample))
  }

  func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
    // 添加小组件时的预览：还没选城市就给示例，选了就用上次取到的（预览不联网）
    Task {
      let entry = await WeatherLoader.entry(fetch: !context.isPreview)
      if context.isPreview, case .weather = entry.content {
        completion(entry)
      } else if context.isPreview {
        completion(placeholder(in: context))
      } else {
        completion(entry)
      }
    }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
    Task {
      let entry = await WeatherLoader.entry(fetch: true)
      // 大约 30 分钟取一次（后端实况缓存 10 分钟、预报 1 小时）；什么时候真的刷新由系统按电量和使用情况决定
      completion(Timeline(entries: [entry], policy: .after(Date.now.addingTimeInterval(30 * 60))))
    }
  }
}

// MARK: - 样式

/// 和 pop_ui 的 Pop 颜色一致
private enum Pop {
  static let yellow = Color(hex: 0xFFD23F)
  static let ink = Color(hex: 0x1B1B1F)
  static let gray = Color(hex: 0xF3F4F6)
  static let mutedOnYellow = Color(hex: 0x3A3A30)
  static let muted = Color(hex: 0x5F6368)
}

private extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}

private extension Font {
  static func pop(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
    .system(size: size, weight: weight, design: .rounded)
  }
}

/// 预警颜色，和 App 的 scene.dart 里 warningColor、onWarningColor 一致
private func warningColor(_ color: String) -> (Color, Color) {
  switch color {
  case "Red": return (Color(hex: 0xD32F2F), .white)
  case "Orange": return (Color(hex: 0xF08C00), Pop.ink)
  case "Yellow": return (Color(hex: 0xFFD23F), Pop.ink)
  case "Blue": return (Color(hex: 0x2F6BFF), .white)
  case "Black": return (Pop.ink, .white)
  default: return (Pop.gray, Pop.ink)
  }
}

/// "2026-11-06T08:00+08:00" → "08:00"（城市当地时间，原样取）
private func hm(_ iso: String?) -> String? {
  guard let iso, let t = iso.firstIndex(of: "T") else { return nil }
  return String(iso[iso.index(after: t)...].prefix(5))
}

/// "2026-11-06T07:00+08:00" → "11-06 07:00"
private func mdhm(_ iso: String) -> String {
  "\(iso.dropFirst(5).prefix(5)) \(hm(iso) ?? "")"
}

// MARK: - 视图

struct WeatherWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: WeatherEntry

  var body: some View {
    content
      .foregroundStyle(Pop.ink)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(12)
      .containerBackground(for: .widget) { background }
  }

  @ViewBuilder private var content: some View {
    switch entry.content {
    case .setup:
      MessageView(title: "什么鬼天气", message: "打开 App 选个城市，这里就有天气了")
    case .unavailable(let city):
      MessageView(title: city, message: "天气暂时拿不到，过会儿再看")
    case .weather(let city, let w):
      if w.serious {
        SeriousView(city: city, w: w, small: family == .systemSmall)
      } else if family == .systemSmall {
        SmallView(city: city, w: w)
      } else {
        MediumView(city: city, w: w)
      }
    }
  }

  private var background: Color {
    if case .weather(_, let w) = entry.content, w.serious { return Pop.gray }
    return Pop.yellow
  }
}

/// 小号：城市、天气、温度；形象；伞和秋裤两张决策卡
private struct SmallView: View {
  let city: String
  let w: WidgetWeather

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 4) {
        VStack(alignment: .leading, spacing: 1) {
          Text(city).font(.pop(15, .black)).lineLimit(1).minimumScaleFactor(0.7)
          Text(w.text).font(.pop(11, .bold)).lineLimit(1)
        }
        Spacer(minLength: 0)
        Text(w.temp).font(.pop(34, .black)).lineLimit(1).minimumScaleFactor(0.6)
      }
      HStack(alignment: .bottom, spacing: 8) {
        AvatarBox(w: w, size: 70)
        VStack(alignment: .leading, spacing: 5) {
          ForEach(w.decisions.prefix(2), id: \.key) { ChipView(d: $0) }
        }
      }
      Spacer(minLength: 0)
      CreditText(text: w.credit)
    }
  }
}

/// 中号：形象在左；右边城市和实况时间、温度、一句话结论、四张决策卡
private struct MediumView: View {
  let city: String
  let w: WidgetWeather

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      AvatarBox(w: w, size: 116)
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(city).font(.pop(15, .black)).lineLimit(1).minimumScaleFactor(0.7)
          Spacer(minLength: 0)
          if let t = hm(w.obsTime) {
            Text("\(t) 实况").font(.pop(9, .bold)).foregroundStyle(Pop.mutedOnYellow)
          }
        }
        HStack(alignment: .center, spacing: 8) {
          Text(w.temp).font(.pop(32, .black)).lineLimit(1).minimumScaleFactor(0.6)
          VStack(alignment: .leading, spacing: 0) {
            Text(w.text).font(.pop(12, .heavy)).lineLimit(1)
            if let range = w.range { Text(range).font(.pop(11, .bold)).lineLimit(1) }
          }
        }
        if let line = w.line {
          Text(line).font(.pop(12, .heavy)).lineLimit(1).minimumScaleFactor(0.75)
        }
        HStack(spacing: 4) {
          ForEach(w.decisions, id: \.key) { ChipView(d: $0) }
        }
        Spacer(minLength: 0)
        CreditText(text: w.credit)
      }
    }
  }
}

/// 严肃模式：预警标题原文、发布单位和时间；形象举着伞。不显示决策卡和吐槽
private struct SeriousView: View {
  let city: String
  let w: WidgetWeather
  let small: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 4) {
        Text(city).font(.pop(15, .black)).lineLimit(1).minimumScaleFactor(0.7)
        Spacer(minLength: 0)
        Text(w.temp).font(.pop(small ? 24 : 28, .black)).lineLimit(1)
      }
      HStack(alignment: .top, spacing: 10) {
        if !small { AvatarBox(w: w, size: 84) }
        VStack(alignment: .leading, spacing: 4) {
          if let warning = w.warning {
            let (bg, fg) = warningColor(warning.color)
            Text(warning.title)
              .font(.pop(small ? 12 : 13, .heavy))
              .lineLimit(small ? 4 : 3)
              .minimumScaleFactor(0.8)
              .foregroundStyle(fg)
              .padding(.horizontal, 7)
              .padding(.vertical, 5)
              .background(RoundedRectangle(cornerRadius: 8).fill(bg))
              .overlay(RoundedRectangle(cornerRadius: 8).stroke(Pop.ink, lineWidth: 2))
            Text("\(warning.sender) \(mdhm(warning.pubTime)) 发布")
              .font(.pop(9, .bold)).lineLimit(1).minimumScaleFactor(0.7)
          }
          Text(w.warningsCount > 1 ? "共 \(w.warningsCount) 条预警，点开看原文" : "点开看预警原文")
            .font(.pop(9, .bold)).foregroundStyle(Pop.muted)
        }
      }
      Spacer(minLength: 0)
      CreditText(text: w.credit)
    }
  }
}

private struct MessageView: View {
  let title: String
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.pop(15, .black)).lineLimit(1)
      Text(message).font(.pop(12, .bold)).foregroundStyle(Pop.mutedOnYellow)
    }
  }
}

/// 形象：白底圆角框里放 App 预先画好的图；还没画好时放一个天气图标
private struct AvatarBox: View {
  let w: WidgetWeather
  let size: CGFloat

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: size * 0.2)
    ZStack {
      shape.fill(Color.white)
      if let image = avatar {
        Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
      } else {
        Image(systemName: "cloud.sun.fill").font(.system(size: size * 0.42)).foregroundStyle(Pop.ink)
      }
    }
    .frame(width: size, height: size)
    .clipShape(shape)
    .overlay(shape.stroke(Pop.ink, lineWidth: 2.5))
  }

  private var avatar: UIImage? {
    guard let dir = WidgetShared.avatarDirectory else { return nil }
    let name = w.cond == "serious" ? "avatar_serious.png" : "avatar_\(w.outfit)_\(w.cond).png"
    return UIImage(contentsOfFile: dir.appendingPathComponent(name).path)
  }
}

/// 决策卡：要行动的（带伞、穿秋裤、洗车、晾衣）黑底黄字
private struct ChipView: View {
  let d: WidgetWeather.Decision

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 7)
    Text("\(d.title) \(d.label)")
      .font(.pop(11, .black))
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .foregroundStyle(d.action ? Pop.yellow : Pop.ink)
      .padding(.horizontal, 6)
      .frame(height: 22)
      .background(shape.fill(d.action ? Pop.ink : Color.white))
      .overlay(shape.stroke(Pop.ink, lineWidth: 2))
  }
}

/// 和风要求：显示了它的数据的地方都写明
private struct CreditText: View {
  let text: String

  var body: some View {
    Text(text).font(.system(size: 7, weight: .medium)).foregroundStyle(Pop.mutedOnYellow).lineLimit(1)
  }
}

// MARK: - 小组件

struct WeatherWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WidgetShared.kind, provider: Provider()) { entry in
      WeatherWidgetView(entry: entry)
    }
    .configurationDisplayName("什么鬼天气")
    .description("常驻城市的天气和你的形象，今天要不要带伞、穿秋裤一眼看到。")
    .supportedFamilies([.systemSmall, .systemMedium])
    .contentMarginsDisabled()
  }
}

@main
struct WeatherWidgetBundle: WidgetBundle {
  var body: some Widget {
    WeatherWidget()
  }
}
