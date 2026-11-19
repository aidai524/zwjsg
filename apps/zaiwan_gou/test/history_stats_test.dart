import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/core/history.dart';
import 'package:zwjsg_app/core/history_stats.dart';
import 'package:zwjsg_app/core/usage_channel.dart';
import 'package:zwjsg_app/features/history/stats_page.dart';

/// 安卓的一天：用了 [minutes] 分钟，按 3 小时的额度算
DayRecord day(String date, int minutes, {String? breed, int goal = 180}) {
  final pct = (minutes / goal * 100).round();
  final stage = [30, 60, 90, 120, 150].where((t) => pct >= t).length;
  return DayRecord(
      date: date, goalMinutes: goal, minutes: minutes, percent: pct, percentLabel: '$pct%', stage: stage, breedKey: breed);
}

/// iOS 的一天：只知道阶段
DayRecord iosDay(String date, int stage) => DayRecord(
    date: date,
    goalMinutes: 180,
    minutes: stage == 0 ? 0 : [54, 108, 162, 216, 270][stage - 1],
    percent: stage == 0 ? 0 : [30, 60, 90, 120, 150][stage - 1],
    percentLabel: stage == 0 ? '<30%' : '≥${[30, 60, 90, 120, 150][stage - 1]}%',
    stage: stage,
    stageOnly: true);

Map<String, DayRecord> byDate(List<DayRecord> list) => {for (final r in list) r.date: r};

void main() {
  // 2026-11-19 是周四
  final today = DateTime(2026, 11, 19, 21);

  group('统计', () {
    // 11-13（周五）到 11-19（周四），11-16 没记录
    final week = byDate([
      day('2026-11-13', 40), // 22% 做人
      day('2026-11-14', 240, breed: 'corgi'), // 133% 阶段 4
      day('2026-11-15', 150, breed: 'corgi'), // 83% 阶段 2
      day('2026-11-17', 30), // 做人
      day('2026-11-18', 20), // 做人
      day('2026-11-19', 120, breed: 'husky'), // 67% 阶段 2
    ]);

    test('平均、做人和变狗天数、最狗的一天、最长连续做人（没记录的日子断开）', () {
      final s = HistoryStats.lastDays(week, 7, today: today);
      expect(s.days, hasLength(7));
      expect(s.days.first, DateTime(2026, 11, 13));
      expect(s.recordedDays, 6);
      expect(s.averageMinutes, 100); // (40+240+150+30+20+120)/6
      expect(s.humanDays, 3);
      expect(s.dogDays, 3);
      expect(s.worstDay!.date, '2026-11-14');
      expect(s.longestHumanStreak, 2); // 11-17、11-18；11-13 前后都断了
      expect(s.stageCounts, [3, 0, 2, 0, 1, 0]);
      expect([for (final e in s.breedCounts) '${e.key}×${e.value}'], ['corgi×2', 'husky×1']);
      expect(s.minutesAreLowerBound, isFalse);
    });

    test('按星期几平均：周六最多，没记录的周一是空的', () {
      final s = HistoryStats.lastDays(week, 7, today: today);
      final w = s.weekdayMinutes;
      expect(w[0], isNull); // 周一 11-16 没记录
      expect(w[5], 240); // 周六 11-14
      expect(w[3], 120); // 周四 11-19
    });

    test('和前一段比：少刷了、做人多了', () {
      final all = {
        ...week,
        ...byDate([day('2026-11-08', 300), day('2026-11-09', 200), day('2026-11-10', 100)]),
      };
      final now = HistoryStats.lastDays(all, 7, today: today);
      final before = now.previous(all);
      expect(before.days.first, DateTime(2026, 11, 6));
      expect(before.days.last, DateTime(2026, 11, 12));
      expect(before.averageMinutes, 200);
      expect(StatsPage.compareLine(now, before), '比前 7 天每天少刷 1 小时 40 分，做人多了 3 天，有点人样了');
      expect(StatsPage.compareLine(before, now), '比前 7 天每天多刷 1 小时 40 分，做人少了 3 天，狗味更重了');
      expect(StatsPage.compareLine(now, HistoryStats.lastDays({}, 7, today: DateTime(2026, 11, 12))), isNull);
    });

    test('iOS 只有阶段：按阶段平均，分钟数是下限', () {
      final ios = byDate([iosDay('2026-11-18', 0), iosDay('2026-11-19', 3)]);
      final s = HistoryStats.lastDays(ios, 7, today: today);
      expect(s.stageOnly, isTrue);
      expect(s.minutesAreLowerBound, isTrue);
      expect(s.averageStage, 1.5);
      expect(s.weekdayStages[3], 3);
      expect(s.breedCounts, isEmpty);
    });
  });

  group('统计页', () {
    Future<AppState> pump(WidgetTester tester, Map<String, DayRecord> records,
        {Future<List<AppUsage>> Function(int days)? apps}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final state = AppState(await SharedPreferences.getInstance());
      await state.history.putAll(records.values);
      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(home: StatsPage(today: today, rankingLoader: apps ?? (_) async => const [])),
      ));
      await tester.pumpAndSettle();
      return state;
    }

    final records = byDate([
      day('2026-11-14', 240, breed: 'corgi'),
      day('2026-11-15', 150, breed: 'corgi'),
      day('2026-11-17', 30),
      day('2026-11-18', 20),
    ]);

    testWidgets('总览四格、每天的柱子、阶段分布、星期几、犬种、最近 7 天的 App', (tester) async {
      var askedDays = 0;
      await pump(tester, records, apps: (days) async {
        askedDays = days;
        return const [
          AppUsage(package: 'a', label: '短视频', minutes: 600),
          AppUsage(package: 'b', label: '聊天', minutes: 200),
        ];
      });

      expect(find.text('平均每天'), findsOneWidget);
      expect(find.text('1 小时 50 分'), findsOneWidget); // (240+150+30+20)/4
      expect(find.text('2 / 2 天'), findsOneWidget);
      expect(find.text('最长连续做人'), findsOneWidget);
      expect(find.text('11 月 14 日'), findsOneWidget);
      expect(find.text('133% · 吐舌头'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^最近 7 天，平均每天 1 小时 50 分，最多的是 11 月 14 日')), findsOneWidget);
      await tester.scrollUntilVisible(find.text('完全体'), 200);
      expect(find.bySemanticsLabel('吐舌头：1 天'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('周六最狗，平均刷 4 小时'), 200);
      await tester.scrollUntilVisible(find.text('柯基 × 2'), 200);
      await tester.scrollUntilVisible(find.text('短视频'), 300);
      expect(find.text('10 小时'), findsOneWidget);
      expect(askedDays, 7);
    });

    testWidgets('换成最近 30 天按 30 天算；没有记录时说清楚，不编数字', (tester) async {
      await pump(tester, records);
      await tester.tap(find.text('最近 30 天'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^最近 30 天，平均每天')), findsOneWidget);

      await pump(tester, {});
      expect(find.text('平均每天'), findsNothing);
      expect(find.textContaining('还没拿到数据'), findsOneWidget);
    });
  });

  group('历史补数', () {
    tearDown(() => UsageChannel.debugSupportedOverride = null);

    testWidgets('安卓：没打开 App 的日子从系统补上；只记了半天的换成一整天；系统没有的日子不编', (tester) async {
      UsageChannel.debugSupportedOverride = true;
      final calls = <MethodCall>[];
      const channel = MethodChannel('zwjsg/usage');
      final now = DateTime.now();
      String ago(int d) => AppState.localDate(DateTime(now.year, now.month, now.day - d));
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'hasPermission' => true,
          'getTodayUsage' => {'totalMinutes': 30, 'pickups': 5, 'lateNightMinutes': 0, 'categoryMinutes': {}},
          'getPastDays' => [
              {'date': ago(1), 'totalMinutes': 200, 'pickups': 50, 'lateNightMinutes': 0, 'categoryMinutes': {'video': 150}},
              {'date': ago(2), 'totalMinutes': 40, 'pickups': 9, 'lateNightMinutes': 0, 'categoryMinutes': {}},
            ],
          _ => null,
        };
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

      SharedPreferences.setMockInitialValues({});
      final state = AppState(await SharedPreferences.getInstance());
      // 前天打开过一次，那时才用了 10 分钟
      await state.history.put(day(ago(2), 10));
      await state.refreshUsage();

      expect(calls.singleWhere((c) => c.method == 'getPastDays').arguments, {'days': AppState.backfillDays});
      final yesterday = state.history.day(ago(1))!;
      expect(yesterday.minutes, 200);
      expect(yesterday.stage, 3); // 111%
      expect(yesterday.breedKey, 'corgi');
      expect(state.history.day(ago(2))!.minutes, 40);
      expect(state.history.day(ago(3)), isNull);
      expect(state.history.day(ago(0))!.minutes, 30);

      // 同一天再打开不再补
      await state.refreshUsage();
      expect(calls.where((c) => c.method == 'getPastDays'), hasLength(1));
    });

    testWidgets('iOS：监控扩展记下的每天最高阶段补进历史，阶段 0 的日子算做人', (tester) async {
      final now = DateTime.now();
      String ago(int d) => AppState.localDate(DateTime(now.year, now.month, now.day - d));
      const channel = MethodChannel('zwjsg/screen_time');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => {
            'authorization': 'approved',
            'categories': 13,
            'monitoring': true,
            'goalMinutes': 180,
            'thresholds': [54, 108, 162, 216, 270],
            'stage': 1,
            'history': {ago(0): 1, ago(1): 3, ago(2): 0},
          });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      SharedPreferences.setMockInitialValues({});
      final state = AppState(await SharedPreferences.getInstance());

      await state.refreshUsage();

      final y = state.history.day(ago(1))!;
      expect([y.stage, y.minutes, y.percentLabel, y.stageOnly, y.breedKey], [3, 162, '≥90%', true, null]);
      final d2 = state.history.day(ago(2))!;
      expect([d2.stage, d2.percentLabel], [0, '<30%']);
      expect(state.history.day(ago(0))!.stage, 1); // 今天照常按当前状态记
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });
}
