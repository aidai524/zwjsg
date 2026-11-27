import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> rgba(ui.Image image) async {
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  image.dispose();
  return bytes;
}

void main() {
  test('名字：存储用的名字认得回来，认不出来是 null；默认的是呆毛', () {
    for (final p in AvatarPreset.values) {
      expect(AvatarPreset.byName(p.name), p);
    }
    expect(AvatarPreset.byName('mohawk'), isNull);
    expect(AvatarPreset.byName(null), isNull);
    expect(AvatarPreset.fallback, AvatarPreset.ahoge);
    expect(AvatarPreset.values.map((p) => p.label).toSet(), hasLength(AvatarPreset.values.length));
  });

  testWidgets('每张预设形象都不一样；完全变狗（阶段 5）以后也认得出是哪张；不传就是呆毛', (tester) async {
    final result = await tester.runAsync(() async {
      Future<Uint8List> draw(AvatarPreset? p, int stage, {Evolution? evolution}) async => rgba(p == null
          ? await renderDogAvatar(stage: stage, pixels: 120, evolution: evolution)
          : await renderDogAvatar(stage: stage, pixels: 120, preset: p, evolution: evolution));
      return {
        for (final stage in [0, 3, 5])
          stage: [for (final p in AvatarPreset.values) await draw(p, stage)],
        -1: [await draw(null, 0), await draw(null, 5)],
        // 穿上进化形态也照样是自己的脸
        -2: [for (final p in AvatarPreset.values) await draw(p, 0, evolution: Evolution.halo)],
      };
    });
    for (final key in [0, 3, 5, -2]) {
      final list = result![key]!;
      for (var a = 0; a < list.length; a++) {
        for (var b = a + 1; b < list.length; b++) {
          expect(listEquals(list[a], list[b]), isFalse,
              reason: '$key：${AvatarPreset.values[a].label} 和 ${AvatarPreset.values[b].label}');
        }
      }
    }
    expect(listEquals(result![-1]![0], result[0]![0]), isTrue, reason: '不传 preset 画的是呆毛');
    expect(listEquals(result[-1]![1], result[5]![0]), isTrue);
  });

  testWidgets('DogAvatar 带上预设形象；不传是呆毛', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: DogAvatar(stage: 1, size: 80, preset: AvatarPreset.bob)),
    ));
    expect(tester.widget<DogAvatar>(find.byType(DogAvatar)).preset, AvatarPreset.bob);
    expect(find.bySemanticsLabel('卡通形象，变狗阶段 1'), findsOneWidget);
    expect(const DogAvatar(stage: 1).preset, AvatarPreset.ahoge);
  });
}
