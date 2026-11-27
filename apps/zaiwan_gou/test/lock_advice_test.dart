import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zwjsg_app/core/app_lock.dart';
import 'package:zwjsg_app/core/lock_advisor.dart';
import 'package:zwjsg_app/core/usage_channel.dart';
import 'package:zwjsg_app/features/locks/locks_page.dart';

import 'locks_test.dart' show FakeLockService;

/// 最近 7 天：总分钟数
const week = [
  AppUsage(package: 'com.tencent.mm', label: '微信', minutes: 1400, category: 'social'),
  AppUsage(package: 'com.ss.android.ugc.aweme', label: '抖音', minutes: 700, category: 'other'),
  AppUsage(package: 'com.example.reader', label: '某阅读', minutes: 420, category: 'other'),
  AppUsage(package: 'com.example.game', label: '某游戏', minutes: 280, category: 'game'),
  AppUsage(package: 'com.example.notes', label: '某笔记', minutes: 210, category: 'productivity'),
  AppUsage(package: 'com.zwjsg.zwjsg_app', label: '再玩我是狗', minutes: 300, category: 'other'),
  AppUsage(package: 'com.example.video', label: '某视频', minutes: 70, category: 'video'),
];

Future<void> pumpAdvice(WidgetTester tester, FakeLockService service, Future<({List<AppUsage> apps, int days})> Function() loader) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: LocksPage(service: service, adviceLoader: loader)));
  await tester.pumpAndSettle();
}

void main() {
  group('超时来电的建议', () {
    test('额度：不超过平均用时七成的最大一档，至少 15 分钟', () {
      expect(LockAdvisor.suggestedMinutes(100), 60);
      expect(LockAdvisor.suggestedMinutes(30), 15);
      expect(LockAdvisor.suggestedMinutes(200), 120);
      expect(LockAdvisor.suggestedMinutes(300), 180);
      expect(LockAdvisor.suggestedMinutes(10), 15);
    });

    test('娱乐类 20 分钟以上就建议，认不出的要 45 分钟；聊天、本 App、已经设了的不建议；娱乐类在前，最多 3 个', () {
      final advice = LockAdvisor.suggest(week, days: 7);
      expect([for (final a in advice) a.app.label], ['抖音', '某游戏', '某阅读']);
      expect([for (final a in advice) a.averageMinutes], [100, 40, 60]);
      expect([for (final a in advice) a.suggestedMinutes], [60, 15, 30]);
      expect(advice.first.reason, '日均 1 小时 40 分');
      // 某笔记 30 分钟、认不出是娱乐类 → 不建议；某视频平均 10 分钟 → 不建议

      final rest = LockAdvisor.suggest(week, days: 7, existing: const [
        AppLock(id: 'a', minutes: 60, packages: ['com.ss.android.ugc.aweme'], labels: ['抖音']),
      ]);
      expect([for (final a in rest) a.app.label], ['某游戏', '某阅读']);
    });

    test('只有一天数据时按一天算平均', () {
      final advice = LockAdvisor.suggest(
          const [AppUsage(package: 'com.smile.gifmaker', label: '快手', minutes: 50)],
          days: 1);
      expect(advice.single.averageMinutes, 50);
      expect(advice.single.suggestedMinutes, 30);
    });
  });

  testWidgets('一开始进来就看到狗版的你的建议：默认都勾上，能改额度，一键设好，一个 App 一个限时', (tester) async {
    final service = FakeLockService();
    await pumpAdvice(tester, service, () async => (apps: week, days: 7));

    expect(find.text('狗版的你帮你看了最近 7 天'), findsOneWidget);
    expect(find.text('最费时间的是：微信、抖音、某阅读'), findsOneWidget);
    expect(find.text('日均 1 小时 40 分'), findsOneWidget);
    expect(find.text('每天 1 小时 ▾'), findsOneWidget);
    expect(find.text('设好这 3 个限时'), findsOneWidget);
    expect(find.textContaining('得学两声狗叫'), findsWidgets);

    // 某阅读不要了；抖音改成每天 45 分钟
    await tester.tap(find.bySemanticsLabel('给某阅读设限时'));
    await tester.pumpAndSettle();
    expect(find.text('设好这 2 个限时'), findsOneWidget);
    await tester.tap(find.text('每天 1 小时 ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每天 45 分钟').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('设好这 2 个限时'));
    await tester.pumpAndSettle();
    expect([for (final l in service.locks) (l.labels.single, l.minutes)], [('抖音', 45), ('某游戏', 15)]);
    // 设好以后列表里有这两个，建议只剩没设的某阅读；刚才取消勾选的，还是不勾
    expect(find.text('还有几个也挺上头'), findsOneWidget);
    expect(find.text('先勾上要管的 App'), findsOneWidget);
  });

  testWidgets('拦截的权限还没开：先去开权限', (tester) async {
    final service = FakeLockService(isReady: false);
    await pumpAdvice(tester, service, () async => (apps: week, days: 7));
    await tester.tap(find.text('先打开权限，再设限时'));
    await tester.pumpAndSettle();
    expect(service.setups, 1);
  });

  testWidgets('没开使用情况访问权限：说清楚开了才能帮你看', (tester) async {
    await pumpAdvice(tester, FakeLockService(), () async => throw PlatformException(code: 'NO_PERMISSION'));
    expect(find.text('狗版的你想帮你看看'), findsOneWidget);
  });

  testWidgets('最近没有上头的 App：夸一句，引导自己加', (tester) async {
    await pumpAdvice(
      tester,
      FakeLockService(),
      () async => (apps: const [AppUsage(package: 'com.example.notes', label: '某笔记', minutes: 60)], days: 7),
    );
    expect(find.textContaining('没有特别上头的 App，好狗'), findsOneWidget);
  });
}
