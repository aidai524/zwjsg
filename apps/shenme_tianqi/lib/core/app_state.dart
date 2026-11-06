import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';

/// 全局状态。游客也能用：城市和毒舌档位存本机；登录后同步到服务端（关心群需要常驻城市）。
class AppState extends ChangeNotifier {
  AppState(this._prefs) {
    _token = _prefs.getString(_kToken);
    _onboarded = _prefs.getBool(_kOnboarded) ?? false;
    _snark = _prefs.getInt(_kSnark) ?? 1;
    final raw = _prefs.getString(_kCities);
    if (raw != null) {
      _cities = (jsonDecode(raw) as List).map((e) => City.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    }
    api.token = _token;
  }

  static const maxCities = 5;
  static const _kToken = 'token';
  static const _kOnboarded = 'onboarded';
  static const _kSnark = 'snark_level';
  static const _kCities = 'cities';

  final SharedPreferences _prefs;
  final WeatherApi api = WeatherApi();

  String? _token;
  bool _onboarded = false;
  int _snark = 1;
  List<City> _cities = [];
  int _currentCity = 0;

  final Map<String, WeatherData> _weather = {};
  final Map<String, DateTime> _fetchedAt = {};
  final Map<String, String> _errors = {};

  bool get isLoggedIn => _token != null;
  bool get onboarded => _onboarded;

  /// 0 正经、1 损友、2 毒舌
  int get snarkLevel => _snark;
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
      _weather[city.locationId] = await api.weather(city.locationId, level: _snark, adm: city.adm);
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
        city = city.copyWith(serverId: saved.id);
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
      await api.updateSettings({'snark_level': _snark, 'timezone': 'Asia/Shanghai'});
    } on ApiException {
      // 忽略
    }
    await _syncCities();
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

  /// 退出账号只清登录信息；本机城市留着，游客照样能看天气
  Future<void> _dropAccount() async {
    _token = null;
    api.token = null;
    await _prefs.remove(_kToken);
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
