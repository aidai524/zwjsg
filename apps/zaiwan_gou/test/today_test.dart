import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zwjsg_app/core/app_lock.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/core/history.dart';
import 'package:zwjsg_app/core/usage_channel.dart';
import 'package:zwjsg_app/features/card/card_page.dart';
import 'package:zwjsg_app/features/history/history_page.dart';
import 'package:zwjsg_app/features/history/stats_page.dart';
import 'package:zwjsg_app/features/today/ranking_page.dart';
import 'package:zwjsg_app/features/today/stage_ring.dart';
import 'package:zwjsg_app/features/today/today_cards.dart';
import 'package:zwjsg_app/features/today/today_page.dart';

import 'locks_test.dart' show FakeLockService;
import 'widget_test.dart' show pumpApp, usePhoneScreen;

DayRecord rec(String date, int stage) =>
    DayRecord(date: date, goalMinutes: 180, minutes: 60, percent: 33, percentLabel: '33%', stage: stage);

const apps = [
  AppUsage(package: 'com.example.video', label: '某短视频', minutes: 52),
  AppUsage(package: 'com.example.chat', label: '某聊天', minutes: 31),
  AppUsage(package: 'com.example.notes', label: '某笔记', minutes: 18),
  AppUsage(package: 'com.example.map', label: '某地图', minutes: 5),
];

Future<AppState> newState({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  return AppState(await SharedPreferences.getInstance());
}

/// 今天用了 [minutes] 分钟的真实数据
UsageSnapshot usedMinutes(int minutes) =>
    UsageSnapshot(totalMinutes: minutes, pickups: 0, lateNightMinutes: 0, categoryMinutes: const {});

void main() {
  group('今天时间去哪了', () {
    test('最费时间的 App 占四成以上时说“一个就占了”，否则只说是谁', () {
      expect(TimeSpentCard.headline(apps), '“某短视频”一个就占了今天的 49%');
      expect(
        TimeSpentCard.headline(const [
          AppUsage(package: 'a', label: '某阅读', minutes: 30),
          AppUsage(package: 'b', label: '某聊天', minutes: 30),
          AppUsage(package: 'c', label: '某音乐', minutes: 30),
        ]),
        '最费时间的是“某阅读”，占今天的 33%',
      );
    });

    testWidgets('今天页直接露出前五名，加上拿起次数和 23 点后的用时', (tester) async {
      usePhoneScreen(tester);
      final state = await newState();
      const six = [
        ...apps,
        AppUsage(package: 'com.example.music', label: '某音乐', minutes: 4),
        AppUsage(package: 'com.example.shop', label: '某购物', minutes: 3),
      ];
      await tester.pumpWidget(
          AppScope(state: state, child: MaterialApp(home: TodayPage(rankingLoader: () async => six))));
      await tester.pumpAndSettle();

      expect(find.text('今天时间去哪了'), findsOneWidget);
      expect(find.text('“某短视频”一个就占了今天的 46%'), findsOneWidget);
      for (final name in ['某短视频', '某聊天', '某笔记', '某地图', '某音乐']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('某购物'), findsNothing);
      expect(find.text('52 分钟'), findsOneWidget);
      // 没拿到今天的数据时不写拿起次数；页面打开时会自己读一次（测试里读不到），读完再塞数据
      expect(find.textContaining('拿起手机'), findsNothing);
      state.debugSetUsage(
          const UsageSnapshot(totalMinutes: 113, pickups: 33, lateNightMinutes: 12, categoryMinutes: {}));
      await tester.pumpAndSettle();
      expect(find.text('拿起手机 33 次 · 23 点后 12 分钟'), findsOneWidget);
      expect(find.text('提前看今晚的结算卡'), findsNothing);
    });

    testWidgets('没有使用情况访问权限、今天还没用 App 时说清楚', (tester) async {
      usePhoneScreen(tester);
      final state = await newState();
      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(
          home: TodayPage(rankingLoader: () async => throw PlatformException(code: 'NO_PERMISSION')),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('打开“使用情况访问权限”后，这里显示今天最费时间的 5 个 App'), findsOneWidget);

      await tester.pumpWidget(
          AppScope(state: state, child: MaterialApp(home: TodayPage(rankingLoader: () async => const []))));
      await tester.pumpAndSettle();
      expect(find.text('今天还没有用满 1 分钟的 App'), findsOneWidget);
    });
  });

  group('这周', () {
    test('连续做人从昨天往前数，变狗或没记录的那天就断了', () {
      final today = DateTime(2026, 11, 20);
      expect(WeekCard.humanStreak({}, today), 0);
      expect(
        WeekCard.humanStreak({
          '2026-11-19': rec('2026-11-19', 0),
          '2026-11-18': rec('2026-11-18', 0),
          '2026-11-17': rec('2026-11-17', 2),
          '2026-11-16': rec('2026-11-16', 0),
        }, today),
        2,
      );
      // 11-18 没打开 App，没有记录
      expect(
        WeekCard.humanStreak({'2026-11-19': rec('2026-11-19', 0), '2026-11-17': rec('2026-11-17', 0)}, today),
        1,
      );
      // 跨月也能接上：10-25 到 11-19 天天做人，一共 26 天
      final records = {
        for (var d = DateTime(2026, 10, 25); d.isBefore(today); d = DateTime(d.year, d.month, d.day + 1))
          AppState.localDate(d): rec(AppState.localDate(d), 0),
      };
      expect(WeekCard.humanStreak(records, today), 26);
      expect(WeekCard.humanStreak(records, DateTime(2026, 12, 1)), 0);
    });

    test('进度那句话：今天还是人就鼓励守住，变狗了明天重新数', () {
      expect(WeekCard.streakLine(0, humanToday: true), '今天守住，就是连续做人第 1 天');
      expect(WeekCard.streakLine(2, humanToday: true), '连续做人 2 天，今天守住就是 3 天');
      expect(WeekCard.streakLine(7, humanToday: true), '已经连续做人 7 天，够格变传说「狼」了');
      expect(WeekCard.streakLine(0, humanToday: false), '今天已经变狗了，明天重新做人');
      expect(WeekCard.streakLine(2, humanToday: false), '连续做人 2 天，今天破功了，明天重新数');
    });

    testWidgets('一排 7 天：做人、变狗、没记录、今天、还没到', (tester) async {
      usePhoneScreen(tester);
      final state = await newState();
      // 2026-11-20 是周五：周一没打开 App，周二变狗，周三、周四做人
      for (final r in [rec('2026-11-17', 2), rec('2026-11-18', 0), rec('2026-11-19', 0)]) {
        await state.history.put(r);
      }
      state.debugSetUsage(usedMinutes(20)); // 今天到现在 11%，还是人
      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(home: Scaffold(body: WeekCard(today: DateTime(2026, 11, 20, 15)))),
      ));

      for (final label in ['周一：没有记录', '周二：变狗（阶段 2）', '周三：做人', '周四：做人', '今天：做人', '周六：还没到', '周日：还没到']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      expect(find.text('连续做人 2 天，今天守住就是 3 天'), findsOneWidget);
      expect(find.text('连做 7 天变传说「狼」'), findsOneWidget);
      // 连续做人 3 天解锁第一种进化形态
      expect(find.text('今天守住，明天解锁进化形态「学霸」'), findsOneWidget);
      // 这周到今天：周二变狗，周三、周四、今天做人；每天 60、60、60、20 分钟
      expect(find.text('做人 3 天 · 变狗 1 天 · 日均 50 分钟'), findsOneWidget);
      expect(find.text('目标'), findsOneWidget);

      state.debugSetUsage(usedMinutes(130)); // 72%，今天变狗了
      await tester.pump();
      expect(find.bySemanticsLabel('今天：变狗（阶段 2）'), findsOneWidget);
      expect(find.text('连续做人 2 天，今天破功了，明天重新数'), findsOneWidget);
      expect(find.text('明天起连续做人 3 天，解锁进化形态「学霸」'), findsOneWidget);
      expect(find.text('做人 2 天 · 变狗 2 天 · 日均 1 小时 18 分'), findsOneWidget);
    });
  });

  test('这周的小结：iOS 只有阶段，不写日均', () {
    expect(WeekCard.summary(const []), '这周还没有记录');
    const ios = DayRecord(
        date: '2026-11-18', goalMinutes: 180, minutes: 108, percent: 60, percentLabel: '≥60%', stage: 2, stageOnly: true);
    expect(WeekCard.summary([ios, rec('2026-11-19', 0)]), '做人 1 天 · 变狗 1 天');
  });

  group('狗头外面一圈', () {
    test('转满一圈是 150%，超过就停在满圈', () {
      expect(StageRing.fractionFor(0), 0);
      expect(StageRing.fractionFor(75), 0.5);
      expect(StageRing.fractionFor(150), 1);
      expect(StageRing.fractionFor(400), 1);
    });

    testWidgets('有数据时圈上念出今日已刷和目标；没数据时只说还没拿到', (tester) async {
      usePhoneScreen(tester);
      final state = await newState();
      await tester.pumpWidget(
          AppScope(state: state, child: MaterialApp(home: TodayPage(rankingLoader: () async => apps))));
      await tester.pumpAndSettle();
      // 圈里的形象也有一句读屏文字，跟在后面
      expect(find.bySemanticsLabel(RegExp('^还没拿到今天的使用数据')), findsOneWidget);
      expect(find.textContaining('今日已刷'), findsNothing);

      state.debugSetUsage(usedMinutes(130));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^今日已刷 2 小时 10 分，目标 3 小时')), findsOneWidget);
      expect(find.text('狗度 '), findsOneWidget);
      expect(find.text('72%'), findsOneWidget);
      // 下一阶段（90%）从 162 分钟开始，还差 32 分钟
      expect(find.text('再刷 32 分钟，你就会脸上长毛'), findsOneWidget);
      final painter = tester.widget<CustomPaint>(find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is StageRingPainter)).painter! as StageRingPainter;
      expect(painter.value, closeTo(72 / 150, 0.001));
    });
  });

  group('超时来电并进“今天时间去哪了”', () {
    test('底下那行：先说再玩中的，再说超时的，再说离限时最近的；没设就引导去设', () {
      expect(TimeSpentCard.limitsLine(const []), '给最上头的 App 设个限时');
      const video = AppLock(id: 'v', minutes: 60, labels: ['某短视频'], packages: ['v'], usedMinutes: 20);
      const game = AppLock(id: 'g', minutes: 30, labels: ['某游戏'], packages: ['g'], usedMinutes: 25);
      expect(TimeSpentCard.limitsLine(const [video]), '某短视频 还剩 40 分钟');
      expect(TimeSpentCard.limitsLine(const [video, game]), '某游戏 还剩 5 分钟 · 共 2 个');
      const over = AppLock(id: 'o', minutes: 30, labels: ['某论坛'], packages: ['f'], usedMinutes: 42, locked: true);
      expect(TimeSpentCard.limitsLine(const [video, over]), '某论坛 已超时 · 共 2 个');
      const grace = AppLock(id: 'r', minutes: 30, labels: ['某阅读'], packages: ['r'], usedMinutes: 35, graceActive: true);
      expect(TimeSpentCard.limitsLine(const [over, grace]), '某阅读 再玩中 · 共 2 个');
      // iOS 拿不到用了多久
      expect(TimeSpentCard.limitsLine(const [AppLock(id: 'i', minutes: 60, apps: 2)]), '已设 1 个，用满了狗会打电话来');
    });

    testWidgets('设了限时的 App 在排行里带电话标记，超时的标红；底下一行点了去管理限时', (tester) async {
      usePhoneScreen(tester);
      final state = await newState();
      final service = FakeLockService(locks: [
        const AppLock(id: 'a', minutes: 30, labels: ['某短视频'], packages: ['com.example.video'], usedMinutes: 52, locked: true),
        const AppLock(id: 'b', minutes: 60, labels: ['某聊天'], packages: ['com.example.chat'], usedMinutes: 31),
      ]);
      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(home: TodayPage(rankingLoader: () async => apps, lockService: service)),
      ));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('超时来电：今天已超时'), findsOneWidget);
      expect(find.bySemanticsLabel('设了超时来电'), findsOneWidget);
      expect(find.text('超时来电'), findsOneWidget);
      expect(find.text('某短视频 已超时 · 共 2 个'), findsOneWidget);
      // 超时来电不再单独占一张卡
      expect(find.text('管理'), findsNothing);

      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(
            home: TodayPage(key: UniqueKey(), rankingLoader: () async => apps, lockService: FakeLockService())),
      ));
      await tester.pumpAndSettle();
      expect(find.text('给最上头的 App 设个限时'), findsOneWidget);
      expect(find.byIcon(Icons.phone_in_talk), findsOneWidget);
    });
  });

  testWidgets('“晒一下”打开结算卡，两张卡片分别打开完整排行和历史记录', (tester) async {
    usePhoneScreen(tester);
    await pumpApp(tester, {'onboarded': true});
    // 没拿到真实数据时没有“晒一下”；有了数据才出现
    expect(find.text('晒一下'), findsNothing);
    AppScope.read(tester.element(find.byType(TodayPage))).debugSetUsage(usedMinutes(130));
    await tester.pumpAndSettle();

    await tester.tap(find.text('晒一下'));
    await tester.pumpAndSettle();
    expect(find.byType(CardPage), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('今天时间去哪了'));
    await tester.tap(find.text('今天时间去哪了'));
    await tester.pumpAndSettle();
    expect(find.byType(RankingPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('这周'));
    await tester.tap(find.text('这周'));
    await tester.pumpAndSettle();
    expect(find.byType(StatsPage), findsOneWidget);

    // 统计页底部进“每天的记录”
    await tester.scrollUntilVisible(find.text('每天的记录'), 300);
    await tester.tap(find.text('每天的记录'));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryPage), findsOneWidget);
  });
}
