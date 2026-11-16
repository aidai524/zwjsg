import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shenme_tianqi/app.dart';
import 'package:shenme_tianqi/core/app_state.dart';
import 'package:shenme_tianqi/core/models.dart';
import 'package:shenme_tianqi/features/home/home_page.dart';
import 'package:shenme_tianqi/features/home/serious_view.dart';
import 'package:shenme_tianqi/features/home/weather_view.dart';
import 'package:shenme_tianqi/widgets/common.dart';

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
    expect(find.text(QWeatherCredit.label), findsOneWidget);
    router.push('/city-search');
    await tester.pumpAndSettle();
    expect(find.text('加个城市'), findsOneWidget);
    expect(find.text(QWeatherCredit.label), findsOneWidget);

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

  group('和风来源标注', () {
    const url = 'https://developer.qweather.com/attribution.html';
    const statement = '当前预警数据可能存在延迟或信息过时，以官方数据发布为准。';

    testWidgets('名称链到官网，网址可以点，其他内容原样显示', (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: QWeatherCredit(
            attributions: const [url, statement],
            opener: (uri) async {
              opened.add('$uri');
              return true;
            },
          ),
        ),
      ));

      await tester.tap(find.text(QWeatherCredit.label));
      await tester.tap(find.text(url));
      await tester.tap(find.text(statement));
      expect(opened, ['https://www.qweather.com', url]);
    });

    testWidgets('链接打不开时给提示', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: QWeatherCredit(opener: (_) async => false)),
      ));

      await tester.tap(find.text(QWeatherCredit.label));
      await tester.pump();
      expect(find.text('打不开链接，稍后再试'), findsOneWidget);
    });

    testWidgets('首页和严肃模式都显示来源和接口给的归因', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      final state = AppState(await SharedPreferences.getInstance());
      final weather = WeatherData(const {
        'now': {'temp': 9, 'feels_like': 7, 'text': '晴', 'humidity': 36, 'wind_dir': '北风', 'wind_scale': 1},
        'view': {'cond': 'sunny', 'outfit': {'key': 'cold'}},
        'attribution': '预警信息来自当地气象部门',
        'attributions': [url, statement],
      });
      const city = City(locationId: '101010100', name: '北京');

      for (final page in [WeatherView(city: city, weather: weather), SeriousView(city: city, weather: weather)]) {
        await tester.pumpWidget(AppScope(
          state: state,
          child: MaterialApp(home: Scaffold(body: page)),
        ));
        await tester.dragUntilVisible(find.text(statement), find.byType(Scrollable).first, const Offset(0, -300));
        expect(find.text(QWeatherCredit.label), findsOneWidget, reason: '${page.runtimeType}');
        expect(find.text(url), findsOneWidget, reason: '${page.runtimeType}');
      }
    });

    test('接口的归因字段能解析出来', () {
      expect(WeatherData(const {'attributions': [url, statement]}).attributions, [url, statement]);
      expect(WeatherData(const {}).attributions, isEmpty);
      expect(Member.fromJson(const {'id': 1, 'nickname': '妈妈', 'weather': {'attributions': [url]}}).attributions, [url]);
    });
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
