import ManagedSettings
import ManagedSettingsUI
import UIKit

/// 超时来电的屏蔽页：单个 App 用满每天的额度后，系统用这里的文案和配色挡一下。
/// iOS 不让 App 在别的 App 上面弹页面，国内上架也不能用系统通话（CallKit），所以“来电”只能做在屏蔽页上：
/// 你的狗（今天到了哪个阶段就是哪张形象）打来电话，问你还确定要玩吗。
/// 按钮由屏蔽页按钮扩展（ShieldActions）处理：“不玩了”关掉 App，“再玩 10 分钟”就放行，不限次数。
final class ShieldConfig: ShieldConfigurationDataSource {
  private static let ink = UIColor(red: 0x1B / 255, green: 0x1B / 255, blue: 0x1F / 255, alpha: 1)
  private static let yellow = UIColor(red: 1, green: 0xD2 / 255, blue: 0x3F / 255, alpha: 1)
  /// 奶油底（pop_ui 的 Pop.paper），亮黄只用在按钮文字上
  private static let paper = UIColor(red: 0xFB / 255, green: 0xF5 / 255, blue: 0xE6 / 255, alpha: 1)

  private func shield(_ name: String?, lock: AppLockRecord?) -> ShieldConfiguration {
    let what = name ?? "这个 App"
    let limit = lock.map { "说好一天 \(Self.format($0.minutes))，" } ?? ""
    return ShieldConfiguration(
      backgroundBlurStyle: .systemUltraThinMaterialLight,
      backgroundColor: Self.paper,
      icon: Self.avatar() ?? UIImage(named: "ShieldIcon"),
      title: .init(text: "你的狗打来电话", color: Self.ink),
      subtitle: .init(text: "\(what)今天的时间用完了。\(limit)你还确定要玩吗？", color: Self.ink),
      primaryButtonLabel: .init(text: "不玩了", color: Self.yellow),
      primaryButtonBackgroundColor: Self.ink,
      secondaryButtonLabel: .init(text: "再玩 \(ScreenTimeStore.snoozeMinutes) 分钟", color: Self.ink)
    )
  }

  /// 今天这个阶段的形象：App 预先画好放在 App Group 里（和桌面小组件同一套图）
  private static func avatar() -> UIImage? {
    guard let dir = GouWidgetShared.avatarDirectory else { return nil }
    return UIImage(contentsOfFile: dir.appendingPathComponent("dog_\(ScreenTimeStore.stageToday).png").path)
  }

  /// 和 DogMeter.formatMinutes 一样
  private static func format(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    if h == 0 { return "\(m) 分钟" }
    return m == 0 ? "\(h) 小时" : "\(h) 小时 \(m) 分"
  }

  override func configuration(shielding application: Application) -> ShieldConfiguration {
    shield(application.localizedDisplayName, lock: application.token.flatMap(LockShield.lock(containing:)))
  }

  override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
    let lock = application.token.flatMap(LockShield.lock(containing:)) ?? category.token.flatMap(LockShield.lock(containing:))
    return shield(application.localizedDisplayName, lock: lock)
  }

  override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
    shield(webDomain.domain, lock: webDomain.token.flatMap(LockShield.lock(containing:)))
  }

  override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
    let lock = webDomain.token.flatMap(LockShield.lock(containing:)) ?? category.token.flatMap(LockShield.lock(containing:))
    return shield(webDomain.domain, lock: lock)
  }
}
