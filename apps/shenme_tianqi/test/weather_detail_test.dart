import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shenme_tianqi/core/app_state.dart';
import 'package:shenme_tianqi/core/models.dart';
import 'package:shenme_tianqi/features/home/decision_page.dart';
import 'package:shenme_tianqi/features/home/weather_backdrop.dart';
import 'package:shenme_tianqi/features/home/weather_detail_page.dart';
import 'package:shenme_tianqi/features/home/weather_view.dart';

import 'temp_unit_test.dart' show UnitApi, city, sample;

List<HourItem> hours(List<int?> pops) => [
      for (var i = 0; i < pops.length; i++)
        HourItem(time: DateTime(2026, 11, 19, 8 + i), temp: 10, text: '晴', pop: pops[i]),
    ];

void main() {
  group('每小时下雨的概率', () {
    test('图上面那句话：全是 0 写清楚“都不会下雨”，不再一片空白', () {
      expect(PopChart.summary(hours(List.filled(16, 0))), '接下来 16 小时都不会下雨（概率都是 0%）');
      expect(PopChart.summary(hours([0, 10, 30, 20])), '最高 30%，下雨的可能不大');
      expect(PopChart.summary(hours([0, 60, 80, 20])), '有 2 个小时下雨概率过半，最高 80%');
      expect(PopChart.summary(hours([null, null])), '暂时拿不到逐小时的降水概率');
    });

    testWidgets('每根柱子都写百分比，0% 也写', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PopChart(hours([0, 0, 55])))));
      expect(find.text('0'), findsNWidgets(2));
      expect(find.text('55'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.bySemanticsLabel('10 点：55%'), findsOneWidget);
    });
  });

  testWidgets('首页只到“今天的决定”，点“天气详情”进详情页', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'cities': '[{"location_id":"101010100","name":"北京","is_home":true}]'});
    final state = AppState(await SharedPreferences.getInstance(), api: UnitApi());
    await state.loadWeather(city);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => Scaffold(body: WeatherView(city: city, weather: sample))),
      GoRoute(path: '/detail/:id', builder: (_, s) => WeatherDetailPage(locationId: s.pathParameters['id']!)),
    ]);
    await tester
        .pumpWidget(AppScope(state: state, child: MaterialApp.router(theme: Pop.theme(), routerConfig: router)));
    await tester.pumpAndSettle();

    expect(find.text('今天的决定'), findsOneWidget);
    expect(find.text('接下来 12 小时'), findsNothing);
    expect(find.text('空气质量'), findsNothing);

    await tester.tap(find.text('天气详情'));
    await tester.pumpAndSettle();
    expect(find.text('北京 · 天气详情'), findsOneWidget);
    expect(find.text('接下来 12 小时'), findsOneWidget);
    expect(find.text('未来 1 天'), findsOneWidget);
    expect(find.text('空气质量'), findsOneWidget);
    expect(find.text('湿度和风'), findsOneWidget);
  });

  group('背景动画', () {
    test('每种天气画什么：晴天和高温分开，严肃模式等不认识的不画', () {
      expect(WeatherBackdrop.kindFor('sunny', 'cold'), BackdropKind.sunny);
      expect(WeatherBackdrop.kindFor('sunny', 'hot'), BackdropKind.hot);
      expect(WeatherBackdrop.kindFor('light_rain', 'cool'), BackdropKind.lightRain);
      expect(WeatherBackdrop.kindFor('thunder', 'warm'), BackdropKind.thunder);
      expect(WeatherBackdrop.kindFor('snow', 'freezing'), BackdropKind.snow);
      expect(WeatherBackdrop.kindFor('serious', 'cold'), isNull);
    });

    testWidgets('每种天气都能画，一直在动；开了“减弱动态效果”就停在一帧', (tester) async {
      WeatherBackdrop.animate = true;
      addTearDown(() => WeatherBackdrop.animate = false);
      const conds = ['sunny', 'cloudy', 'light_rain', 'heavy_rain', 'thunder', 'snow', 'wind', 'smog', 'dust', 'humid'];
      for (final c in [...conds, 'sunny/hot']) {
        final parts = c.split('/');
        await tester.pumpWidget(MaterialApp(
          home: SizedBox(
            width: 390,
            height: 800,
            child:
                WeatherBackdrop(key: ValueKey(c), cond: parts.first, outfitKey: parts.length > 1 ? parts.last : 'cool'),
          ),
        ));
        final painter = tester
            .widget<CustomPaint>(
                find.descendant(of: find.byType(WeatherBackdrop), matching: find.byType(CustomPaint)).first)
            .painter! as BackdropPainter;
        final before = painter.clock.value;
        await tester.pump(const Duration(seconds: 2));
        expect(painter.clock.value, isNot(before), reason: c);
        expect(tester.takeException(), isNull, reason: c);
      }

      await tester.pumpWidget(const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: WeatherBackdrop(key: ValueKey('still'), cond: 'snow', outfitKey: 'cold')),
      ));
      final painter = tester
          .widget<CustomPaint>(
              find.descendant(of: find.byType(WeatherBackdrop), matching: find.byType(CustomPaint)).first)
          .painter! as BackdropPainter;
      final still = painter.clock.value;
      await tester.pump(const Duration(seconds: 2));
      expect(painter.clock.value, still);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
