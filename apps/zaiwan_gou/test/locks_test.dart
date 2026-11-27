import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zwjsg_app/core/app_groups.dart';
import 'package:zwjsg_app/core/app_lock.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/core/usage_channel.dart';
import 'package:zwjsg_app/features/locks/app_picker_page.dart';
import 'package:zwjsg_app/features/locks/lock_editor_page.dart';
import 'package:zwjsg_app/features/locks/lock_selection_view.dart';
import 'package:zwjsg_app/features/locks/locks_page.dart';
import 'package:zwjsg_app/features/today/today_cards.dart';

class FakeLockService extends LockService {
  FakeLockService({this.isReady = true, List<AppLock>? locks}) : locks = locks ?? [];

  bool isReady;
  int setups = 0;
  int discards = 0;
  final List<AppLock> locks;

  /// 交给原生层的每天目标
  final goals = <int>[];

  @override
  Future<void> syncGoal(int goalMinutes) async => goals.add(goalMinutes);

  @override
  Future<bool> ready() async => isReady;

  @override
  Future<void> setup() async {
    setups++;
    isReady = true;
  }

  @override
  String get setupTitle => '还差一步：打开权限';

  @override
  String get setupBody => '测试用的说明';

  @override
  String get setupAction => '去打开';

  @override
  Future<List<AppLock>> list() async => List.of(locks);

  @override
  Future<bool> pickApps(BuildContext context, LockDraft draft) async {
    draft
      ..packages = ['com.example.video']
      ..labels = ['某短视频'];
    return true;
  }

  @override
  Future<List<AppLock>> save(LockDraft draft) async {
    final lock = AppLock(
      id: draft.id ?? 'lock${locks.length + 1}',
      minutes: draft.minutes,
      dogPercent: draft.dogPercent,
      packages: draft.packages,
      labels: draft.labels,
      usedMinutes: 10,
    );
    locks
      ..removeWhere((l) => l.id == lock.id)
      ..add(lock);
    return list();
  }

  @override
  Future<List<AppLock>> delete(String id) async {
    locks.removeWhere((l) => l.id == id);
    return list();
  }

  @override
  Future<void> discardDraft() async => discards++;
}

/// 像 iOS：系统选择页只告诉数量，可能整类选中
class FakeIosLockService extends FakeLockService {
  @override
  String? get pickHint => '点类别名称展开，就能只勾某一个 App';

  @override
  Future<bool> pickApps(BuildContext context, LockDraft draft) async {
    draft.categories = 1;
    return true;
  }
}

Future<void> pumpLocks(WidgetTester tester, FakeLockService service) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: LocksPage(service: service)));
  await tester.pumpAndSettle();
}

void main() {
  test('iOS 的锁只有数量，标题按数量写', () {
    final lock = AppLock.fromMap({'id': 'a', 'minutes': 30, 'apps': 2, 'categories': 1, 'locked': true});
    expect(lock.title, '2 个 App、1 个类别');
    expect(lock.locked, isTrue);
    expect(lock.usedMinutes, isNull);
  });

  testWidgets('没开权限时先引导去开，开了才能加锁', (tester) async {
    final service = FakeLockService(isReady: false);
    await pumpLocks(tester, service);

    expect(find.text('还差一步：打开权限'), findsOneWidget);
    await tester.tap(find.text('去打开'));
    await tester.pumpAndSettle();

    expect(service.setups, 1);
    expect(find.text('还差一步：打开权限'), findsNothing);
    expect(find.text('还没设限时'), findsOneWidget);
  });

  testWidgets('新建限时：选 App、选额度，保存后出现在列表里', (tester) async {
    final service = FakeLockService();
    await pumpLocks(tester, service);

    await tester.tap(find.text('加一个限时'));
    await tester.pumpAndSettle();
    expect(find.text('新的限时'), findsOneWidget);
    expect(find.text('还没选 App'), findsOneWidget);

    await tester.tap(find.text('选择 App'));
    await tester.pumpAndSettle();
    expect(find.text('某短视频'), findsOneWidget);

    await tester.tap(find.text('1 小时'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(service.locks.single.minutes, 60);
    expect(find.text('某短视频'), findsOneWidget);
    expect(find.text('每天 1 小时 · 今天用了 10 分钟，还剩 50 分钟'), findsOneWidget);
    expect(service.discards, 0, reason: '保存了就不用丢草稿');
  });

  testWidgets('只勾了整个类别时，提醒会锁住这一类的所有 App', (tester) async {
    final service = FakeIosLockService();
    await pumpLocks(tester, service);

    await tester.tap(find.text('加一个限时'));
    await tester.pumpAndSettle();
    expect(find.text('点类别名称展开，就能只勾某一个 App'), findsOneWidget);
    expect(find.textContaining('你选了整个类别'), findsNothing);

    await tester.tap(find.text('选择 App'));
    await tester.pumpAndSettle();
    expect(find.text('1 个类别'), findsOneWidget);
    expect(find.textContaining('你选了整个类别'), findsOneWidget);
  });

  testWidgets('编辑页没保存就关掉，丢掉选好的 App', (tester) async {
    final service = FakeLockService();
    await pumpLocks(tester, service);

    await tester.tap(find.text('加一个限时'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(service.discards, 1);
    expect(service.locks, isEmpty);
  });

  testWidgets('已锁的显示状态，删掉要确认', (tester) async {
    final service = FakeLockService(locks: [
      const AppLock(
        id: 'a',
        minutes: 30,
        packages: ['com.example.game'],
        labels: ['某游戏'],
        usedMinutes: 42,
        locked: true,
      ),
    ]);
    await pumpLocks(tester, service);

    expect(find.text('每天 30 分钟 · 今天已经超时，打开就来电'), findsOneWidget);

    await tester.tap(find.byTooltip('删掉'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('再想想'));
    await tester.pumpAndSettle();
    expect(service.locks, hasLength(1));

    await tester.tap(find.byTooltip('删掉'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删掉'));
    await tester.pumpAndSettle();
    expect(service.locks, isEmpty);
    expect(find.text('某游戏'), findsNothing);
  });

  testWidgets('超时不禁止：接了电话再玩的那几分钟显示还剩多久又会来电；没有每天几次的临时解锁', (tester) async {
    final service = FakeLockService(locks: [
      const AppLock(id: 'a', minutes: 30, labels: ['某游戏'], packages: ['g'], usedMinutes: 35, graceActive: true),
      const AppLock(id: 'b', minutes: 60, labels: ['某短视频'], packages: ['v'], usedMinutes: 20),
    ]);
    await pumpLocks(tester, service);

    expect(find.text('每天 30 分钟 · 再玩中，再用满 10 分钟又会来电'), findsOneWidget);
    expect(find.text('每天 1 小时 · 今天用了 20 分钟，还剩 40 分钟'), findsOneWidget);
    expect(find.textContaining('临时解锁'), findsNothing);
    expect(find.textContaining('狗版的你就打电话过来问你'), findsOneWidget);
  });

  testWidgets('安卓选 App：勾选后完成，带回名称', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    List<AppUsage>? picked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => picked = await Navigator.of(context).push<List<AppUsage>>(MaterialPageRoute(
            builder: (_) => AppPickerPage(
              initial: const ['com.example.chat'],
              loader: () async => const [
                AppUsage(package: 'com.example.video', label: '某短视频', minutes: 95),
                AppUsage(package: 'com.example.chat', label: '某聊天', minutes: 0),
              ],
            ),
          )),
          child: const Text('打开'),
        ),
      ),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('今天用了 1 小时 35 分'), findsOneWidget);
    expect(find.text('完成（1）'), findsOneWidget);
    await tester.tap(find.text('某短视频'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成（2）'));
    await tester.pumpAndSettle();

    expect([for (final a in picked!) a.label], ['某短视频', '某聊天']);
  });

  group('按狗度来电（2026-11-27）', () {
    test('读得出门槛；规则和今天的状态这么写；“今天”页卡片不给它算倒计时', () {
      final dog = AppLock.fromMap({'id': 'd', 'minutes': 30, 'dogPercent': 100, 'packages': ['v'], 'labels': ['某短视频']});
      expect(dog.byDog, isTrue);
      expect(dog.rule, '狗度到 100% 后');
      expect(limitStatus(dog), '今天狗度还没到');
      const quota = AppLock(id: 'q', minutes: 60, labels: ['某游戏'], packages: ['g'], usedMinutes: 20);
      expect(quota.byDog, isFalse);
      expect(quota.rule, '每天 1 小时');

      final over = AppLock.fromMap(
          {'id': 'd', 'minutes': 30, 'dogPercent': 120, 'packages': ['v'], 'labels': ['某短视频'], 'locked': true, 'usedMinutes': 5});
      expect(limitStatus(over), '今天狗度到了，打开就来电');
      expect(TimeSpentCard.limitsLine([over, quota]), '某短视频 狗度到了 · 共 2 个');
      // 没到的按狗度限时不参加“还剩多久”
      expect(TimeSpentCard.limitsLine([dog, quota]), '某游戏 还剩 40 分钟 · 共 2 个');
    });

    testWidgets('新建限时选“今天狗度到了”：默认 100%，说明按目标写刷多久，保存时带上狗度、把目标交给原生层', (tester) async {
      SharedPreferences.setMockInitialValues({'goal_minutes': 300});
      final state = AppState(await SharedPreferences.getInstance());
      final service = FakeLockService();
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppScope(state: state, child: MaterialApp(home: LocksPage(service: service))));
      await tester.pumpAndSettle();

      await tester.tap(find.text('加一个限时'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择 App'));
      await tester.pumpAndSettle();
      expect(find.text('每天最多用'), findsOneWidget);
      expect(find.text('100%'), findsNothing);

      await tester.tap(find.text('今天狗度到了'));
      await tester.pumpAndSettle();
      expect(find.text('狗度到多少'), findsOneWidget);
      for (final p in LockService.dogPresets) {
        expect(find.text('$p%'), findsOneWidget);
      }
      expect(find.text('1 小时'), findsNothing, reason: '按狗度来就不选额度');
      expect(find.textContaining('今天狗度到 100%（按你的目标，就是今天一共刷了 5 小时）以后'), findsOneWidget);

      await tester.tap(find.text('120%'));
      await tester.pumpAndSettle();
      expect(find.textContaining('今天狗度到 120%（按你的目标，就是今天一共刷了 6 小时）以后'), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(service.locks.single.dogPercent, 120);
      expect(service.goals, [300]);
      expect(find.text('狗度到 120% 后 · 今天狗度还没到'), findsOneWidget);

      // 改回按额度
      await tester.tap(find.text('某短视频'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('这些 App 用满额度'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('45 分钟'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(service.locks.single.dogPercent, isNull);
      expect(service.locks.single.minutes, 45);
    });
  });

  group('安卓选 App：按类勾、白名单（2026-11-27）', () {
    test('哪些算短视频、社交、游戏：先认包名，再看系统分类；聊天办公、白名单里的不算', () {
      AppUsage app(String pkg, {String? category, bool whitelisted = false}) =>
          AppUsage(package: pkg, label: pkg, minutes: 0, category: category, whitelisted: whitelisted);
      expect(AppGroup.of(app('com.ss.android.ugc.aweme', category: 'other')), AppGroup.shortVideo);
      expect(AppGroup.of(app('com.example.player', category: 'video')), AppGroup.shortVideo);
      expect(AppGroup.of(app('com.sina.weibo')), AppGroup.social);
      expect(AppGroup.of(app('com.tencent.tmgp.sgame')), AppGroup.game);
      expect(AppGroup.of(app('com.example.puzzle', category: 'game')), AppGroup.game);
      expect(AppGroup.of(app('com.tencent.mm', category: 'social')), isNull, reason: '微信是聊天，不跟着社交整类勾');
      expect(AppGroup.of(app('com.example.notes', category: 'productivity')), isNull);
      expect(AppGroup.of(app('com.ss.android.ugc.aweme', whitelisted: true)), isNull);
    });

    testWidgets('整类勾、再点一次整类取消；白名单里的灰着勾不了，以前选进去的也去掉', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      List<AppUsage>? picked;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await Navigator.of(context).push<List<AppUsage>>(MaterialPageRoute(
              builder: (_) => AppPickerPage(
                initial: const ['com.eg.android.AlipayGphone'],
                loader: () async => const [
                  AppUsage(package: 'com.ss.android.ugc.aweme', label: '抖音', minutes: 95),
                  AppUsage(package: 'com.example.player', label: '某视频', minutes: 30, category: 'video'),
                  AppUsage(package: 'com.sina.weibo', label: '微博', minutes: 20),
                  AppUsage(package: 'com.tencent.mm', label: '微信', minutes: 120, category: 'social'),
                  AppUsage(package: 'com.example.puzzle', label: '某游戏', minutes: 10, category: 'game'),
                  AppUsage(package: 'com.eg.android.AlipayGphone', label: '支付宝', minutes: 3, whitelisted: true),
                ],
              ),
            )),
            child: const Text('打开'),
          ),
        ),
      ));
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('完成（0）'), findsOneWidget, reason: '以前选进去的支付宝不算');
      expect(find.text('短视频 2'), findsOneWidget);
      expect(find.text('社交 1'), findsOneWidget);
      expect(find.text('游戏 1'), findsOneWidget);
      expect(find.textContaining('永不来电：电话、短信、地图、支付'), findsOneWidget);

      await tester.tap(find.text('短视频 2'));
      await tester.pumpAndSettle();
      expect(find.text('完成（2）'), findsOneWidget);
      await tester.tap(find.text('短视频 2'));
      await tester.pumpAndSettle();
      expect(find.text('完成（0）'), findsOneWidget);

      await tester.tap(find.text('社交 1'));
      await tester.tap(find.text('抖音'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('支付宝'));
      await tester.pumpAndSettle();
      expect(find.text('完成（2）'), findsOneWidget, reason: '点白名单里的没反应');

      await tester.tap(find.text('完成（2）'));
      await tester.pumpAndSettle();
      expect([for (final a in picked!) a.label], ['抖音', '微博']);
    });
  });

  test('iOS 限时里选了哪些：一行一个，最多 3 行，多的一行写还有几个，高度跟着算', () {
    expect(LockSelectionView.heightFor(1), 34);
    expect(LockSelectionView.heightFor(2), 34 * 2 + 4);
    expect(LockSelectionView.heightFor(3), 34 * 3 + 4 * 2);
    expect(LockSelectionView.heightFor(7), 34 * 3 + 4 * 2 + 4 + 18);
  });

  group('从狗版的你的建议去设限时（iOS，2026-11-27）', () {
    testWidgets('一进编辑页就打开系统的选择页；选额度的地方再列一遍建议，按狗度来时不列', (tester) async {
      final service = _AdviceLockService();
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: LockEditorPage(service: service, fromAdvice: true)));
      await tester.pumpAndSettle();

      expect(service.picks, 1, reason: '不用再点“选择 App”');
      expect(find.text('1 个类别'), findsOneWidget);
      expect(find.text('狗版的你建议的额度，照着点下面一档：'), findsOneWidget);
      expect(find.text('建议的那几行'), findsOneWidget);

      await tester.tap(find.text('今天狗度到了'));
      await tester.pumpAndSettle();
      expect(find.text('建议的那几行'), findsNothing);
    });

    testWidgets('自己点“加一个限时”进来的：不自动打开选择页，也不列建议', (tester) async {
      final service = _AdviceLockService();
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: LockEditorPage(service: service)));
      await tester.pumpAndSettle();
      expect(service.picks, 0);
      expect(find.text('建议的那几行'), findsNothing);
    });
  });
}

/// 像 iOS：建议由系统画（这里用一行字代替），记下打开了几次选择页
class _AdviceLockService extends FakeIosLockService {
  int picks = 0;

  @override
  Widget? adviceReference() => const Text('建议的那几行');

  @override
  Future<bool> pickApps(BuildContext context, LockDraft draft) {
    picks++;
    return super.pickApps(context, draft);
  }
}