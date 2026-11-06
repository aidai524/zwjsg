import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'breeds.dart';
import 'dog_meter.dart';
import 'usage_channel.dart';

/// 全局状态。MVP 足够用；功能多了再换 Riverpod 之类的方案。
class AppState extends ChangeNotifier {
  AppState(this._prefs) {
    _token = _prefs.getString(_kToken);
    _onboarded = _prefs.getBool(_kOnboarded) ?? false;
    _goalMinutes = _prefs.getInt(_kGoal) ?? 180;
    api.token = _token;
  }

  static const _kToken = 'token';
  static const _kOnboarded = 'onboarded';
  static const _kGoal = 'goal_minutes';

  final SharedPreferences _prefs;
  final ApiClient api = ApiClient();

  String? _token;
  bool _onboarded = false;
  int _goalMinutes = 180;
  UsageSnapshot? _usage;
  bool _hasPermission = false;
  Set<String> _ownedBreeds = {};
  List<String> _newlyUnlocked = [];

  /// 拿不到真实数据时的演示时长，方便在模拟器和 iOS 上看效果
  int demoMinutes = 130;

  bool get isLoggedIn => _token != null;
  bool get onboarded => _onboarded;
  int get goalMinutes => _goalMinutes;
  bool get hasUsagePermission => _hasPermission;
  Set<String> get ownedBreeds => _ownedBreeds;
  List<String> get newlyUnlocked => _newlyUnlocked;

  UsageSnapshot get usage => _usage ?? UsageSnapshot.demo(demoMinutes);
  int get minutesUsed => usage.totalMinutes;
  int get percent => DogMeter.percentFor(minutesUsed, _goalMinutes);
  int get stage => DogMeter.stageFor(percent);
  String? get breedKey => judgeBreed(usage, _goalMinutes);

  static String localDate([DateTime? t]) {
    final d = t ?? DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> login(String phone, String code) async {
    final token = await api.smsLogin(phone, code);
    _token = token;
    api.token = token;
    await _prefs.setString(_kToken, token);
    notifyListeners();
  }

  Future<void> setGoal(int minutes) async {
    _goalMinutes = minutes;
    await _prefs.setInt(_kGoal, minutes);
    notifyListeners();
    if (isLoggedIn) {
      try {
        await api.updateSettings({'daily_goal_minutes': minutes});
      } on ApiException {
        // 离线时先存本地，下次同步
      }
    }
  }

  Future<void> completeOnboarding() async {
    _onboarded = true;
    await _prefs.setBool(_kOnboarded, true);
    notifyListeners();
  }

  /// 读取当天使用情况，并把分数（只有分数）同步到服务端
  Future<void> refreshUsage() async {
    _hasPermission = await UsageChannel.hasPermission();
    _usage = _hasPermission ? await UsageChannel.todayUsage() : null;
    notifyListeners();
    await _sync();
  }

  Future<void> _sync() async {
    if (!isLoggedIn || usage.isDemo) return;
    try {
      _newlyUnlocked = await api.putDailyRecord(
        date: localDate(),
        dogPercent: percent,
        minutesUsed: minutesUsed,
        breedKey: breedKey,
      );
      _ownedBreeds = await api.ownedBreeds();
      notifyListeners();
    } on ApiException {
      // 网络失败不影响本地展示
    }
  }

  void setDemoMinutes(int minutes) {
    demoMinutes = minutes;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } on ApiException {
      // 忽略
    }
    await _clearLocal();
  }

  Future<void> deleteAccount() async {
    await api.deleteAccount();
    await _clearLocal();
  }

  Future<void> _clearLocal() async {
    _token = null;
    api.token = null;
    _onboarded = false;
    _goalMinutes = 180;
    _ownedBreeds = {};
    await _prefs.clear();
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// 只读取、不订阅变化（在回调里用）
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
