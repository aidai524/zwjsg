import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'avatar_store.dart';
import 'breeds.dart';
import 'dog_meter.dart';
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
  static const privacyVersion = 3;

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
  static const _kPendingUnlocks = 'pending_unlocks';

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
  Set<String> _ownedBreeds = {};
  List<String> _newlyUnlocked = [];

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
  Set<String> get ownedBreeds => _ownedBreeds;

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

  /// iOS 拿不到分类和时段，judgeBreed 会落到默认的柯基
  String? get breedKey => judgeBreed(usage, _goalMinutes);

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
  bool get faceConsented => (_prefs.getInt(_kFaceConsent) ?? 0) >= faceConsentVersion;

  Future<void> acceptFaceConsent() async {
    await _prefs.setInt(_kFaceConsent, faceConsentVersion);
    notifyListeners();
  }

  ui.Image? _photoAvatar;
  Uint8List? _photoAvatarPng;
  int? _avatarRegenLeft;

  /// 拍照做的卡通形象（平涂墨线贴纸）；没有时各处用代码画的默认形象
  ui.Image? get photoAvatar => _photoAvatar;

  /// [photoAvatar] 的原图（PNG）。桌面小组件按它判断形象换没换、要不要重画形象图
  Uint8List? get photoAvatarPng => _photoAvatarPng;

  /// 登录后服务端给的“还能换几次形象”；没登录、还没拉到时是 null
  int? get avatarRegenLeft => _avatarRegenLeft;

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
      _photoAvatar = await _decode(png);
      _photoAvatarPng = png;
    } catch (_) {
      return; // 图坏了也先用默认形象，用户可以在“我的”里重新拍
    }
    notifyListeners();
    // 补传放到后台，不耽误 App 打开
    if (isLoggedIn && (_prefs.getBool(_kAvatarPending) ?? false)) unawaited(_uploadPendingAvatar());
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

  /// 登录后对一下形象：手机上有没传上去的就补传；手机上没有、服务端有（比如换了手机），就下载回来
  Future<void> _syncAvatar(Map<String, dynamic> me) async {
    _avatarRegenLeft = (me['avatar_regen_left'] as num?)?.toInt();
    if (_photoAvatarPng != null) {
      if (_prefs.getBool(_kAvatarPending) ?? false) await _uploadPendingAvatar();
      return;
    }
    final url = me['avatar_url'] as String?;
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
      filled = [
        for (final d in await UsageChannel.pastDays(backfillDays))
          if (d.date != today && _isMoreComplete(history.day(d.date), d.usage)) _minutesRecord(d.date, d.usage),
      ];
    }
    _backfilledOn = today;
    if (filled.isEmpty) return;
    await history.putAll(filled);
    notifyListeners();
    await _syncBackfilled(filled);
  }

  bool _isMoreComplete(DayRecord? old, UsageSnapshot full) => old == null || old.stageOnly || full.totalMinutes > old.minutes;

  /// 安卓：一整天的分钟数。目标用那天记录里的（没记录用现在的）
  DayRecord _minutesRecord(String date, UsageSnapshot usage) {
    final goal = history.day(date)?.goalMinutes ?? _goalMinutes;
    final pct = DogMeter.percentFor(usage.totalMinutes, goal);
    return DayRecord(
      date: date,
      goalMinutes: goal,
      minutes: usage.totalMinutes,
      percent: pct,
      percentLabel: '$pct%',
      stage: DogMeter.stageFor(pct),
      breedKey: judgeBreed(usage, goal),
    );
  }

  /// iOS：只知道那天到了第几阶段。分钟数取那个阶段的阈值（下限）；犬种判断不了，不记
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
      _ownedBreeds = await api.ownedBreeds();
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
    _ownedBreeds = {};
    _newlyUnlocked = [];
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
    // 退出后不该再收到提醒
    if (_remindOn) await disableReminder();
    _remindAt = defaultRemindAt;
    // 同意隐私政策、同意用照片做形象是这台手机上的事，退出或注销后不用再问一遍
    final faceConsent = faceConsented;
    await _prefs.clear();
    if (_privacyAccepted) await _prefs.setInt(_kPrivacyVersion, privacyVersion);
    if (faceConsent) await _prefs.setInt(_kFaceConsent, faceConsentVersion);
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// 只读取、不订阅变化（在回调里用）
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
