import DeviceActivity
import Foundation
import WidgetKit

/// 系统在后台调起的监控扩展：每天 0 点开始新的统计周期，选中的 App 用量到阈值时通知。
/// 两类统计周期：
/// - `.daily`：狗度阶段，只记下到了第几阶段；阈值由主 App 传进来（Flutter 按 dog_meter.dart 的规则算）
/// - `lock.<id>`：App 时间锁，用满了就挡住那些 App，0 点解开
final class ScreenTimeMonitor: DeviceActivityMonitor {
  override func intervalDidStart(for activity: DeviceActivityName) {
    super.intervalDidStart(for: activity)
    if activity == .daily {
      ScreenTimeStore.startDayIfNeeded()
      ScreenTimeStore.append("统计周期开始")
      // 新的一天：桌面小组件变回人
      WidgetCenter.shared.reloadTimelines(ofKind: GouWidgetShared.kind)
    } else if let id = ScreenTimeStore.lockId(of: activity) {
      // 新的一天解锁。刚开始监控时如果已经因为补算今天的用量锁上了，就别解开
      if !ScreenTimeStore.isLockedToday(id) { LockShield.clear(id) }
    }
  }

  override func intervalDidEnd(for activity: DeviceActivityName) {
    super.intervalDidEnd(for: activity)
    if activity == .daily {
      ScreenTimeStore.append("统计周期结束，今天到了阶段 \(ScreenTimeStore.stageToday)")
    } else if let id = ScreenTimeStore.lockId(of: activity) {
      // 0 点前也解一次，免得 0 点那一刻手机关着、第二天还锁着
      LockShield.clear(id)
      ScreenTimeStore.setGraceActive(id, false)
      ScreenTimeStore.append("时间锁 \(id.prefix(4))：一天结束，解锁")
    }
  }

  override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
    super.eventDidReachThreshold(event, activity: activity)
    if activity == .daily {
      guard let stage = ScreenTimeStore.stage(of: event) else { return }
      ScreenTimeStore.recordStage(stage)
      let thresholds = ScreenTimeStore.thresholds
      let minutes = thresholds.indices.contains(stage - 1) ? "（\(thresholds[stage - 1]) 分钟）" : ""
      ScreenTimeStore.append("到达阶段 \(stage)\(minutes)")
      // 桌面小组件马上换成新阶段的样子
      WidgetCenter.shared.reloadTimelines(ofKind: GouWidgetShared.kind)
    } else if let id = ScreenTimeStore.lockId(of: activity), let lock = ScreenTimeStore.lock(id) {
      // 正在紧急解锁的几分钟里不打断，等那几分钟用满再锁
      guard !ScreenTimeStore.isGraceActive(id) else { return }
      LockShield.apply(lock)
      ScreenTimeStore.append("时间锁 \(id.prefix(4))：用满 \(lock.minutes) 分钟，锁上")
    } else if let id = ScreenTimeStore.graceLockId(of: activity), let lock = ScreenTimeStore.lock(id) {
      ScreenTimeStore.setGraceActive(id, false)
      LockShield.apply(lock)
      ScreenTimeStore.append("时间锁 \(id.prefix(4))：临时解锁的 \(ScreenTimeStore.graceMinutes) 分钟用完，重新锁上")
      DeviceActivityCenter().stopMonitoring([activity])
    }
  }
}
