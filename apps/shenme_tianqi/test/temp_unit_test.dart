import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shenme_tianqi/core/api_client.dart';
import 'package:shenme_tianqi/core/app_state.dart';
import 'package:shenme_tianqi/core/models.dart';
import 'package:shenme_tianqi/core/scene.dart';
import 'package:shenme_tianqi/core/temp_unit.dart';
import 'package:shenme_tianqi/features/home/serious_view.dart';
import 'package:shenme_tianqi/features/home/weather_view.dart';

/// 接口给的数字都是摄氏度：现在 9°、体感 7°、逐小时 10°、今天 2–12°
final sample = WeatherData(const {
  'now': {'temp': 9, 'feels_like': 7, 'text': '晴', 'humidity': 36, 'wind_dir': '北风', 'wind_scale': 1},
  'hourly': [
    {'time': '2026-11-18T09:00:00+08:00', 'temp': 10, 'text': '晴', 'pop': 0},
  ],
  'daily': [
    {'date': '2026-11-18', 'temp_max': 12, 'temp_min': 2, 'text_day': '晴'},
  ],
  'view': {
    'cond': 'sunny',
    'outfit': {'key': 'cold', 'label': '外套'},
  },
});

const city = City(locationId: '101010100', name: '北京');

/// 记下每次请求带的单位
class UnitApi extends WeatherApi {
  final units = <String?>[];

  @override
  Future<WeatherData> weather(String locationId, {int? level, String? adm, String? unit}) async {
    units.add(unit);
    return sample;
  }
}

Future<AppState> pumpPage(WidgetTester tester, Widget page, {required String unit}) async {
  // 视口拉高，整页都建出来
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'temp_unit': unit});
  final state = AppState(await SharedPreferences.getInstance());
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp(home: Scaffold(body: page))));
  return state;
}

void main() {
  test('摄氏度换华氏度四舍五入到整数，和服务端的 TempUnitTest 用同一组数', () {
    const pairs = {0: 32, 100: 212, -40: -40, 37: 99, 14: 57, 10: 50, -1: 30, -18: 0, 20: 68, 19: 66};
    pairs.forEach((c, f) {
      expect(TempUnit.fahrenheit.convert(c), f, reason: '$c℃');
      expect(TempUnit.celsius.convert(c), c);
    });
    expect(TempUnit.fahrenheit.deg(14), '57°');
    expect(TempUnit.celsius.deg(-3), '-3°');
    expect(TempUnit.fromKey('f'), TempUnit.fahrenheit);
    expect(TempUnit.fromKey(null), TempUnit.celsius);
    expect(TempUnit.fromKey('k'), TempUnit.celsius);
  });

  test('秋裤的判断说明按单位写阈值', () {
    expect(decisionRule('long_johns', TempUnit.celsius), contains('低于 10°'));
    expect(decisionRule('long_johns', TempUnit.fahrenheit), contains('低于 50°'));
    expect(decisionRule('umbrella', TempUnit.fahrenheit), contains('50%'));
  });

  test('请求都带上单位，换单位后重新取天气，单位存在手机上', () async {
    SharedPreferences.setMockInitialValues({'temp_unit': 'f'});
    final api = UnitApi();
    final state = AppState(await SharedPreferences.getInstance(), api: api);
    expect(state.tempUnit, TempUnit.fahrenheit);

    await state.loadWeather(city);
    await state.loadWeather(city); // 10 分钟内不重复取
    await state.setTempUnit(TempUnit.celsius);
    await state.loadWeather(city); // 秋裤理由这类句子要按新单位重新取
    expect(api.units, ['f', 'c']);

    final reopened = AppState(await SharedPreferences.getInstance());
    expect(reopened.tempUnit, TempUnit.celsius);
  });

  testWidgets('首页按单位显示，切回摄氏度马上变', (tester) async {
    final state = await pumpPage(tester, WeatherView(city: city, weather: sample), unit: 'f');
    expect(find.text('48°'), findsOneWidget); // 现在 9℃
    expect(find.text('体感 45° · 54° / 36°'), findsOneWidget);
    expect(find.text('50°'), findsOneWidget); // 逐小时 10℃
    expect(find.text('36°'), findsOneWidget); // 7 天里的最低 2℃
    expect(find.text('54°'), findsOneWidget); // 7 天里的最高 12℃

    await state.setTempUnit(TempUnit.celsius);
    await tester.pump();
    expect(find.text('9°'), findsOneWidget);
    expect(find.text('体感 7° · 12° / 2°'), findsOneWidget);
    expect(find.text('48°'), findsNothing);
  });

  testWidgets('严肃模式的温度也按单位显示', (tester) async {
    await pumpPage(tester, SeriousView(city: city, weather: sample), unit: 'f');
    expect(find.text('48°\n晴'), findsOneWidget);
  });
}
