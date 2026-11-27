import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shenme_tianqi/app.dart';
import 'package:shenme_tianqi/core/app_state.dart';
import 'package:shenme_tianqi/core/models.dart';
import 'package:shenme_tianqi/features/home/home_page.dart';
import 'package:shenme_tianqi/core/api_client.dart';
import 'package:shenme_tianqi/features/home/serious_view.dart';
import 'package:shenme_tianqi/features/home/weather_detail_page.dart';
import 'package:shenme_tianqi/features/home/weather_view.dart';
import 'package:shenme_tianqi/features/privacy/privacy_page.dart';
import 'package:shenme_tianqi/widgets/common.dart';

void main() {
  testWidgets('加完城市回到城市列表，不留空白的搜索页', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'privacy_version': AppState.privacyVersion,
      'onboarded': true,
      'cities': '[{"location_id":"101010100","name":"北京","is_home":true}]',
    });
    final state = AppState(await SharedPreferences.getInstance());
    await tester.pumpWidget(AppScope(state: state, child: ShenmeTianqiApp(state: state)));
    await tester.pumpAndSettle();

    final router = GoRouter.of(tester.element(find.byType(HomePage)));
    router.push('/cities');
    await tester.pumpAndSettle();
    // “天气服务由和风天气驱动”只在设置页（2026-11-19 用户要求）
    expect(find.text(QWeatherCredit.label), findsNothing);
    router.push('/city-search');
    await tester.pumpAndSettle();
    expect(find.text('加个城市'), findsOneWidget);
    expect(find.text(QWeatherCredit.label), findsNothing);

    // 和搜索页选中城市时的顺序一样：先改状态，紧接着返回
    await state.addCity(const CityHit(locationId: '101070101', name: '沈阳', adm: '辽宁省'));
    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('我的城市'), findsOneWidget);
    expect(find.text('加个城市'), findsNothing);
  });

  // 这个测试会加载全部页面，任何一页编译不过都会失败
  testWidgets('首次打开先看隐私政策，同意后进入欢迎页', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final state = AppState(await SharedPreferences.getInstance());
    await tester.pumpWidget(AppScope(state: state, child: ShenmeTianqiApp(state: state)));
    await tester.pumpAndSettle();
    expect(find.text('用之前，先说清楚'), findsOneWidget);

    // 同意之前，别的页面都进不去
    GoRouter.of(tester.element(find.text('用之前，先说清楚'))).go('/');
    await tester.pumpAndSettle();
    expect(find.text('用之前，先说清楚'), findsOneWidget);

    await tester.tap(find.text('看完整的《隐私政策》'));
    await tester.pumpAndSettle();
    expect(find.text(PrivacyPage.summary), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(find.text('选个城市，开始'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getInt('privacy_version'), AppState.privacyVersion);
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

    testWidgets('“由和风天气驱动”只在设置页；严肃模式、详情页和有预警横幅的首页原样显示接口给的来源', (tester) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      Map<String, dynamic> json({bool banner = false}) => {
            'now': {'temp': 9, 'feels_like': 7, 'text': '晴', 'humidity': 36, 'wind_dir': '北风', 'wind_scale': 1},
            'view': {
              'cond': 'sunny',
              'outfit': {'key': 'cold'},
              if (banner)
                'banner_warnings': [
                  {'title': '海上大风防御提醒', 'text': '原文', 'sender': '某气象台', 'pub_time': '2026-11-19T08:00+08:00', 'color': '', 'type_name': '大风'},
                ],
            },
            'air': {'aqi': 28, 'category': '优', 'primary': ''},
            'attribution': '预警信息来自当地气象部门',
            'attributions': [url, statement],
          };
      const city = City(locationId: '101010100', name: '北京');
      SharedPreferences.setMockInitialValues({'cities': '[{"location_id":"101010100","name":"北京","is_home":true}]'});
      final state = AppState(await SharedPreferences.getInstance(), api: _FixedWeather(WeatherData(json())));
      await state.loadWeather(city);

      Future<void> pump(Widget page) async {
        await tester.pumpWidget(AppScope(state: state, child: MaterialApp(home: Scaffold(body: page))));
        await tester.pumpAndSettle();
      }

      // 首页：没有预警横幅时什么都不标
      await pump(WeatherView(city: city, weather: WeatherData(json())));
      expect(find.text(QWeatherCredit.label), findsNothing);
      expect(find.text(statement), findsNothing);
      // 有预警横幅：原样显示来源，但不写“由和风天气驱动”
      await pump(WeatherView(city: city, weather: WeatherData(json(banner: true))));
      expect(find.text(QWeatherCredit.label), findsNothing);
      expect(find.text(statement), findsOneWidget);
      expect(find.text(url), findsOneWidget);

      for (final page in [SeriousView(city: city, weather: WeatherData(json())), const WeatherDetailPage(locationId: '101010100')]) {
        await pump(page);
        expect(find.text(QWeatherCredit.label), findsNothing, reason: '${page.runtimeType}');
        expect(find.text(statement), findsOneWidget, reason: '${page.runtimeType}');
        expect(find.text(url), findsOneWidget, reason: '${page.runtimeType}');
      }

      // 设置页那种用法：名称和链接都在
      await pump(const QWeatherCredit(attributions: [url]));
      expect(find.text(QWeatherCredit.label), findsOneWidget);
      await pump(const QWeatherCredit(brand: false));
      expect(find.text(QWeatherCredit.label), findsNothing);
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

/// 每次都给同一份天气
class _FixedWeather extends WeatherApi {
  _FixedWeather(this.data);
  final WeatherData data;

  @override
  Future<WeatherData> weather(String locationId, {int? level, String? adm, String? unit}) async => data;
}
