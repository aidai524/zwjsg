import DeviceActivity
import SwiftUI

// 主 App 和报告扩展都编译这个文件：主 App 用这个名字请求报告，系统交给扩展里同名的场景来画
extension DeviceActivityReport.Context {
  /// 今日各 App 用时排行
  static let topApps = Self("topApps")
  /// “今天”页卡片里的精简版：一句话 + 前三名
  static let topAppsCompact = Self("topAppsCompact")
}
