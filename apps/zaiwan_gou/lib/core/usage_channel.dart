import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 当天的使用汇总。只有分类汇总，不含任何具体 app 名称。
class UsageSnapshot {
  const UsageSnapshot({
    required this.totalMinutes,
    required this.pickups,
    required this.lateNightMinutes,
    required this.categoryMinutes,
    this.available = true,
    this.stageOnly = false,
  });

  final int totalMinutes;
  final int pickups;

  /// 23 点以后的使用分钟数
  final int lateNightMinutes;

  /// video / social / game / productivity / other
  final Map<String, int> categoryMinutes;

  /// false 表示还拿不到真实数据（没开权限、iOS 没开屏幕使用时间、模拟器）。
  /// 这时界面上不显示任何数字，只引导去开权限；不记历史、不上报。不用演示数据充数。
  final bool available;

  /// true 表示数据来自 iOS 屏幕使用时间：系统只告诉我们用量越过了哪个阈值。
  /// totalMinutes 是已经越过的阈值（下限），拿起次数、23 点后时长和分类都拿不到。
  final bool stageOnly;

  /// 还拿不到真实数据
  static const unavailable =
      UsageSnapshot(totalMinutes: 0, pickups: 0, lateNightMinutes: 0, categoryMinutes: {}, available: false);

  factory UsageSnapshot.fromMap(Map<dynamic, dynamic> m) {
    final cats = <String, int>{};
    (m['categoryMinutes'] as Map? ?? {}).forEach((k, v) => cats[k.toString()] = (v as num).toInt());
    return UsageSnapshot(
      totalMinutes: (m['totalMinutes'] as num? ?? 0).toInt(),
      pickups: (m['pickups'] as num? ?? 0).toInt(),
      lateNightMinutes: (m['lateNightMinutes'] as num? ?? 0).toInt(),
      categoryMinutes: cats,
    );
  }
}

/// 某个 app 的用时。隐私约定：只在手机上显示（排行、限时选 app），绝不上传。
class AppUsage {
  const AppUsage({required this.package, required this.label, required this.minutes, this.icon});

  factory AppUsage.fromMap(Map<dynamic, dynamic> m) => AppUsage(
        package: m['package'] as String,
        label: m['label'] as String,
        minutes: (m['minutes'] as num).toInt(),
        icon: m['icon'] as Uint8List?,
      );

  final String package;
  final String label;
  final int minutes;

  /// 96px 的 PNG 图标；拿不到时为 null
  final Uint8List? icon;
}

/// 前几天的汇总（安卓）：系统还留着明细的日子才有，一般是最近 7–10 天
class PastDayUsage {
  const PastDayUsage(this.date, this.usage);

  factory PastDayUsage.fromMap(Map<dynamic, dynamic> m) => PastDayUsage(m['date'] as String, UsageSnapshot.fromMap(m));

  /// yyyy-MM-dd，本地日期
  final String date;
  final UsageSnapshot usage;
}

/// 原生插件：安卓见 android/app/src/main/kotlin/.../UsagePlugin.kt。
/// iOS 拿不到分钟数，屏幕使用时间还在技术验证，见 screen_time_channel.dart。
class UsageChannel {
  UsageChannel._();

  static const _channel = MethodChannel('zwjsg/usage');

  static bool get isSupported => debugSupportedOverride ?? Platform.isAndroid;

  /// 测试里当成安卓跑原生通道（真机上不用）
  @visibleForTesting
  static bool? debugSupportedOverride;

  static Future<bool> hasPermission() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('hasPermission') ?? false;
  }

  /// 打开系统“使用情况访问权限”设置页，用户需要手动打开开关
  static Future<void> openPermissionSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openPermissionSettings');
  }

  /// 今日排行：用时最多的 app 在前，不到 1 分钟的不算。没有权限时抛 [PlatformException]
  static Future<List<AppUsage>> todayRanking() async {
    final list = await _channel.invokeMethod<List<dynamic>>('getTodayRanking') ?? const [];
    return [for (final m in list) AppUsage.fromMap(m as Map<dynamic, dynamic>)];
  }

  /// 最近 [days] 天（含今天）的排行，历史统计页用。没有权限时抛 [PlatformException]
  static Future<List<AppUsage>> ranking({required int days}) async {
    final list = await _channel.invokeMethod<List<dynamic>>('getRanking', {'days': days}) ?? const [];
    return [for (final m in list) AppUsage.fromMap(m as Map<dynamic, dynamic>)];
  }

  /// 昨天往前 [days] 天里，系统还留着明细的日子，每天一条汇总
  static Future<List<PastDayUsage>> pastDays(int days) async {
    if (!isSupported) return const [];
    try {
      final list = await _channel.invokeMethod<List<dynamic>>('getPastDays', {'days': days}) ?? const [];
      return [for (final m in list) PastDayUsage.fromMap(m as Map<dynamic, dynamic>)];
    } on PlatformException {
      return const [];
    }
  }

  static Future<UsageSnapshot?> todayUsage() async {
    if (!isSupported) return null;
    try {
      final m = await _channel.invokeMethod<Map<dynamic, dynamic>>('getTodayUsage');
      return m == null ? null : UsageSnapshot.fromMap(m);
    } on PlatformException {
      return null;
    }
  }
}
