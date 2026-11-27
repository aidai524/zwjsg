import 'dart:io';

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/core/history.dart';
import 'package:zwjsg_app/core/dog_meter.dart';
import 'package:zwjsg_app/core/home_widget.dart';
import 'package:zwjsg_app/core/usage_channel.dart';

import 'avatar_test.dart' show FakeApi, MemoryAvatarStore, stickerPng, whiteSticker;
import 'me_features_test.dart' show FakeReminders;

/// 假的原生小组件：记下 App 交过去的配置和叫重画的次数
class FakeBridge implements HomeWidgetBridge {
  FakeBridge([this.dir]);

  final String? dir;
  final configs = <DogWidgetConfig>[];
  int reloads = 0;

  @override
  Future<String?> directory() async => dir;

  @override
  Future<void> configure(DogWidgetConfig config) async => configs.add(config);

  @override
  Future<void> reload() async => reloads++;
}

Future<AppState> newState({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({'privacy_version': AppState.privacyVersion, 'onboarded': true, ...prefs});
  return AppState(await SharedPreferences.getInstance(), reminders: FakeReminders(), api: FakeApi(), avatars: MemoryAvatarStore());
}

/// iOS 屏幕使用时间的原生通道：返回在监控、到了第 [stage] 阶段
void mockScreenTime(WidgetTester tester, int Function() stage) {
  const channel = MethodChannel('zwjsg/screen_time');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => {
        'authorization': 'approved',
        'categories': 13,
        'monitoring': true,
        'goalMinutes': 180,
        'thresholds': [54, 108, 162, 216, 270],
        'stage': stage(),
      });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
}

Directory tempDir() {
  final dir = Directory.systemTemp.createTempSync('gou_widget_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

void main() {
  test('数据来源看 App 拿到的是什么：真实分钟数、只有阶段、还没拿到', () {
    const real = UsageSnapshot(totalMinutes: 95, pickups: 30, lateNightMinutes: 0, categoryMinutes: {});
    const stageOnly = UsageSnapshot(totalMinutes: 108, pickups: 0, lateNightMinutes: 0, categoryMinutes: {}, stageOnly: true);
    expect(HomeWidgetSync.sourceFor(real), DogWidgetSource.usage);
    expect(HomeWidgetSync.sourceFor(stageOnly), DogWidgetSource.screenTime);
    expect(HomeWidgetSync.sourceFor(UsageSnapshot.unavailable), DogWidgetSource.none);
  });

  testWidgets('读过使用情况之后才交配置：规则和文案照搬 DogMeter，拿不到数据时让小组件提示打开 App', (tester) async {
    final state = await newState(prefs: {'goal_minutes': 300});
    final bridge = FakeBridge();
    final sync = HomeWidgetSync(state, bridge: bridge);

    // 刚打开 App、还没读过使用情况：先不交，免得小组件闪一下“打开 App 开权限”
    await tester.runAsync(sync.sync);
    expect(bridge.configs, isEmpty);

    await tester.runAsync(state.refreshUsage); // 测试环境拿不到权限 → 没有数据
    await tester.runAsync(sync.sync);
    final config = bridge.configs.single;
    expect(config.ready, isTrue);
    expect(config.source, DogWidgetSource.none);
    expect(config.toMap(), {
      'ready': true,
      'source': 'none',
      'goal_minutes': 300,
      'thresholds': DogMeter.stageThresholds,
      'stage_names': DogMeter.stageNames,
      'quips': DogMeter.quips,
      'next_change': DogMeter.nextChange,
    });

    // 没变化就不重复交；改了目标再交
    await tester.runAsync(sync.sync);
    expect(bridge.configs, hasLength(1));
    await tester.runAsync(() => state.setGoalTier(GoalTier.hooked));
    await tester.runAsync(sync.sync);
    expect(bridge.configs.last.goalMinutes, 480);
  });

  testWidgets('还没做完引导时小组件提示打开 App', (tester) async {
    final state = await newState(prefs: {'onboarded': false});
    final bridge = FakeBridge();
    await tester.runAsync(state.refreshUsage);
    await tester.runAsync(HomeWidgetSync(state, bridge: bridge).sync);
    expect(bridge.configs.single.ready, isFalse);
  });

  testWidgets('iOS 开了屏幕使用时间：小组件读阶段；App 里阶段变了叫小组件重画', (tester) async {
    var stage = 2;
    mockScreenTime(tester, () => stage);
    final state = await newState();
    final bridge = FakeBridge();
    final sync = HomeWidgetSync(state, bridge: bridge);

    await tester.runAsync(state.refreshUsage);
    await tester.runAsync(sync.sync);
    expect(bridge.configs.single.source, DogWidgetSource.screenTime);
    expect(bridge.reloads, 0, reason: '刚交过配置，小组件已经重画了');

    stage = 3;
    await tester.runAsync(state.refreshUsage);
    await tester.runAsync(sync.sync);
    expect(bridge.reloads, 1);
    expect(bridge.configs, hasLength(1));

    await tester.runAsync(state.refreshUsage);
    await tester.runAsync(sync.sync);
    expect(bridge.reloads, 1, reason: '阶段没变不叫');
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('画好 6 张形象图（阶段 0–5）；换了预设形象、拍了新形象、换了做人时穿的进化形态才重画', (tester) async {
    final dir = tempDir();
    final state = await newState();
    final bridge = FakeBridge(dir.path);
    final sync = HomeWidgetSync(state, bridge: bridge);

    await tester.runAsync(sync.sync);
    final names = dir.listSync().map((f) => f.uri.pathSegments.last).toSet();
    expect(names, {for (var s = 0; s <= 5; s++) HomeWidgetSync.fileName(s), WidgetImages.versionFile});
    expect(File('${dir.path}/${WidgetImages.versionFile}').readAsStringSync(), 'v$dogAvatarArtVersion:ahoge:plain');
    expect(bridge.reloads, 1);

    await tester.runAsync(sync.sync);
    expect(bridge.reloads, 1, reason: '形象没变不重画');

    await tester.runAsync(() => state.setAvatarPreset(AvatarPreset.bun));
    await tester.runAsync(sync.sync);
    expect(bridge.reloads, 2);
    expect(File('${dir.path}/${WidgetImages.versionFile}').readAsStringSync(), 'v$dogAvatarArtVersion:bun:plain');

    // 拍了新形象就用拍照形象
    final png = await stickerPng(tester, await whiteSticker(tester));
    await tester.runAsync(() => state.setPhotoAvatar(png));
    await tester.runAsync(sync.sync);
    expect(bridge.reloads, 3);
    expect(File('${dir.path}/${WidgetImages.versionFile}').readAsStringSync(),
        'v$dogAvatarArtVersion:${WidgetImages.fingerprint(png)}:plain');

    // 连续做人 3 天解锁了「学霸」：做人那张换成穿着它的
    await tester.runAsync(() => state.history.putAll([
          for (var i = 1; i <= 3; i++)
            DayRecord(date: AppState.localDate(DateTime.now().subtract(Duration(days: i))), goalMinutes: 180,
                minutes: 20, percent: 11, percentLabel: '11%', stage: 0),
        ]));
    await tester.runAsync(state.checkEvolutions);
    await tester.runAsync(sync.sync);
    expect(bridge.reloads, 4);
    expect(File('${dir.path}/${WidgetImages.versionFile}').readAsStringSync(),
        'v$dogAvatarArtVersion:${WidgetImages.fingerprint(png)}:scholar');

    await tester.runAsync(() => state.wearEvolution(null));
    await tester.runAsync(sync.sync);
    expect(bridge.reloads, 5);
    expect(File('${dir.path}/${WidgetImages.versionFile}').readAsStringSync(), endsWith(':plain'));
  });

  test('形象图的文件名', () {
    expect(HomeWidgetSync.fileName(0), 'dog_0.png');
    expect(HomeWidgetSync.fileName(5), 'dog_5.png');
    expect(listEquals(DogMeter.stageThresholds, [30, 60, 90, 120, 150]), isTrue);
  });
}
