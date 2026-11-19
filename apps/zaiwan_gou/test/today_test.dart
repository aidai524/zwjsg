import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/core/history.dart';
import 'package:zwjsg_app/core/usage_channel.dart';
import 'package:zwjsg_app/features/card/card_page.dart';
import 'package:zwjsg_app/features/history/history_page.dart';
import 'package:zwjsg_app/features/history/stats_page.dart';
import 'package:zwjsg_app/features/today/ranking_page.dart';
import 'package:zwjsg_app/features/today/today_cards.dart';
import 'package:zwjsg_app/features/today/today_page.dart';

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

    testWidgets('今天页直接露出前三名，加上拿起次数和 23 点后的用时', (tester) async {
      usePhoneScreen(tester);
      final state = await newState();
      await tester.pumpWidget(
          AppScope(state: state, child: MaterialApp(home: TodayPage(rankingLoader: () async => apps))));
      await tester.pumpAndSettle();

      expect(find.text('今天时间去哪了'), findsOneWidget);
      expect(find.text('“某短视频”一个就占了今天的 49%'), findsOneWidget);
      for (final name in ['某短视频', '某聊天', '某笔记']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('某地图'), findsNothing);
      expect(find.text('52 分钟'), findsOneWidget);
      expect(find.textContaining('拿起手机'), findsOneWidget);
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
      expect(find.text('打开“使用情况访问权限”后，这里显示今天最费时间的 3 个 App'), findsOneWidget);

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

      state.debugSetUsage(usedMinutes(130)); // 72%，今天变狗了
      await tester.pump();
      expect(find.bySemanticsLabel('今天：变狗（阶段 2）'), findsOneWidget);
      expect(find.text('连续做人 2 天，今天破功了，明天重新数'), findsOneWidget);
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
