import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';
import 'temp_unit.dart';

/// 全局状态。游客也能用：城市、毒舌档位和温度单位存本机；登录后同步到服务端（关心群需要常驻城市）。
class AppState extends ChangeNotifier {
  /// [api]、[avatars] 只在测试里传，换成假的
  AppState(this._prefs, {WeatherApi? api, AvatarStore? avatars})
      : api = api ?? WeatherApi(),
        avatars = avatars ?? const FileAvatarStore() {
    _token = _prefs.getString(_kToken);
    _privacyAccepted = (_prefs.getInt(_kPrivacyVersion) ?? 0) >= privacyVersion;
    _onboarded = _prefs.getBool(_kOnboarded) ?? false;
    _snark = _prefs.getInt(_kSnark) ?? 1;
    _unit = TempUnit.fromKey(_prefs.getString(_kTempUnit));
    final raw = _prefs.getString(_kCities);
    if (raw != null) {
      _cities = (jsonDecode(raw) as List).map((e) => City.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    }
    this.api.token = _token;
    ready.value = _isReady;
    consented.value = _privacyAccepted;
  }

  /// 给路由用：只在“能不能进首页”变化时通知。
  /// 不要把 AppState 直接当 refreshListenable：每次状态变化路由都会重算，
  /// 紧跟在后面的 pop 会被撤销，刚关掉的页面又回来了。
  final ValueNotifier<bool> ready = ValueNotifier(false);

  /// 给路由用：用户同意了当前版本的隐私政策没有
  final ValueNotifier<bool> consented = ValueNotifier(false);

  bool get _isReady => _onboarded && _cities.isNotEmpty;

  @override
  void notifyListeners() {
    ready.value = _isReady;
    consented.value = _privacyAccepted;
    super.notifyListeners();
  }

  /// 隐私政策的版本。内容有重要变化时加 1，所有人打开 App 时重新同意一次。
  /// 2：2026-11-18 可以从“再玩我是狗”导入卡通形象，登录后存服务端、关心群里的家人能看到
  /// 3：2026-11-18 天气卡能存进相册（只写入）、用系统分享面板发出去
  static const privacyVersion = 3;

  bool _privacyAccepted = false;

  /// 第一次打开先同意隐私政策（国内商店的要求），同意之前不查天气、不请求任何权限
  bool get privacyAccepted => _privacyAccepted;

  Future<void> acceptPrivacy() async {
    _privacyAccepted = true;
    await _prefs.setInt(_kPrivacyVersion, privacyVersion);
    notifyListeners();
  }

  static const maxCities = 5;
  static const _kToken = 'token';
  static const _kOnboarded = 'onboarded';
  static const _kSnark = 'snark_level';
  static const _kTempUnit = 'temp_unit';
  static const _kCities = 'cities';
  static const _kPrivacyVersion = 'privacy_version';
  static const _kAvatarPending = 'avatar_pending_upload';

  final SharedPreferences _prefs;
  final WeatherApi api;
  final AvatarStore avatars;

  String? _token;
  bool _onboarded = false;
  int _snark = 1;
  TempUnit _unit = TempUnit.celsius;
  List<City> _cities = [];
  int _currentCity = 0;

  final Map<String, WeatherData> _weather = {};
  final Map<String, DateTime> _fetchedAt = {};
  final Map<String, String> _errors = {};

  bool get isLoggedIn => _token != null;
  bool get onboarded => _onboarded;

  /// 0 正经、1 损友、2 毒舌
  int get snarkLevel => _snark;

  /// 显示温度用的单位：接口给的数字都是摄氏度，显示时用它换算
  TempUnit get tempUnit => _unit;
  List<City> get cities => List.unmodifiable(_cities);
  City? get homeCity => _cities.where((c) => c.isHome).firstOrNull ?? _cities.firstOrNull;

  /// 首页当前显示的城市；从城市页选中后要通知首页翻过去
  int get currentCity => _currentCity;
  set currentCity(int i) {
    if (_currentCity == i) return;
    _currentCity = i;
    notifyListeners();
  }

  WeatherData? weatherOf(String locationId) => _weather[locationId];
  String? errorOf(String locationId) => _errors[locationId];

  // ---- 天气 ----

  /// 10 分钟内不重复请求（服务端也有缓存），下拉刷新时 force
  Future<void> loadWeather(City city, {bool force = false}) async {
    final last = _fetchedAt[city.locationId];
    if (!force && last != null && DateTime.now().difference(last) < const Duration(minutes: 10)) return;
    try {
      _weather[city.locationId] = await api.weather(city.locationId, level: _snark, adm: city.adm, unit: _unit.key);
      _fetchedAt[city.locationId] = DateTime.now();
      _errors.remove(city.locationId);
    } on ApiException catch (e) {
      _errors[city.locationId] = e.message;
    }
    notifyListeners();
  }

  // ---- 城市 ----

  Future<void> addCity(CityHit hit, {bool makeHome = false}) async {
    if (_cities.any((c) => c.locationId == hit.locationId)) {
      _currentCity = _cities.indexWhere((c) => c.locationId == hit.locationId);
      notifyListeners();
      return;
    }
    if (_cities.length >= maxCities) throw ApiException('最多关注 $maxCities 个城市');

    var city = City(locationId: hit.locationId, name: hit.name, adm: hit.adm, isHome: makeHome || _cities.isEmpty);
    if (city.isHome) _cities = [for (final c in _cities) c.copyWith(isHome: false)];
    _cities.add(city);
    _currentCity = _cities.length - 1;
    await _saveCities();

    if (isLoggedIn) {
      try {
        final saved = await api.addCity(city);
        city = city.copyWith(serverId: saved.serverId);
        _cities[_cities.indexWhere((c) => c.locationId == city.locationId)] = city;
        await _saveCities();
      } on ApiException {
        // 下次登录时再同步
      }
    }
  }

  Future<void> removeCity(City city) async {
    _cities.removeWhere((c) => c.locationId == city.locationId);
    if (city.isHome && _cities.isNotEmpty) _cities[0] = _cities[0].copyWith(isHome: true);
    _currentCity = _currentCity.clamp(0, _cities.isEmpty ? 0 : _cities.length - 1);
    await _saveCities();
    if (isLoggedIn && city.serverId != null) {
      try {
        await api.deleteCity(city.serverId!);
      } on ApiException {
        // 忽略
      }
    }
  }

  /// 常驻城市：关心群里家人看到的是这个城市的天气
  Future<void> setHome(City city) async {
    _cities = [for (final c in _cities) c.copyWith(isHome: c.locationId == city.locationId)];
    await _saveCities();
    if (isLoggedIn && city.serverId != null) {
      try {
        await api.setHomeCity(city.serverId!);
      } on ApiException {
        // 忽略
      }
    }
  }

  Future<void> _saveCities() async {
    await _prefs.setString(_kCities, jsonEncode(_cities.map((c) => c.toJson()).toList()));
    notifyListeners();
  }

  /// 登录后：本机城市传上去，再以服务端为准
  Future<void> _syncCities() async {
    try {
      var remote = await api.cities();
      for (final c in _cities) {
        if (!remote.any((r) => r.locationId == c.locationId) && remote.length < maxCities) {
          await api.addCity(c);
        }
      }
      final localHome = homeCity;
      remote = await api.cities();
      final home = remote.where((r) => r.locationId == localHome?.locationId).firstOrNull;
      if (home != null && !home.isHome && home.serverId != null) await api.setHomeCity(home.serverId!);
      _cities = await api.cities();
      await _saveCities();
    } on ApiException {
      // 离线时先用本机的
    }
  }

  // ---- 设置 ----

  Future<void> setSnark(int level) async {
    _snark = level;
    await _prefs.setInt(_kSnark, level);
    _fetchedAt.clear(); // 换档后重新取吐槽
    notifyListeners();
    if (isLoggedIn) {
      try {
        await api.updateSettings({'snark_level': level});
      } on ApiException {
        // 忽略
      }
    }
  }

  /// 换温度单位：数字马上按新单位显示；秋裤理由这类服务端拼好的句子要重新取。
  /// 登录了就同步到服务端，早安推送按这个单位写
  Future<void> setTempUnit(TempUnit unit) async {
    if (unit == _unit) return;
    _unit = unit;
    await _prefs.setString(_kTempUnit, unit.key);
    _fetchedAt.clear();
    notifyListeners();
    if (isLoggedIn) {
      try {
        await api.updateSettings({'temp_unit': unit.key});
      } on ApiException {
        // 天气请求每次都带单位，传失败只影响推送里的写法；下次登录时再同步
      }
    }
  }

  PushSettings? _push;
  bool _pushLoading = false;
  String? _pushError;

  /// 推送设置：登录后从服务端拉；没登录、还没拉到时是 null
  PushSettings? get push => _push;
  bool get pushLoading => _pushLoading;
  String? get pushError => _pushError;

  Future<void> loadPush() async {
    if (!isLoggedIn || _pushLoading) return;
    _pushLoading = true;
    _pushError = null;
    notifyListeners();
    try {
      _push = PushSettings.fromJson(await api.me());
    } on ApiException catch (e) {
      _pushError = e.message;
    } finally {
      _pushLoading = false;
      notifyListeners();
    }
  }

  /// 改推送设置：界面先改过来；传服务端失败就改回去，并抛 [ApiException]
  Future<void> updatePush(PushSettings next) async {
    final old = _push;
    if (old == null) return;
    final changes = next.changesFrom(old);
    if (changes.isEmpty) return;
    _push = next;
    notifyListeners();
    try {
      await api.updateSettings(changes);
    } on ApiException {
      _push = old;
      notifyListeners();
      rethrow;
    }
  }

  // ---- 形象 ----

  ui.Image? _avatar;
  Uint8List? _avatarPng;

  /// 从“再玩我是狗”导入的卡通形象（贴纸）；没导入时是 null，各处用代码画的默认形象
  ui.Image? get avatar => _avatar;

  /// [avatar] 的原图（PNG）。桌面小组件按它判断形象换没换、要不要重画形象图
  Uint8List? get avatarPng => _avatarPng;

  /// App 启动时读出存在手机上的形象。登录了、上次没传上去的，顺便补传
  Future<void> loadAvatar() async {
    Uint8List? png;
    try {
      png = await avatars.load();
    } catch (_) {
      return; // 读不到就先用默认形象
    }
    if (png == null) return;
    try {
      _avatar = await _decode(png);
      _avatarPng = png;
    } catch (_) {
      return; // 图坏了也先用默认形象，可以重新导入
    }
    notifyListeners();
    // 补传放到后台，不耽误 App 打开
    if (isLoggedIn && (_prefs.getBool(_kAvatarPending) ?? false)) unawaited(_uploadPendingAvatar());
  }

  /// 凭导出码从“再玩我是狗”导入卡通形象：先存在手机上，登录了再传服务端（换手机能找回，关心群里的家人能看到）。
  /// 码不对、过期或者连不上时抛 [ApiException]，手机上原来的形象不变
  Future<void> importAvatar(String code) async {
    final png = await api.importAvatar(code);
    final ui.Image image;
    try {
      image = await _decode(png);
    } catch (_) {
      throw ApiException('导入的形象打不开，回「再玩我是狗」重新生成一个导出码试试');
    }
    await avatars.save(png);
    await _prefs.setBool(_kAvatarPending, true);
    _avatar = image;
    _avatarPng = png;
    notifyListeners();
    if (isLoggedIn) await _uploadPendingAvatar();
  }

  /// 用回默认形象。登录了先删服务端的，删不掉时抛 [ApiException]，手机上的不动
  Future<void> clearAvatar() async {
    if (isLoggedIn) await api.deleteAvatar();
    await _forgetAvatar();
    notifyListeners();
  }

  Future<void> _forgetAvatar() async {
    try {
      await avatars.delete();
    } catch (_) {
      // 删不掉也当没有
    }
    await _prefs.remove(_kAvatarPending);
    _avatar = null;
    _avatarPng = null;
  }

  Future<void> _uploadPendingAvatar() async {
    final png = _avatarPng;
    if (png == null || !isLoggedIn) return;
    try {
      await api.uploadAvatar(png);
      await _prefs.setBool(_kAvatarPending, false);
    } on ApiException catch (e) {
      // 服务端不收就不再补传，手机上的照用；没网就等下次
      if (e.statusCode == 422) await _prefs.setBool(_kAvatarPending, false);
    }
  }

  /// 登录后对一下形象：手机上有、还没传上去的就补传；手机上没有、服务端有（比如换了手机），就下载回来
  Future<void> _syncAvatar() async {
    if (_avatarPng != null) {
      if (_prefs.getBool(_kAvatarPending) ?? false) await _uploadPendingAvatar();
      return;
    }
    try {
      final url = (await api.me())['avatar_url'] as String?;
      if (url == null) return;
      final png = await api.downloadAvatar(url);
      final image = await _decode(png);
      await avatars.save(png);
      await _prefs.setBool(_kAvatarPending, false);
      _avatar = image;
      _avatarPng = png;
    } catch (_) {
      // 拉不到就先用默认形象，下次登录再试
    }
  }

  final Map<String, Future<ui.Image?>> _memberAvatars = {};

  /// 关心群里别人的形象：同一个地址只下载一次，App 开着时记住；下载不到、图坏了返回 null（用默认形象，下次再试）
  Future<ui.Image?> memberAvatar(String url) => _memberAvatars.putIfAbsent(url, () async {
        try {
          return await _decode(await api.downloadAvatar(url));
        } catch (_) {
          _memberAvatars.remove(url);
          return null;
        }
      });

  static Future<ui.Image> _decode(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  Future<void> completeOnboarding() async {
    _onboarded = true;
    await _prefs.setBool(_kOnboarded, true);
    notifyListeners();
  }

  // ---- 账号 ----

  Future<void> login(String phone, String code) async {
    final token = await api.smsLogin(phone, code);
    _token = token;
    api.token = token;
    await _prefs.setString(_kToken, token);
    try {
      await api.updateSettings({'snark_level': _snark, 'temp_unit': _unit.key, 'timezone': 'Asia/Shanghai'});
    } on ApiException {
      // 忽略
    }
    await _syncCities();
    await _syncAvatar();
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } on ApiException {
      // 忽略
    }
    await _dropAccount();
  }

  Future<void> deleteAccount() async {
    await api.deleteAccount();
    await _dropAccount();
  }

  /// 退出账号只清登录信息；本机城市留着，游客照样能看天气。
  /// 导入的形象从手机上删掉（再登录时从服务端找回来）
  Future<void> _dropAccount() async {
    _token = null;
    api.token = null;
    _push = null;
    _pushError = null;
    await _prefs.remove(_kToken);
    await _forgetAvatar();
    _memberAvatars.clear();
    _cities = [for (final c in _cities) City(locationId: c.locationId, name: c.name, adm: c.adm, isHome: c.isHome)];
    await _saveCities();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// 只读取、不订阅变化（在回调里用）
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
