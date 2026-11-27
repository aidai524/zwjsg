import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/core/breeds.dart';
import 'package:zwjsg_app/core/festivals.dart';
import 'package:zwjsg_app/features/dex/breed_sheet.dart';
import 'package:zwjsg_app/core/history.dart';
import 'package:zwjsg_app/core/usage_channel.dart';

/// 安卓的一天：用了 [minutes] 分钟，按 3 小时的额度算
DayRecord day(String date, int minutes, {int goal = 180}) {
  final pct = (minutes / goal * 100).round();
  final stage = [30, 60, 90, 120, 150].where((t) => pct >= t).length;
  return DayRecord(date: date, goalMinutes: goal, minutes: minutes, percent: pct, percentLabel: '$pct%', stage: stage);
}

/// iOS 的一天：只知道阶段
DayRecord iosDay(String date, int stage) => DayRecord(
    date: date, goalMinutes: 180, minutes: 0, percent: 0, percentLabel: '', stage: stage, stageOnly: true);

/// 安卓的今天：一共 [total] 分钟，各类各多少
UsageSnapshot today(int total, {Map<String, int> categories = const {}, int pickups = 40, int lateNight = 0}) =>
    UsageSnapshot(totalMinutes: total, pickups: pickups, lateNightMinutes: lateNight, categoryMinutes: categories);

void main() {
  group('稀有「串串」：同一天里短视频、游戏、聊天办公三样各占两成以上', () {
    test('三样都沾就是串串；缺一样（游戏不到两成）就按占大头的算', () {
      expect(judgeBreed(today(120, categories: {'video': 40, 'game': 30, 'social': 20, 'productivity': 10}), 180), 'mutt');
      expect(judgeBreed(today(120, categories: {'video': 70, 'game': 20, 'social': 30}), 180), 'corgi');
    });

    test('还是人的那天不算；比哈士奇、吉娃娃先判（稀有的优先）', () {
      expect(judgeBreed(today(50, categories: {'video': 20, 'game': 15, 'social': 15}), 180), isNull);
      expect(
        judgeBreed(today(120, categories: {'video': 40, 'game': 40, 'social': 40}, pickups: 200, lateNight: 60), 180),
        'mutt',
      );
    });
  });

  group('稀有「金毛寻回犬」：今天之前连续 4 天一天比一天刷得少，昨天、今天都还是狗', () {
    final d = ['2026-11-21', '2026-11-22', '2026-11-23', '2026-11-24'];

    test('安卓比分钟数：一天比一天少就是；有一天没少、少记一天、昨天已经做回人了都不算', () {
      expect(isRetrieverTrend([day(d[0], 240), day(d[1], 200), day(d[2], 150), day(d[3], 100)]), isTrue);
      expect(isRetrieverTrend([day(d[0], 240), day(d[1], 240), day(d[2], 150), day(d[3], 100)]), isFalse);
      expect(isRetrieverTrend([null, day(d[1], 200), day(d[2], 150), day(d[3], 100)]), isFalse);
      expect(isRetrieverTrend([day(d[1], 200), day(d[2], 150), day(d[3], 100)]), isFalse);
      // 昨天 40 分钟（22%），已经做回人了：今天再变狗是反弹，不算
      expect(isRetrieverTrend([day(d[0], 200), day(d[1], 150), day(d[2], 100), day(d[3], 40)]), isFalse);
    });

    test('iOS 只知道每天到过的最高阶段：得一天低一个阶段', () {
      expect(isRetrieverTrend([iosDay(d[0], 4), iosDay(d[1], 3), iosDay(d[2], 2), iosDay(d[3], 1)]), isTrue);
      expect(isRetrieverTrend([iosDay(d[0], 3), iosDay(d[1], 3), iosDay(d[2], 2), iosDay(d[3], 1)]), isFalse);
    });

    test('今天还是狗才算；比串串先判；iOS 拿不到分类，平时是柯基', () {
      final before = [day(d[0], 240), day(d[1], 200), day(d[2], 150), day(d[3], 100)];
      final mixed = today(120, categories: {'video': 40, 'game': 40, 'social': 40});
      expect(judgeBreed(mixed, 180, before: before), 'retriever');
      expect(judgeBreed(today(30), 180, before: before), isNull);
      const ios = UsageSnapshot(totalMinutes: 54, pickups: 0, lateNightMinutes: 0, categoryMinutes: {}, stageOnly: true);
      expect(judgeBreed(ios, 180), 'corgi');
      expect(
        judgeBreed(ios, 180, before: [iosDay(d[0], 4), iosDay(d[1], 3), iosDay(d[2], 2), iosDay(d[3], 1)]),
        'retriever',
      );
    });
  });

  test('犬种表和后端 config/dog.php 一致（名字、稀有度、梗、怎么变成，顺序也一样）', () {
    final php = File('../../backends/zaiwan_gou_api/config/dog.php').readAsStringSync();
    final rows = RegExp(r"'(\w+)' => \['name' => '([^']*)', 'rarity' => '(\w+)', 'quip' => '([^']*)', 'rule' => '([^']*)'")
        .allMatches(php)
        .map((m) => [m[1], m[2], m[3], m[4], m[5]])
        .toList();
    expect(rows, [
      for (final b in kBreeds) [b.key, b.name, b.rarity.name, b.quip, b.rule],
    ]);
    expect(kBreeds.where((b) => b.rarity == Rarity.rare).map((b) => b.key), ['mutt', 'retriever']);
  });

  group('安卓：从系统补上前几天以后，今天变金毛寻回犬', () {
    tearDown(() => UsageChannel.debugSupportedOverride = null);

    testWidgets('前 4 天一天比一天少（从系统补上的），今天还是狗', (tester) async {
      UsageChannel.debugSupportedOverride = true;
      final now = DateTime.now();
      String ago(int n) => AppState.localDate(DateTime(now.year, now.month, now.day - n));
      Map<String, Object> past(int n, int minutes) =>
          {'date': ago(n), 'totalMinutes': minutes, 'pickups': 30, 'lateNightMinutes': 0, 'categoryMinutes': {'video': minutes}};
      const channel = MethodChannel('zwjsg/usage');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        return switch (call.method) {
          'hasPermission' => true,
          'getTodayUsage' => {'totalMinutes': 80, 'pickups': 20, 'lateNightMinutes': 0, 'categoryMinutes': {'video': 80}},
          // 系统给的顺序不一定是从早到晚
          'getPastDays' => [past(1, 100), past(3, 200), past(2, 150), past(4, 240), past(5, 230)],
          _ => null,
        };
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

      SharedPreferences.setMockInitialValues({});
      final state = AppState(await SharedPreferences.getInstance());
      await state.refreshUsage();

      expect(state.breedKey, 'retriever');
      expect(state.history.day(ago(0))!.breedKey, 'retriever');
      // 补上的那几天各按各的算：5 天前到 2 天前那段不是一天比一天少（5 天前比 4 天前少），所以 1 天前不是金毛
      expect(state.history.day(ago(1))!.breedKey, 'corgi');
    });
  });

  group('节日限定犬种（2026-11-27）', () {
    const dog = UsageSnapshot(totalMinutes: 130, pickups: 200, lateNightMinutes: 0, categoryMinutes: {'video': 100});
    const human = UsageSnapshot(totalMinutes: 20, pickups: 0, lateNightMinutes: 0, categoryMinutes: {'video': 20});

    test('四个节日的日子和后端 config/dog.php 的 festival_breeds 一致', () {
      final php = File('../../backends/zaiwan_gou_api/config/dog.php').readAsStringSync();
      final section = php.substring(php.indexOf("'festival_breeds' =>"));
      final keys = [for (final f in kFestivals) f.breedKey];
      expect([for (final m in RegExp(r"'(\w+)' => \['(?:every_year|windows)'").allMatches(section)) m.group(1)], keys);
      for (var i = 0; i < kFestivals.length; i++) {
        final f = kFestivals[i];
        final start = section.indexOf("'${f.breedKey}' =>");
        final end = i + 1 < keys.length ? section.indexOf("'${keys[i + 1]}' =>") : section.length;
        final block = section.substring(start, end);
        final fixed = f.everyYear;
        if (fixed != null) {
          final mmdd = '${fixed.$1.toString().padLeft(2, '0')}-${fixed.$2.toString().padLeft(2, '0')}';
          expect(block, contains("'every_year' => '$mmdd'"));
        } else {
          final pairs = [
            for (final m in RegExp(r"\['(\d{4}-\d{2}-\d{2})', '(\d{4}-\d{2}-\d{2})'\]").allMatches(block)) (m.group(1)!, m.group(2)!)
          ];
          expect(pairs, f.windows.values.toList(), reason: f.name);
        }
      }
      // 每个节日对应一个限定犬种
      expect(kFestivals.map((f) => breedByKey(f.breedKey)?.rarity), everyElement(Rarity.limited));
      expect(kBreeds.where((b) => b.rarity == Rarity.limited).map((b) => b.key), keys);
    });

    test('那几天变狗就是限定犬种，比稀有的还先判；还是人、不在节日里的照旧', () {
      expect(judgeBreed(dog, 180, day: DateTime(2027, 1, 1)), 'flag');
      expect(judgeBreed(dog, 180, day: DateTime(2028, 1, 25)), 'wangcai', reason: '2028 年的除夕');
      expect(judgeBreed(dog, 180, day: DateTime(2028, 1, 31)), 'wangcai', reason: '2028 年的初六');
      expect(judgeBreed(dog, 180, day: DateTime(2028, 2, 1)), 'chihuahua', reason: '过了初六照旧按刷法判');
      expect(judgeBreed(dog, 180, day: DateTime(2027, 8, 8)), 'single');
      expect(judgeBreed(dog, 180, day: DateTime(2027, 9, 15)), 'tiangou');
      expect(judgeBreed(human, 180, day: DateTime(2027, 1, 1)), isNull, reason: '还是人就没有');
      // 金毛寻回犬的势头也让给节日
      final trend = [day('2026-12-28', 300), day('2026-12-29', 250), day('2026-12-30', 200), day('2026-12-31', 150)];
      expect(isRetrieverTrend(trend), isTrue);
      expect(judgeBreed(dog, 180, before: trend, day: DateTime(2027, 1, 1)), 'flag');
      expect(judgeBreed(dog, 180, before: trend, day: DateTime(2026, 12, 31)), 'retriever');
    });

    test('图鉴：没拿到的限定犬种只在节日那几天出现，拿到了一直在；在节日里写还剩几天', () {
      final permanent = kBreeds.where((b) => b.rarity != Rarity.limited).length;
      expect(dexBreeds({}, DateTime(2026, 11, 27)), hasLength(permanent));
      expect(dexBreeds({}, DateTime(2027, 2, 6)).map((b) => b.key), contains('wangcai'));
      expect(dexBreeds({}, DateTime(2027, 2, 6)).map((b) => b.key), isNot(contains('single')));
      expect(dexBreeds({'single'}, DateTime(2026, 11, 27)).map((b) => b.key), contains('single'));

      final spring = festivalOf('wangcai')!;
      expect(spring.daysLeft(DateTime(2027, 2, 5)), 7);
      expect(spring.daysLeft(DateTime(2027, 2, 11, 23, 30)), 1);
      expect(spring.daysLeft(DateTime(2027, 2, 12)), isNull);
      expect(festivalOf('flag')!.window(2031), (DateTime(2031), DateTime(2031)));
      expect(festivalOf('single')!.window(2031), isNull, reason: '农历节日的表到 2030 年，往后要补');
      expect(festivalOf('corgi'), isNull);

      expect(breedByKey('wangcai')!.limitedWhen(DateTime(2027, 2, 7)), '就是这几天，还剩 5 天；过了没拿到的不再出现，明年再来');
      expect(breedByKey('single')!.limitedWhen(DateTime(2026, 11, 27)), allOf(startsWith('每年七夕才有，下一回是'), contains('8 月 8 日')));
      expect(breedByKey('corgi')!.limitedWhen(DateTime(2026, 11, 27)), isNull);
      expect(breedByKey('tiangou')!.judgedOnIos, isTrue);
    });
  });
}
