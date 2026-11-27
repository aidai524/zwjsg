import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zwjsg_app/core/api_client.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/core/breeds.dart';
import 'package:zwjsg_app/core/history.dart';
import 'package:zwjsg_app/features/dex/breed_sheet.dart';
import 'package:zwjsg_app/features/dex/dex_page.dart';

import 'widget_test.dart' show usePhoneScreen;

class DexApi extends ApiClient {
  Map<String, String> unlocks = {};
  int fetches = 0;

  @override
  Future<Map<String, String>> breedUnlocks() async {
    fetches++;
    return unlocks;
  }
}

/// [n] 天前的日期
String ago(int n) {
  final d = DateTime.now();
  return AppState.localDate(DateTime(d.year, d.month, d.day - n));
}

DayRecord day(String date, int stage, {String? breed}) => DayRecord(
      date: date,
      goalMinutes: 180,
      minutes: stage == 0 ? 30 : 120,
      percent: stage == 0 ? 17 : 67,
      percentLabel: stage == 0 ? '17%' : '67%',
      stage: stage,
      breedKey: breed,
    );

/// 图鉴上面多了进化形态，下面的格子要先滚出来再点
Future<void> tapTile(WidgetTester tester, String label) async {
  final tile = find.bySemanticsLabel(label);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<AppState> loggedIn(DexApi api) async {
  SharedPreferences.setMockInitialValues({'token': 't', 'onboarded': true});
  return AppState(await SharedPreferences.getInstance(), api: api);
}

void main() {
  test('第一次解锁的日子：今年的不写年份', () {
    expect(breedDateLabel('${DateTime.now().year}-11-17'), '11 月 17 日');
    expect(breedDateLabel('2025-03-02'), '2025 年 3 月 2 日');
  });

  testWidgets('解锁了的显示梗和变成过几天，没解锁的是剪影和条件，狼带连续做人的进度', (tester) async {
    usePhoneScreen(tester);
    final api = DexApi()..unlocks = {'corgi': '2026-11-17'};
    final state = await loggedIn(api);
    await state.history.putAll([
      day(ago(3), 0),
      day(ago(2), 2, breed: 'corgi'),
      day(ago(1), 3, breed: 'corgi'),
    ]);
    await tester.pumpWidget(AppScope(state: state, child: const MaterialApp(home: DexPage())));
    await tester.pumpAndSettle();

    // 打开图鉴时去服务端取了一次解锁情况
    expect(api.fetches, 1);
    // 节日那几天图鉴里会多出没拿到的限定犬种，总数按今天算
    expect(find.text('已收集 1 / ${dexBreeds({'corgi'}, DateTime.now()).length}'), findsOneWidget);
    expect(find.text('腿短，停不下来'), findsOneWidget);
    expect(find.text('变成过 2 天'), findsOneWidget);
    // 没解锁的不露梗，只写怎么变成
    expect(find.text('半夜不睡的拆家狗'), findsNothing);
    expect(find.text('23 点后使用占比最高'), findsOneWidget);
    // 两种稀有犬种（2026-11-26 定的）：没解锁也写名字和怎么变成
    expect(find.text('串串'), findsOneWidget);
    expect(find.text('同一天里短视频、游戏、聊天办公三样各占两成以上'), findsOneWidget);
    expect(find.text('金毛寻回犬'), findsOneWidget);
    // 昨天变狗了，今天还没数据：狼的进度是 0
    expect(find.text('连续做人 0 / 7 天'), findsOneWidget);
  });

  testWidgets('点开一种狗：怎么变成、第一次是哪天、变成过几天；没解锁的狼看进度', (tester) async {
    usePhoneScreen(tester);
    final api = DexApi()..unlocks = {'corgi': '${DateTime.now().year}-11-17'};
    final state = await loggedIn(api);
    await state.history.putAll([
      for (var i = 4; i >= 3; i--) day(ago(i), 0),
      day(ago(2), 2, breed: 'corgi'),
      day(ago(1), 0),
    ]);
    await tester.pumpWidget(AppScope(state: state, child: const MaterialApp(home: DexPage())));
    await tester.pumpAndSettle();

    await tapTile(tester, '柯基，普通，已解锁');
    expect(find.byType(BreedSheet), findsOneWidget);
    expect(find.text('“腿短，停不下来”'), findsOneWidget);
    expect(find.text('短视频类使用最多'), findsOneWidget);
    expect(find.text('11 月 17 日'), findsOneWidget);
    expect(find.textContaining('1 天 · 最近一次'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tapTile(tester, '狼，传说，未解锁');
    expect(find.text('？？？'), findsNothing);
    expect(find.text('狼'), findsWidgets);
    // 昨天做人（2 天前变狗断了），今天还没数据
    expect(find.text('连续做人 1 / 7 天'), findsWidgets);
    expect(find.text('第一次'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tapTile(tester, '金毛寻回犬，稀有，未解锁');
    expect(find.text('连续 4 天一天比一天刷得少（算到昨天），今天还没做回人'), findsWidgets);
    expect(find.textContaining('看前 4 天的记录'), findsOneWidget);
    expect(find.text('“每天叼回一点自己”'), findsNothing);
  });

  group('iOS：手机上判定传说「狼」', () {
    final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

    void mockScreenTime(WidgetTester tester, Map<String, int> history, {int stage = 0}) {
      const channel = MethodChannel('zwjsg/screen_time');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => {
            'authorization': 'approved',
            'categories': 13,
            'monitoring': true,
            'goalMinutes': 180,
            'thresholds': [54, 108, 162, 216, 270],
            'stage': stage,
            'history': history,
          });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    }

    testWidgets('节日限定：监控扩展记着那天到了阶段 2，没打开 App 也算，按那天的日子解锁；不用登录', (tester) async {
      // 2026 年的元旦早就过了：记录里那天变了狗，就是立flag犬
      mockScreenTime(tester, {'2026-01-01': 2, ago(1): 0});
      SharedPreferences.setMockInitialValues({'onboarded': true});
      final api = DexApi();
      final state = AppState(await SharedPreferences.getInstance(), api: api);

      await state.refreshUsage();
      await state.refreshUsage();
      expect(state.history.day('2026-01-01')?.breedKey, 'flag');
      expect(state.ownedBreeds, contains('flag'));
      expect(state.unlockedOn('flag'), '2026-01-01');
      expect(state.newlyUnlocked, contains('flag'));
      expect(api.fetches, 0);
    }, variant: ios);

    testWidgets('连续 6 天做人、今天到现在还是人：解锁狼，弹解锁动画；不用登录、不上传', (tester) async {
      mockScreenTime(tester, {for (var i = 1; i <= 6; i++) ago(i): 0});
      SharedPreferences.setMockInitialValues({'onboarded': true});
      final api = DexApi();
      final state = AppState(await SharedPreferences.getInstance(), api: api);

      await state.refreshUsage();
      expect(state.ownedBreeds, {'wolf'});
      // 连续做人 6 天（不算今天）也够解锁进化形态「学霸」了，一起排队弹
      expect(state.newlyUnlocked, ['wolf', 'evo:scholar']);
      expect(state.unlockedOn('wolf'), ago(0));
      expect(api.fetches, 0);

      // 只弹一次
      await state.markUnlockSeen('wolf');
      await state.markUnlockSeen('evo:scholar');
      await state.refreshUsage();
      expect(state.newlyUnlocked, isEmpty);

      // 重新打开 App 还在
      final again = AppState(await SharedPreferences.getInstance(), api: api);
      expect(again.ownedBreeds, {'wolf'});
    }, variant: ios);

    testWidgets('今天已经变狗、或者中间断了一天，都不解锁', (tester) async {
      mockScreenTime(tester, {for (var i = 1; i <= 6; i++) ago(i): 0}, stage: 1);
      SharedPreferences.setMockInitialValues({'onboarded': true});
      final state = AppState(await SharedPreferences.getInstance(), api: DexApi());
      await state.refreshUsage();
      expect(state.ownedBreeds, isEmpty);
      expect(state.humanStreakNow, 6);

      mockScreenTime(tester, {for (var i = 1; i <= 6; i++) ago(i): i == 3 ? 2 : 0});
      SharedPreferences.setMockInitialValues({'onboarded': true});
      final broken = AppState(await SharedPreferences.getInstance(), api: DexApi());
      await broken.refreshUsage();
      expect(broken.ownedBreeds, isEmpty);
      expect(broken.humanStreakNow, 3);
    }, variant: ios);

    testWidgets('前 4 天每天到过的最高阶段一天比一天低、今天还是狗：解锁金毛寻回犬；有一天没低就不算', (tester) async {
      mockScreenTime(tester, {ago(4): 4, ago(3): 3, ago(2): 2, ago(1): 1}, stage: 1);
      SharedPreferences.setMockInitialValues({'onboarded': true});
      final state = AppState(await SharedPreferences.getInstance(), api: DexApi());
      await state.refreshUsage();
      expect(state.breedKey, 'retriever');
      expect(state.ownedBreeds, {'retriever'});
      expect(state.newlyUnlocked, ['retriever']);
      expect(state.history.day(ago(0))!.breedKey, 'retriever');

      mockScreenTime(tester, {ago(4): 3, ago(3): 3, ago(2): 2, ago(1): 1}, stage: 1);
      SharedPreferences.setMockInitialValues({'onboarded': true});
      final flat = AppState(await SharedPreferences.getInstance(), api: DexApi());
      await flat.refreshUsage();
      expect(flat.breedKey, 'corgi');
      expect(flat.ownedBreeds, isEmpty);
    }, variant: ios);

    testWidgets('图鉴上说清楚 iPhone 只能变狼、金毛寻回犬和节日限定的', (tester) async {
      usePhoneScreen(tester);
      mockScreenTime(tester, const {});
      SharedPreferences.setMockInitialValues({'onboarded': true});
      final state = AppState(await SharedPreferences.getInstance(), api: DexApi());
      await tester.pumpWidget(AppScope(state: state, child: const MaterialApp(home: DexPage())));
      await tester.pumpAndSettle();
      expect(find.textContaining('iPhone 上只能变传说「狼」、稀有「金毛寻回犬」和节日限定的'), findsOneWidget);

      await tapTile(tester, '柯基，普通，未解锁');
      expect(find.textContaining('这种狗暂时只能在安卓上变'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tapTile(tester, '金毛寻回犬，稀有，未解锁');
      expect(find.textContaining('这种狗暂时只能在安卓上变'), findsNothing);
      expect(find.textContaining('iPhone 比每天到过的最高阶段'), findsOneWidget);
    }, variant: ios);
  });
}
