import 'dart:async';
import 'dart:convert';

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/services.dart';

import 'api_client.dart' show kApiBase;
import 'app_state.dart';

/// 桌面小组件要知道的事：查哪个城市、温度用什么单位、找哪个后端。
/// 小组件自己大约每 30 分钟向后端取一次精简天气（GET /widget/{locationId}），不登录、不带个人信息。
class HomeWidgetConfig {
  const HomeWidgetConfig({
    required this.apiBase,
    required this.locationId,
    required this.city,
    this.adm,
    required this.unit,
  });

  final String apiBase;
  final String locationId;

  /// 显示在小组件上的城市名
  final String city;

  /// 省份：判断回南天要用
  final String? adm;

  /// 温度单位：c / f，后端按它写好温度和句子
  final String unit;

  Map<String, Object?> toMap() => {'api_base': apiBase, 'location_id': locationId, 'city': city, 'adm': adm, 'unit': unit};
}

/// 和原生的桌面小组件打交道（iOS 的 WidgetKit 扩展、安卓的 AppWidget）。测试里换成假的
abstract class HomeWidgetBridge {
  /// 形象图放在哪个目录：iOS 是和小组件共享的 App Group 目录，安卓是 App 自己的 files 目录。拿不到时返回 null
  Future<String?> directory();

  /// 告诉小组件查哪个城市，小组件马上重新取天气。null 表示还没选城市或还没同意隐私政策，小组件提示打开 App
  Future<void> configure(HomeWidgetConfig? config);

  /// 形象图换了，让小组件重画
  Future<void> reload();
}

class ChannelHomeWidgetBridge implements HomeWidgetBridge {
  const ChannelHomeWidgetBridge();

  static const _channel = MethodChannel('shenmetianqi/home_widget');

  @override
  Future<String?> directory() => _call<String>('directory');

  @override
  Future<void> configure(HomeWidgetConfig? config) => _call<void>('configure', config?.toMap());

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
/// - 常驻城市、温度单位变了，或者 App 刚打开 → 把城市和单位告诉小组件，小组件马上重新取天气；
/// - 形象变了（导入、用回默认、换手机找回、退出登录）→ 重画每种天气下的形象图，存到小组件能读的目录。
///   小组件跑不了 Flutter，只能按后端给的衣服档和天气状态挑一张画好的图。
///   画好后在目录里记下画的是哪个形象（[versionFile]），下次打开 App 时一样就不重画。
class HomeWidgetSync {
  HomeWidgetSync(this.state, {this.bridge = const ChannelHomeWidgetBridge()});

  final AppState state;
  final HomeWidgetBridge bridge;

  /// 形象图的边长（像素）。小组件上最大约 140 点，3 倍屏 420 像素，360 已经够清楚
  static const avatarPixels = 360;

  /// 记录目录里的形象图画的是哪个形象（见 [WidgetImages]）
  static const versionFile = WidgetImages.versionFile;

  /// 要画的形象：6 档衣服 × 10 种天气，加上预警时举着伞的一张（严肃模式不分衣服档），共 61 张
  static final List<(WeatherTemp, WeatherCond)> avatarStates = [
    for (final t in WeatherTemp.values)
      for (final c in WeatherCond.values)
        if (c != WeatherCond.serious) (t, c),
    (WeatherTemp.mild, WeatherCond.serious),
  ];

  /// 文件名用后端的名字，小组件拿到 outfit 和 cond 直接拼：avatar_mild_light_rain.png；严肃模式是 avatar_serious.png
  static String fileName(WeatherTemp t, WeatherCond c) =>
      c == WeatherCond.serious ? 'avatar_serious.png' : 'avatar_${weatherTempKey(t)}_${weatherCondKey(c)}.png';

  String? _configured;
  Future<void>? _running;
  bool _again = false;

  /// App 启动时调用：之后状态一变就同步
  void start() {
    state.addListener(_changed);
    _changed();
  }

  void stop() => state.removeListener(_changed);

  void _changed() => unawaited(sync());

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
      await _syncConfig();
      await _syncAvatars();
    } while (_again);
  }

  HomeWidgetConfig? get _config {
    final home = state.homeCity;
    // 同意隐私政策之前不查天气，小组件也一样
    if (!state.privacyAccepted || home == null) return null;
    return HomeWidgetConfig(apiBase: kApiBase, locationId: home.locationId, city: home.name, adm: home.adm, unit: state.tempUnit.key);
  }

  Future<void> _syncConfig() async {
    final config = _config;
    final key = jsonEncode(config?.toMap());
    if (key == _configured) return;
    _configured = key;
    await bridge.configure(config);
  }

  Future<void> _syncAvatars() async {
    final dir = await bridge.directory();
    if (dir == null) return;
    final png = state.avatarPng;
    final sticker = state.avatar;
    // 签名 = 画法版本 + 形象原图的指纹；对得上、图也都在就不重画（卸载重装时目录会被清空）
    final drew = await WidgetImages.sync(
      dir: dir,
      signature: 'v$weatherAvatarArtVersion:${png == null ? 'default' : WidgetImages.fingerprint(png)}',
      images: {
        for (final (t, c) in avatarStates)
          fileName(t, c): () => renderWeatherAvatar(temp: t, cond: c, sticker: sticker, pixels: avatarPixels),
      },
      stale: () => !identical(state.avatarPng, png),
    );
    // 画到一半形象又换了：这一轮作废，再来一轮
    if (!identical(state.avatarPng, png)) {
      _again = true;
      return;
    }
    if (drew) await bridge.reload();
  }
}
