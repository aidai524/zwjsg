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
  });

  final int totalMinutes;
  final int pickups;

  /// 23 点以后的使用分钟数
  final int lateNightMinutes;

  /// video / social / game / productivity / other
  final Map<String, int> categoryMinutes;

  /// true 表示拿不到真实数据（iOS 未接入、无权限或模拟器），用的是演示数据
  final bool isDemo;

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

/// 原生插件：安卓见 android/app/src/main/kotlin/.../UsagePlugin.kt；iOS 待接入屏幕使用时间接口。
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
