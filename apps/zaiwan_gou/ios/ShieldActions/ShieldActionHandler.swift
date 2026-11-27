import ManagedSettings
import UserNotifications

/// 超时来电屏蔽页上的两个按钮（系统在后台调起这个扩展），2026-11-23 起：
/// - “接听”：这个扩展打不开 App、不能开麦克风，就记下“已接听”、发一条通知，关掉那个 App；
///   点通知打开「再玩我是狗」，就是通话中的来电界面：听狗版的你说两句，学两声狗叫再玩 10 分钟，或者挂断不玩了
/// - “拒接（今天锁死）”：这个限时今天锁死，屏蔽页换成“今天锁死了”，明天 0 点解开
/// 今天拒接过以后，哪个按钮都只是关掉那个 App
final class ShieldActionHandler: ShieldActionDelegate {
  override func handle(
    action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void
  ) {
    respond(action, lock: LockShield.lock(containing: application), completionHandler)
  }

  override func handle(
    action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void
  ) {
    respond(action, lock: LockShield.lock(containing: webDomain), completionHandler)
  }

  override func handle(
    action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void
  ) {
    respond(action, lock: LockShield.lock(containing: category), completionHandler)
  }

  private func respond(_ action: ShieldAction, lock: AppLockRecord?, _ done: @escaping (ShieldActionResponse) -> Void) {
    guard let lock, !ScreenTimeStore.isDeclinedToday(lock.id) else { return done(.close) }
    switch action {
    case .primaryButtonPressed:
      ScreenTimeStore.recordCall(lock.id, answered: true)
      // 通知没开也没关系：屏蔽页上写了去「再玩我是狗」里接，30 分钟内打开 App 就是通话中
      CallNotice.answered { done(.close) }
    case .secondaryButtonPressed:
      ScreenTimeStore.setDeclinedToday(lock.id)
      ScreenTimeStore.clearCall()
      CallNotice.cancel()
      ScreenTimeStore.append("限时 \(lock.id.prefix(4))：在屏蔽页上拒接，今天锁死")
      done(.close)
    @unknown default:
      done(.close)
    }
  }
}
