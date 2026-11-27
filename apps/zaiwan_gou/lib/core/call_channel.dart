import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'app_lock.dart';
import 'bark_detector.dart';
import 'dog_meter.dart';

/// 一通超时来电（2026-11-23 起两端共用一个像 FaceTime 的 Flutter 来电界面，lib/features/call/call_screen.dart）：
/// - 安卓：无障碍服务发现超时，打开 CallReminderActivity（单独的任务栈、单独的 Flutter 引擎，入口是 main.dart 的 callMain），
///   一打开就用手机自己的来电铃声响起来、震动
/// - iOS：监控扩展发现超时，挡上屏蔽页、发一条带原创铃声的通知；点通知、在屏蔽页上点“接听”，或者 10 分钟内自己打开 App，
///   就弹出来电界面（CallGate）
class IncomingCall {
  const IncomingCall({
    required this.lockId,
    required this.limitMinutes,
    this.dogPercent,
    this.label,
    this.apps = 0,
    this.categories = 0,
    this.webDomains = 0,
    this.usedMinutes,
    this.todayMinutes,
    this.stage,
    this.answered = false,
    this.locked = false,
    this.preview = false,
  });

  factory IncomingCall.fromMap(Map<dynamic, dynamic> m) {
    int n(String k) => (m[k] as num? ?? 0).toInt();
    int? maybe(String k) => (m[k] as num?)?.toInt();
    return IncomingCall(
      lockId: m['lockId'] as String,
      limitMinutes: n('limitMinutes'),
      dogPercent: maybe('dogPercent'),
      label: m['label'] as String?,
      apps: n('apps'),
      categories: n('categories'),
      webDomains: n('webDomains'),
      usedMinutes: maybe('usedMinutes'),
      todayMinutes: maybe('todayMinutes'),
      stage: maybe('stage'),
      answered: m['answered'] as bool? ?? false,
      locked: m['locked'] as bool? ?? false,
      preview: m['preview'] as bool? ?? false,
    );
  }

  /// 交给原生（iOS 的“试一下来电通知”记下这通电话）。不放空值：iOS 的 UserDefaults 存不了
  Map<String, Object> toMap() => {
        'lockId': lockId,
        'limitMinutes': limitMinutes,
        if (dogPercent != null) 'dogPercent': dogPercent!,
        if (label != null) 'label': label!,
        'apps': apps,
        'categories': categories,
        'webDomains': webDomains,
        if (usedMinutes != null) 'usedMinutes': usedMinutes!,
        if (todayMinutes != null) 'todayMinutes': todayMinutes!,
        if (stage != null) 'stage': stage!,
        'answered': answered,
        'locked': locked,
        'preview': preview,
      };

  final String lockId;

  /// 这个限时每天多少分钟
  final int limitMinutes;

  /// 按狗度来的限时：今天狗度到这么多（%）就来电；按额度的是 null
  final int? dogPercent;

  /// 安卓：超时的 App 名。只显示在来电界面上，不念出来、不上传
  final String? label;

  /// iOS：系统只告诉选了几个
  final int apps;
  final int categories;
  final int webDomains;

  /// 安卓：这个限时今天用了多久；iOS 拿不到
  final int? usedMinutes;

  /// 安卓：今天一共刷了多少分钟，用来按 [DogMeter] 算狗版的你现在是第几阶段
  final int? todayMinutes;

  /// iOS：监控扩展记下的今天的阶段
  final int? stage;

  /// iOS：在屏蔽页上点了“接听”，打开就是通话中
  final bool answered;

  /// 安卓：今天拒接过，再打开这个 App 直接是“今天锁死了”
  final bool locked;

  /// “试一下来电”：响铃、说话、听狗叫都是真的，但不会真的锁上或放行
  final bool preview;

  String get title => label ?? describeSelection(apps, categories, webDomains);

  /// 狗版的你现在的阶段：iOS 用记下的阶段，安卓按今天的用量和每日目标算
  int stageFor(int goalMinutes) {
    if (stage != null) return stage!.clamp(0, DogMeter.stageNames.length - 1);
    final minutes = todayMinutes;
    if (minutes == null) return 0;
    return DogMeter.stageFor(DogMeter.percentFor(minutes, goalMinutes));
  }
}

/// 接通、挂断时的提示音（assets/sounds/，两端原生播放）
enum CallTone { connect, hangup }

/// 来电界面要的原生能力。抽成接口，测试里换成假的
abstract class CallBackend {
  /// 有没有正在打来的电话；没有返回 null
  Future<IncomingCall?> pending();

  /// 响铃、震动（安卓用手机自己的来电铃声，iOS 用原创铃声）；跟系统一样，静音模式下只震动
  Future<void> ring();
  Future<void> stopRing();

  Future<void> tone(CallTone tone);

  /// 放一句打包好的狗版的你的语音（Flutter 资源路径，见 CallVoice），返回它有多长（毫秒）；放不了返回 null
  Future<int?> playVoice(String asset);

  /// 狗版的你说话（系统语音）：只在打包的语音放不了时用。念的话里不带 App 名称：安卓的语音引擎可能是第三方的
  Future<void> speak(String text);

  /// 停掉正在放的语音和系统语音
  Future<void> stopSpeaking();

  /// 开麦克风听狗叫：'listening'（音量 + 手机上的声音分类）/ 'levels'（分类器用不了，只有音量）/
  /// 'denied'（没给权限）/ 'failed'（打不开）。只在手机上听，不录音、不保存、不上传
  Future<String> startListening();
  Future<void> stopListening();

  /// 听狗叫时原生交过来的：每 20 毫秒一个音量，和手机上的声音分类器每 0.25 秒一次的判断
  Stream<MicInput> mic();

  /// 学会两声狗叫：放行这个限时，再玩 [LockService.snoozeMinutes] 分钟，到点再来电
  Future<bool> grant(String lockId);

  /// 拒接：这个限时今天锁死，明天 0 点解开
  Future<void> decline(String lockId);

  /// 接了又挂了（不玩了）：不放行，也不锁死，下次打开那个 App 还会来电
  Future<void> hangUp(String lockId);

  /// 关掉来电界面。安卓来电页：放行了就回到那个 App，没放行就回桌面；
  /// iOS 和“试一下来电”：页面由 Flutter 自己关，原生只停掉声音、把声音还给别的 App
  Future<void> close({required bool granted});

  Future<void> openSettings();

  /// iOS 的“试一下来电通知”：[delay] 以后响一条和真的一样的来电通知（铃声也一样），点通知回到 App 就是 [call] 这通试一下的来电。
  /// 返回 'scheduled' / 'noSound'（通知的声音关着）/ 'denied'（通知没开）/ 'failed' / 'unsupported'（安卓：来电页直接盖在 App 上，没有来电通知）
  Future<String> previewNotice(IncomingCall call, {Duration delay = const Duration(seconds: 8)});
}

/// 两端的实现：安卓 CallPlugin.kt（只在来电页的引擎里注册），iOS CallPlugin.swift
class PlatformCallBackend implements CallBackend {
  const PlatformCallBackend();

  static const _method = MethodChannel('zwjsg/call');
  static const _mic = EventChannel('zwjsg/bark_sounds');

  @override
  Future<IncomingCall?> pending() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final m = await _method.invokeMethod<Map<dynamic, dynamic>>('pending');
      // 没有来电时原生返回空；拿到的不像样也当没有
      return m == null || m['lockId'] is! String ? null : IncomingCall.fromMap(m);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _call(String method, [Map<String, Object?>? args]) async {
    try {
      await _method.invokeMethod<void>(method, args);
    } on PlatformException {
      // 响铃、说话、提示音出不来不影响接着用
    } on MissingPluginException {
      // 同上
    }
  }

  @override
  Future<void> ring() => _call('ring');

  @override
  Future<void> stopRing() => _call('stopRing');

  @override
  Future<void> tone(CallTone tone) => _call('tone', {'name': tone.name});

  @override
  Future<int?> playVoice(String asset) async {
    try {
      return (await _method.invokeMethod<num>('playVoice', {'asset': asset}))?.toInt();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> speak(String text) => _call('speak', {'text': text});

  @override
  Future<void> stopSpeaking() => _call('stopSpeaking');

  @override
  Future<String> startListening() async {
    try {
      return await _method.invokeMethod<String>('startListening') ?? 'failed';
    } on PlatformException {
      return 'failed';
    } on MissingPluginException {
      return 'failed';
    }
  }

  @override
  Future<void> stopListening() => _call('stopListening');

  /// 一批音量是一个列表，一个分类结果是一个 Map（见 [SoundWindow.fromMap]）
  @override
  Stream<MicInput> mic() => _mic.receiveBroadcastStream().expand((event) => switch (event) {
        List<dynamic> levels => [for (final v in levels) MicLevel((v as num).toDouble())],
        Map<dynamic, dynamic> window => [SoundWindow.fromMap(window)],
        _ => const <MicInput>[],
      });

  @override
  Future<bool> grant(String lockId) async => await _method.invokeMethod<bool>('grant', {'lockId': lockId}) ?? false;

  @override
  Future<void> decline(String lockId) => _call('decline', {'lockId': lockId});

  @override
  Future<void> hangUp(String lockId) => _call('hangUp', {'lockId': lockId});

  @override
  Future<void> close({required bool granted}) => _call('close', {'granted': granted});

  @override
  Future<void> openSettings() => _call('openSettings');

  @override
  Future<String> previewNotice(IncomingCall call, {Duration delay = const Duration(seconds: 8)}) async {
    try {
      return await _method.invokeMethod<String>(
              'previewNotice', {'call': call.toMap(), 'delaySeconds': delay.inSeconds}) ??
          'failed';
    } on PlatformException {
      return 'failed';
    } on MissingPluginException {
      return 'unsupported';
    }
  }
}
