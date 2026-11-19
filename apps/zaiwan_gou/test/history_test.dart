import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/core/history.dart';
import 'package:zwjsg_app/features/history/history_page.dart';

DayRecord rec(String date, int stage, {String label = '33%'}) => DayRecord(
      date: date,
      goalMinutes: 180,
      minutes: 60,
      percent: 33,
      percentLabel: label,
      stage: stage,
    );

void main() {
  test('同一天反复刷新只留最后一次', () async {
    SharedPreferences.setMockInitialValues({});
    final store = HistoryStore(await SharedPreferences.getInstance());

    await store.put(rec('2026-11-14', 1));
    await store.put(rec('2026-11-14', 2));

    expect(store.all(), hasLength(1));
    expect(store.day('2026-11-14')!.stage, 2);
  });

  test('最多留 ${HistoryStore.keepDays} 天，最早的先删', () async {
    SharedPreferences.setMockInitialValues({});
    final store = HistoryStore(await SharedPreferences.getInstance());
    final start = DateTime(2025, 1, 1);

    for (var i = 0; i < HistoryStore.keepDays + 2; i++) {
      await store.put(rec(AppState.localDate(start.add(Duration(days: i))), 0));
    }

    expect(store.all(), hasLength(HistoryStore.keepDays));
    expect(store.day('2025-01-01'), isNull);
    expect(store.day('2025-01-03'), isNotNull);
  });

  testWidgets('拿不到真实数据时不记历史', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(await SharedPreferences.getInstance());

    await state.refreshUsage();

    expect(state.hasUsageData, isFalse);
    expect(state.history.all(), isEmpty);
  });

  testWidgets('iOS 刷新今天的数据时记一条，存当时显示的狗度', (tester) async {
    const channel = MethodChannel('zwjsg/screen_time');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => {
          'authorization': 'approved',
          'categories': 13,
          'monitoring': true,
          'goalMinutes': 180,
          'thresholds': [54, 108, 162, 216, 270],
          'stage': 2,
        });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    SharedPreferences.setMockInitialValues({});
    final state = AppState(await SharedPreferences.getInstance());

    await state.refreshUsage();

    final today = state.history.day(AppState.localDate())!;
    expect(today.stage, 2);
    expect(today.percentLabel, '≥60%');
    expect(today.minutes, 108);
    expect(today.stageOnly, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('历史页：最近 7 天和按月', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'history': jsonEncode({
        '2026-11-14': rec('2026-11-14', 2, label: '≥60%').toJson(),
        '2026-11-12': rec('2026-11-12', 0, label: '<30%').toJson(),
      }),
    });
    final state = AppState(await SharedPreferences.getInstance());
    await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(home: HistoryPage(today: DateTime(2026, 11, 14))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('记录了 2 天：做人 1 天，变狗 1 天'), findsOneWidget);
    expect(find.text('≥60%'), findsOneWidget);
    expect(find.text('没打开 App，没记录'), findsNWidgets(5));

    await tester.tap(find.text('按月'));
    await tester.pumpAndSettle();
    expect(find.text('2026 年 11 月'), findsOneWidget);
    expect(find.text('记录了 2 天：做人 1 天，变狗 1 天'), findsOneWidget);

    await tester.tap(find.byTooltip('上个月'));
    await tester.pumpAndSettle();
    expect(find.text('2026 年 10 月'), findsOneWidget);
    expect(find.text('这段时间还没有记录'), findsOneWidget);
  });
}
