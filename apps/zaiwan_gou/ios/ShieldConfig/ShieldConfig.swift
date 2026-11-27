import ManagedSettings
import ManagedSettingsUI
import UIKit

/// 超时来电的屏蔽页：单个 App 用满每天的额度后，系统用这里的文案和配色挡一下。
/// iOS 不让 App 在别的 App 上面弹页面，国内上架也不能用系统通话（CallKit），屏蔽页本身也放不了动画和声音，
/// 所以挡上的同时监控扩展发一条带铃声的通知（狗版的你打来电话），像 FaceTime 的来电界面在「再玩我是狗」里（2026-11-23）：
/// - 绿色的“接听”：发通知把人带回 App，接着通话；学两声狗叫才能再玩 10 分钟
/// - 红字的“拒接（今天锁死）”：今天锁死，屏蔽页换成“今天锁死了”，只剩一个按钮
/// 按钮由屏蔽页按钮扩展（ShieldActions）处理。
final class ShieldConfig: ShieldConfigurationDataSource {
  private static let ink = UIColor(red: 0x1B / 255, green: 0x1B / 255, blue: 0x1F / 255, alpha: 1)
  private static let yellow = UIColor(red: 1, green: 0xD2 / 255, blue: 0x3F / 255, alpha: 1)
  /// 奶油底（pop_ui 的 Pop.paper）
  private static let paper = UIColor(red: 0xFB / 255, green: 0xF5 / 255, blue: 0xE6 / 255, alpha: 1)
  /// 接听、拒接用手机通话界面常见的绿和红（和 Flutter 的 CallColors 一致）
  private static let green = UIColor(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255, alpha: 1)
  private static let red = UIColor(red: 1, green: 0x3B / 255, blue: 0x30 / 255, alpha: 1)

  private func shield(_ name: String?, lock: AppLockRecord?) -> ShieldConfiguration {
    let what = name ?? "这个 App"
    if let lock, ScreenTimeStore.isDeclinedToday(lock.id) {
      return ShieldConfiguration(
        backgroundBlurStyle: .systemUltraThinMaterialLight,
        backgroundColor: Self.paper,
        icon: Self.avatar() ?? UIImage(named: "ShieldIcon"),
        title: .init(text: "今天锁死了", color: Self.ink),
        subtitle: .init(text: "你拒接了狗版自己的电话。\(what)明天 0 点才能再打开。", color: Self.ink),
        primaryButtonLabel: .init(text: "好吧", color: Self.yellow),
        primaryButtonBackgroundColor: Self.ink,
        secondaryButtonLabel: nil
      )
    }
    // 按狗度来的限时（2026-11-27）：不是这个 App 用完了，是今天一共刷多了
    let reason: String
    if let pct = lock?.dogPercent {
      reason = "今天狗度过了 \(pct)%，\(what)先停一停。"
    } else {
      let limit = lock.map { "说好一天 \(ScreenTimeStore.formatMinutes($0.minutes))，" } ?? ""
      reason = "\(what)今天的时间用完了。\(limit)"
    }
    return ShieldConfiguration(
      backgroundBlurStyle: .systemUltraThinMaterialLight,
      backgroundColor: Self.paper,
      icon: Self.avatar() ?? UIImage(named: "ShieldIcon"),
      title: .init(text: "狗版的你打来电话…", color: Self.ink),
      subtitle: .init(
        text: "\(reason)接听后学两声狗叫，能再玩 \(ScreenTimeStore.snoozeMinutes) 分钟；拒接今天就锁死。",
        color: Self.ink),
      primaryButtonLabel: .init(text: "接听", color: .white),
      primaryButtonBackgroundColor: Self.green,
      secondaryButtonLabel: .init(text: "拒接（今天锁死）", color: Self.red)
    )
  }

  /// 今天这个阶段的形象：App 预先画好放在 App Group 里（和桌面小组件同一套图）
  private static func avatar() -> UIImage? {
    guard let dir = GouWidgetShared.avatarDirectory else { return nil }
    return UIImage(contentsOfFile: dir.appendingPathComponent("dog_\(ScreenTimeStore.stageToday).png").path)
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
