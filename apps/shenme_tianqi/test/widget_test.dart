import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shenme_tianqi/app.dart';
import 'package:shenme_tianqi/core/app_state.dart';
import 'package:shenme_tianqi/core/models.dart';
import 'package:shenme_tianqi/features/home/home_page.dart';

void main() {
  testWidgets('加完城市回到城市列表，不留空白的搜索页', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'onboarded': true,
      'cities': '[{"location_id":"101010100","name":"北京","is_home":true}]',
    });
    final state = AppState(await SharedPreferences.getInstance());
    await tester.pumpWidget(AppScope(state: state, child: ShenmeTianqiApp(state: state)));
    await tester.pumpAndSettle();

    final router = GoRouter.of(tester.element(find.byType(HomePage)));
    router.push('/cities');
    await tester.pumpAndSettle();
    router.push('/city-search');
    await tester.pumpAndSettle();
    expect(find.text('加个城市'), findsOneWidget);

    // 和搜索页选中城市时的顺序一样：先改状态，紧接着返回
    await state.addCity(const CityHit(locationId: '101070101', name: '沈阳', adm: '辽宁省'));
    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('我的城市'), findsOneWidget);
    expect(find.text('加个城市'), findsNothing);
  });

  // 这个测试会加载全部页面，任何一页编译不过都会失败
  testWidgets('首次打开进入欢迎页', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final state = AppState(await SharedPreferences.getInstance());
    await tester.pumpWidget(AppScope(state: state, child: ShenmeTianqiApp(state: state)));
    await tester.pumpAndSettle();

    expect(find.text('选个城市，开始'), findsOneWidget);
  });

  testWidgets('所有衣服档 × 天气状态的形象都能画出来', (tester) async {
    for (final t in WeatherTemp.values) {
      for (final c in WeatherCond.values) {
        await tester.pumpWidget(MaterialApp(home: Center(child: WeatherAvatar(temp: t, cond: c, size: 120))));
        expect(tester.takeException(), isNull, reason: '$t / $c');
      }
    }
  });

  test('接口里的字符串能映射到形象状态', () {
    expect(weatherCondFromKey('heavy_rain'), WeatherCond.heavyRain);
    expect(weatherCondFromKey('unknown'), WeatherCond.sunny);
    expect(weatherTempFromKey('freezing'), WeatherTemp.freezing);
  });
}
