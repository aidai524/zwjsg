import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shenme_tianqi/app.dart';
import 'package:shenme_tianqi/core/api_client.dart';
import 'package:shenme_tianqi/core/app_state.dart';
import 'package:shenme_tianqi/core/models.dart';
import 'package:shenme_tianqi/features/home/home_page.dart';
import 'package:shenme_tianqi/features/privacy/privacy_page.dart';

/// 服务端：推送设置从 me() 来，改设置记下来；error 不为空时改设置失败
class FakeApi extends WeatherApi {
  Map<String, dynamic> me_ = {
    'morning_push_on': true,
    'morning_push_weekday': '07:30:00',
    'morning_push_weekend': '09:00:00',
    'alert_push_on': false,
  };
  final updates = <Map<String, dynamic>>[];
  ApiException? error;

  @override
  Future<Map<String, dynamic>> me() async => me_;

  @override
  Future<void> updateSettings(Map<String, dynamic> settings) async {
    final e = error;
    if (e != null) throw e;
    updates.add(settings);
  }
}

Future<AppState> openSettings(WidgetTester tester, {bool loggedIn = false, FakeApi? api}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'privacy_version': AppState.privacyVersion,
    'onboarded': true,
    'cities': '[{"location_id":"101010100","name":"北京","is_home":true}]',
    if (loggedIn) 'token': 't',
  });
  final state = AppState(await SharedPreferences.getInstance(), api: api ?? FakeApi());
  await tester.pumpWidget(AppScope(state: state, child: ShenmeTianqiApp(state: state)));
  await tester.pumpAndSettle();
  GoRouter.of(tester.element(find.byType(HomePage))).push('/settings');
  await tester.pumpAndSettle();
  return state;
}

Finder switchOf(String title) =>
    find.descendant(of: find.widgetWithText(SwitchListTile, title), matching: find.byType(Switch));

void main() {
  test('推送设置：服务端的时间带秒也能读，只把改了的字段传上去', () {
    final p = PushSettings.fromJson(const {
      'morning_push_on': 1,
      'morning_push_weekday': '07:30:00',
      'morning_push_weekend': null,
      'alert_push_on': false,
    });
    expect(p.morningOn, isTrue);
    expect(p.weekday, '07:30');
    expect(p.weekend, '09:00');
    expect(p.alertOn, isFalse);
    expect(p.copyWith(weekday: '08:00', alertOn: true).changesFrom(p), {'morning_push_weekday': '08:00', 'alert_push_on': true});
    expect(p.changesFrom(p), isEmpty);
  });

  testWidgets('设置页能打开隐私政策', (tester) async {
    await openSettings(tester);
    await tester.scrollUntilVisible(find.text('隐私政策'), 300);
    await tester.tap(find.text('隐私政策'));
    await tester.pumpAndSettle();
    expect(find.text(PrivacyPage.summary), findsOneWidget);
  });

  testWidgets('没登录时推送设置提示先登录', (tester) async {
    await openSettings(tester);
    expect(find.text('推送'), findsOneWidget);
    expect(find.text('登录后可以设置：推送要发到你的账号上。'), findsOneWidget);
    expect(find.text('早安播报'), findsNothing);
  });

  testWidgets('登录后拉推送设置；改时间、开关都传服务端', (tester) async {
    final api = FakeApi();
    final state = await openSettings(tester, loggedIn: true, api: api);
    expect(state.push?.weekday, '07:30');
    expect(find.text('07:30  ›'), findsOneWidget);
    expect(find.text('09:00  ›'), findsOneWidget);
    expect(tester.widget<Switch>(switchOf('预警推送')).value, isFalse);

    await tester.tap(find.text('工作日'));
    await tester.pumpAndSettle();
    expect(find.text('工作日几点推'), findsOneWidget);
    await tester.tap(find.text('08:00'));
    await tester.pumpAndSettle();
    expect(api.updates, [
      {'morning_push_weekday': '08:00'}
    ]);
    expect(find.text('08:00  ›'), findsOneWidget);

    await tester.tap(switchOf('预警推送'));
    await tester.pumpAndSettle();
    expect(api.updates.last, {'alert_push_on': true});

    // 关掉早安播报，时间就收起来
    await tester.tap(switchOf('早安播报'));
    await tester.pumpAndSettle();
    expect(api.updates.last, {'morning_push_on': false});
    expect(find.text('工作日'), findsNothing);
  });

  testWidgets('传服务端失败时开关改回去，并说原因', (tester) async {
    final api = FakeApi()..error = ApiException('网络不太行，稍后再试');
    final state = await openSettings(tester, loggedIn: true, api: api);

    await tester.tap(switchOf('预警推送'));
    await tester.pumpAndSettle();
    expect(state.push?.alertOn, isFalse);
    expect(tester.widget<Switch>(switchOf('预警推送')).value, isFalse);
    expect(find.text('网络不太行，稍后再试'), findsOneWidget);
  });

  testWidgets('推送设置拉不到时可以重试', (tester) async {
    final api = _FailingMe();
    await openSettings(tester, loggedIn: true, api: api);
    expect(find.text('推送设置没拉到：网络不太行，稍后再试'), findsOneWidget);

    api.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('早安播报'), findsOneWidget);
  });
}

class _FailingMe extends FakeApi {
  bool fail = true;

  @override
  Future<Map<String, dynamic>> me() async {
    if (fail) throw ApiException('网络不太行，稍后再试');
    return super.me();
  }
}
