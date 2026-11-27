import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/locks/app_picker_page.dart';
import '../features/locks/lock_selection_view.dart';
import 'dog_meter.dart';
import 'screen_time_channel.dart';
import 'usage_channel.dart';

/// 一个单个 App 限时（超时来电）：这些 App 每天合计用满 [minutes] 分钟，狗版的你就打“电话”来问还玩不玩；
/// 或者按狗度来（[dogPercent]，2026-11-27）：今天狗度到了这么多，再打开这些 App 就来电。
/// 接了电话、学两声狗叫就能再玩 10 分钟，到点再来电；拒接就今天锁死，明天 0 点解开（2026-11-23 起）。
/// 限时只存在手机上，不上传。
class AppLock {
  const AppLock({
    required this.id,
    required this.minutes,
    this.dogPercent,
    this.packages = const [],
    this.labels = const [],
    this.apps = 0,
    this.categories = 0,
    this.webDomains = 0,
    this.usedMinutes,
    this.locked = false,
    this.graceActive = false,
    this.declined = false,
  });

  factory AppLock.fromMap(Map<dynamic, dynamic> m) {
    int number(String key) => (m[key] as num? ?? 0).toInt();
    List<String> strings(String key) => [for (final v in m[key] as List? ?? const []) v.toString()];
    return AppLock(
      id: m['id'] as String,
      minutes: number('minutes'),
      dogPercent: (m['dogPercent'] as num?)?.toInt(),
      packages: strings('packages'),
      labels: strings('labels'),
      apps: number('apps'),
      categories: number('categories'),
      webDomains: number('webDomains'),
      usedMinutes: (m['usedMinutes'] as num?)?.toInt(),
      locked: m['locked'] as bool? ?? false,
      graceActive: m['graceActive'] as bool? ?? false,
      declined: m['declined'] as bool? ?? false,
    );
  }

  final String id;

  /// 按额度：这些 App 每天合计最多用多少分钟（按狗度来的限时不看它）
  final int minutes;

  /// 按狗度来：今天狗度到这么多（%）以后，打开这些 App 就来电；按额度的是 null
  final int? dogPercent;

  bool get byDog => dogPercent != null;

  /// 什么时候来电：“每天 30 分钟”“狗度到 100% 后”
  String get rule => dogPercent != null ? '狗度到 $dogPercent% 后' : '每天 ${DogMeter.formatMinutes(minutes)}';

  /// 安卓：锁住的 App 包名和名称（只在手机上显示）
  final List<String> packages;
  final List<String> labels;

  /// iOS：系统只告诉 App 选了几个
  final int apps;
  final int categories;
  final int webDomains;

  /// 安卓：今天已经用了多久；iOS 拿不到
  final int? usedMinutes;

  /// 今天已经用满：每次打开都会来电
  final bool locked;

  /// 学了狗叫放行的那 10 分钟里
  final bool graceActive;

  /// 今天拒接了来电：锁死到明天 0 点
  final bool declined;

  String get title => labels.isNotEmpty ? labels.join('、') : describeSelection(apps, categories, webDomains);
}

String describeSelection(int apps, int categories, int webDomains) {
  final parts = [
    if (apps > 0) '$apps 个 App',
    if (categories > 0) '$categories 个类别',
    if (webDomains > 0) '$webDomains 个网站',
  ];
  return parts.isEmpty ? '还没选 App' : parts.join('、');
}

/// 新建或修改限时时的草稿
class LockDraft {
  LockDraft({this.id, this.minutes = 30, this.dogPercent, this.packages = const [], this.labels = const []});

  LockDraft.of(AppLock lock)
      : id = lock.id,
        minutes = lock.minutes,
        dogPercent = lock.dogPercent,
        packages = lock.packages,
        labels = lock.labels,
        apps = lock.apps,
        categories = lock.categories,
        webDomains = lock.webDomains;

  /// null 表示新建
  final String? id;
  int minutes;

  /// 按狗度来（%）；按额度时是 null
  int? dogPercent;

  /// 安卓
  List<String> packages;
  List<String> labels;

  /// iOS
  int apps = 0;
  int categories = 0;
  int webDomains = 0;

  bool get hasApps => packages.isNotEmpty || apps + categories + webDomains > 0;

  String get summary => labels.isNotEmpty ? labels.join('、') : describeSelection(apps, categories, webDomains);
}

/// 超时来电的平台实现：安卓用无障碍服务发现超时、弹来电页，iOS 用系统的屏幕使用时间挡一下（屏蔽页做成来电的样子）。
/// 抽成接口，测试里换成假的。
abstract class LockService {
  /// 当前平台的实现；其他平台为 null
  static LockService? get platform {
    if (Platform.isAndroid) return AndroidLockService();
    if (Platform.isIOS) return IosLockService();
    return null;
  }

  /// 最多几个限时，和原生层一致
  static const maxLocks = 10;

  /// 每天额度能选的几档（分钟）
  static const presets = [15, 30, 45, 60, 90, 120, 180];

  /// 按狗度来电能选的几档（%，2026-11-27）；默认 100%：刷满了今天的目标
  static const dogPresets = [60, 90, 100, 120, 150];
  static const defaultDogPercent = 100;

  /// 接了电话能再玩几分钟，不限次数（原生层 LockStore.SNOOZE_MINUTES / ScreenTimeStore.snoozeMinutes 说了算，这里只用来显示）
  static const snoozeMinutes = 10;

  /// 拦截要的权限开了没有：安卓是无障碍服务，iOS 是屏幕使用时间授权
  Future<bool> ready();

  /// 去开权限
  Future<void> setup();

  String get setupTitle;
  String get setupBody;
  String get setupAction;

  Future<List<AppLock>> list();

  /// 选 App：改 [draft] 里的选择，用户取消时返回 false
  Future<bool> pickApps(BuildContext context, LockDraft draft);

  Future<List<AppLock>> save(LockDraft draft);

  Future<List<AppLock>> delete(String id);

  /// 编辑页没保存就关掉时调用
  Future<void> discardDraft() async {}

  /// 选中项的图标和名字。iOS 的令牌是不透明的，只能让系统画；安卓直接显示名称，不需要。[count] 是选了几个（定高度用）
  Widget? selectionPreview({String? lockId, bool draft = false, int count = 1}) => null;

  /// 选 App 之前的说明
  String? get pickHint => null;

  /// 从建议点进编辑页时，选额度的地方再列一遍建议（iOS 由报告扩展画；安卓的建议卡片能一键设好，不用）
  Widget? adviceReference() => null;

  /// 编辑页底部说明怎么算
  String get limitNote => '选中的 App 合计用满这么久，狗版的你就打电话来问你还玩不玩。';

  /// 来电以后怎么办（两端不一样），接在“什么时候来电”后面
  String get callTail => '狗版的你就打电话来问你还玩不玩。';

  /// 按狗度来电时，编辑页底部的说明。[goalMinutes] 是每天的目标
  String dogNote(int percent, int goalMinutes) {
    final at = DogMeter.formatMinutes((goalMinutes * percent / 100).round());
    return '今天狗度到 $percent%（按你的目标，就是今天一共刷了 $at）以后，再打开选中的 App，$callTail';
  }

  /// 每天的目标变了：按狗度来的限时要跟着变（安卓交给原生层；iOS 在重新开始统计狗度时一起改）
  Future<void> syncGoal(int goalMinutes) async {}
}

List<AppLock> _locks(List<dynamic>? list) => [for (final m in list ?? const []) AppLock.fromMap(m as Map)];

class AndroidLockService extends LockService {
  static const _channel = MethodChannel('zwjsg/locks');

  @override
  Future<bool> ready() async => await _channel.invokeMethod<bool>('isServiceEnabled') ?? false;

  @override
  Future<void> setup() => _channel.invokeMethod<void>('openServiceSettings');

  @override
  String get setupTitle => '还差一步：打开“无障碍”里的超时来电';

  @override
  String get setupBody => '在系统“设置 › 无障碍”（有的手机在“更多设置”或“已下载的应用”里）找到“再玩我是狗 · 超时来电”并打开。'
      '它只用来发现设了限时的 App 被打开、到点弹出来电，不读屏幕内容。小米、华为等手机还要允许本 App 自启动，不然可能被系统关掉。';

  @override
  String get setupAction => '去打开';

  @override
  String get limitNote => '选中的 App 合计用满这么久，$callTail今天已经用掉的也算，已经超了的话，下次打开就会来电。';

  @override
  String get callTail => '狗版的你就打电话来：接了学两声狗叫，能再玩 ${LockService.snoozeMinutes} 分钟，到点再打来；'
      '挂断就回桌面；拒接的话今天锁死，明天 0 点解开。';

  @override
  Future<void> syncGoal(int goalMinutes) => _channel.invokeMethod<void>('setGoal', {'goalMinutes': goalMinutes});

  @override
  Future<List<AppLock>> list() async => _locks(await _channel.invokeMethod<List<dynamic>>('listLocks'));

  /// 桌面上有图标的 App，今天用得多的在前
  Future<List<AppUsage>> launchableApps() async => [
        for (final m in await _channel.invokeMethod<List<dynamic>>('launchableApps') ?? const [])
          AppUsage.fromMap(m as Map),
      ];

  @override
  Future<bool> pickApps(BuildContext context, LockDraft draft) async {
    final picked = await Navigator.of(context).push<List<AppUsage>>(
      MaterialPageRoute(builder: (_) => AppPickerPage(loader: launchableApps, initial: draft.packages)),
    );
    if (picked == null) return false;
    draft
      ..packages = [for (final a in picked) a.package]
      ..labels = [for (final a in picked) a.label];
    return true;
  }

  @override
  Future<List<AppLock>> save(LockDraft draft) async => _locks(await _channel.invokeMethod<List<dynamic>>('saveLock', {
        'id': draft.id,
        'packages': draft.packages,
        'minutes': draft.minutes,
        'dogPercent': draft.dogPercent,
      }));

  @override
  Future<List<AppLock>> delete(String id) async =>
      _locks(await _channel.invokeMethod<List<dynamic>>('deleteLock', {'id': id}));

}

class IosLockService extends LockService {
  static const _channel = MethodChannel('zwjsg/screen_time');

  @override
  Future<bool> ready() async => (await ScreenTimeChannel.status()).authorized;

  @override
  Future<void> setup() => ScreenTimeChannel.requestAuthorization();

  @override
  String get setupTitle => '还差一步：授权“屏幕使用时间”';

  @override
  String get setupBody => 'iOS 用系统的屏幕使用时间：用满额度后系统会挡一下，同时狗版的你打来电话（一条响铃的通知）。'
      '接了学两声狗叫，能再玩 ${LockService.snoozeMinutes} 分钟；拒接的话今天锁死。';

  @override
  String get setupAction => '去授权';

  @override
  String? get pickHint => '系统的选择页先按类别列出 App：点类别名称展开，就能只勾某一个 App；直接勾类别前面的圆圈，这一类的所有 App 都算进去。';

  @override
  String get limitNote => '选中的 App 合计用满这么久，$callTail';

  @override
  String get callTail => '系统会挡一下，狗版的你打来电话：点“接听”回到这里学两声狗叫，'
      '能再玩 ${LockService.snoozeMinutes} 分钟，到点再挡；点“拒接”今天锁死，明天 0 点解开。';

  @override
  Widget? selectionPreview({String? lockId, bool draft = false, int count = 1}) =>
      LockSelectionView(lockId: lockId, draft: draft, count: count);

  /// 报告扩展画的精简版建议（只有几行“App + 建议每天多久”），高度和 ScreenTimeReport.swift 的 LimitAdviceView 精简版一致，
  /// 看的天数和建议卡片（LockAdviceCard.days）一样是 7 天
  @override
  Widget? adviceReference() => const SizedBox(
        height: 126,
        child: UiKitView(
          viewType: 'zwjsg/screen_time_report',
          creationParams: {'advice': true, 'compact': true, 'days': 7},
          creationParamsCodec: StandardMessageCodec(),
        ),
      );

  @override
  Future<List<AppLock>> list() async => _locks(await _channel.invokeMethod<List<dynamic>>('listLocks'));

  @override
  Future<bool> pickApps(BuildContext context, LockDraft draft) async {
    final m = await _channel.invokeMethod<Map<dynamic, dynamic>>('pickLockApps', {'id': draft.id});
    if (m == null) return false;
    draft
      ..apps = (m['apps'] as num? ?? 0).toInt()
      ..categories = (m['categories'] as num? ?? 0).toInt()
      ..webDomains = (m['webDomains'] as num? ?? 0).toInt();
    return true;
  }

  @override
  Future<List<AppLock>> save(LockDraft draft) async => _locks(await _channel.invokeMethod<List<dynamic>>(
      'saveLock', {'id': draft.id, 'minutes': draft.minutes, 'dogPercent': draft.dogPercent}));

  @override
  Future<List<AppLock>> delete(String id) async =>
      _locks(await _channel.invokeMethod<List<dynamic>>('deleteLock', {'id': id}));

  @override
  Future<void> discardDraft() => _channel.invokeMethod<void>('discardLockDraft');
}
