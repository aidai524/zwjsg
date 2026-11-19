import 'dart:async';
import 'dart:convert';

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'dog_meter.dart';
import 'usage_channel.dart';

/// 桌面小组件拿什么算狗度
enum DogWidgetSource {
  /// 安卓开了“使用情况访问权限”：小组件自己算今天刷了多久（和 App 用同一个 TodayUsage）
  usage,

  /// iOS 在按屏幕使用时间统计：小组件读监控扩展记下的阶段（只知道越过了哪个阈值）
  screenTime,

  /// 还拿不到真实数据（没开权限、没开屏幕使用时间、模拟器）：小组件提示打开 App，不显示演示数据
  none,
}

/// 交给桌面小组件的东西。规则和文案都从 [DogMeter] 来，小组件原样用，不在原生代码里再写一份；
/// 原生只做“分钟 ÷ 目标 → 百分比 → 数越过了几个阈值”这一步（和 [DogMeter.percentFor]、[DogMeter.stageFor] 一样）。
/// 只有狗度和阶段，没有任何 App 名称，也不上传。
class DogWidgetConfig {
  const DogWidgetConfig({required this.ready, required this.source, required this.goalMinutes});

  /// 同意了隐私政策、做完了引导
  final bool ready;
  final DogWidgetSource source;
  final int goalMinutes;

  Map<String, Object?> toMap() => {
        'ready': ready,
        'source': source.name,
        'goal_minutes': goalMinutes,
        // 阶段 1–5 的狗度阈值（百分比）
        'thresholds': DogMeter.stageThresholds,
        'stage_names': DogMeter.stageNames,
        'quips': DogMeter.quips,
        // 下一阶段会变成什么样，长度比阶段名少 1
        'next_change': DogMeter.nextChange,
      };
}

/// 和原生的桌面小组件打交道（iOS 的 WidgetKit 扩展、安卓的 AppWidget）。测试里换成假的
abstract class HomeWidgetBridge {
  /// 形象图放在哪个目录：iOS 是和小组件共享的 App Group 目录，安卓是 App 自己的 files 目录。拿不到时返回 null
  Future<String?> directory();

  /// 把规则、目标和数据来源交给小组件，小组件马上重画
  Future<void> configure(DogWidgetConfig config);

  /// 让小组件重新算一次、重画（形象图换了，或者狗度变了）
  Future<void> reload();
}

class ChannelHomeWidgetBridge implements HomeWidgetBridge {
  const ChannelHomeWidgetBridge();

  static const _channel = MethodChannel('zwjsg/home_widget');

  @override
  Future<String?> directory() => _call<String>('directory');

  @override
  Future<void> configure(DogWidgetConfig config) => _call<void>('configure', config.toMap());

  @override
  Future<void> reload() => _call<void>('reload');

  /// 小组件出问题不能影响 App：调不通就当没有小组件
  static Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

/// 把 App 里的状态同步给桌面小组件：
/// - 每日目标、数据来源变了，或者 App 刚打开 → 交给小组件；
/// - 形象变了（拍照做了新形象、换手机找回、注销）→ 重画 6 张形象图（变狗阶段 0–5），存到小组件能读的目录；
/// - App 里算出的阶段变了 → 让小组件也重画一次（安卓的小组件自己会定时算，iOS 的由监控扩展叫醒）。
class HomeWidgetSync {
  HomeWidgetSync(this.state, {this.bridge = const ChannelHomeWidgetBridge()});

  final AppState state;
  final HomeWidgetBridge bridge;

  /// 形象图的边长（像素）。小组件上最大约 120 点，3 倍屏 360 像素
  static const avatarPixels = 360;

  /// 形象图的文件名：dog_0.png … dog_5.png
  static String fileName(int stage) => 'dog_$stage.png';

  String? _configured;
  int? _stage;
  Future<void>? _running;
  bool _again = false;

  /// App 启动时调用：之后状态一变就同步
  void start() {
    state.addListener(_changed);
    _changed();
  }

  void stop() => state.removeListener(_changed);

  void _changed() => unawaited(sync());

  /// 看 App 自己拿到的是什么数据：真实分钟数（安卓开了权限）→ 小组件自己按分钟算；
  /// 只有阶段（iOS 屏幕使用时间）→ 小组件读阶段；还拿不到数据 → 小组件提示打开 App
  static DogWidgetSource sourceFor(UsageSnapshot usage) => !usage.available
      ? DogWidgetSource.none
      : (usage.stageOnly ? DogWidgetSource.screenTime : DogWidgetSource.usage);

  DogWidgetSource get _source => sourceFor(state.usage);

  DogWidgetConfig get config => DogWidgetConfig(
        ready: state.privacyAccepted && state.onboarded,
        source: _source,
        goalMinutes: state.goalMinutes,
      );

  /// 同步一次。正在同步时又有变化，等这一轮做完再做一轮
  Future<void> sync() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      final configured = await _syncConfig();
      final drew = await _syncAvatars();
      // 配置刚交过去时小组件已经重画了，不用再叫一次
      if (!configured && !drew) await _syncStage();
    } while (_again);
  }

  Future<bool> _syncConfig() async {
    // 刚打开 App、还没读过使用情况时先不交：这时还不知道有没有数据，小组件会闪一下“打开 App 开权限”
    if (!state.usageChecked) return false;
    final c = config;
    final key = jsonEncode(c.toMap());
    if (key == _configured) return false;
    _configured = key;
    _stage = state.stage;
    await bridge.configure(c);
    return true;
  }

  Future<bool> _syncAvatars() async {
    final dir = await bridge.directory();
    if (dir == null) return false;
    final png = state.photoAvatarPng;
    final sticker = state.photoAvatar;
    final drew = await WidgetImages.sync(
      dir: dir,
      signature: 'v$dogAvatarArtVersion:${png == null ? 'default' : WidgetImages.fingerprint(png)}',
      images: {
        for (var stage = 0; stage <= 5; stage++)
          fileName(stage): () => sticker == null
              ? renderDogAvatar(stage: stage, pixels: avatarPixels)
              : renderPhotoDogAvatar(sticker: sticker, stage: stage, pixels: avatarPixels),
      },
      stale: () => !identical(state.photoAvatarPng, png),
    );
    // 画到一半形象又换了：这一轮作废，再来一轮
    if (!identical(state.photoAvatarPng, png)) {
      _again = true;
      return false;
    }
    if (drew) await bridge.reload();
    return drew;
  }

  /// App 里刷新用量后阶段变了，小组件也跟着重画（没拿到数据时不算）
  Future<void> _syncStage() async {
    if (_source == DogWidgetSource.none) return;
    final stage = state.stage;
    if (stage == _stage) return;
    _stage = stage;
    await bridge.reload();
  }
}
