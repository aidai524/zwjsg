import SwiftUI
import WidgetKit

// 再玩我是狗的桌面小组件：不打开 App 也能看到现在的形象和狗度（需求文档 P1）。
// iOS 只知道今天越过了哪个阈值：狗度显示成“≥60%”，已刷时长是下限。阶段由监控扩展记下，到了新阶段时它叫小组件刷新；
// 每天 0 点变回人。规则和文案都是 App 交过来的（照搬 dog_meter.dart），这里只按阶段挑。和安卓的 GouWidget.kt 对应。

// MARK: - 数据

struct Dog {
  let stage: Int
  /// “≥60%”“<30%”
  let percent: String
  let stageName: String
  let quip: String
  /// “至少 1 小时 48 分”“不到 54 分钟”
  let used: String
  /// “目标 3 小时”
  let goal: String
  /// “今天用满 2 小时 42 分，你就会脸上长毛”
  let hint: String

  static let sample = Dog(
    stage: 2, percent: "≥60%", stageName: "阶段 2 · 狗鼻子", quip: "鼻子湿了，闻到短视频的味了吧",
    used: "至少 1 小时 48 分", goal: "目标 3 小时", hint: "今天用满 2 小时 42 分，你就会脸上长毛")
}

struct DogEntry: TimelineEntry {
  enum Content {
    case dog(Dog)
    /// 还没做完设置、还没开屏幕使用时间
    case message(String)
  }

  let date: Date
  let content: Content
}

enum DogLoader {
  /// [stageZero] 为 true 时按 0 点刚过算：变回人
  static func entry(at date: Date, stageZero: Bool = false) -> DogEntry {
    guard let c = GouWidgetShared.loadConfig(), c.ready else {
      return DogEntry(date: date, content: .message("打开 App 做完设置，这里就能看到你今天有多像狗"))
    }
    let minutes = GouWidgetShared.screenTimeThresholds()
    guard c.source == "screenTime", !minutes.isEmpty, minutes.count == c.thresholds.count,
          c.stageNames.count == minutes.count + 1, c.quips.count == minutes.count + 1, c.nextChange.count == minutes.count
    else {
      return DogEntry(date: date, content: .message("打开 App 开启“屏幕使用时间”，这里就能看到狗度"))
    }

    let stage = stageZero ? 0 : min(max(GouWidgetShared.screenTimeStageToday(), 0), minutes.count)
    // 和 App 的 percentLabel、minutesUsedLabel、今天页的提示一样：越过了阈值显示下限，一个都没越过显示“不到”
    let percent = stage == 0
      ? "<\(percentFor(minutes[0], c.goalMinutes))%"
      : "≥\(percentFor(minutes[stage - 1], c.goalMinutes))%"
    let used = stage == 0 ? "不到 \(formatMinutes(minutes[0]))" : "至少 \(formatMinutes(minutes[stage - 1]))"
    let hint = stage >= minutes.count
      ? "已经到底了，再刷也还是狗"
      : "今天用满 \(formatMinutes(minutes[stage]))，你就会\(c.nextChange[stage])"
    return DogEntry(date: date, content: .dog(Dog(
      stage: stage, percent: percent, stageName: c.stageNames[stage], quip: c.quips[stage],
      used: used, goal: "目标 \(formatMinutes(c.goalMinutes))", hint: hint)))
  }

  /// 和 DogMeter.percentFor 一样：四舍五入
  static func percentFor(_ minutes: Int, _ goal: Int) -> Int {
    goal <= 0 ? 0 : Int((Double(minutes) / Double(goal) * 100).rounded())
  }

  /// 和 DogMeter.formatMinutes 一样
  static func formatMinutes(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    if h == 0 { return "\(m) 分钟" }
    if m == 0 { return "\(h) 小时" }
    return "\(h) 小时 \(m) 分"
  }
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> DogEntry {
    DogEntry(date: .now, content: .dog(.sample))
  }

  func getSnapshot(in context: Context, completion: @escaping (DogEntry) -> Void) {
    let entry = DogLoader.entry(at: .now)
    // 添加小组件时的预览：还没开屏幕使用时间就给示例
    if context.isPreview, case .message = entry.content {
      completion(placeholder(in: context))
    } else {
      completion(entry)
    }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<DogEntry>) -> Void) {
    let now = Date.now
    // 0 点变回人；过了 0 点系统再来要新的时间线。白天到了新阶段，监控扩展会叫小组件刷新
    let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
      ?? Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 3600)
    let entries = [DogLoader.entry(at: now), DogLoader.entry(at: midnight, stageZero: true)]
    completion(Timeline(entries: entries, policy: .atEnd))
  }
}

// MARK: - 样式

/// 和 pop_ui 的 Pop 颜色一致：奶油底，亮黄只用在阶段牌上
private enum Pop {
  static let yellow = Color(hex: 0xFFD23F)
  static let ink = Color(hex: 0x1B1B1F)
  static let paper = Color(hex: 0xFBF5E6)
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

// MARK: - 视图

struct GouWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: DogEntry

  var body: some View {
    content
      .foregroundStyle(Pop.ink)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(12)
      .containerBackground(for: .widget) { Pop.paper }
  }

  @ViewBuilder private var content: some View {
    switch entry.content {
    case .message(let text):
      VStack(alignment: .leading, spacing: 6) {
        Text("再玩我是狗").font(.pop(15, .black)).lineLimit(1)
        Text(text).font(.pop(12, .bold)).foregroundStyle(Pop.muted)
      }
    case .dog(let dog):
      if family == .systemSmall { SmallView(dog: dog) } else { MediumView(dog: dog) }
    }
  }
}

/// 小号：狗度、形象、阶段、一句吐槽
private struct SmallView: View {
  let dog: Dog

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 4) {
        VStack(alignment: .leading, spacing: 0) {
          Text("狗度").font(.pop(12, .bold))
          Text(dog.percent).font(.pop(30, .black)).lineLimit(1).minimumScaleFactor(0.6)
        }
        Spacer(minLength: 0)
        AvatarCircle(stage: dog.stage, size: 66)
      }
      StagePill(text: dog.stageName)
      Text(dog.quip).font(.pop(11, .bold)).lineLimit(2).minimumScaleFactor(0.85)
      Spacer(minLength: 0)
    }
  }
}

/// 中号：形象在左；右边狗度、阶段、吐槽、已刷多久、再刷多久变成什么样
private struct MediumView: View {
  let dog: Dog

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      AvatarCircle(stage: dog.stage, size: 118)
      VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text("狗度").font(.pop(13, .bold))
          Text(dog.percent).font(.pop(32, .black)).lineLimit(1).minimumScaleFactor(0.6)
        }
        StagePill(text: dog.stageName)
        Text(dog.quip).font(.pop(12, .heavy)).lineLimit(1).minimumScaleFactor(0.8)
        Text("\(dog.used) · \(dog.goal)").font(.pop(10, .bold)).foregroundStyle(Pop.muted).lineLimit(1)
          .minimumScaleFactor(0.8)
        Text(dog.hint).font(.pop(11, .heavy)).lineLimit(2).minimumScaleFactor(0.8)
      }
      Spacer(minLength: 0)
    }
  }
}

/// 形象：白底圆框里放 App 预先画好的图，和“今天”页一样；还没画好时放一个狗爪图标
private struct AvatarCircle: View {
  let stage: Int
  let size: CGFloat

  var body: some View {
    ZStack(alignment: .bottom) {
      Circle().fill(Color.white)
      if let image {
        Image(uiImage: image).resizable().interpolation(.high).scaledToFit().frame(width: size * 0.92, height: size * 0.92)
      } else {
        Image(systemName: "pawprint.fill").font(.system(size: size * 0.4)).foregroundStyle(Pop.ink)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .overlay(Circle().stroke(Pop.ink, lineWidth: 2.5))
  }

  private var image: UIImage? {
    guard let dir = GouWidgetShared.avatarDirectory else { return nil }
    return UIImage(contentsOfFile: dir.appendingPathComponent("dog_\(stage).png").path)
  }
}

/// 阶段牌：黑底黄字，和“今天”页一样
private struct StagePill: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.pop(11, .heavy))
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .foregroundStyle(Pop.yellow)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(Capsule().fill(Pop.ink))
  }
}

// MARK: - 小组件

struct GouWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: GouWidgetShared.kind, provider: Provider()) { entry in
      GouWidgetView(entry: entry)
    }
    .configurationDisplayName("今天有多像狗")
    .description("不打开 App 也能看到现在的形象和狗度。")
    .supportedFamilies([.systemSmall, .systemMedium])
    .contentMarginsDisabled()
  }
}

@main
struct GouWidgetBundle: WidgetBundle {
  var body: some Widget {
    GouWidget()
  }
}
