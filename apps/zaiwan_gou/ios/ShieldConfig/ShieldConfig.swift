import ManagedSettings
import ManagedSettingsUI
import UIKit

/// App 时间锁的屏蔽页：被锁的 App 打开时，系统用这里的文案和配色挡住它。
/// 没有配按钮动作扩展，主按钮按系统默认行为关掉被锁的 App。
final class ShieldConfig: ShieldConfigurationDataSource {
  private static let ink = UIColor(red: 0x1B / 255, green: 0x1B / 255, blue: 0x1F / 255, alpha: 1)
  private static let yellow = UIColor(red: 1, green: 0xD2 / 255, blue: 0x3F / 255, alpha: 1)

  private func shield(_ name: String?) -> ShieldConfiguration {
    let title = name.map { "汪！\($0)今天的时间用完了" } ?? "汪！今天的时间用完了"
    return ShieldConfiguration(
      backgroundBlurStyle: .systemUltraThinMaterialLight,
      backgroundColor: Self.yellow,
      icon: UIImage(named: "ShieldIcon"),
      title: .init(text: title, color: Self.ink),
      subtitle: .init(text: "明天 0 点自动解锁。实在要用，去“再玩我是狗 › App 时间锁”临时解锁 5 分钟，每天 3 次。", color: Self.ink),
      primaryButtonLabel: .init(text: "算了，不刷了", color: Self.yellow),
      primaryButtonBackgroundColor: Self.ink
    )
  }

  override func configuration(shielding application: Application) -> ShieldConfiguration {
    shield(application.localizedDisplayName)
  }

  override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
    shield(application.localizedDisplayName)
  }

  override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
    shield(webDomain.domain)
  }

  override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
    shield(webDomain.domain)
  }
}
