import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// 当天的使用汇总。只有分类汇总，不含任何具体 app 名称。
class UsageSnapshot {
  const UsageSnapshot({
    required this.totalMinutes,
    required this.pickups,
    required this.lateNightMinutes,
    required this.categoryMinutes,
    this.isDemo = false,
    this.stageOnly = false,
  });

  final int totalMinutes;
  final int pickups;

  /// 23 点以后的使用分钟数
  final int lateNightMinutes;

  /// video / social / game / productivity / other
  final Map<String, int> categoryMinutes;

  /// true 表示拿不到真实数据（没开权限、模拟器），用的是演示数据
  final bool isDemo;

  /// true 表示数据来自 iOS 屏幕使用时间：系统只告诉我们用量越过了哪个阈值。
  /// totalMinutes 是已经越过的阈值（下限），拿起次数、23 点后时长和分类都拿不到。
  final bool stageOnly;

  static UsageSnapshot demo(int totalMinutes) => UsageSnapshot(
        totalMinutes: totalMinutes,
        pickups: 86,
        lateNightMinutes: 20,
        categoryMinutes: {'video': (totalMinutes * 0.6).round(), 'social': (totalMinutes * 0.3).round()},
        isDemo: true,
      );

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

/// 今天某个 app 的用时。隐私约定：只在手机上显示（今日排行、时间锁选 app），绝不上传。
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

/// 原生插件：安卓见 android/app/src/main/kotlin/.../UsagePlugin.kt。
/// iOS 拿不到分钟数，屏幕使用时间还在技术验证，见 screen_time_channel.dart。
class UsageChannel {
  UsageChannel._();

  static const _channel = MethodChannel('zwjsg/usage');

  static bool get isSupported => Platform.isAndroid;

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
