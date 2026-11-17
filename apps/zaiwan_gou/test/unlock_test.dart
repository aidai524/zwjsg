import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/features/dex/dex_page.dart';
import 'package:zwjsg_app/widgets/unlock_celebration.dart';

import 'widget_test.dart' show pumpApp, usePhoneScreen;

Finder inDialog(Finder f) => find.descendant(of: find.byType(UnlockDialog), matching: f);

void main() {
  test('上报结果里的新解锁和还没看过的合在一起存；后面的空结果不会冲掉', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final state = AppState(prefs);

    await state.receiveUnlocked(['corgi']);
    await state.receiveUnlocked([]);
    await state.receiveUnlocked(['corgi', 'wolf']);
    expect(state.newlyUnlocked, ['corgi', 'wolf']);
    expect(prefs.getStringList('pending_unlocks'), ['corgi', 'wolf']);

    // App 被关掉再打开，还没看过的还在
    expect(AppState(prefs).newlyUnlocked, ['corgi', 'wolf']);

    await state.markUnlockSeen('corgi');
    expect(state.newlyUnlocked, ['wolf']);
    expect(prefs.getStringList('pending_unlocks'), ['wolf']);
  });

  testWidgets('有新解锁的犬种时弹解锁动画，看过就不再弹', (tester) async {
    usePhoneScreen(tester);
    await pumpApp(tester, {'onboarded': true, 'pending_unlocks': ['corgi']});

    expect(find.byType(UnlockDialog), findsOneWidget);
    expect(find.bySemanticsLabel('解锁新犬种：柯基'), findsOneWidget);
    expect(inDialog(find.text('柯基')), findsOneWidget);
    expect(inDialog(find.text('普通')), findsOneWidget);
    expect(inDialog(find.text('腿短，停不下来')), findsOneWidget);
    expect(inDialog(find.text('解锁条件：短视频类使用最多')), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.byType(UnlockDialog), findsNothing);
    expect((await SharedPreferences.getInstance()).getStringList('pending_unlocks'), isEmpty);
  });

  testWidgets('一次解锁两种就一个个弹；点“去图鉴看看”打开图鉴', (tester) async {
    usePhoneScreen(tester);
    await pumpApp(tester, {'onboarded': true, 'pending_unlocks': ['corgi', 'wolf']});

    expect(inDialog(find.text('柯基')), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    expect(inDialog(find.text('狼')), findsOneWidget);
    expect(inDialog(find.text('传说')), findsOneWidget);
    await tester.tap(find.text('去图鉴看看'));
    await tester.pumpAndSettle();
    expect(find.byType(UnlockDialog), findsNothing);
    expect(find.byType(DexPage), findsOneWidget);
  });

  testWidgets('会员卡不再写“硬核模式”（时间锁免费，苹果 4.10 不许收费）', (tester) async {
    usePhoneScreen(tester);
    await pumpApp(tester, {'onboarded': true});
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.textContaining('硬核模式'), findsNothing);
    expect(find.text('动态结算卡、周报月报、多套形象'), findsOneWidget);
  });
}
