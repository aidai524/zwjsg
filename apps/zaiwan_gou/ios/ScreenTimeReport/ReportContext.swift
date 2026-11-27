import DeviceActivity
import SwiftUI

// 主 App 和报告扩展都编译这个文件：主 App 用这个名字请求报告，系统交给扩展里同名的场景来画
extension DeviceActivityReport.Context {
  /// 今日各 App 用时排行
  static let topApps = Self("topApps")
  /// “今天”页卡片里的精简版：一句话 + 前五名
  static let topAppsCompact = Self("topAppsCompact")
  /// 超时来电页：最近 7 天最上头的几个 App，建议每天限多久
  static let limitAdvice = Self("limitAdvice")
  /// 从建议点“去设限时”进的编辑页：只有那几行“App + 建议每天多久”，对着选额度（2026-11-27）
  static let limitAdviceCompact = Self("limitAdviceCompact")
}
