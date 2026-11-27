import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/core/evolution.dart';
import 'package:zwjsg_app/core/history.dart';
import 'package:zwjsg_app/core/usage_channel.dart';
import 'package:zwjsg_app/features/card/card_page.dart';
import 'package:zwjsg_app/features/dex/evolution_section.dart';
import 'package:zwjsg_app/widgets/my_avatar.dart';
import 'package:zwjsg_app/widgets/unlock_celebration.dart';

import 'widget_test.dart' show pumpApp, usePhoneScreen;

/// [n] 天前
String ago(int n) {
  final d = DateTime.now();
  return AppState.localDate(DateTime(d.year, d.month, d.day - n));
}

DayRecord day(int daysAgo, int stage) => DayRecord(
      date: ago(daysAgo),
      goalMinutes: 180,
      minutes: stage == 0 ? 20 : 130,
      percent: stage == 0 ? 11 : 72,
      percentLabel: stage == 0 ? '11%' : '72%',
      stage: stage,
    );

/// 从昨天往前连续做人 [n] 天
List<DayRecord> humanDays(int n) => [for (var i = 1; i <= n; i++) day(i, 0)];

Future<AppState> newState([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues({'onboarded': true, ...prefs});
  return AppState(await SharedPreferences.getInstance());
}

UsageSnapshot used(int minutes) =>
    UsageSnapshot(totalMinutes: minutes, pickups: 0, lateNightMinutes: 0, categoryMinutes: const {});

/// 图里穿着哪种进化形态（默认形象）
Evolution? wornOn(WidgetTester tester, Finder avatar) =>
    tester.widget<DogAvatar>(find.descendant(of: avatar, matching: find.byType(DogAvatar))).evolution;

void main() {
  group('规则', () {
    test('连续做人 3 / 7 / 14 / 30 天各解锁一种，按天数从少到多', () {
      expect(kEvolutions.map((i) => i.days), [3, 7, 14, 30]);
      expect(kEvolutions.map((i) => i.name), ['学霸', '西装精英', '养生大师', '头顶光环']);
      expect(kEvolutions.map((i) => i.evolution), Evolution.values);
      expect(evolutionsFor(2), isEmpty);
      expect(evolutionsFor(3), [Evolution.scholar]);
      expect(evolutionsFor(13), [Evolution.scholar, Evolution.elite]);
      expect(evolutionsFor(14), [Evolution.scholar, Evolution.elite, Evolution.wellness]);
      expect(evolutionsFor(40), Evolution.values);
    });

    test('解锁弹窗队列里的名字：进化形态带前缀，和犬种分得开', () {
      expect(evolutionInfo(Evolution.elite).unlockKey, 'evo:elite');
      expect(evolutionByUnlockKey('evo:elite')!.name, '西装精英');
      expect(evolutionByUnlockKey('corgi'), isNull);
      expect(evolutionByUnlockKey('evo:unknown'), isNull);
    });

    test('进度那句话：今天还是人算上今天；今天变狗了明天起重新数；中断以后要攒满下一种的天数', () {
      expect(evolutionLine(0, {}, humanToday: true), '再做人 3 天（算上今天），解锁进化形态「学霸」');
      expect(evolutionLine(2, {}, humanToday: true), '今天守住，明天解锁进化形态「学霸」');
      expect(evolutionLine(2, {}, humanToday: false), '明天起连续做人 3 天，解锁进化形态「学霸」');
      // 学霸早就有了，中间断过：下一种要连续 7 天
      expect(evolutionLine(1, {Evolution.scholar}, humanToday: true), '再做人 6 天（算上今天），解锁进化形态「西装精英」');
      expect(evolutionLine(30, Evolution.values.toSet(), humanToday: true), '四种进化形态都解锁了，做人做到头顶冒光');
    });
  });

  group('解锁和穿哪一种', () {
    test('连续做人 3 天（不算今天）解锁学霸：记下日子、排进解锁弹窗，没挑过就穿最新解锁的', () async {
      final state = await newState();
      await state.history.putAll(humanDays(2));
      await state.checkEvolutions();
      expect(state.unlockedEvolutions, isEmpty);
      expect(state.wornEvolution, isNull);

      await state.history.putAll(humanDays(3));
      await state.checkEvolutions();
      expect(state.unlockedEvolutions, {Evolution.scholar});
      expect(state.evolutions[Evolution.scholar], ago(0));
      expect(state.newlyUnlocked, ['evo:scholar']);
      expect(state.wornEvolution, Evolution.scholar);

      // 再查一次不会重复排队
      await state.checkEvolutions();
      expect(state.newlyUnlocked, ['evo:scholar']);
    });

    test('中断只清零连续天数，解锁了的还在；重新打开 App 也在', () async {
      final state = await newState();
      await state.history.putAll(humanDays(7));
      await state.checkEvolutions();
      expect(state.unlockedEvolutions, {Evolution.scholar, Evolution.elite});
      expect(state.wornEvolution, Evolution.elite);

      await state.history.put(day(1, 3));
      await state.checkEvolutions();
      expect(state.humanStreakDone, 0);
      expect(state.unlockedEvolutions, {Evolution.scholar, Evolution.elite});

      final again = AppState(await SharedPreferences.getInstance());
      expect(again.unlockedEvolutions, {Evolution.scholar, Evolution.elite});
      expect(again.evolutions[Evolution.elite], ago(0));
    });

    test('自己挑：挑了就穿挑的，挑“不穿”就不穿，没解锁的挑不了；退出登录后清掉', () async {
      final state = await newState();
      await state.history.putAll(humanDays(7));
      await state.checkEvolutions();

      await state.wearEvolution(Evolution.scholar);
      expect(state.wornEvolution, Evolution.scholar);
      await state.wearEvolution(Evolution.halo);
      expect(state.wornEvolution, Evolution.scholar);
      await state.wearEvolution(null);
      expect(state.wornEvolution, isNull);
      expect(AppState(await SharedPreferences.getInstance()).wornEvolution, isNull);

      await state.logout();
      expect(state.unlockedEvolutions, isEmpty);
      expect(state.wornEvolution, isNull);
    });
  });

  group('形象', () {
    Future<AppState> withScholar(WidgetTester tester) async {
      final state = await newState();
      await state.history.putAll(humanDays(3));
      await state.checkEvolutions();
      return state;
    }

    testWidgets('做人时穿上，变狗就脱掉；以前的日子、犬种预览不穿；可以指定看某一种', (tester) async {
      final state = await withScholar(tester);
      await tester.pumpWidget(AppScope(
        state: state,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              MyAvatar(key: Key('human'), stage: 0, size: 60),
              MyAvatar(key: Key('dog'), stage: 2, size: 60),
              MyAvatar(key: Key('past'), stage: 0, size: 60, evolved: false),
              MyAvatar(key: Key('halo'), stage: 0, size: 60, evolution: Evolution.halo),
            ],
          ),
        ),
      ));
      expect(wornOn(tester, find.byKey(const Key('human'))), Evolution.scholar);
      expect(wornOn(tester, find.byKey(const Key('dog'))), isNull);
      expect(wornOn(tester, find.byKey(const Key('past'))), isNull);
      expect(wornOn(tester, find.byKey(const Key('halo'))), Evolution.halo);
    });

    testWidgets('结算卡：做人那天写进化形态的名字和梗；变狗了照旧写犬种', (tester) async {
      usePhoneScreen(tester);
      final state = await withScholar(tester);
      state.debugSetUsage(used(20));
      await tester.pumpWidget(AppScope(state: state, child: MaterialApp(home: CardPage(now: DateTime(2026, 11, 26, 23)))));
      await tester.pumpAndSettle();
      expect(find.text('学霸'), findsOneWidget);
      expect(find.text('三天没变狗，脑子都清醒了'), findsOneWidget);

      state.debugSetUsage(used(130));
      await tester.pumpAndSettle();
      expect(find.text('学霸'), findsNothing);
    });
  });

  group('图鉴和解锁弹窗', () {
    testWidgets('图鉴上面一排四种：解锁了的能换着穿、能不穿，没解锁的写要连续做人几天', (tester) async {
      usePhoneScreen(tester);
      final state = await newState();
      await state.history.putAll(humanDays(7));
      await state.checkEvolutions();
      state.debugSetUsage(used(20));
      await tester.pumpWidget(AppScope(state: state, child: const MaterialApp(home: Scaffold(body: EvolutionSection()))));

      expect(find.text('已解锁 2 / 4'), findsOneWidget);
      expect(find.text('再做人 7 天（算上今天），解锁进化形态「养生大师」'), findsOneWidget);
      expect(find.bySemanticsLabel('学霸，已解锁'), findsOneWidget);
      expect(find.bySemanticsLabel('西装精英，正穿着'), findsOneWidget);
      expect(find.bySemanticsLabel('养生大师，连续做人 14 天解锁'), findsOneWidget);
      expect(find.bySemanticsLabel('头顶光环，连续做人 30 天解锁'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('学霸，已解锁'));
      await tester.pumpAndSettle();
      expect(find.byType(EvolutionSheet), findsOneWidget);
      expect(find.text('三天没变狗，脑子都清醒了'), findsOneWidget);
      await tester.tap(find.text('做人时穿这个'));
      await tester.pumpAndSettle();
      expect(state.wornEvolution, Evolution.scholar);
      expect(find.bySemanticsLabel('学霸，正穿着'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('学霸，正穿着'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('不穿了'));
      await tester.pumpAndSettle();
      expect(state.wornEvolution, isNull);

      // 没解锁的：看得到要穿什么、要连续做人几天，没有按钮
      await tester.tap(find.bySemanticsLabel('头顶光环，连续做人 30 天解锁'));
      await tester.pumpAndSettle();
      expect(find.text('还没解锁：头顶光环，身边冒金光'), findsOneWidget);
      expect(find.textContaining('连续做人 30 天解锁'), findsOneWidget);
      expect(find.text('做人时穿这个'), findsNothing);
      expect(find.text('不穿了'), findsNothing);
    });

    testWidgets('解锁了弹“进化了”：点“穿上看看”就穿上，看过不再弹', (tester) async {
      usePhoneScreen(tester);
      await pumpApp(tester, {
        'onboarded': true,
        'evolutions': '{"scholar":"${ago(5)}","elite":"${ago(0)}"}',
        'evolution_worn': 'scholar',
        'pending_unlocks': ['evo:elite'],
      });

      expect(find.byType(EvolutionUnlockDialog), findsOneWidget);
      final state = AppScope.read(tester.element(find.byType(EvolutionUnlockDialog)));
      expect(find.bySemanticsLabel('解锁进化形态：西装精英'), findsOneWidget);
      expect(find.text('人模人样，可以去面试了'), findsOneWidget);
      expect(find.text('连续做人 7 天'), findsOneWidget);
      expect(state.wornEvolution, Evolution.scholar);

      await tester.tap(find.text('穿上看看'));
      await tester.pumpAndSettle();
      expect(find.byType(EvolutionUnlockDialog), findsNothing);
      expect(state.wornEvolution, Evolution.elite);
      expect(state.newlyUnlocked, isEmpty);
    });
  });
}
