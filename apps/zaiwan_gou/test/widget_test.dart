import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zwjsg_app/app.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/features/onboarding/goal_page.dart';
import 'package:zwjsg_app/features/today/today_page.dart';

/// 默认 800x600 不是手机比例，页面会误报溢出
void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> pumpApp(WidgetTester tester, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final state = AppState(await SharedPreferences.getInstance());
  await tester.pumpWidget(AppScope(state: state, child: ZwjsgApp(state: state)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首次打开进入引导页', (tester) async {
    usePhoneScreen(tester);
    await pumpApp(tester, {});

    expect(find.text('开始变身'), findsOneWidget);
  });

  testWidgets('修改每日目标后回到上一页', (tester) async {
    usePhoneScreen(tester);
    await pumpApp(tester, {'onboarded': true});
    final today = tester.element(find.byType(TodayPage));
    final router = GoRouter.of(today);
    router.push('/goal?edit=1');
    await tester.pumpAndSettle();
    expect(find.byType(GoalPage), findsOneWidget);

    // 和目标页保存时的顺序一样：先改状态，紧接着返回
    await AppScope.read(today).setGoal(120);
    router.pop();
    await tester.pumpAndSettle();

    expect(find.byType(GoalPage), findsNothing);
  });

  testWidgets('状态栏图标跟随页面底色，离开页面后恢复', (tester) async {
    usePhoneScreen(tester);
    await pumpApp(tester, {'onboarded': true});
    final router = GoRouter.of(tester.element(find.byType(TodayPage)));

    // Brightness.dark 是深色图标（浅底页面），Brightness.light 是白色图标（深底页面）
    Brightness? icons() => SystemChrome.latestStyle?.statusBarIconBrightness;
    const pages = {
      '/login': Brightness.dark,
      '/avatar': Brightness.dark,
      '/goal?edit=1': Brightness.dark,
      '/hardcore': Brightness.dark,
      '/card': Brightness.light, // 结算卡是深色底
    };

    final seen = <String, Brightness?>{'首页': icons()};
    final want = <String, Brightness>{'首页': Brightness.dark};
    for (final MapEntry(key: path, value: brightness) in pages.entries) {
      router.push(path);
      await tester.pumpAndSettle();
      seen[path] = icons();
      want[path] = brightness;

      router.pop();
      await tester.pumpAndSettle();
      seen['离开 $path'] = icons();
      want['离开 $path'] = Brightness.dark;
    }

    expect(seen, want);
  });
}
