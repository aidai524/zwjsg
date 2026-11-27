import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/core/bark_detector.dart';
import 'package:zwjsg_app/core/call_channel.dart';
import 'package:zwjsg_app/core/usage_channel.dart';
import 'package:zwjsg_app/core/app_lock.dart' show LockService;
import 'package:zwjsg_app/core/dog_meter.dart';
import 'package:zwjsg_app/core/sound_labels.dart';
import 'package:zwjsg_app/features/call/call_screen.dart';
import 'package:zwjsg_app/features/call/call_script.dart';
import 'package:zwjsg_app/features/call/call_voice.dart';
import 'package:zwjsg_app/features/locks/locks_page.dart';
import 'package:zwjsg_app/widgets/call_gate.dart';

import 'locks_test.dart' show FakeLockService;

/// 一段声音：[ms] 毫秒都是 [db]
List<double> sound(int ms, double db) => List.filled(ms ~/ 20, db);

/// 安静的房间先待 0.4 秒（估计环境噪音）
final calm = sound(400, -60);

/// 按时间线喂听狗叫：音量每个 20 毫秒；分类结果默认是到现在为止的 1 秒
class Feeder {
  Feeder(this.d);

  final BarkDetector d;

  /// 这次开始听以后过了多久（毫秒）
  int ms = 0;

  /// 判出来的每一声
  final heard = <BarkSound>[];

  void levels(List<double> levels) {
    for (final db in levels) {
      ms += 20;
      heard.addAll(d.feed(MicLevel(db)));
    }
  }

  void window(SoundScores scores, {int length = 1000}) =>
      heard.addAll(d.feed(SoundWindow(endMs: ms, lengthMs: length, scores: scores)));

  List<Heard> get kinds => [for (final s in heard) s.heard];
}

/// 只按音量算（分类器用不了），返回最后一共听到几声
int feedAll(BarkDetector d, List<double> levels) {
  final f = Feeder(d)..levels(levels);
  return f.heard.where((s) => s.heard == Heard.bark).lastOrNull?.count ?? 0;
}

/// 分类器常见的几种判断
const voiceLike = SoundScores(voice: 0.62, dog: 0.04);
const dogLike = SoundScores(dog: 0.83, voice: 0.2);
const clapLike = SoundScores(clap: 0.71, voice: 0.02);
const blowLike = SoundScores(breath: 0.45);
const unsure = SoundScores(voice: 0.05, clap: 0.08);

class FakeCallBackend implements CallBackend {
  FakeCallBackend({this.call, this.listenResult = 'listening', this.voiceMs = 2000});

  IncomingCall? call;
  String listenResult;
  final micController = StreamController<MicInput>.broadcast();
  final log = <String>[];
  final granted = <String>[];
  final declined = <String>[];
  final spoken = <String>[];
  final closes = <bool>[];
  int rings = 0;
  int listens = 0;

  @override
  Future<IncomingCall?> pending() async => call;

  @override
  Future<void> ring() async {
    rings++;
    log.add('ring');
  }

  @override
  Future<void> stopRing() async => log.add('stopRing');

  @override
  Future<void> tone(CallTone tone) async => log.add('tone:${tone.name}');

  /// 打包的语音有多长；null = 放不了（资源缺了之类），来电界面改用系统语音念
  int? voiceMs;
  final played = <String>[];

  @override
  Future<int?> playVoice(String asset) async {
    played.add(asset);
    return voiceMs;
  }

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stopSpeaking() async {}

  @override
  Future<String> startListening() async {
    listens++;
    return listenResult;
  }

  @override
  Future<void> stopListening() async => log.add('stopListening');

  @override
  Stream<MicInput> mic() => micController.stream;

  @override
  Future<bool> grant(String lockId) async {
    granted.add(lockId);
    return true;
  }

  @override
  Future<void> decline(String lockId) async => declined.add(lockId);

  @override
  Future<void> hangUp(String lockId) async => log.add('hangUp');

  @override
  Future<void> close({required bool granted}) async => closes.add(granted);

  @override
  Future<void> openSettings() async => log.add('settings');

  /// “试一下来电通知”的结果，默认排上了
  String noticeResult = 'scheduled';
  final notices = <(IncomingCall, Duration)>[];

  @override
  Future<String> previewNotice(IncomingCall call, {Duration delay = const Duration(seconds: 8)}) async {
    notices.add((call, delay));
    return noticeResult;
  }
}

/// 安卓：今天抖音刷了 75 分钟，说好 60 分钟；今天一共刷了 200 分钟（每日目标 180 分钟 → 狗度 111%，阶段 3）
const androidCall = IncomingCall(lockId: 'lock1', limitMinutes: 60, label: '抖音', usedMinutes: 75, todayMinutes: 200);

/// iOS：只知道选了 1 个 App，阶段是监控扩展记下的
const iosCall = IncomingCall(lockId: 'lock2', limitMinutes: 30, apps: 1, stage: 2);

Future<AppState> newState() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await SharedPreferences.getInstance());
}

/// 来电界面单独跑（安卓的样子：关掉交给原生）。动画按“减弱动态效果”画静止的一帧，pumpAndSettle 才停得下来
/// [at] 是来电时几点（默认下午，半夜会换一句开场）；[voice] 是用户挑的声音（默认没挑过）
Future<void> pumpCall(WidgetTester tester, FakeCallBackend backend, IncomingCall call, {DateTime? at, CallVoice? voice}) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final state = await newState();
  if (voice != null) await state.setCallVoiceName(voice.name);
  await tester.pumpWidget(AppScope(
    state: state,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      // 每次都是新的一通来电（同一个测试里再打一次，也不沿用上一通的状态）
      home: CallScreen(
        key: UniqueKey(),
        call: call,
        backend: backend,
        onClose: (granted) => backend.close(granted: granted),
        random: math.Random(1),
        now: () => at ?? DateTime(2026, 11, 23, 14),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// 这几句台词里有一句在屏幕上（去掉语气词以后）
Finder anyText(Iterable<String> lines) {
  final plain = {for (final l in lines) CallScript.plain(l)};
  return find.byWidgetPredicate((w) => w is Text && plain.contains(w.data));
}

/// 模拟原生听狗叫：按时间线交音量（每个 20 毫秒）和分类结果；原生重新开始听（狗版的你插完话）时间归零
class FakeMic {
  FakeMic(this.backend);

  final FakeCallBackend backend;
  int ms = 0;

  Future<void> levels(WidgetTester tester, List<double> levels) async {
    for (final db in levels) {
      ms += 20;
      backend.micController.add(MicLevel(db));
    }
    // 是从流里异步送来的：先让它们送到，再画一帧
    await tester.pumpAndSettle();
  }

  Future<void> window(WidgetTester tester, SoundScores scores, {int length = 1000}) async {
    backend.micController.add(SoundWindow(endMs: ms, lengthMs: length, scores: scores));
    await tester.pumpAndSettle();
  }

  /// 叫一声（0.2 秒，后面安静 0.3 秒），分类器给 [scores]
  Future<void> bark(WidgetTester tester, SoundScores scores, {double db = -20}) async {
    await levels(tester, [...sound(200, db), ...sound(300, -60)]);
    await window(tester, scores);
  }
}

void main() {
  group('听两声狗叫：先按音量切出每一声', () {
    test('安静的房间里，两声短促的“汪”就算学会了', () {
      final d = BarkDetector(classify: false);
      final heard = feedAll(d, [...calm, ...sound(200, -20), ...sound(300, -60), ...sound(240, -18), ...sound(200, -60)]);
      expect(heard, 2);
      expect(d.done, isTrue);
    });

    test('一直喊、放音乐（太长）不算，判成“太长了”；太短的咔哒声不管', () {
      final long = Feeder(BarkDetector(classify: false))..levels([...calm, ...sound(1500, -20), ...sound(300, -60)]);
      expect(long.kinds, [Heard.tooLong]);
      expect(long.d.count, 0);
      final click = Feeder(BarkDetector(classify: false))
        ..levels([...calm, ...sound(40, -10), ...sound(300, -60), ...sound(40, -10), ...sound(300, -60)]);
      expect(click.heard, isEmpty);
    });

    test('两声隔多久都算（中间狗版的你会插话）', () {
      final d = BarkDetector(classify: false);
      feedAll(d, [...calm, ...sound(200, -20), ...sound(4000, -60), ...sound(200, -20), ...sound(200, -60)]);
      expect(d.count, 2);
    });

    test('一声里中间小一点也算同一声；不够响的说话声不算', () {
      final dip = BarkDetector(classify: false);
      expect(feedAll(dip, [...calm, ...sound(120, -20), ...sound(40, -40), ...sound(120, -20), ...sound(200, -60)]), 1);
      // 比环境只响 10 dB，不算；分类器用不了时也不提醒（不知道是不是人声）
      final soft = Feeder(BarkDetector(classify: false))
        ..levels([...calm, ...sound(200, -50), ...sound(300, -60), ...sound(200, -50), ...sound(200, -60)]);
      expect(soft.heard, isEmpty);
    });

    test('吵的地方要更大声：环境 -40 dB 时，-30 dB 不算，-20 dB 算', () {
      final noisy = sound(400, -40);
      final quiet = BarkDetector(classify: false);
      expect(feedAll(quiet, [...noisy, ...sound(200, -30), ...sound(300, -40), ...sound(200, -30), ...sound(200, -40)]), 0);
      final loud = BarkDetector(classify: false);
      expect(feedAll(loud, [...noisy, ...sound(200, -20), ...sound(300, -40), ...sound(200, -20), ...sound(200, -40)]), 2);
    });

    test('一打开就喊，环境噪音也不会估得太高', () {
      final d = BarkDetector(classify: false);
      expect(
        feedAll(d, [...sound(100, -20), ...sound(300, -60), ...sound(200, -20), ...sound(300, -60), ...sound(200, -20), ...sound(200, -60)]),
        2,
      );
    });
  });

  group('听两声狗叫：再看手机上的声音分类器怎么说', () {
    test('叫出来的（人声）算一声：等分类器判完才算，像狗指数照分类器给的', () {
      final f = Feeder(BarkDetector())..levels([...calm, ...sound(200, -20), ...sound(300, -60)]);
      // 切出了一声，但分类器还没说话
      expect(f.heard, isEmpty);
      expect(f.d.busy, isTrue);
      f.window(voiceLike);
      expect(f.kinds, [Heard.bark]);
      expect(f.heard.single.count, 1);
      expect(f.heard.single.dogPercent, 4);
      expect(f.heard.single.veryDog, isFalse);
      expect(f.d.busy, isFalse);
    });

    test('学得特别像：像狗指数高，狗版的你都服了', () {
      final f = Feeder(BarkDetector())..levels([...calm, ...sound(200, -20), ...sound(300, -60)]);
      f.window(dogLike);
      expect(f.heard.single.dogPercent, 83);
      expect(f.heard.single.veryDog, isTrue);
    });

    test('拍手、敲桌子不算；吹气、吹口哨也不算', () {
      final clap = Feeder(BarkDetector())..levels([...calm, ...sound(200, -15), ...sound(300, -60)]);
      clap.window(clapLike);
      expect(clap.kinds, [Heard.clap]);
      expect(clap.d.count, 0);
      final blow = Feeder(BarkDetector())..levels([...calm, ...sound(400, -20), ...sound(300, -60)]);
      blow.window(blowLike);
      expect(blow.kinds, [Heard.notVoice]);
      expect(blow.d.count, 0);
    });

    test('分类器拿不准的也算一声：宁可放过，不把人卡死', () {
      final f = Feeder(BarkDetector())..levels([...calm, ...sound(200, -20), ...sound(300, -60)]);
      f.window(unsure);
      expect(f.kinds, [Heard.bark]);
    });

    test('人声但太小声：提醒大点声，不算；小声的别的声音不管', () {
      final f = Feeder(BarkDetector())..levels([...calm, ...sound(200, -46), ...sound(300, -60)]);
      f.window(voiceLike);
      expect(f.kinds, [Heard.tooQuiet]);
      expect(f.d.count, 0);
      final rustle = Feeder(BarkDetector())..levels([...calm, ...sound(200, -46), ...sound(300, -60)]);
      rustle.window(clapLike);
      expect(rustle.heard, isEmpty);
    });

    test('一直说话（太长）不算', () {
      final f = Feeder(BarkDetector())..levels([...calm, ...sound(1400, -22), ...sound(300, -60)]);
      f.window(voiceLike, length: 1800);
      expect(f.kinds, [Heard.tooLong]);
    });

    test('连着“汪！汪！”：一个分类结果判完两声', () {
      final f = Feeder(BarkDetector())..levels([...calm, ...sound(200, -20), ...sound(200, -60), ...sound(200, -20), ...sound(300, -60)]);
      f.window(voiceLike, length: 1200);
      expect(f.kinds, [Heard.bark, Heard.bark]);
      expect(f.d.done, isTrue);
    });

    test('分类结果先到、这一声后切完：用已经到了的结果', () {
      final f = Feeder(BarkDetector())..levels([...calm, ...sound(200, -20), ...sound(40, -60)]);
      f.window(clapLike);
      expect(f.heard, isEmpty);
      f.levels(sound(200, -60));
      expect(f.kinds, [Heard.clap]);
    });

    test('分类器一直没结果：一声结束 1.5 秒后按音量算', () {
      final f = Feeder(BarkDetector())..levels([...calm, ...sound(200, -20), ...sound(1200, -60)]);
      expect(f.heard, isEmpty);
      f.levels(sound(400, -60));
      expect(f.kinds, [Heard.bark]);
      expect(f.heard.single.scores, isNull);
      expect(f.heard.single.dogPercent, isNull);
    });

    test('狗版的你插完话重新开始听：时间从 0 算，已经听到几声、环境有多吵都沿用', () {
      final f = Feeder(BarkDetector())..levels([...calm, ...sound(200, -20), ...sound(300, -60)]);
      f.window(voiceLike);
      expect(f.d.count, 1);
      f.d.restart(classify: true);
      f.ms = 0;
      // 不用再估一遍环境噪音：一开始就叫也算
      f.levels([...sound(200, -20), ...sound(300, -60)]);
      f.window(voiceLike);
      expect(f.d.count, 2);
      expect(f.d.done, isTrue);
    });

    test('原生交过来的分类结果：两个平台的类别名都认得，每种取最高的，不认识的不管', () {
      final ios = SoundWindow.fromMap({
        'end': 1250,
        'length': 1000,
        'labels': {'dog_bark': 0.7, 'dog': 0.9, 'speech': 0.3, 'clapping': 0.1, 'music': 0.8},
      });
      expect(ios.endMs, 1250);
      expect(ios.startMs, 250);
      expect(ios.scores.dog, 0.9);
      expect(ios.scores.voice, 0.3);
      expect(ios.scores.clap, 0.1);
      expect(ios.scores.breath, 0);
      final android = SoundWindow.fromMap({
        'end': 975,
        'length': 975,
        'labels': {'Bark': 0.4, 'Speech': 0.55, 'Clapping': 0.02, 'Wind noise (microphone)': 0.3, 'Cap gun': 0.6},
      });
      expect(android.scores.dog, 0.4);
      expect(android.scores.voice, 0.55);
      expect(android.scores.breath, 0.3);
    });

    test('归类表里的名字都是分类器真有的类别（iOS 的从 Mac 上导出，安卓的是 YAMNet 自带的），两边狗叫都归了类', () {
      final apple = File('test/fixtures/apple_sound_labels.txt').readAsLinesSync().toSet();
      final yamnet = File('android/app/src/main/assets/yamnet_labels.txt').readAsLinesSync().toSet();
      expect(apple, hasLength(303));
      expect(yamnet, hasLength(521));
      for (final name in soundKinds.keys) {
        expect(apple.contains(name) || yamnet.contains(name), isTrue, reason: '$name 两个分类器都没有');
      }
      for (final name in apple.where((n) => n.startsWith('dog'))) {
        expect(soundKinds[name], SoundKind.dog, reason: name);
      }
      for (final name in ['Dog', 'Bark', 'Yip', 'Howl', 'Bow-wow', 'Growling', 'Whimper (dog)']) {
        expect(soundKinds[name], SoundKind.dog, reason: name);
      }
      for (final name in ['speech', 'shout', 'yell', 'Speech', 'Shout', 'Yell']) {
        expect(soundKinds[name], SoundKind.voice, reason: name);
      }
    });
  });

  group('狗版的你的台词', () {
    test('不叫“你的狗”，不带 App 名；去掉语气词以后没有括号', () {
      for (final line in CallScript.all) {
        expect(line, isNot(contains('你的狗')));
        expect(line, isNot(contains('「')));
        expect(CallScript.plain(line), isNot(matches(RegExp(r'[()]'))));
      }
      expect(CallScript.plain('(pant)喂？(sniffs)'), '喂？');
    });

    test('每个阶段一句吐槽；说“十分钟”的跟再玩几分钟对得上', () {
      expect(CallScript.stage, hasLength(DogMeter.stageNames.length));
      expect(LockService.snoozeMinutes, 10, reason: '台词里说的是“十分钟”');
      expect([...CallScript.ask, ...CallScript.granted].where((l) => l.contains('十分钟')), isNotEmpty);
    });

    test('半夜是 23 点到早上 5 点', () {
      expect(CallScript.isNight(DateTime(2026, 1, 1, 23)), isTrue);
      expect(CallScript.isNight(DateTime(2026, 1, 1, 4, 59)), isTrue);
      expect(CallScript.isNight(DateTime(2026, 1, 1, 5)), isFalse);
      expect(CallScript.isNight(DateTime(2026, 1, 1, 22, 59)), isFalse);
    });
  });

  group('狗版的你的声音', () {
    test('文件名跟生成脚本一样算（FNV-1a）；没挑过、认不出都用默认', () {
      expect(clipName('(pant)喂？喂？是我，狗版的你！时间到了，先别挂！'), 'f081c2d2');
      expect(CallVoice.byName('girl'), CallVoice.girl);
      expect(CallVoice.byName(null), CallVoice.spirit);
      expect(CallVoice.byName('没有这个'), CallVoice.spirit);
    });

    test('每句台词在每个声音下都有打包好的语音，也没有多余的（改了台词要跑 tools/voice/make_voice.py）', () {
      final names = {for (final line in CallScript.all) '${clipName(line)}.m4a'};
      for (final voice in CallVoice.values) {
        final files = {
          for (final f in Directory('assets/voice/${voice.name}').listSync().whereType<File>())
            if (f.path.endsWith('.m4a')) f.uri.pathSegments.last,
        };
        expect(files, names, reason: '${voice.name} 的语音跟台词对不上');
      }
    });

    test('三个声音的目录都写进了 pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final voice in CallVoice.values) {
        expect(pubspec, contains('- assets/voice/${voice.name}/'));
      }
    });
  });

  group('来电', () {
    test('原生交过来的来电：阶段 iOS 用记下的，安卓按今天的用量和每日目标算', () {
      final call = IncomingCall.fromMap({'lockId': 'a', 'limitMinutes': 60, 'label': '抖音', 'usedMinutes': 75, 'todayMinutes': 200});
      expect(call.title, '抖音');
      expect(call.stageFor(180), 3);
      expect(call.stageFor(480), 1);
      expect(IncomingCall.fromMap({'lockId': 'b', 'limitMinutes': 30, 'apps': 2, 'stage': 4}).stageFor(180), 4);
      expect(IncomingCall.fromMap({'lockId': 'b', 'limitMinutes': 30, 'apps': 2}).title, '2 个 App');
    });

    test('交给原生的来电不带空值（iOS 存得进 UserDefaults），原样读回来', () {
      const call = IncomingCall(lockId: 'preview', limitMinutes: 60, apps: 1, stage: 2, preview: true);
      final map = call.toMap();
      expect(map.containsKey('label'), isFalse);
      expect(map.containsKey('usedMinutes'), isFalse);
      final back = IncomingCall.fromMap(map);
      expect((back.lockId, back.limitMinutes, back.apps, back.stage, back.preview), ('preview', 60, 1, 2, true));
    });

    testWidgets('一打开就响铃：狗版的你、语音通话、哪个限时用了多久、拒接会锁死的提示；30 秒没人接就不响了，界面还在', (tester) async {
      final backend = FakeCallBackend();
      await pumpCall(tester, backend, androidCall);
      expect(backend.rings, 1);
      expect(find.text('狗版的你'), findsOneWidget);
      expect(find.text('「抖音」今天 1 小时 15 分 · 一天限 1 小时'), findsOneWidget);
      expect(find.textContaining('语音通话'), findsOneWidget);
      expect(find.text('阶段 3 · 长毛了'), findsOneWidget);
      expect(find.text('拒接 = 「抖音」今天锁死，明天 0 点再来'), findsOneWidget);
      expect(find.bySemanticsLabel('拒接，今天锁死'), findsOneWidget);
      expect(find.bySemanticsLabel('接听'), findsOneWidget);

      await tester.pump(CallScreen.ringFor);
      await tester.pump();
      expect(backend.log.last, 'stopRing');
      expect(find.textContaining('它不挂，接一下吧'), findsOneWidget);
      expect(find.bySemanticsLabel('接听'), findsOneWidget);
    });

    testWidgets('接听：停铃、接通音、计时；狗版的你一句一句说（开场、按阶段吐槽、提条件，念的和字幕一样，不带 App 名）；学会两声狗叫就放行，说完再挂断', (tester) async {
      final backend = FakeCallBackend();
      await pumpCall(tester, backend, androidCall);
      await tester.tap(find.bySemanticsLabel('接听'));
      await tester.pump();
      expect(backend.log, containsAllInOrder(['ring', 'stopRing', 'tone:connect']));
      expect(find.text('00:00 · AI 合成语音'), findsOneWidget);
      expect(anyText(CallScript.open), findsOneWidget);

      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(find.text('00:11 · AI 合成语音'), findsOneWidget);
      final roast = CallScript.plain(CallScript.stage[3]);
      expect(find.text(roast), findsOneWidget);
      expect(anyText(CallScript.ask), findsOneWidget);
      // 放的是默认声音打包好的语音：开场、这个阶段的吐槽、提条件，一句一句
      const voice = CallVoice.spirit;
      expect(backend.played, hasLength(3));
      expect(CallScript.open.map(voice.asset), contains(backend.played[0]));
      expect(backend.played[1], voice.asset(CallScript.stage[3]));
      expect(CallScript.ask.map(voice.asset), contains(backend.played[2]));
      expect(backend.spoken, isEmpty);

      await tester.tap(find.bySemanticsLabel('学两声狗叫，再玩 10 分钟'));
      await tester.pumpAndSettle();
      expect(backend.listens, 1);
      expect(find.textContaining('对着手机学两声狗叫'), findsOneWidget);
      expect(find.bySemanticsLabel('听到 0 声'), findsOneWidget);

      final mic = FakeMic(backend);
      await mic.levels(tester, calm);
      await mic.bark(tester, voiceLike);
      expect(find.bySemanticsLabel('听到 1 声'), findsOneWidget);
      // 爪印下面写着像狗多少；不是试一下来电，不写分类器的细节
      expect(find.text('这声像狗 4%'), findsOneWidget);
      await mic.bark(tester, voiceLike);
      expect(backend.granted, ['lock1']);
      expect(anyText(CallScript.granted), findsOneWidget);
      expect(CallScript.granted.map(voice.asset), contains(backend.played.last));
      expect(backend.closes, isEmpty);

      // 放行那句（假的语音 2 秒）说完停一下就挂断，不用等满 grantedFor
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('通话结束'), findsOneWidget);
      expect(backend.log.last, 'tone:hangup');
      expect(backend.closes, isEmpty);
      await tester.pump(CallScreen.endedFor);
      expect(backend.closes, [true]);
    });

    testWidgets('打包的语音放不了：改用系统语音念（去掉语气词，不带 App 名）', (tester) async {
      final backend = FakeCallBackend(voiceMs: null);
      await pumpCall(tester, backend, androidCall);
      await tester.tap(find.bySemanticsLabel('接听'));
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      expect(backend.played, hasLength(3));
      expect(backend.spoken, hasLength(3));
      expect(backend.spoken[1], CallScript.plain(CallScript.stage[3]));
      for (final said in backend.spoken) {
        expect(said, isNot(contains('(')));
        expect(said, isNot(contains('抖音')));
      }
    });

    testWidgets('用用户挑的声音', (tester) async {
      final backend = FakeCallBackend();
      await pumpCall(tester, backend, androidCall, voice: CallVoice.girl);
      await tester.tap(find.bySemanticsLabel('接听'));
      await tester.pump(const Duration(seconds: 1));
      expect(backend.played.single, startsWith('assets/voice/girl/'));
    });

    testWidgets('半夜打来换一句开场', (tester) async {
      final backend = FakeCallBackend();
      await pumpCall(tester, backend, androidCall, at: DateTime(2026, 11, 23, 23, 30));
      await tester.tap(find.bySemanticsLabel('接听'));
      await tester.pump();
      expect(find.text(CallScript.plain(CallScript.openNight)), findsOneWidget);
    });

    testWidgets('提完条件半天没动静：催一句，只催一次', (tester) async {
      final backend = FakeCallBackend();
      await pumpCall(tester, backend, androidCall);
      await tester.tap(find.bySemanticsLabel('接听'));
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(anyText(CallScript.nudge), findsOneWidget);
      expect(backend.played, hasLength(4));
      expect(CallScript.nudge.map(CallVoice.spirit.asset), contains(backend.played.last));
      await tester.pump(const Duration(seconds: 30));
      expect(backend.played, hasLength(4));
    });

    testWidgets('拒接：挂断音、今天锁死了的卡片，点“好”才关；不放行', (tester) async {
      final backend = FakeCallBackend();
      await pumpCall(tester, backend, androidCall);
      await tester.tap(find.bySemanticsLabel('拒接，今天锁死'));
      await tester.pumpAndSettle();
      expect(backend.declined, ['lock1']);
      expect(backend.log, containsAllInOrder(['stopRing', 'tone:hangup']));
      expect(find.text('已拒接'), findsOneWidget);
      expect(find.text('今天锁死了'), findsOneWidget);
      expect(find.textContaining('「抖音」明天 0 点才能再玩'), findsOneWidget);
      expect(backend.closes, isEmpty);

      await tester.tap(find.text('好'));
      await tester.pump();
      expect(backend.closes, [false]);
      expect(backend.granted, isEmpty);
    });

    testWidgets('接了又挂断：不放行也不锁死，“通话结束”停一下再关', (tester) async {
      final backend = FakeCallBackend();
      await pumpCall(tester, backend, androidCall);
      await tester.tap(find.bySemanticsLabel('接听'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('挂断，不玩了'));
      await tester.pumpAndSettle();
      expect(find.text('通话结束'), findsOneWidget);
      expect(backend.log, containsAllInOrder(['tone:hangup', 'hangUp']));
      await tester.pump(CallScreen.endedFor);
      expect(backend.closes, [false]);
      expect(backend.declined, isEmpty);
      expect(backend.granted, isEmpty);
    });

    testWidgets('关了扬声器就不念，只看字幕', (tester) async {
      final backend = FakeCallBackend();
      await pumpCall(tester, backend, androidCall);
      await tester.tap(find.bySemanticsLabel('接听'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('扬声器开着'));
      await tester.pump(const Duration(seconds: 1));
      expect(backend.spoken, isEmpty);
      expect(backend.played, isEmpty);
      expect(find.bySemanticsLabel('扬声器关了'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('12 秒没听清：再学一次；还可以挂断', (tester) async {
      final backend = FakeCallBackend();
      await pumpCall(tester, backend, androidCall);
      await tester.tap(find.bySemanticsLabel('接听'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('学两声狗叫，再玩 10 分钟'));
      await tester.pumpAndSettle();
      await tester.pump(CallScreen.listenFor);
      await tester.pump();
      expect(find.text(CallScript.plain(CallScript.missed)), findsOneWidget);
      expect(backend.played.last, CallVoice.spirit.asset(CallScript.missed));
      expect(backend.log, contains('stopListening'));
      await tester.tap(find.text('再学一次'));
      await tester.pumpAndSettle();
      expect(backend.listens, 2);
      expect(find.bySemanticsLabel('挂断，不玩了'), findsOneWidget);
    });

    testWidgets('学了一声：等一会儿没接着叫，狗版的你插一句“再来一声”（先停下不听，说完接着听，已经听到的接着算）', (tester) async {
      final backend = FakeCallBackend();
      await pumpCall(tester, backend, androidCall);
      await tester.tap(find.bySemanticsLabel('接听'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('学两声狗叫，再玩 10 分钟'));
      await tester.pumpAndSettle();
      final mic = FakeMic(backend);
      await mic.levels(tester, calm);
      await mic.bark(tester, voiceLike);
      final played = backend.played.length;

      await tester.pump(CallScreen.reactAfter);
      await tester.pump();
      expect(backend.log.last, 'stopListening');
      expect(anyText(CallScript.barkOne), findsOneWidget);
      expect(CallScript.barkOne.map(CallVoice.spirit.asset), contains(backend.played.last));
      expect(backend.played, hasLength(played + 1));
      expect(find.text('狗版的你在说话，说完接着听'), findsOneWidget);
      expect(find.textContaining('AI 合成语音'), findsOneWidget);
      // 插话的时候交过来的声音不管（原生已经停了）
      await mic.bark(tester, voiceLike);
      expect(find.bySemanticsLabel('听到 1 声'), findsOneWidget);

      // 那句（假的语音 2 秒）说完接着听：原生重新开始听，时间从 0 算
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(backend.listens, 2);
      expect(find.text('我在听…只在手机上听，不录音'), findsOneWidget);
      expect(find.text('还差一声：汪！'), findsOneWidget);
      mic.ms = 0;
      await mic.bark(tester, voiceLike);
      expect(backend.granted, ['lock1']);
      await tester.pump(CallScreen.grantedFor + CallScreen.endedFor);
    });

    testWidgets('连着“汪！汪！”不打断，直接放行', (tester) async {
      final backend = FakeCallBackend();
      await pumpCall(tester, backend, androidCall);
      await tester.tap(find.bySemanticsLabel('接听'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('学两声狗叫，再玩 10 分钟'));
      await tester.pumpAndSettle();
      final played = backend.played.length;
      final mic = FakeMic(backend);
      await mic.levels(tester, [...calm, ...sound(200, -20), ...sound(200, -60), ...sound(200, -20), ...sound(300, -60)]);
      await mic.window(tester, voiceLike, length: 1200);
      expect(backend.granted, ['lock1']);
      // 只说了放行那句
      expect(backend.played, hasLength(played + 1));
      expect(CallScript.granted.map(CallVoice.spirit.asset), contains(backend.played.last));
      await tester.pump(CallScreen.grantedFor + CallScreen.endedFor);
    });

    testWidgets('拍手：“拍手不算，张嘴叫！”，不算；同一句一轮只说一次', (tester) async {
      final backend = FakeCallBackend();
      await pumpCall(tester, backend, androidCall);
      await tester.tap(find.bySemanticsLabel('接听'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('学两声狗叫，再玩 10 分钟'));
      await tester.pumpAndSettle();
      final mic = FakeMic(backend);
      await mic.levels(tester, calm);
      await mic.bark(tester, clapLike);
      expect(find.bySemanticsLabel('听到 0 声'), findsOneWidget);
      expect(find.text('拍手、敲东西不算'), findsOneWidget);
      await tester.pump(CallScreen.reactAfter);
      await tester.pump();
      expect(find.text(CallScript.plain(CallScript.notVoice)), findsOneWidget);
      expect(backend.played.last, CallVoice.spirit.asset(CallScript.notVoice));
      final played = backend.played.length;

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      mic.ms = 0;
      await mic.bark(tester, clapLike);
      await tester.pump(CallScreen.reactAfter * 2);
      expect(backend.played, hasLength(played));
      expect(find.bySemanticsLabel('听到 0 声'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('挂断，不玩了'));
      await tester.pumpAndSettle();
      await tester.pump(CallScreen.endedFor);
    });

    testWidgets('太小声：“这是蚊子叫吧？大点声。”；太长：“别跟我讲道理”；特别像：“这声太像了”', (tester) async {
      final backend = FakeCallBackend();
      await pumpCall(tester, backend, androidCall);
      await tester.tap(find.bySemanticsLabel('接听'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('学两声狗叫，再玩 10 分钟'));
      await tester.pumpAndSettle();
      final mic = FakeMic(backend);
      await mic.levels(tester, calm);

      Future<void> afterReaction() async {
        await tester.pump(CallScreen.reactAfter);
        await tester.pump();
      }

      Future<void> resumed() async {
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
        mic.ms = 0;
      }

      await mic.bark(tester, voiceLike, db: -46);
      expect(find.text('太小声，没算'), findsOneWidget);
      await afterReaction();
      expect(find.text(CallScript.plain(CallScript.tooQuiet)), findsOneWidget);
      await resumed();

      await mic.levels(tester, [...sound(1400, -22), ...sound(300, -60)]);
      await mic.window(tester, voiceLike, length: 1800);
      expect(find.text('太长了，没算'), findsOneWidget);
      await afterReaction();
      expect(find.text(CallScript.plain(CallScript.tooLong)), findsOneWidget);
      await resumed();

      await mic.bark(tester, dogLike);
      expect(find.text('这声像狗 83%'), findsOneWidget);
      await afterReaction();
      expect(find.text(CallScript.plain(CallScript.veryDog)), findsOneWidget);
      expect(backend.played.last, CallVoice.spirit.asset(CallScript.veryDog));
      expect(find.bySemanticsLabel('听到 1 声'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('挂断，不玩了'));
      await tester.pumpAndSettle();
      await tester.pump(CallScreen.endedFor);
    });

    testWidgets('分类器用不了（原生说只有音量）：跟以前一样按音量算，马上算一声', (tester) async {
      final backend = FakeCallBackend(listenResult: 'levels');
      await pumpCall(tester, backend, androidCall);
      await tester.tap(find.bySemanticsLabel('接听'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('学两声狗叫，再玩 10 分钟'));
      await tester.pumpAndSettle();
      final mic = FakeMic(backend);
      await mic.levels(tester, [...calm, ...sound(200, -20), ...sound(300, -60)]);
      expect(find.bySemanticsLabel('听到 1 声'), findsOneWidget);
      expect(find.text('听到一声'), findsOneWidget);
      await mic.levels(tester, [...sound(200, -20), ...sound(300, -60)]);
      expect(backend.granted, ['lock1']);
      await tester.pump(CallScreen.grantedFor + CallScreen.endedFor);
    });

    testWidgets('没给麦克风：能去设置，也能按住 10 秒代替，不会被卡死', (tester) async {
      final backend = FakeCallBackend(listenResult: 'denied');
      await pumpCall(tester, backend, androidCall);
      await tester.tap(find.bySemanticsLabel('接听'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('学两声狗叫，再玩 10 分钟'));
      await tester.pumpAndSettle();
      expect(find.textContaining('没开麦克风'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('去设置打开麦克风'));
      expect(backend.log, contains('settings'));

      // 按一下就松手不算
      final hold = find.bySemanticsLabel(RegExp('按住 10 秒'));
      final quick = await tester.startGesture(tester.getCenter(hold));
      await tester.pump(const Duration(seconds: 2));
      await quick.up();
      await tester.pump();
      expect(backend.granted, isEmpty);

      final gesture = await tester.startGesture(tester.getCenter(hold));
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(backend.granted, ['lock1']);
      await tester.pump(CallScreen.grantedFor + CallScreen.endedFor);
      expect(backend.closes, [true]);
    });

    testWidgets('安卓：今天拒接过，再打开那个 App 直接是“今天锁死了”，不响铃', (tester) async {
      final backend = FakeCallBackend();
      await pumpCall(tester, backend,
          const IncomingCall(lockId: 'lock1', limitMinutes: 60, label: '抖音', usedMinutes: 75, locked: true));
      expect(backend.rings, 0);
      expect(find.text('今天锁死了'), findsOneWidget);
      expect(find.textContaining('你今天拒接过狗版自己的电话'), findsOneWidget);
      await tester.tap(find.text('好'));
      await tester.pump();
      expect(backend.closes, [false]);
    });

    testWidgets('按狗度来的限时：标题下面写狗度过了多少，不写一天限多久', (tester) async {
      final backend = FakeCallBackend();
      const call = IncomingCall(lockId: 'lock3', limitMinutes: 30, dogPercent: 100, label: '抖音', usedMinutes: 40);
      expect(IncomingCall.fromMap(call.toMap()).dogPercent, 100);
      expect(IncomingCall.fromMap(androidCall.toMap()).dogPercent, isNull);
      await pumpCall(tester, backend, call);
      expect(find.text('「抖音」今天 40 分钟 · 狗度过了 100%'), findsOneWidget);
      expect(find.textContaining('一天限'), findsNothing);
    });

    testWidgets('iOS：屏蔽页上点了接听，打开就是通话中，写的是限时不是 App 名', (tester) async {
      final backend = FakeCallBackend();
      await pumpCall(tester, backend, const IncomingCall(lockId: 'lock2', limitMinutes: 30, apps: 1, stage: 2, answered: true));
      expect(backend.rings, 0);
      expect(backend.log, contains('tone:connect'));
      expect(find.text('阶段 2 · 狗鼻子'), findsOneWidget);
      // iOS 拿不到用了多久，只写限时
      expect(find.text('1 个 App · 一天限 30 分钟，用满了'), findsOneWidget);
      expect(find.text(CallScript.plain(CallScript.stage[2])), findsNothing);
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(find.text(CallScript.plain(CallScript.stage[2])), findsOneWidget);
    });

    testWidgets('iOS：打开 App 时有来电就弹出来电界面，处理完关掉回到原来的页面', (tester) async {
      final state = await newState();
      final backend = FakeCallBackend(call: iosCall);
      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: CallGate(backend: backend, enabled: true, child: const Scaffold(body: Text('今天页'))),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(CallScreen), findsOneWidget);
      expect(backend.rings, 1);
      expect(find.text('拒接 = 这个限时里的 App 今天锁死，明天 0 点再来'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('拒接，今天锁死'));
      await tester.pumpAndSettle();
      expect(backend.declined, ['lock2']);
      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.byType(CallScreen), findsNothing);
      expect(find.text('今天页'), findsOneWidget);
    });

    testWidgets('试一下来电：照样响铃、能接能拒，但不会真的锁上或放行', (tester) async {
      final backend = FakeCallBackend();
      await pumpCall(tester, backend, const IncomingCall(lockId: 'preview', limitMinutes: 60, label: '某短视频', usedMinutes: 75, preview: true));
      expect(backend.rings, 1);
      expect(find.text('试一下：不会真的锁上，也不会真的放行'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('拒接，今天锁死'));
      await tester.pumpAndSettle();
      expect(find.text('今天锁死了'), findsOneWidget);
      expect(backend.declined, isEmpty);

      final again = FakeCallBackend();
      await pumpCall(tester, again, const IncomingCall(lockId: 'preview', limitMinutes: 60, label: '某短视频', usedMinutes: 75, preview: true));
      await tester.tap(find.bySemanticsLabel('接听'));
      await tester.pumpAndSettle();
      // 试一下来电的开场是“演习”
      expect(find.text(CallScript.plain(CallScript.openDrill)), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('学两声狗叫，再玩 10 分钟'));
      await tester.pumpAndSettle();
      final mic = FakeMic(again);
      await mic.levels(tester, calm);
      await mic.bark(tester, dogLike);
      // 试一下来电：爪印下面多写一行分类器给的分数，方便在真机上看判得准不准
      expect(find.text('这声像狗 83%\n狗叫 83% · 人声 20% · 拍打 0% · 吹气 0%'), findsOneWidget);
      await mic.bark(tester, voiceLike);
      expect(anyText(CallScript.granted), findsOneWidget);
      expect(again.granted, isEmpty);
      await tester.pump(CallScreen.grantedFor + CallScreen.endedFor);
    });

    testWidgets('超时来电页底下能“试一下来电”', (tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final state = await newState();
      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: LocksPage(service: FakeLockService(), adviceLoader: () async => (apps: const <AppUsage>[], days: 7)),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('试一下来电：听听狗版的你打来是什么样'), 200);
      await tester.tap(find.text('试一下来电：听听狗版的你打来是什么样'));
      await tester.pumpAndSettle();
      expect(find.byType(CallScreen), findsOneWidget);
      expect(find.text('试一下：不会真的锁上，也不会真的放行'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('拒接，今天锁死'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.byType(CallScreen), findsNothing);
    });

    testWidgets('超时来电页能挑狗版的你的声音，点一下就试听', (tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final state = await newState();
      final backend = FakeCallBackend();
      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(
          home: LocksPage(
            service: FakeLockService(),
            adviceLoader: () async => (apps: const <AppUsage>[], days: 7),
            callBackend: backend,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('俏皮女生'), 200);
      expect(find.text('憨憨萌兽（默认）'), findsOneWidget);
      expect(find.textContaining('AI 合成语音'), findsOneWidget);
      await tester.tap(find.text('俏皮女生'));
      await tester.pumpAndSettle();
      expect(state.callVoiceName, 'girl');
      expect(backend.played.single, CallVoice.girl.asset(CallVoice.sample));
    });

    testWidgets('iOS：试一下来电通知，过 8 秒响，提示先回到桌面；通知没开就引导去设置', (tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final state = await newState();
      final backend = FakeCallBackend();
      Future<void> open() async {
        await tester.pumpWidget(AppScope(
          state: state,
          child: MaterialApp(
            home: LocksPage(
              key: UniqueKey(),
              service: FakeLockService(),
              adviceLoader: () async => (apps: const <AppUsage>[], days: 7),
              callBackend: backend,
              noticeTest: true,
            ),
          ),
        ));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.textContaining('试一下来电通知'), 200);
        await tester.tap(find.textContaining('试一下来电通知'));
        await tester.pumpAndSettle();
      }

      await open();
      final (call, delay) = backend.notices.single;
      expect(call.preview, isTrue);
      expect(delay, LocksPage.noticeDelay);
      expect(find.textContaining('8 秒后狗版的你打来'), findsOneWidget);

      backend.noticeResult = 'denied';
      await open();
      expect(find.textContaining('通知没开'), findsOneWidget);
      await tester.tap(find.text('去设置'));
      await tester.pump();
      expect(backend.log, contains('settings'));
    });

    testWidgets('没有来电、不是 iOS：什么都不弹', (tester) async {
      final state = await newState();
      final backend = FakeCallBackend(call: iosCall);
      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(home: CallGate(backend: backend, enabled: false, child: const Text('今天页'))),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(CallScreen), findsNothing);
      backend.call = null;
      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(home: CallGate(backend: backend, enabled: true, child: const Text('今天页'))),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(CallScreen), findsNothing);
    });
  });
}
