import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zwjsg_app/app.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/core/dog_meter.dart';
import 'package:zwjsg_app/core/screen_time_channel.dart';
import 'package:zwjsg_app/features/me/screen_time_page.dart';

void main() {
  test('阶段阈值按每日目标折算成分钟', () {
    expect(ScreenTimeChannel.thresholdMinutes(180), [54, 108, 162, 216, 270]);
    expect(ScreenTimeChannel.thresholdMinutes(ScreenTimePage.testGoalMinutes), [3, 6, 9, 12, 15]);
  });

  test('用量到阈值时，按狗度规则正好进入对应阶段', () {
    for (final goal in [10, 45, 90, 180, 200, 365]) {
      final minutes = ScreenTimeChannel.thresholdMinutes(goal);
      for (var i = 0; i < minutes.length; i++) {
        expect(DogMeter.stageFor(DogMeter.percentFor(minutes[i], goal)), i + 1, reason: '目标 $goal 分钟，阶段 ${i + 1}');
      }
    }
  });

  test('原生状态能解析，阶段只换算成狗度下限', () {
    final s = ScreenTimeStatus.fromMap({
      'authorization': 'approved',
      'apps': 2,
      'categories': 13,
      'monitoring': true,
      'goalMinutes': 10,
      'thresholds': [3, 6, 9, 12, 15],
      'stage': 2,
      'log': ['11-14 10:00:00 到达阶段 2（6 分钟）'],
    });
    expect(s.authorized, isTrue);
    expect(s.hasSelection, isTrue);
    expect(s.minPercent, 60);
    expect(const ScreenTimeStatus().minPercent, 0);
    expect(const ScreenTimeStatus().hasSelection, isFalse);
  });

  testWidgets('验证页：授权并选好 App 后，可以按测试目标开始监控', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    const channel = MethodChannel('zwjsg/screen_time');
    final calls = <MethodCall>[];
    var status = <String, Object?>{'authorization': 'approved', 'categories': 13};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'startMonitoring') {
        final args = call.arguments as Map;
        status = {
          ...status,
          'monitoring': true,
          'goalMinutes': args['goalMinutes'],
          'thresholds': args['thresholds'],
          'log': ['11-14 10:00:00 开始监控'],
        };
      }
      return status;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    SharedPreferences.setMockInitialValues({});
    final state = AppState(await SharedPreferences.getInstance());
    await tester.pumpWidget(AppScope(state: state, child: const MaterialApp(home: ScreenTimePage())));
    await tester.pumpAndSettle();

    expect(find.text('已授权'), findsOneWidget);
    expect(find.text('已选 0 个 App、13 个类别、0 个网站'), findsOneWidget);

    final testButton = find.text('测试：按 10 分钟目标开始');
    await tester.ensureVisible(testButton);
    await tester.tap(testButton);
    await tester.pumpAndSettle();

    final start = calls.lastWhere((c) => c.method == 'startMonitoring');
    expect(start.arguments, {
      'goalMinutes': 10,
      'thresholds': [3, 6, 9, 12, 15],
    });
    expect(find.text('监控中：目标 10 分钟，阈值 3 / 6 / 9 / 12 / 15 分钟'), findsOneWidget);
    expect(find.text('11-14 10:00:00 开始监控'), findsOneWidget);
  });

  testWidgets('验证页：没授权时不能选 App，也不能开始监控', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    const channel = MethodChannel('zwjsg/screen_time');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => {'authorization': 'notDetermined'});
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    SharedPreferences.setMockInitialValues({});
    final state = AppState(await SharedPreferences.getInstance());
    await tester.pumpWidget(AppScope(state: state, child: const MaterialApp(home: ScreenTimePage())));
    await tester.pumpAndSettle();

    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '选择')).onPressed, isNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '授权')).onPressed, isNotNull);
  });

  group('iOS 今天页', () {
    final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

    /// 模拟原生插件：按调用更新状态，startMonitoring 后假定系统已补发到阶段 [stageAfterStart]
    List<MethodCall> mockScreenTime(WidgetTester tester, Map<String, Object?> initial, {int stageAfterStart = 0}) {
      const channel = MethodChannel('zwjsg/screen_time');
      final calls = <MethodCall>[];
      var status = Map<String, Object?>.of(initial);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'requestAuthorization':
            status['authorization'] = 'approved';
          case 'pickActivities':
            status['categories'] = 13;
          case 'startMonitoring':
            final args = call.arguments as Map;
            status = {
              ...status,
              'monitoring': true,
              'goalMinutes': args['goalMinutes'],
              'thresholds': args['thresholds'],
              'stage': stageAfterStart,
            };
        }
        return status;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      return calls;
    }

    testWidgets('开启屏幕使用时间后显示真实阶段，不再是演示数据', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final calls = mockScreenTime(tester, {'authorization': 'notDetermined'}, stageAfterStart: 2);

      SharedPreferences.setMockInitialValues({'onboarded': true, 'privacy_version': AppState.privacyVersion});
      final state = AppState(await SharedPreferences.getInstance());
      await tester.pumpWidget(AppScope(state: state, child: ZwjsgApp(state: state)));
      await tester.pumpAndSettle();
      expect(find.text('演示数据'), findsOneWidget);

      await tester.ensureVisible(find.text('去开启'));
      await tester.tap(find.text('去开启'));
      await tester.pumpAndSettle();

      expect(calls.map((c) => c.method), containsAllInOrder(['requestAuthorization', 'pickActivities', 'startMonitoring']));
      expect(calls.lastWhere((c) => c.method == 'startMonitoring').arguments, {
        'goalMinutes': 180,
        'thresholds': [54, 108, 162, 216, 270],
      });
      expect(find.text('演示数据'), findsNothing);
      expect(find.text('去开启'), findsNothing);
      expect(find.text('≥60%'), findsOneWidget);
      expect(find.text('今日已刷 至少 1 小时 48 分'), findsOneWidget);
      expect(find.text('今天用满 2 小时 42 分，你就会脸上长毛'), findsOneWidget);
      expect(find.text('拿起手机'), findsNothing);
      expect(state.stage, 2);
    }, variant: ios);

    testWidgets('还没到第一个阈值时显示上限，改每日目标后按新阈值重新统计', (tester) async {
      final calls = mockScreenTime(tester, {
        'authorization': 'approved',
        'categories': 13,
        'monitoring': true,
        'goalMinutes': 180,
        'thresholds': [54, 108, 162, 216, 270],
        'stage': 0,
      });
      SharedPreferences.setMockInitialValues({});
      final state = AppState(await SharedPreferences.getInstance());
      await state.refreshUsage();

      expect(state.usage.isDemo, isFalse);
      expect(state.percentLabel, '<30%');
      expect(state.minutesUsedLabel, '不到 54 分钟');

      await state.setGoal(120);
      expect(calls.lastWhere((c) => c.method == 'startMonitoring').arguments, {
        'goalMinutes': 120,
        'thresholds': [36, 72, 108, 144, 180],
      });
      expect(state.screenTimeGoalMismatch, isFalse);
      expect(state.minutesUsedLabel, '不到 36 分钟');
    }, variant: ios);

    testWidgets('验证页的测试目标还在用时，按真实下限显示并提示改回', (tester) async {
      mockScreenTime(tester, {
        'authorization': 'approved',
        'categories': 13,
        'monitoring': true,
        'goalMinutes': 10,
        'thresholds': [3, 6, 9, 12, 15],
        'stage': 2,
      });
      SharedPreferences.setMockInitialValues({});
      final state = AppState(await SharedPreferences.getInstance());
      await state.refreshUsage();

      // 测试目标下到了阶段 2，只能确定今天至少用了 6 分钟；按 3 小时的每日目标算，狗度至少 3%
      expect(state.screenTimeGoalMismatch, isTrue);
      expect(state.minutesUsedLabel, '至少 6 分钟');
      expect(state.percentLabel, '≥3%');
      expect(state.stage, 0);
    }, variant: ios);
  });
}
