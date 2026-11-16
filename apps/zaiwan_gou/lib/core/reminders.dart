import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 每晚提醒看结算卡。用手机本地通知，不需要推送服务器。抽成接口，测试里换成假的。
abstract class ReminderScheduler {
  /// 请求通知权限，返回用户是否允许
  Future<bool> requestPermission();

  /// 每天在 [minutesOfDay]（从 0 点算的分钟数）提醒一次，替换之前排的
  Future<void> scheduleDaily(int minutesOfDay);

  Future<void> cancel();

  /// 登记“点了提醒”要做的事（App 开着时点提醒会调用 [onOpen]），
  /// 返回这次 App 是不是被提醒点开的
  Future<bool> handleOpen(VoidCallback onOpen);
}

class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler._();

  static final instance = LocalReminderScheduler._();

  static const _id = 1;

  final _plugin = FlutterLocalNotificationsPlugin();
  VoidCallback? _onOpen;
  Future<void>? _ready;

  Future<void> _init() => _ready ??= _doInit();

  Future<void> _doInit() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // 读不到时区就按北京时间（只做国内市场）
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // 不在初始化时弹权限，等用户要开提醒时再问
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (_) => _onOpen?.call(),
    );
  }

  @override
  Future<bool> requestPermission() async {
    await _init();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, sound: true) ?? false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> scheduleDaily(int minutesOfDay) async {
    await _init();
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, minutesOfDay ~/ 60, minutesOfDay % 60);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: _id,
      scheduledDate: at,
      title: '今晚的结算卡出炉了',
      body: '今天是人是狗？点开看看，顺手晒一晒。',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'nightly_card',
          '每晚结算提醒',
          channelDescription: '每天晚上提醒你看今天的结算卡',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      // 不用精确闹钟：晚几分钟没关系，也不用申请精确闹钟权限
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> cancel() async {
    await _init();
    await _plugin.cancel(id: _id);
  }

  @override
  Future<bool> handleOpen(VoidCallback onOpen) async {
    _onOpen = onOpen;
    try {
      await _init();
      final details = await _plugin.getNotificationAppLaunchDetails();
      return details?.didNotificationLaunchApp ?? false;
    } catch (_) {
      // 测试环境和不支持通知的平台没有这个插件
      return false;
    }
  }
}
