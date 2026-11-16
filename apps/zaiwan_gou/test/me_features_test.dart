import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zwjsg_app/app.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/core/card_exporter.dart';
import 'package:zwjsg_app/core/reminders.dart';
import 'package:zwjsg_app/features/card/card_page.dart';
import 'package:zwjsg_app/features/me/privacy_page.dart';
import 'package:zwjsg_app/features/today/today_page.dart';

class FakeReminders implements ReminderScheduler {
  FakeReminders({this.allow = true});

  bool allow;
  int? scheduled;
  int cancels = 0;

  @override
  Future<bool> requestPermission() async => allow;

  @override
  Future<void> scheduleDaily(int minutesOfDay) async => scheduled = minutesOfDay;

  @override
  Future<void> cancel() async {
    cancels++;
    scheduled = null;
  }

  @override
  Future<bool> handleOpen(VoidCallback onOpen) async => false;
}

class FakeExporter implements CardExporter {
  final saved = <Uint8List>[];
  final shared = <Uint8List>[];
  Object? saveError;

  @override
  Future<Uint8List> capture(GlobalKey boundaryKey) async => Uint8List.fromList([1, 2, 3]);

  @override
  Future<void> save(Uint8List png) async {
    if (saveError != null) throw saveError!;
    saved.add(png);
  }

  @override
  Future<void> share(Uint8List png, {Rect? origin}) async => shared.add(png);
}

void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<AppState> pumpApp(WidgetTester tester, Map<String, Object> prefs, {ReminderScheduler? reminders}) async {
  SharedPreferences.setMockInitialValues({'privacy_version': AppState.privacyVersion, ...prefs});
  final state = AppState(await SharedPreferences.getInstance(), reminders: reminders ?? FakeReminders());
  await tester.pumpWidget(AppScope(state: state, child: ZwjsgApp(state: state)));
  await tester.pumpAndSettle();
  return state;
}

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  group('昵称', () {
    test('去掉首尾空格后 1–16 个字，按字符算', () {
      expect(AppState.nicknameError('  '), '名字不能是空的');
      expect(AppState.nicknameError('狗' * 16), isNull);
      expect(AppState.nicknameError('狗' * 17), '最多 16 个字');
    });

    testWidgets('我的页点名字修改，存在本机', (tester) async {
      usePhoneScreen(tester);
      final state = await pumpApp(tester, {'onboarded': true});
      await go(tester, '/me');

      await tapText(tester, '给自己起个名字');
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(find.text('名字不能是空的'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '  小狗勾 ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('小狗勾'), findsOneWidget);
      expect(state.nickname, '小狗勾');
      expect((await SharedPreferences.getInstance()).getString('nickname'), '小狗勾');
    });
  });

  group('每晚提醒', () {
    testWidgets('没给通知权限时保持关闭；给了就按选的时间排上，关掉后记住时间', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fake = FakeReminders(allow: false);
      final state = AppState(await SharedPreferences.getInstance(), reminders: fake);

      expect(await state.enableReminder(), isFalse);
      expect(state.reminderLabel, '已关闭');
      expect(fake.scheduled, isNull);

      fake.allow = true;
      expect(await state.enableReminder(21 * 60 + 30), isTrue);
      expect(fake.scheduled, 21 * 60 + 30);
      expect(state.reminderLabel, '21:30');

      await state.disableReminder();
      expect(fake.cancels, 1);
      expect(state.reminderLabel, '已关闭');

      await state.enableReminder();
      expect(fake.scheduled, 21 * 60 + 30);
    });

    testWidgets('我的页可以换提醒时间', (tester) async {
      usePhoneScreen(tester);
      final fake = FakeReminders();
      final state = await pumpApp(tester, {'onboarded': true}, reminders: fake);
      await go(tester, '/me');
      expect(find.text('已关闭  ›'), findsOneWidget);

      await tapText(tester, '结算卡提醒');
      await tester.tap(find.text('21:30'));
      await tester.pumpAndSettle();
      expect(fake.scheduled, 21 * 60 + 30);
      expect(state.reminderOn, isTrue);

      await tester.tapAt(const Offset(20, 20)); // 点空白处关掉面板
      await tester.pumpAndSettle();
      expect(find.text('21:30  ›'), findsOneWidget);
    });

    testWidgets('引导最后一步点“开始做人”时顺带打开，默认 22:00', (tester) async {
      usePhoneScreen(tester);
      final fake = FakeReminders();
      final state = await pumpApp(tester, {}, reminders: fake);
      await go(tester, '/goal');
      expect(find.text('每晚 22:00 提醒你看结算卡，可以在“我的”里关掉或改时间。'), findsOneWidget);

      await tapText(tester, '就这么定，开始做人');

      expect(fake.scheduled, 22 * 60);
      expect(state.reminderOn, isTrue);
      expect(find.byType(TodayPage), findsOneWidget);
    });

    testWidgets('退出登录后取消提醒', (tester) async {
      // 不带 token：带了的话，打开提醒时会把时间同步到后端
      SharedPreferences.setMockInitialValues({'onboarded': true});
      final fake = FakeReminders();
      final state = AppState(await SharedPreferences.getInstance(), reminders: fake);
      await state.enableReminder();
      expect(fake.scheduled, 22 * 60);

      // 退出会请求后端：测试的模拟时钟里网络请求不会返回，要在真实异步环境里跑。请求失败也会清掉本机数据
      await tester.runAsync(state.logout);
      expect(fake.scheduled, isNull);
      expect(state.reminderOn, isFalse);
    });
  });

  group('隐私政策', () {
    testWidgets('我的页能打开', (tester) async {
      usePhoneScreen(tester);
      await pumpApp(tester, {'onboarded': true});
      await go(tester, '/me');

      await tapText(tester, '隐私政策');
      expect(find.text(PrivacyPage.summary), findsOneWidget);
      expect(find.text('我们申请的权限'), findsOneWidget);
    });

    testWidgets('还没走完引导时，从登录页也能打开', (tester) async {
      usePhoneScreen(tester);
      await pumpApp(tester, {});
      await go(tester, '/login');

      await tapText(tester, '登录即表示你同意《隐私政策》');
      expect(find.byType(PrivacyPage), findsOneWidget);
    });
  });

  group('结算卡', () {
    Future<FakeExporter> pumpCard(WidgetTester tester) async {
      usePhoneScreen(tester);
      SharedPreferences.setMockInitialValues({'nickname': '小狗勾'});
      final state = AppState(await SharedPreferences.getInstance(), reminders: FakeReminders());
      final exporter = FakeExporter();
      await tester.pumpWidget(AppScope(state: state, child: MaterialApp(home: CardPage(exporter: exporter))));
      await tester.pumpAndSettle();
      return exporter;
    }

    testWidgets('能保存到相册、能分享，卡片上没有占位文字', (tester) async {
      final exporter = await pumpCard(tester);
      expect(find.textContaining('[码]'), findsNothing);
      expect(find.textContaining('[品牌名]'), findsNothing);
      expect(find.text('@小狗勾 · 刷得越多，越像狗'), findsOneWidget);

      await tester.tap(find.text('保存图片'));
      await tester.pumpAndSettle();
      expect(exporter.saved, hasLength(1));
      expect(find.text('已保存到相册'), findsOneWidget);

      await tester.tap(find.text('晒给朋友'));
      await tester.pumpAndSettle();
      expect(exporter.shared, hasLength(1));
    });

    testWidgets('没有相册权限时告诉用户怎么办', (tester) async {
      final exporter = await pumpCard(tester);
      exporter.saveError = const CardExportException('没有相册权限，去系统设置里允许“再玩我是狗”添加照片');

      await tester.tap(find.text('保存图片'));
      await tester.pumpAndSettle();
      expect(find.text('没有相册权限，去系统设置里允许“再玩我是狗”添加照片'), findsOneWidget);
      expect(exporter.saved, isEmpty);
    });
  });
}
