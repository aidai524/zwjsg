import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zwjsg_app/core/app_lock.dart';
import 'package:zwjsg_app/core/usage_channel.dart';
import 'package:zwjsg_app/features/locks/app_picker_page.dart';
import 'package:zwjsg_app/features/locks/locks_page.dart';

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

  @override
  Future<List<AppLock>> grantGrace(String id) async {
    final i = locks.indexWhere((l) => l.id == id);
    final l = locks[i];
    locks[i] = AppLock(
      id: l.id,
      minutes: l.minutes,
      packages: l.packages,
      labels: l.labels,
      usedMinutes: l.usedMinutes,
      graceLeft: l.graceLeft - 1,
      graceActive: true,
    );
    return list();
  }
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
    expect(find.text('还没有时间锁'), findsOneWidget);
  });

  testWidgets('新建时间锁：选 App、选额度，保存后出现在列表里', (tester) async {
    final service = FakeLockService();
    await pumpLocks(tester, service);

    await tester.tap(find.text('加一个时间锁'));
    await tester.pumpAndSettle();
    expect(find.text('新的时间锁'), findsOneWidget);
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

    await tester.tap(find.text('加一个时间锁'));
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

    await tester.tap(find.text('加一个时间锁'));
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
        graceLeft: 3,
      ),
    ]);
    await pumpLocks(tester, service);

    expect(find.text('每天 30 分钟 · 今天已锁，明天 0 点解开'), findsOneWidget);

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

  testWidgets('锁上后可以紧急解锁，确认后显示临时解锁中', (tester) async {
    final service = FakeLockService(locks: [
      const AppLock(
        id: 'a',
        minutes: 30,
        packages: ['com.example.game'],
        labels: ['某游戏'],
        usedMinutes: 42,
        locked: true,
        graceLeft: 3,
      ),
    ]);
    await pumpLocks(tester, service);

    await tester.tap(find.text('临时解锁 5 分钟（今天还剩 3 次）'));
    await tester.pumpAndSettle();
    expect(find.text('真的还要刷？'), findsOneWidget);
    await tester.tap(find.text('算了，不刷了'));
    await tester.pumpAndSettle();
    expect(service.locks.single.graceActive, isFalse);

    await tester.tap(find.text('临时解锁 5 分钟（今天还剩 3 次）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('再刷 5 分钟'));
    await tester.pumpAndSettle();

    expect(find.text('每天 30 分钟 · 临时解锁中，再用满 5 分钟就锁回去'), findsOneWidget);
    expect(find.textContaining('临时解锁 5 分钟（'), findsNothing);
  });

  testWidgets('临时解锁用完了就不再显示按钮', (tester) async {
    final service = FakeLockService(locks: [
      const AppLock(id: 'a', minutes: 30, labels: ['某游戏'], packages: ['g'], locked: true, graceLeft: 0),
    ]);
    await pumpLocks(tester, service);

    expect(find.text('每天 30 分钟 · 今天已锁，临时解锁也用完了'), findsOneWidget);
    expect(find.textContaining('临时解锁 5 分钟（'), findsNothing);
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
