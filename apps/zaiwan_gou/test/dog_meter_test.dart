import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zwjsg_app/core/breeds.dart';
import 'package:zwjsg_app/core/dog_meter.dart';
import 'package:zwjsg_app/core/usage_channel.dart';

void main() {
  test('阶段与后端阈值一致', () {
    expect(DogMeter.stageFor(0), 0);
    expect(DogMeter.stageFor(29), 0);
    expect(DogMeter.stageFor(30), 1);
    expect(DogMeter.stageFor(72), 2);
    expect(DogMeter.stageFor(134), 4);
    expect(DogMeter.stageFor(150), 5);
  });

  test('狗度按目标计算', () {
    expect(DogMeter.percentFor(130, 180), 72);
    expect(DogMeter.minutesToNextStage(130, 180), 32); // 90% = 162 分钟
    expect(DogMeter.minutesToNextStage(300, 180), isNull);
  });

  test('犬种按模式判定，做人当天没有犬种', () {
    const human = UsageSnapshot(totalMinutes: 20, pickups: 10, lateNightMinutes: 0, categoryMinutes: {});
    expect(judgeBreed(human, 180), isNull);

    const night = UsageSnapshot(totalMinutes: 200, pickups: 50, lateNightMinutes: 90, categoryMinutes: {'video': 150});
    expect(judgeBreed(night, 180), 'husky');

    const video = UsageSnapshot(totalMinutes: 200, pickups: 50, lateNightMinutes: 0, categoryMinutes: {'video': 150, 'social': 30});
    expect(judgeBreed(video, 180), 'corgi');

    const game = UsageSnapshot(totalMinutes: 200, pickups: 50, lateNightMinutes: 0, categoryMinutes: {'game': 150, 'video': 30});
    expect(judgeBreed(game, 180), 'collie');

    const work = UsageSnapshot(totalMinutes: 200, pickups: 50, lateNightMinutes: 0, categoryMinutes: {'social': 100, 'productivity': 60, 'video': 30});
    expect(judgeBreed(work, 180), 'shiba');
  });

  test('每日目标三档：3、5、8 小时，和后端 config/dog.php 的 goal_tiers 一致', () {
    expect([for (final t in GoalTier.values) t.minutes], [180, 300, 480]);
    expect([for (final t in GoalTier.values) t.label], ['正常使用', '重度使用', '无可自拔']);
    final php = File('../../backends/zaiwan_gou_api/config/dog.php').readAsStringSync();
    expect(RegExp(r"'goal_tiers' => \[([0-9, ]+)\]").firstMatch(php)?.group(1), '180, 300, 480');
  });

  test('旧版本自己设的小时数换成最接近的一档，正好在中间取严的', () {
    expect(GoalTier.nearest(60), GoalTier.normal);
    expect(GoalTier.nearest(240), GoalTier.normal);
    expect(GoalTier.nearest(241), GoalTier.heavy);
    expect(GoalTier.nearest(390), GoalTier.heavy);
    expect(GoalTier.nearest(420), GoalTier.hooked);
    expect(GoalTier.nearest(480), GoalTier.hooked);
  });
}
