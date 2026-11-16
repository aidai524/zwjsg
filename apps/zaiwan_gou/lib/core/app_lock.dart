import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/locks/app_picker_page.dart';
import '../features/locks/lock_selection_view.dart';
import 'screen_time_channel.dart';
import 'usage_channel.dart';

/// 一个 App 时间锁：这些 App 每天合计用满 [minutes] 分钟，就锁到第二天 0 点。
/// 锁只存在手机上，不上传。
class AppLock {
  const AppLock({
    required this.id,
    required this.minutes,
    this.packages = const [],
    this.labels = const [],
    this.apps = 0,
    this.categories = 0,
    this.webDomains = 0,
    this.usedMinutes,
    this.locked = false,
    this.graceLeft = 0,
    this.graceActive = false,
  });

  factory AppLock.fromMap(Map<dynamic, dynamic> m) {
    int number(String key) => (m[key] as num? ?? 0).toInt();
    List<String> strings(String key) => [for (final v in m[key] as List? ?? const []) v.toString()];
    return AppLock(
      id: m['id'] as String,
      minutes: number('minutes'),
      packages: strings('packages'),
      labels: strings('labels'),
      apps: number('apps'),
      categories: number('categories'),
      webDomains: number('webDomains'),
      usedMinutes: (m['usedMinutes'] as num?)?.toInt(),
      locked: m['locked'] as bool? ?? false,
      graceLeft: number('graceLeft'),
      graceActive: m['graceActive'] as bool? ?? false,
    );
  }

  final String id;
  final int minutes;

  /// 安卓：锁住的 App 包名和名称（只在手机上显示）
  final List<String> packages;
  final List<String> labels;

  /// iOS：系统只告诉 App 选了几个
  final int apps;
  final int categories;
  final int webDomains;

  /// 安卓：今天已经用了多久；iOS 拿不到
  final int? usedMinutes;

  /// 今天已经用满、锁上了
  final bool locked;

  /// 今天还能紧急解锁几次
  final int graceLeft;

  /// 正在紧急解锁的那几分钟里
  final bool graceActive;

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

/// 新建或修改时间锁时的草稿
class LockDraft {
  LockDraft({this.id, this.minutes = 30, this.packages = const [], this.labels = const []});

  LockDraft.of(AppLock lock)
      : id = lock.id,
        minutes = lock.minutes,
        packages = lock.packages,
        labels = lock.labels,
        apps = lock.apps,
        categories = lock.categories,
        webDomains = lock.webDomains;

  /// null 表示新建
  final String? id;
  int minutes;

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

/// 时间锁的平台实现：安卓用无障碍服务拦，iOS 用系统的屏幕使用时间屏蔽。抽成接口，测试里换成假的。
abstract class LockService {
  /// 当前平台的实现；其他平台为 null
  static LockService? get platform {
    if (Platform.isAndroid) return AndroidLockService();
    if (Platform.isIOS) return IosLockService();
    return null;
  }

  /// 最多几个锁，和原生层一致
  static const maxLocks = 10;

  /// 紧急解锁每次再用几分钟（原生层 LockStore.GRACE_MINUTES / ScreenTimeStore.graceMinutes 说了算，这里只用来显示）
  static const graceMinutes = 5;

  /// 紧急解锁：再用 [graceMinutes] 分钟，用满自动再锁上。每天次数有限
  Future<List<AppLock>> grantGrace(String id);

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

  /// 选中项的图标和名字。iOS 的令牌是不透明的，只能让系统画；安卓直接显示名称，不需要
  Widget? selectionPreview({String? lockId, bool draft = false}) => null;

  /// 选 App 之前的说明
  String? get pickHint => null;

  /// 编辑页底部说明怎么算
  String get limitNote => '选中的 App 合计用满这么久，就锁到第二天 0 点。';
}

List<AppLock> _locks(List<dynamic>? list) => [for (final m in list ?? const []) AppLock.fromMap(m as Map)];

class AndroidLockService extends LockService {
  static const _channel = MethodChannel('zwjsg/locks');

  @override
  Future<bool> ready() async => await _channel.invokeMethod<bool>('isServiceEnabled') ?? false;

  @override
  Future<void> setup() => _channel.invokeMethod<void>('openServiceSettings');

  @override
  String get setupTitle => '还差一步：打开“无障碍”里的时间锁';

  @override
  String get setupBody => '在系统“设置 › 无障碍”（有的手机在“更多设置”或“已下载的应用”里）找到“再玩我是狗 · App 时间锁”并打开。'
      '它只用来发现被锁的 App 被打开，不读屏幕内容。小米、华为等手机还要允许本 App 自启动，不然可能被系统关掉。';

  @override
  String get setupAction => '去打开';

  @override
  String get limitNote => '选中的 App 合计用满这么久，就锁到第二天 0 点。今天已经用掉的也算，已经超了的话，下次打开就会被拦住。';

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
      }));

  @override
  Future<List<AppLock>> delete(String id) async =>
      _locks(await _channel.invokeMethod<List<dynamic>>('deleteLock', {'id': id}));

  @override
  Future<List<AppLock>> grantGrace(String id) async =>
      _locks(await _channel.invokeMethod<List<dynamic>>('grantGrace', {'id': id}));
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
  String get setupBody => 'iOS 用系统的屏幕使用时间来锁 App：用满额度后系统会直接挡住，第二天 0 点自动解开。';

  @override
  String get setupAction => '去授权';

  @override
  String? get pickHint => '系统的选择页先按类别列出 App：点类别名称展开，就能只勾某一个 App；直接勾类别前面的圆圈，会锁住这一类的所有 App。';

  @override
  String get limitNote => '选中的 App 合计用满这么久，系统就会挡住它们，第二天 0 点自动解开。';

  @override
  Widget? selectionPreview({String? lockId, bool draft = false}) => LockSelectionView(lockId: lockId, draft: draft);

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
  Future<List<AppLock>> save(LockDraft draft) async =>
      _locks(await _channel.invokeMethod<List<dynamic>>('saveLock', {'id': draft.id, 'minutes': draft.minutes}));

  @override
  Future<List<AppLock>> delete(String id) async =>
      _locks(await _channel.invokeMethod<List<dynamic>>('deleteLock', {'id': id}));

  @override
  Future<void> discardDraft() => _channel.invokeMethod<void>('discardLockDraft');

  @override
  Future<List<AppLock>> grantGrace(String id) async =>
      _locks(await _channel.invokeMethod<List<dynamic>>('grantGrace', {'id': id}));
}
