import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shenme_tianqi/core/api_client.dart';
import 'package:shenme_tianqi/core/app_state.dart';
import 'package:shenme_tianqi/core/models.dart';
import 'package:shenme_tianqi/features/cities/cities_page.dart';
import 'package:shenme_tianqi/features/cities/city_search_page.dart';
import 'package:shenme_tianqi/features/home/weather_view.dart';

import 'weather_card_test.dart' show weatherJson, beijing;

/// 记下城市接口的调用；登录后加城市时给一个服务端 id
class CityApi extends WeatherApi {
  final added = <Map<String, Object?>>[];
  final deleted = <int>[];
  final permanent = <int>[];
  var nextId = 100;

  @override
  Future<List<CityHit>> searchCities(String q) async =>
      const [CityHit(locationId: '101280101', name: '广州', adm: '广东省', adm2: '广州')];

  @override
  Future<City> addCity(City c) async {
    added.add({'location_id': c.locationId, 'expires_at': c.toJson()['expires_at'], 'is_home': c.isHome});
    return c.copyWith(serverId: nextId++);
  }

  @override
  Future<void> deleteCity(int serverId) async => deleted.add(serverId);

  @override
  Future<void> makeCityPermanent(int serverId) async => permanent.add(serverId);

  @override
  Future<void> setHomeCity(int serverId) async {}

  /// 首页有一条没有颜色的防御提醒（蓝色和其他颜色只显示横幅）
  @override
  Future<WeatherData> weather(String locationId, {int? level, String? adm, String? unit}) async {
    final j = Map<String, dynamic>.from(weatherJson());
    final view = Map<String, dynamic>.from(j['view'] as Map)
      ..['banner_warnings'] = [
        {'title': '海上大风防御提醒', 'text': '原文', 'sender': '某气象台', 'pub_time': '2026-11-19T08:00+08:00', 'color': '', 'type_name': '大风'},
      ];
    return WeatherData({...j, 'view': view});
  }
}

const guangzhou = CityHit(locationId: '101280101', name: '广州', adm: '广东省');

Future<AppState> newState({Map<String, Object> prefs = const {}, CityApi? api, bool loggedIn = false}) async {
  SharedPreferences.setMockInitialValues({
    'privacy_version': AppState.privacyVersion,
    'onboarded': true,
    'cities': '[{"location_id":"101010100","name":"北京","is_home":true}]',
    if (loggedIn) 'token': 'test-token',
    ...prefs,
  });
  return AppState(await SharedPreferences.getInstance(), api: api ?? CityApi());
}

void main() {
  group('临时城市', () {
    test('看 3 天：今天算第 1 天，第 4 天 0 点到期；最后一天还剩 1 天', () {
      final added = DateTime(2026, 11, 19, 21, 30);
      final expires = City.expiryFor(3, added);
      expect(expires, DateTime(2026, 11, 22));
      final city = City(locationId: '1', name: '广州', expiresAt: expires);
      expect(city.daysLeft(added), 3);
      expect(city.daysLeft(DateTime(2026, 11, 21, 23, 59)), 1);
      expect(city.isExpired(DateTime(2026, 11, 21, 23, 59)), isFalse);
      expect(city.isExpired(DateTime(2026, 11, 22)), isTrue);

      // 存进手机、从服务端读回来，到期时间不变
      final back = City.fromJson(city.toJson());
      expect(back.expiresAt, expires);
      expect(City.fromJson(const City(locationId: '2', name: '北京').toJson()).isTemporary, isFalse);
    });

    test('不再限制 5 个城市', () async {
      final state = await newState();
      for (var i = 0; i < 7; i++) {
        await state.addCity(CityHit(locationId: '10100$i', name: '城市$i'));
      }
      expect(state.cities, hasLength(8));
    });

    test('临时城市不当常驻；改成长期关注后才能设常驻；第一个城市只能长期关注', () async {
      final state = await newState();
      await state.addCity(guangzhou, tempDays: 3);
      final gz = state.cities.last;
      expect(gz.isTemporary, isTrue);
      expect(gz.isHome, isFalse);
      expect(() => state.setHome(gz), throwsA(isA<ApiException>()));

      await state.makePermanent(gz);
      expect(state.cities.last.isTemporary, isFalse);
      await state.setHome(state.cities.last);
      expect(state.homeCity!.name, '广州');

      final empty = await newState(prefs: {'cities': '[]'});
      await empty.addCity(guangzhou, tempDays: 3);
      expect(empty.cities.single.isTemporary, isFalse);
      expect(empty.cities.single.isHome, isTrue);
    });

    test('到期自动移除：正看着的话翻回常驻城市；登录了也让服务端删掉', () async {
      final api = CityApi();
      final state = await newState(api: api, loggedIn: true);
      await state.addCity(guangzhou, tempDays: 1);
      expect(api.added.single['expires_at'], isNotNull);
      expect(api.added.single['is_home'], isFalse);
      expect(state.currentCity, 1);

      await state.pruneExpiredCities(DateTime.now().add(const Duration(days: 1, hours: 1)));
      expect(state.cities.map((c) => c.name), ['北京']);
      expect(state.currentCity, 0);
      expect(api.deleted, [100]);
    });

    test('打开 App 时已经过期的临时城市直接不显示', () async {
      final state = await newState(prefs: {
        'cities': '[{"location_id":"101010100","name":"北京","is_home":true},'
            '{"location_id":"101280101","name":"广州","is_home":false,"expires_at":"2020-01-01T00:00:00.000Z"}]',
      });
      expect(state.cities.map((c) => c.name), ['北京']);
    });

    testWidgets('加城市时选“临时 3 天”，城市列表写还剩几天，能改成长期关注', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final state = await newState();
      // 和 App 一样：城市列表上面推出搜索页，选完退回列表
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const CitiesPage(),
          routes: [GoRoute(path: 'search', builder: (_, __) => const CitySearchPage())],
        ),
      ]);
      await tester.pumpWidget(AppScope(state: state, child: MaterialApp.router(theme: Pop.theme(), routerConfig: router)));
      router.push('/search');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '广州');
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(find.text('广州').last);
      await tester.pumpAndSettle();

      expect(find.text('怎么关注「广州」？'), findsOneWidget);
      await tester.tap(find.text('临时 3 天'));
      await tester.pumpAndSettle();
      expect(state.cities.last.daysLeft(DateTime.now()), 3);

      expect(find.byType(CitiesPage), findsOneWidget);
      expect(find.text('临时 · 还剩 3 天'), findsOneWidget);
      expect(find.textContaining('最多关注'), findsNothing);

      await tester.tap(find.byIcon(Icons.more_vert).last);
      await tester.pumpAndSettle();
      expect(find.text('设为常驻城市'), findsNothing);
      await tester.tap(find.text('改成长期关注'));
      await tester.pumpAndSettle();
      expect(find.text('临时 · 还剩 3 天'), findsNothing);
      expect(state.cities.last.isTemporary, isFalse);
    });
  });

  group('预警横幅', () {
    testWidgets('点 × 关掉这一条，换城市、重开 App 都不再显示', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final state = await newState();
      await state.loadWeather(beijing);
      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(theme: Pop.theme(), home: Scaffold(body: WeatherView(city: beijing, weather: state.weatherOf(beijing.locationId)!))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('海上大风防御提醒'), findsOneWidget);

      await tester.tap(find.byTooltip('关掉这条预警'));
      await tester.pumpAndSettle();
      expect(find.text('海上大风防御提醒'), findsNothing);

      // 重开 App：还记得
      final again = AppState(await SharedPreferences.getInstance(), api: CityApi());
      await again.loadWeather(beijing);
      expect(again.isWarningDismissed(again.weatherOf(beijing.locationId)!.bannerWarnings.single), isTrue);
    });

    test('关掉的记录只留 ${AppState.dismissedWarningDays} 天', () async {
      final state = await newState(prefs: {
        'dismissed_warnings': '{"旧的|2026-01-01":"2026-01-01","新的|x":"${DateTime.now().toIso8601String().substring(0, 10)}"}',
      });
      const old = Warning(title: '旧的', text: '', sender: '', pubTime: '2026-01-01', color: '', typeName: '');
      const fresh = Warning(title: '新的', text: '', sender: '', pubTime: 'x', color: '', typeName: '');
      expect(state.isWarningDismissed(old), isFalse);
      expect(state.isWarningDismissed(fresh), isTrue);
    });
  });
}
