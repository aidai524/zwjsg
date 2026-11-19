import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zwjsg_app/core/app_lock.dart';
import 'package:zwjsg_app/core/usage_channel.dart';
import 'package:zwjsg_app/features/locks/app_picker_page.dart';
import 'package:zwjsg_app/features/locks/locks_page.dart';
import 'package:zwjsg_app/features/today/today_cards.dart';

class FakeLockService extends LockService {
  FakeLockService({this.isReady = true, List<AppLock>? locks}) : locks = locks ?? [];

  bool isReady;
  int setups = 0;
  int discards = 0;
  final List<AppLock> locks;

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
    expect(find.textContaining('你的狗就打电话过来问你'), findsOneWidget);
  });

  testWidgets('“今天”页的超时来电卡：没设时引导去设，设了就露出每个限时用到哪了', (tester) async {
    Future<void> pumpCard(FakeLockService service) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [LimitsCard(key: UniqueKey(), service: service)]))));
      await tester.pumpAndSettle();
    }

    await pumpCard(FakeLockService());
    expect(find.text('超时来电'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
    expect(find.textContaining('你的狗会打电话问你还玩不玩'), findsOneWidget);

    await pumpCard(FakeLockService(locks: [
      const AppLock(id: 'a', minutes: 30, labels: ['某游戏'], packages: ['g'], usedMinutes: 42, locked: true),
      const AppLock(id: 'b', minutes: 60, labels: ['某短视频'], packages: ['v'], usedMinutes: 20),
      const AppLock(id: 'c', minutes: 60, labels: ['某购物'], packages: ['s'], usedMinutes: 5),
      const AppLock(id: 'd', minutes: 90, labels: ['某论坛'], packages: ['f'], usedMinutes: 0),
    ]));
    expect(find.text('管理'), findsOneWidget);
    expect(find.text('某游戏'), findsOneWidget);
    expect(find.text('今天已经超时，打开就来电'), findsOneWidget);
    expect(find.text('今天用了 20 分钟，还剩 40 分钟'), findsOneWidget);
    expect(find.text('某论坛'), findsNothing);
    expect(find.text('还有 1 个'), findsOneWidget);
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
}
