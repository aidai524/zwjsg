import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart' show AvatarPreset, Evolution;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'app_lock.dart' show LockService;
import 'avatar_store.dart';
import 'breeds.dart';
import 'dog_meter.dart';
import 'evolution.dart';
import 'festivals.dart';
import 'history.dart';
import 'reminders.dart';
import 'screen_time_channel.dart';
import 'usage_channel.dart';

/// 全局状态。MVP 足够用；功能多了再换 Riverpod 之类的方案。
class AppState extends ChangeNotifier {
  /// [reminders]、[api]、[avatars] 只在测试里传，换成假的
  AppState(this._prefs, {ReminderScheduler? reminders, ApiClient? api, AvatarStore? avatars})
      : reminders = reminders ?? LocalReminderScheduler.instance,
        api = api ?? ApiClient(),
        avatars = avatars ?? const FileAvatarStore() {
    _token = _prefs.getString(_kToken);
    _onboarded = _prefs.getBool(_kOnboarded) ?? false;
    // 目标改成三档以后，旧版本自己设的小时数换成最接近的一档
    final storedGoal = _prefs.getInt(_kGoal);
    _goalMinutes = GoalTier.nearest(storedGoal ?? GoalTier.normal.minutes).minutes;
    if (storedGoal != null && storedGoal != _goalMinutes) unawaited(_prefs.setInt(_kGoal, _goalMinutes));
    _nickname = _prefs.getString(_kNickname);
    _remindOn = _prefs.getBool(_kRemindOn) ?? false;
    _remindAt = parseHhmm(_prefs.getString(_kRemindAt)) ?? defaultRemindAt;
    _privacyAccepted = (_prefs.getInt(_kPrivacyVersion) ?? 0) >= privacyVersion;
    _newlyUnlocked = _prefs.getStringList(_kPendingUnlocks) ?? [];
    _localUnlocks = _readLocalUnlocks();
    _evolutions = _readEvolutions();
    _evolutionWorn = _prefs.getString(_kEvolutionWorn);
    _avatarPreset = AvatarPreset.byName(_prefs.getString(_kAvatarPreset));
    this.api.token = _token;
    ready.value = _onboarded;
    consented.value = _privacyAccepted;
  }

  final ReminderScheduler reminders;

  /// 拍照形象存在手机上的地方
  final AvatarStore avatars;

  /// 给路由用：只在“引导是否完成”变化时通知。
  /// 不要把 AppState 直接当 refreshListenable：每次状态变化路由都会重算，
  /// 紧跟在后面的 pop 会被撤销，刚关掉的页面又回来了。
  final ValueNotifier<bool> ready = ValueNotifier(false);

  /// 给路由用：用户同意了当前版本的隐私政策没有
  final ValueNotifier<bool> consented = ValueNotifier(false);

  @override
  void notifyListeners() {
    ready.value = _onboarded;
    consented.value = _privacyAccepted;
    super.notifyListeners();
  }

  /// 隐私政策的版本。内容有重要变化时加 1，所有人打开 App 时重新同意一次
  /// 2：2026-11-16 加了拍照形象（相机、人脸单独同意、AI 生成标识）
  /// 3：2026-11-18 可以把卡通形象导出给“什么鬼天气”
  /// 4：2026-11-20 加了群组（群里的人能看到你每天的狗度、阶段和犬种）；登录验证码短信由阿里云发送；
  ///    2026-11-23 超时来电想再玩要学狗叫，用到麦克风（只听音量，不录音）；2026-11-24 改成在手机上判断是不是叫出来的、
  ///    像不像狗叫（iOS 系统自带的声音分类器，安卓打包的 YAMNet），还是不录音、不上传；2026-11-27 加了预设形象
  ///    （登录后同步挑的是哪张，群里的人看到的是这张），安卓也能用自拍做形象了（App 里开相机，照片只在内存里）。
  ///    都还没发出去，算在同一版里
  static const privacyVersion = 4;

  bool _privacyAccepted = false;

  /// 同意隐私政策之前，不读使用数据、不读应用列表、不请求任何权限
  bool get privacyAccepted => _privacyAccepted;

  Future<void> acceptPrivacy() async {
    _privacyAccepted = true;
    await _prefs.setInt(_kPrivacyVersion, privacyVersion);
    notifyListeners();
  }

  static const _kToken = 'token';
  static const _kOnboarded = 'onboarded';
  static const _kGoal = 'goal_minutes';
  static const _kNickname = 'nickname';
  static const _kRemindOn = 'remind_on';
  static const _kRemindAt = 'remind_at';
  static const _kPrivacyVersion = 'privacy_version';
  static const _kFaceConsent = 'face_consent_version';
  static const _kAvatarPending = 'avatar_pending_upload';
  static const _kAvatarPreset = 'avatar_preset';
  static const _kAvatarPresetPending = 'avatar_preset_pending';
  static const _kPendingUnlocks = 'pending_unlocks';
  static const _kLocalUnlocks = 'local_breed_unlocks';
  static const _kEvolutions = 'evolutions';
  static const _kEvolutionWorn = 'evolution_worn';

  /// [_kEvolutionWorn] 存这个表示用户挑了“不穿”
  static const _wearNone = 'none';
  static const _kCallVoice = 'call_voice';

  /// 默认每晚 22:00 提醒看结算卡
  static const defaultRemindAt = 22 * 60;

  /// 昵称最长 16 个字，和后端的校验一致（按字符数，不按字节）
  static const nicknameMaxLength = 16;

  final SharedPreferences _prefs;
  final ApiClient api;

  /// 每天的结果，只存在手机上
  late final HistoryStore history = HistoryStore(_prefs);

  String? _token;
  bool _onboarded = false;
  int _goalMinutes = GoalTier.normal.minutes;
  String? _nickname;
  bool _remindOn = false;
  int _remindAt = defaultRemindAt;
  UsageSnapshot? _usage;
  bool _hasPermission = false;
  ScreenTimeStatus? _screenTime;
  /// 服务端判定解锁的犬种：key → 第一次解锁的日期
  Map<String, String> _serverUnlocks = {};

  /// 手机上判定解锁的犬种（iOS 的传说「狼」、稀有「金毛寻回犬」）：key → 第一次解锁的日期
  Map<String, String> _localUnlocks = {};
  List<String> _newlyUnlocked = [];

  /// 解锁了的进化形态 → 第一次解锁的日期（只在手机上，见 evolution.dart）
  Map<Evolution, String> _evolutions = {};

  /// 自己挑的进化形态（名字或“不穿”）；没挑过是 null，穿最新解锁的
  String? _evolutionWorn;

  bool get isLoggedIn => _token != null;
  bool get onboarded => _onboarded;
  int get goalMinutes => _goalMinutes;
  GoalTier get goalTier => GoalTier.nearest(_goalMinutes);

  /// 没起过名字时为 null
  String? get nickname => _nickname;

  bool get reminderOn => _remindOn;

  /// 提醒时间，从 0 点算的分钟数
  int get reminderMinutes => _remindAt;

  /// “我的”页显示：开着时显示时间，关了显示“已关闭”
  String get reminderLabel => _remindOn ? formatHhmm(_remindAt) : '已关闭';
  bool get hasUsagePermission => _hasPermission;

  /// 已经解锁的犬种：服务端判定的，加上手机上判定的（iOS 的狼和金毛寻回犬）
  Set<String> get ownedBreeds => {..._serverUnlocks.keys, ..._localUnlocks.keys};

  /// 第一次解锁的日期（yyyy-MM-dd）；没解锁或不知道时为 null
  String? unlockedOn(String key) {
    final d = _serverUnlocks[key] ?? _localUnlocks[key];
    return d == null || d.isEmpty ? null : d;
  }

  /// 手机上记下的、变成过这种狗的日子，新的在前
  List<DayRecord> breedDays(String key) =>
      history.all().values.where((r) => r.breedKey == key).toList()..sort((a, b) => b.date.compareTo(a.date));

  /// 到今天为止连续做人几天：今天到现在还是人就算上今天。给图鉴里的「狼」看进度
  int get humanStreakNow {
    final before = humanStreakBefore(history.all(), DateTime.now());
    return hasUsageData && stage == 0 ? before + 1 : before;
  }

  /// 到昨天为止连续做人几天（今天还没过完不算）：进化形态按这个解锁
  int get humanStreakDone => humanStreakBefore(history.all(), DateTime.now());

  /// 解锁了的进化形态 → 第一次解锁的日期（yyyy-MM-dd）
  Map<Evolution, String> get evolutions => Map.unmodifiable(_evolutions);

  Set<Evolution> get unlockedEvolutions => _evolutions.keys.toSet();

  /// 做人时穿哪一种：自己挑过就穿挑的，挑了“不穿”是 null；没挑过穿最新解锁的（要连续做人最久的那种）
  Evolution? get wornEvolution {
    if (_evolutionWorn == _wearNone) return null;
    final chosen = Evolution.byName(_evolutionWorn);
    if (chosen != null && _evolutions.containsKey(chosen)) return chosen;
    for (final i in kEvolutions.reversed) {
      if (_evolutions.containsKey(i.evolution)) return i.evolution;
    }
    return null;
  }

  /// 挑做人时穿哪一种；null = 不穿。没解锁的不让穿
  Future<void> wearEvolution(Evolution? evolution) async {
    if (evolution != null && !_evolutions.containsKey(evolution)) return;
    _evolutionWorn = evolution?.name ?? _wearNone;
    await _prefs.setString(_kEvolutionWorn, _evolutionWorn!);
    notifyListeners();
  }

  Map<Evolution, String> _readEvolutions() {
    try {
      final raw = jsonDecode(_prefs.getString(_kEvolutions) ?? '{}') as Map<String, dynamic>;
      return {
        for (final e in raw.entries)
          if (Evolution.byName(e.key) case final evolution?) evolution: e.value as String,
      };
    } on FormatException {
      return {};
    }
  }

  /// 连续做人够了天数就解锁进化形态：记下日期，放进解锁弹窗的队列（和新犬种共用，在哪个页面都会弹）。
  /// 每次读完使用情况、记好每天的结果以后调；解锁了的不会再收回
  @visibleForTesting
  Future<void> checkEvolutions() async {
    final fresh = evolutionsFor(humanStreakDone).where((e) => !_evolutions.containsKey(e)).toList();
    if (fresh.isEmpty) return;
    final today = localDate();
    _evolutions = {..._evolutions, for (final e in fresh) e: today};
    await _prefs.setString(_kEvolutions, jsonEncode({for (final e in _evolutions.entries) e.key.name: e.value}));
    await receiveUnlocked([for (final e in fresh) evolutionInfo(e).unlockKey]);
    notifyListeners();
  }

  /// 打开图鉴时刷新一下服务端的解锁情况（登录了才有）
  Future<void> refreshBreeds() async {
    if (!isLoggedIn) return;
    try {
      _serverUnlocks = await api.breedUnlocks();
      notifyListeners();
    } on ApiException {
      // 网络失败就用上次的
    }
  }

  Map<String, String> _readLocalUnlocks() {
    try {
      return Map<String, String>.from(jsonDecode(_prefs.getString(_kLocalUnlocks) ?? '{}') as Map);
    } on FormatException {
      return {};
    }
  }

  /// iOS：使用数据不能传出手机（苹果开发者协议 3.3.3(P)），服务端判定不了，就在手机上按同样的规则判：
  /// - 传说「狼」：连续 7 天做人，今天到现在还是人也算一天
  /// - 稀有「金毛寻回犬」：前 4 天每天到过的最高阶段一天比一天低，今天还是狗（见 [isRetrieverTrend]）
  /// - 节日限定（2026-11-27）：节日那几天变狗。今天的看现在，前几天的看记录（那天没打开 App，监控扩展也记着阶段）
  /// iOS 拿不到 App 类别、拿起次数和时段，按刷法定的犬种判定不了
  Future<void> _judgeLocalBreeds() async {
    if (!ScreenTimeChannel.isSupported || !hasUsageData) return;
    final today = localDate();
    final found = <String, String>{
      for (final r in history.all().values)
        if (festivalOf(r.breedKey) != null) r.breedKey!: r.date,
      if (humanStreakNow >= DogMeter.legendStreakDays) 'wolf': today,
      if (breedKey == 'retriever' || festivalOf(breedKey) != null) breedKey!: today,
    }..removeWhere((k, _) => ownedBreeds.contains(k));
    final unlocked = found.keys.toList();
    if (unlocked.isEmpty) return;
    _localUnlocks = {..._localUnlocks, ...found};
    await _prefs.setString(_kLocalUnlocks, jsonEncode(_localUnlocks));
    await receiveUnlocked(unlocked);
    notifyListeners();
  }

  /// 新解锁、还没给用户看过解锁动画的犬种。服务端只在第一次解锁时告诉一次，
  /// 所以先存在手机上，看过再删（App 被关掉也不会漏）
  List<String> get newlyUnlocked => List.unmodifiable(_newlyUnlocked);

  /// 上报每日结果后服务端说新解锁了哪些。和还没看过的合在一起存：
  /// 下一次上报会返回空列表，不能把还没弹的冲掉
  @visibleForTesting
  Future<void> receiveUnlocked(List<String> keys) async {
    if (keys.isEmpty) return;
    _newlyUnlocked = {..._newlyUnlocked, ...keys}.toList();
    await _prefs.setStringList(_kPendingUnlocks, _newlyUnlocked);
  }

  /// 解锁动画看过了
  Future<void> markUnlockSeen(String key) async {
    _newlyUnlocked = [for (final k in _newlyUnlocked) if (k != key) k];
    await _prefs.setStringList(_kPendingUnlocks, _newlyUnlocked);
    notifyListeners();
  }

  UsageSnapshot get usage => _usage ?? UsageSnapshot.unavailable;

  /// 拿到了今天的真实数据。没拿到时界面不显示狗度、时长，只引导去开权限
  bool get hasUsageData => usage.available;

  bool _usageChecked = false;

  /// 打开 App 后读过一次使用情况了（读到了真实数据，或者确认拿不到）
  bool get usageChecked => _usageChecked;
  int get minutesUsed => usage.totalMinutes;
  int get percent => DogMeter.percentFor(minutesUsed, _goalMinutes);
  int get stage => DogMeter.stageFor(percent);

  /// 今天是哪种狗（今天还是人时为 null）。iOS 拿不到分类和时段：除了看前几天的金毛寻回犬，都落到默认的柯基
  String? get breedKey =>
      judgeBreed(usage, _goalMinutes, before: daysBefore(history.all(), DateTime.now(), retrieverDays));

  /// iOS 屏幕使用时间的状态；安卓上、或者读不到时是 null
  ScreenTimeStatus? get screenTime => _screenTime;

  /// iOS：已经在按屏幕使用时间统计
  bool get screenTimeActive => _screenTime?.active ?? false;

  /// iOS：监控用的目标和每日目标不一样（验证页的测试目标还在用）
  bool get screenTimeGoalMismatch => screenTimeActive && _screenTime!.goalMinutes != _goalMinutes;

  /// 狗度的显示。iOS 只知道越过了哪个阈值：越过了显示“≥60%”，一个都没越过显示“<30%”
  String get percentLabel {
    // 还没拿到数据：大字号的“--”像两块黑条，用问号
    if (!hasUsageData) return '？';
    final first = _firstThreshold;
    if (first == null) return '$percent%';
    return minutesUsed > 0 ? '≥$percent%' : '<${DogMeter.percentFor(first, _goalMinutes)}%';
  }

  /// 今日已刷的显示。iOS 上是下限：“至少 1 小时 48 分”或“不到 54 分钟”
  String get minutesUsedLabel {
    if (!hasUsageData) return '--';
    final used = DogMeter.formatMinutes(minutesUsed);
    final first = _firstThreshold;
    if (first == null) return used;
    return minutesUsed > 0 ? '至少 $used' : '不到 ${DogMeter.formatMinutes(first)}';
  }

  /// iOS 监控的第一个阈值（分钟）；不是 iOS 的阶段数据时为 null
  int? get _firstThreshold {
    final t = _screenTime?.thresholds ?? const <int>[];
    return usage.stageOnly && t.isNotEmpty ? t.first : null;
  }

  static String localDate([DateTime? t]) {
    final d = t ?? DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String formatHhmm(int minutesOfDay) =>
      '${(minutesOfDay ~/ 60).toString().padLeft(2, '0')}:${(minutesOfDay % 60).toString().padLeft(2, '0')}';

  static int? parseHhmm(String? value) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value ?? '');
    if (m == null) return null;
    final h = int.parse(m[1]!);
    final min = int.parse(m[2]!);
    return h < 24 && min < 60 ? h * 60 + min : null;
  }

  /// 昵称不合规时返回给用户看的话，合规返回 null
  static String? nicknameError(String value) {
    final v = value.trim();
    if (v.isEmpty) return '名字不能是空的';
    if (v.runes.length > nicknameMaxLength) return '最多 $nicknameMaxLength 个字';
    return null;
  }

  // MARK: 拍照形象

  /// 用照片做形象的单独同意（人脸信息）的版本。说明有重要变化时加 1，大家重新同意一次
  static const faceConsentVersion = 1;

  /// 用照片做形象之前，要单独同意处理照片里的人脸信息（深度合成规定第十四条）
  /// 超时来电里狗版的你用哪个声音（CallVoice 的名字），只存在手机上；没选过是 null（用默认）
  String? get callVoiceName => _prefs.getString(_kCallVoice);

  Future<void> setCallVoiceName(String name) async {
    await _prefs.setString(_kCallVoice, name);
    notifyListeners();
  }

  bool get faceConsented => (_prefs.getInt(_kFaceConsent) ?? 0) >= faceConsentVersion;

  Future<void> acceptFaceConsent() async {
    await _prefs.setInt(_kFaceConsent, faceConsentVersion);
    notifyListeners();
  }

  ui.Image? _photoAvatar;
  Uint8List? _photoAvatarPng;
  int? _avatarRegenLeft;

  /// 挑的预设形象（2026-11-27：不做捏脸，预设几张捏好的脸给用户挑）；没挑过、或者换回了拍照形象是 null
  AvatarPreset? _avatarPreset;

  /// 正用着的拍照形象（平涂墨线贴纸）。没有拍照形象、或者换成了预设形象时是 null，各处用代码画的 [avatarPreset]
  ui.Image? get photoAvatar => _avatarPreset == null ? _photoAvatar : null;

  /// [photoAvatar] 的原图（PNG）。桌面小组件按它判断形象换没换、要不要重画形象图
  Uint8List? get photoAvatarPng => _avatarPreset == null ? _photoAvatarPng : null;

  /// 存在手机上的拍照形象：换成预设形象以后也还留着，形象页上能换回来
  ui.Image? get savedPhotoAvatar => _photoAvatar;

  /// 不用拍照形象时画哪张脸：挑过的那张，没挑过是原来的默认形象（呆毛）
  AvatarPreset get avatarPreset => _avatarPreset ?? AvatarPreset.fallback;

  /// 挑过预设形象（正用着）
  bool get usesPreset => _avatarPreset != null;

  /// 登录后服务端给的“还能换几次形象”；没登录、还没拉到时是 null
  int? get avatarRegenLeft => _avatarRegenLeft;

  /// App 启动时读出存在手机上的形象。登录了、上次没传上去的拍照形象，没告诉服务端换了哪张脸的，顺便补上
  Future<void> loadAvatar() async {
    Uint8List? png;
    try {
      png = await avatars.load();
    } catch (_) {
      png = null; // 读不到就先用代码画的形象
    }
    if (png != null) {
      try {
        _photoAvatar = await _decode(png);
        _photoAvatarPng = png;
        notifyListeners();
      } catch (_) {
        // 图坏了也先用代码画的形象，用户可以在“我的”里重新拍
      }
    }
    // 补传放到后台，不耽误 App 打开
    if (isLoggedIn) unawaited(_syncPendingAvatar());
  }

  /// 先补传拍照形象，再说换了哪张脸：服务端收到新的拍照形象会清掉预设形象，反过来就乱了
  Future<void> _syncPendingAvatar() async {
    if (_photoAvatarPng != null && (_prefs.getBool(_kAvatarPending) ?? false)) await _uploadPendingAvatar();
    if (_prefs.getBool(_kAvatarPresetPending) ?? false) await _pushAvatarPreset();
  }

  /// 换成预设形象 [preset]；传 null 是换回存在手机上的拍照形象。
  /// 登录了就告诉服务端（群里的人看到的也跟着换）；没登录、没网时先记在手机上，登录后、下次打开 App 时补上
  Future<void> setAvatarPreset(AvatarPreset? preset) async {
    assert(preset != null || _photoAvatar != null, '手机上没有拍照形象，换不回去');
    _avatarPreset = preset;
    if (preset == null) {
      await _prefs.remove(_kAvatarPreset);
    } else {
      await _prefs.setString(_kAvatarPreset, preset.name);
    }
    await _prefs.setBool(_kAvatarPresetPending, true);
    notifyListeners();
    await _pushAvatarPreset();
  }

  Future<void> _pushAvatarPreset() async {
    if (!isLoggedIn) return;
    try {
      await api.updateSettings({'avatar_preset': _avatarPreset?.name});
      await _prefs.setBool(_kAvatarPresetPending, false);
    } on ApiException {
      // 没网就等下次
    }
  }

  static Future<ui.Image> _decode(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  /// 换成新的拍照形象（平涂墨线贴纸的 PNG，不是照片）。
  /// 登录了就先传服务端：服务端不收（比如换形象的次数用完了）时抛 [ApiException]，手机上的形象不变；
  /// 没网时先存在手机上，下次打开 App 或登录时补传。
  Future<void> setPhotoAvatar(Uint8List png) async {
    final image = await _decode(png);
    var pending = true;
    if (isLoggedIn) {
      try {
        await _uploadAvatar(png);
        pending = false;
      } on ApiException catch (e) {
        if (e.statusCode == 422) rethrow;
      }
    }
    await avatars.save(png);
    await _prefs.setBool(_kAvatarPending, pending);
    // 做了新的拍照形象就用它：服务端收到新形象时也会把预设形象清掉
    _avatarPreset = null;
    await _prefs.remove(_kAvatarPreset);
    await _prefs.setBool(_kAvatarPresetPending, false);
    _photoAvatar = image;
    _photoAvatarPng = png;
    notifyListeners();
  }

  Future<void> _uploadAvatar(Uint8List png) async {
    final me = await api.uploadAvatar(png);
    _avatarRegenLeft = (me['avatar_regen_left'] as num?)?.toInt();
  }

  Future<void> _uploadPendingAvatar() async {
    final png = _photoAvatarPng;
    if (png == null) return;
    try {
      await _uploadAvatar(png);
      await _prefs.setBool(_kAvatarPending, false);
      notifyListeners();
    } on ApiException catch (e) {
      // 服务端不收就不再补传，手机上的形象照用；没网就等下次
      if (e.statusCode == 422) await _prefs.setBool(_kAvatarPending, false);
    }
  }

  /// 把卡通形象一次性导出给“什么鬼天气”，返回导出码（8 位，10 分钟内有效，只能用一次）。
  /// 要先登录：天气 App 是从服务端取图的。手机上的形象还没传上去的先补传，传不上去时抛 [ApiException]
  Future<({String code, DateTime expiresAt})> exportAvatar() async {
    final png = _photoAvatarPng;
    if (png != null && (_prefs.getBool(_kAvatarPending) ?? false)) {
      await _uploadAvatar(png);
      await _prefs.setBool(_kAvatarPending, false);
    }
    return api.exportAvatar();
  }

  /// 登录后对一下形象：手机上有没传上去的就补传；手机上没有、服务端有（比如换了手机），就下载回来。
  /// 预设形象也一样：没登录时在这台手机上挑过的传上去，没挑过的用服务端记着的那张
  Future<void> _syncAvatar(Map<String, dynamic> me) async {
    _avatarRegenLeft = (me['avatar_regen_left'] as num?)?.toInt();
    // 没传上去的拍照形象是这台手机上新做的，传上去以后服务端会清掉它记着的预设形象
    final photoPending = _photoAvatarPng != null && (_prefs.getBool(_kAvatarPending) ?? false);
    if (_photoAvatarPng != null) {
      if (photoPending) await _uploadPendingAvatar();
    } else {
      await _downloadAvatar(me['avatar_url'] as String?);
    }
    if (_prefs.getBool(_kAvatarPresetPending) ?? false) {
      await _pushAvatarPreset();
    } else if (!photoPending) {
      final remote = AvatarPreset.byName(me['avatar_preset'] as String?);
      _avatarPreset = remote;
      if (remote == null) {
        await _prefs.remove(_kAvatarPreset);
      } else {
        await _prefs.setString(_kAvatarPreset, remote.name);
      }
    }
  }

  Future<void> _downloadAvatar(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      final png = await api.downloadAvatar(url);
      final image = await _decode(png);
      await avatars.save(png);
      await _prefs.setBool(_kAvatarPending, false);
      _photoAvatar = image;
      _photoAvatarPng = png;
    } catch (_) {
      // 下载不下来就先用默认形象，下次登录再试
    }
  }

  Future<void> login(String phone, String code) async {
    final token = await api.smsLogin(phone, code);
    _token = token;
    api.token = token;
    await _prefs.setString(_kToken, token);
    notifyListeners();
    await _pullProfile();
  }

  /// 登录后对一下设置：服务端有昵称就用服务端的，没有就把本机起的名字传上去
  Future<void> _pullProfile() async {
    try {
      final me = await api.me();
      await _syncAvatar(me);
      notifyListeners();
      final remote = (me['nickname'] as String?)?.trim() ?? '';
      if (remote.isNotEmpty) {
        _nickname = remote;
        await _prefs.setString(_kNickname, remote);
        notifyListeners();
      } else if (_nickname != null) {
        await api.updateSettings({'nickname': _nickname});
      }
      if (_remindOn) await api.updateSettings({'remind_at': formatHhmm(_remindAt)});
    } on ApiException {
      // 拉不到就先用本机的，下次改设置时再同步
    }
  }

  /// 登录了就把设置同步到服务端；离线时先存本地，下次改的时候再同步
  Future<void> _pushSettings(Map<String, dynamic> settings) async {
    if (!isLoggedIn) return;
    try {
      await api.updateSettings(settings);
    } on ApiException {
      // 忽略
    }
  }

  /// 改昵称。先用 [nicknameError] 校验
  Future<void> setNickname(String value) async {
    assert(nicknameError(value) == null);
    final v = value.trim();
    _nickname = v;
    await _prefs.setString(_kNickname, v);
    notifyListeners();
    await _pushSettings({'nickname': v});
  }

  /// 打开每晚提醒，或者换个时间。先要通知权限，用户不允许就保持关闭；返回最后是否开着。
  Future<bool> enableReminder([int? minutesOfDay]) async {
    final at = minutesOfDay ?? _remindAt;
    var ok = false;
    try {
      ok = await reminders.requestPermission();
      if (ok) await reminders.scheduleDaily(at);
    } catch (_) {
      ok = false;
    }
    _remindOn = ok;
    if (ok) _remindAt = at;
    await _prefs.setBool(_kRemindOn, ok);
    await _prefs.setString(_kRemindAt, formatHhmm(_remindAt));
    notifyListeners();
    if (ok) await _pushSettings({'remind_at': formatHhmm(at)});
    return ok;
  }

  Future<void> disableReminder() async {
    try {
      await reminders.cancel();
    } catch (_) {
      // 插件出错也当作已关闭
    }
    _remindOn = false;
    await _prefs.setBool(_kRemindOn, false);
    notifyListeners();
  }

  /// App 启动后调用：登记“点了提醒就打开结算卡”；提醒开着就重排一次，换了时区也能对上。
  /// 返回这次 App 是不是被提醒点开的。
  Future<bool> startReminders(VoidCallback openCard) async {
    final launched = await reminders.handleOpen(openCard);
    if (_remindOn) {
      try {
        await reminders.scheduleDaily(_remindAt);
      } catch (_) {
        // 排不上就等用户在“我的”里重新打开
      }
    }
    return launched;
  }

  Future<void> setGoalTier(GoalTier tier) async {
    final minutes = tier.minutes;
    _goalMinutes = minutes;
    await _prefs.setInt(_kGoal, minutes);
    notifyListeners();
    // 按狗度来电的限时跟着目标走（安卓交给原生层；iOS 下面重新统计时一起改）
    try {
      await LockService.platform?.syncGoal(minutes);
    } on PlatformException {
      // 原生层没收到，下次保存限时时会再交一次
    }
    if (screenTimeActive) {
      // iOS 的阈值跟着目标走，换了目标要按新阈值重新统计
      try {
        await restartScreenTime();
      } on PlatformException {
        // 没重启成功时，“今天”页会提示目标不一致，可以再点一次
      }
    }
    await _pushSettings({'daily_goal_minutes': minutes});
  }

  Future<void> completeOnboarding() async {
    _onboarded = true;
    await _prefs.setBool(_kOnboarded, true);
    notifyListeners();
  }

  /// 读取当天使用情况，并把分数（只有分数）同步到服务端
  Future<void> refreshUsage() async {
    if (ScreenTimeChannel.isSupported) {
      _screenTime = await _readScreenTime();
      _usage = screenTimeActive ? _screenTime!.toUsage() : null;
      _usageChecked = true;
      notifyListeners();
      await _recordToday();
      await _backfillHistory();
      await _judgeLocalBreeds();
      await checkEvolutions();
      // iOS 的阶段数据先只在手机上用、不上传：苹果开发者协议 3.3.3(P) 不允许把使用数据传出设备，
      // iOS 怎么上报还没定
      return;
    }
    _hasPermission = await UsageChannel.hasPermission();
    _usage = _hasPermission ? await UsageChannel.todayUsage() : null;
    _usageChecked = true;
    notifyListeners();
    await _recordToday();
    await _backfillHistory();
    await checkEvolutions();
    await _sync();
  }

  /// 安卓能补多少天：系统一般只留 7–10 天的明细
  static const backfillDays = 10;

  /// 今天已经补过历史了（每次打开 App 只补一次）
  String? _backfilledOn;

  /// 历史里补上前几天的真实数据，没打开 App 的日子也有：安卓从系统读每天的汇总，
  /// iOS 用监控扩展记下的每天最高阶段。已经有记录的日子（打开 App 时记的，可能只记到半天），换成更完整的那份。
  Future<void> _backfillHistory() async {
    final today = localDate();
    if (_backfilledOn == today) return;
    final List<DayRecord> filled;
    if (ScreenTimeChannel.isSupported) {
      final s = _screenTime;
      if (s == null || !s.authorized) return;
      filled = [
        for (final MapEntry(key: date, value: stage) in s.history.entries)
          if (date != today && (history.day(date)?.stage ?? -1) < stage) _stageRecord(date, stage, s.thresholds),
      ];
    } else {
      if (!_hasPermission) return;
      // 从早到晚补：判金毛寻回犬要看那天之前几天的记录，前面补上的要算进去
      final days = [...await UsageChannel.pastDays(backfillDays)]..sort((a, b) => a.date.compareTo(b.date));
      final records = history.all();
      filled = [];
      for (final d in days) {
        if (d.date == today || !_isMoreComplete(records[d.date], d.usage)) continue;
        final r = _minutesRecord(d.date, d.usage, records);
        records[d.date] = r;
        filled.add(r);
      }
    }
    _backfilledOn = today;
    if (filled.isEmpty) return;
    await history.putAll(filled);
    // 前几天补完整了，今天的犬种（金毛寻回犬看前几天）可能跟着变
    await _recordToday();
    notifyListeners();
    await _syncBackfilled(filled);
  }

  bool _isMoreComplete(DayRecord? old, UsageSnapshot full) => old == null || old.stageOnly || full.totalMinutes > old.minutes;

  /// 安卓：一整天的分钟数。目标用那天记录里的（没记录用现在的）；[records] 是到这天为止的历史，判金毛寻回犬用
  DayRecord _minutesRecord(String date, UsageSnapshot usage, Map<String, DayRecord> records) {
    final goal = records[date]?.goalMinutes ?? _goalMinutes;
    final pct = DogMeter.percentFor(usage.totalMinutes, goal);
    return DayRecord(
      date: date,
      goalMinutes: goal,
      minutes: usage.totalMinutes,
      percent: pct,
      percentLabel: '$pct%',
      stage: DogMeter.stageFor(pct),
      breedKey: judgeBreed(usage, goal, before: daysBefore(records, DateTime.parse(date), retrieverDays), day: DateTime.parse(date)),
    );
  }

  /// iOS：只知道那天到了第几阶段。分钟数取那个阶段的阈值（下限）；犬种只判得了节日限定的（只看日期和阶段），别的不记
  DayRecord _stageRecord(String date, int stage, List<int> thresholds) {
    final pct = stage == 0 ? 0 : DogMeter.stageThresholds[stage - 1];
    final minutes = stage > 0 && stage <= thresholds.length ? thresholds[stage - 1] : 0;
    return DayRecord(
      date: date,
      goalMinutes: _goalMinutes,
      minutes: minutes,
      percent: pct,
      percentLabel: stage == 0 ? '<${DogMeter.humanBelow}%' : '≥$pct%',
      stage: stage,
      stageOnly: true,
      breedKey: stage > 0 ? festivalOn(DateTime.parse(date))?.breedKey : null,
    );
  }

  /// 登录了的话，补上的日子也报给服务端（安卓；服务端只收今天和前两天），图鉴和传说犬种才算得准
  Future<void> _syncBackfilled(List<DayRecord> filled) async {
    if (!isLoggedIn || ScreenTimeChannel.isSupported) return;
    final earliest = localDate(DateTime.now().subtract(const Duration(days: 2)));
    for (final r in filled) {
      if (r.date.compareTo(earliest) < 0 || r.stageOnly) continue;
      try {
        await receiveUnlocked(await api.putDailyRecord(
          date: r.date,
          dogPercent: r.percent,
          minutesUsed: r.minutes,
          breedKey: r.breedKey,
        ));
      } on ApiException {
        // 补报失败不影响本地
      }
    }
  }

  /// 把今天的结果记进历史，同一天只留最后一次。拿不到真实数据时不记
  Future<void> _recordToday() async {
    if (!usage.available) return;
    await history.put(DayRecord(
      date: localDate(),
      goalMinutes: _goalMinutes,
      minutes: minutesUsed,
      percent: percent,
      percentLabel: percentLabel,
      stage: stage,
      breedKey: breedKey,
      stageOnly: usage.stageOnly,
    ));
  }

  Future<ScreenTimeStatus?> _readScreenTime() async {
    try {
      return await ScreenTimeChannel.status();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// iOS：授权 → 选 App → 按每日目标开始统计。用户在哪一步取消，就停在哪一步；出错时抛 PlatformException。
  Future<void> enableScreenTime() async {
    var s = await ScreenTimeChannel.status();
    if (!s.authorized) s = await ScreenTimeChannel.requestAuthorization();
    if (s.authorized && !s.hasSelection) s = await ScreenTimeChannel.pickActivities();
    if (s.authorized && s.hasSelection) await ScreenTimeChannel.startMonitoring(_goalMinutes);
    await refreshUsage();
  }

  /// iOS：按当前的每日目标重新开始统计
  Future<void> restartScreenTime() async {
    await ScreenTimeChannel.startMonitoring(_goalMinutes);
    await refreshUsage();
  }

  Future<void> _sync() async {
    if (!isLoggedIn || !usage.available) return;
    try {
      final unlocked = await api.putDailyRecord(
        date: localDate(),
        dogPercent: percent,
        minutesUsed: minutesUsed,
        breedKey: breedKey,
      );
      await receiveUnlocked(unlocked);
      _serverUnlocks = await api.breedUnlocks();
      notifyListeners();
    } on ApiException {
      // 网络失败不影响本地展示
    }
  }

  /// 测试用：直接给一份今天的使用数据（真机上只来自系统）
  @visibleForTesting
  void debugSetUsage(UsageSnapshot usage) {
    _usage = usage;
    _usageChecked = true;
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
    _goalMinutes = GoalTier.normal.minutes;
    _serverUnlocks = {};
    _localUnlocks = {};
    _newlyUnlocked = [];
    _evolutions = {};
    _evolutionWorn = null;
    _nickname = null;
    // 形象是账号的：退出或注销后从手机上删掉（服务端的跟着账号走，注销时一起删）
    try {
      await avatars.delete();
    } catch (_) {
      // 删不掉也不影响退出
    }
    _photoAvatar = null;
    _photoAvatarPng = null;
    _avatarRegenLeft = null;
    _avatarPreset = null;
    // 退出后不该再收到提醒
    if (_remindOn) await disableReminder();
    _remindAt = defaultRemindAt;
    // 同意隐私政策、同意用照片做形象是这台手机上的事，退出或注销后不用再问一遍
    final faceConsent = faceConsented;
    await _prefs.clear();
    history.forget();
    if (_privacyAccepted) await _prefs.setInt(_kPrivacyVersion, privacyVersion);
    if (faceConsent) await _prefs.setInt(_kFaceConsent, faceConsentVersion);
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// 外面可能没有 AppScope 时用（单独测某个页面）
  static AppState? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()?.notifier;

  /// 只读取、不订阅变化（在回调里用）
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
