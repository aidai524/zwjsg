import ManagedSettings

/// 超时来电屏蔽页上的两个按钮（系统在后台调起这个扩展）：
/// - “不玩了”：关掉那个 App
/// - “再玩 10 分钟”：放行，再用满 10 分钟又会来电。不限次数——是提醒，不是禁止
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
    switch action {
    case .secondaryButtonPressed:
      guard let lock else { return done(.close) }
      LockShield.snooze(lock)
      // 屏蔽已经撤掉了，让系统重新看一眼，App 就能接着用
      done(.defer)
    default:
      done(.close)
    }
  }
}
