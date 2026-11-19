import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dog_meter.dart';
import 'usage_channel.dart';

/// iOS 屏幕使用时间（技术验证）的状态。
/// 系统只告诉 App 用量到了哪个阈值，拿不到准确分钟数；选中的 App 是不透明令牌，只留在原生层，这里只有数量。
class ScreenTimeStatus {
  const ScreenTimeStatus({
    this.authorization = 'notDetermined',
    this.apps = 0,
    this.categories = 0,
    this.webDomains = 0,
    this.monitoring = false,
    this.goalMinutes = 0,
    this.thresholds = const [],
    this.stage = 0,
    this.history = const {},
    this.log = const [],
  });

  factory ScreenTimeStatus.fromMap(Map<dynamic, dynamic> m) {
    int number(String key) => (m[key] as num? ?? 0).toInt();
    return ScreenTimeStatus(
      authorization: m['authorization'] as String? ?? 'notDetermined',
      apps: number('apps'),
      categories: number('categories'),
      webDomains: number('webDomains'),
      monitoring: m['monitoring'] as bool? ?? false,
      goalMinutes: number('goalMinutes'),
      thresholds: [for (final v in m['thresholds'] as List? ?? const []) (v as num).toInt()],
      stage: number('stage'),
      history: {
        for (final e in (m['history'] as Map? ?? const {}).entries) e.key.toString(): (e.value as num).toInt(),
      },
      log: [for (final v in m['log'] as List? ?? const []) v.toString()],
    );
  }

  /// approved / denied / notDetermined
  final String authorization;
  final int apps;
  final int categories;
  final int webDomains;
  final bool monitoring;
  final int goalMinutes;

  /// 各阶段的分钟数阈值
  final List<int> thresholds;

  /// 今天到了第几阶段（0–5）
  final int stage;

  /// 监控扩展记下的每天最高阶段（yyyy-MM-dd → 0–5）。没在统计的日子没有
  final Map<String, int> history;

  /// 原生层的调试记录，旧的在前
  final List<String> log;

  bool get authorized => authorization == 'approved';
  bool get hasSelection => apps + categories + webDomains > 0;

  /// 已授权、选了 App，并且监控已经开始
  bool get active => authorized && hasSelection && monitoring;

  /// 到了阶段 n，只能确定狗度至少是第 n 个阈值；阶段 0 只知道还没到第一个阈值
  int get minPercent => stage == 0 ? 0 : DogMeter.stageThresholds[stage - 1];

  /// 给“今天”页用的使用数据：分钟数取已经越过的阈值，是下限
  UsageSnapshot toUsage() => UsageSnapshot(
        totalMinutes: stage > 0 && stage <= thresholds.length ? thresholds[stage - 1] : 0,
        pickups: 0,
        lateNightMinutes: 0,
        categoryMinutes: const {},
        stageOnly: true,
      );
}

/// 原生插件见 ios/Runner/ScreenTimePlugin.swift，监控扩展见 ios/ScreenTimeMonitor/。
class ScreenTimeChannel {
  ScreenTimeChannel._();

  static const _channel = MethodChannel('zwjsg/screen_time');

  /// 用 defaultTargetPlatform 判断，测试里可以模拟成 iOS
  static bool get isSupported => defaultTargetPlatform == TargetPlatform.iOS;

  /// 各阶段对应的分钟数：按 DogMeter 的阈值折算，向上取整，至少 1 分钟
  static List<int> thresholdMinutes(int goalMinutes) => [
        for (final p in DogMeter.stageThresholds) math.max(1, (p * goalMinutes / 100).ceil()),
      ];

  static Future<ScreenTimeStatus> status() => _call('status');

  /// 系统会弹窗，要用户本人用面容 ID 或密码确认
  static Future<ScreenTimeStatus> requestAuthorization() => _call('requestAuthorization');

  /// 弹出系统的 App 选择页
  static Future<ScreenTimeStatus> pickActivities() => _call('pickActivities');

  static Future<ScreenTimeStatus> startMonitoring(int goalMinutes) => _call('startMonitoring', {
        'goalMinutes': goalMinutes,
        'thresholds': thresholdMinutes(goalMinutes),
      });

  static Future<ScreenTimeStatus> stopMonitoring() => _call('stopMonitoring');

  static Future<ScreenTimeStatus> _call(String method, [Object? arguments]) async {
    final m = await _channel.invokeMethod<Map<dynamic, dynamic>>(method, arguments);
    return ScreenTimeStatus.fromMap(m ?? const {});
  }
}
