import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const n = PhotoSticker.inputSize;
const c = PhotoSticker.canvasSize;

/// 合成一张“卡通头像”：浅灰底上一个肤色圆脸（圆心 144,170，半径 100），脸上一条 3 像素粗的深色眉毛；蒙版就是这个圆
(Uint8List, Uint8List) fakeFace() {
  final rgba = Uint8List(n * n * 4);
  final mask = Uint8List(n * n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final i = y * n + x;
      final inFace = (x - 144) * (x - 144) + (y - 170) * (y - 170) <= 100 * 100;
      final brow = inFace && y >= 119 && y <= 121 && x >= 95 && x <= 130;
      final color = brow ? const [40, 30, 30] : (inFace ? const [245, 220, 200] : const [230, 230, 230]);
      rgba.setRange(i * 4, i * 4 + 3, color);
      rgba[i * 4 + 3] = 255;
      mask[i] = inFace ? 255 : 0;
    }
  }
  return (rgba, mask);
}

List<int> pixel(Uint8List out, int x, int y) => out.sublist((y * c + x) * 4, (y * c + x) * 4 + 4);

void main() {
  group('平涂墨线贴纸', () {
    late Uint8List out;

    setUpAll(() {
      final (rgba, mask) = fakeFace();
      out = PhotoSticker.render(rgba, mask);
    });

    test('输出 320x320，人像以外是透明的', () {
      expect(out.length, c * c * 4);
      expect(pixel(out, 0, 0)[3], 0);
      expect(pixel(out, c - 1, 0)[3], 0);
      // 圆脸左边缘在画布 x=60（16 + 44），往外 12 像素已经超出描边
      expect(pixel(out, 48, 202)[3], 0);
    });

    test('脸是平涂的肤色，眉毛描成墨线', () {
      final face = pixel(out, 144 + PhotoSticker.offsetX, 200 + PhotoSticker.offsetY);
      expect(face[3], 255);
      for (final (got, want) in [(face[0], 245), (face[1], 220), (face[2], 200)]) {
        expect((got - want).abs(), lessThan(12));
      }
      expect(pixel(out, 110 + PhotoSticker.offsetX, 120 + PhotoSticker.offsetY), [0x1B, 0x1B, 0x1F, 255]);
    });

    test('人像外面先是白边，再是黑描边', () {
      // 圆脸左边缘在画布 x=60：往外 3 像素是白边，往外 7 像素是黑描边
      expect(pixel(out, 57, 202), [255, 255, 255, 255]);
      expect(pixel(out, 53, 202), [0x1B, 0x1B, 0x1F, 255]);
    });

    test('同一张图每次结果一样', () {
      final (rgba, mask) = fakeFace();
      expect(PhotoSticker.render(rgba, mask), out);
    });
  });

  test('蒙版里没有人、尺寸不对时报错', () {
    final (rgba, _) = fakeFace();
    expect(() => PhotoSticker.render(rgba, Uint8List(n * n)), throwsStateError);
    expect(() => PhotoSticker.render(Uint8List(4), Uint8List(1)), throwsArgumentError);
  });

  testWidgets('照片形象按阶段叠变狗图层：耳朵、鼻子、狗毛、舌头和尾巴、嘴筒', (tester) async {
    final image = await tester.runAsync(() async {
      final (rgba, mask) = fakeFace();
      return PhotoSticker.toImage(PhotoSticker.render(rgba, mask));
    });
    for (final stage in [0, 1, 2, 3, 4, 5]) {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: PhotoDogAvatar(sticker: image!, stage: stage, size: 160)),
      ));
      expect(find.bySemanticsLabel('照片卡通形象，变狗阶段 $stage'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(image, isA<ui.Image>());
  });

  testWidgets('照片形象叠天气图层：每种衣服档 × 天气状态都能画出来', (tester) async {
    final image = await tester.runAsync(() async {
      final (rgba, mask) = fakeFace();
      return PhotoSticker.toImage(PhotoSticker.render(rgba, mask));
    });
    for (final temp in WeatherTemp.values) {
      for (final cond in WeatherCond.values) {
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: PhotoWeatherAvatar(sticker: image!, temp: temp, cond: cond, size: 120)),
        ));
        expect(tester.takeException(), isNull, reason: '$temp $cond');
      }
    }
    expect(find.bySemanticsLabel('照片卡通形象，天气：预警中'), findsOneWidget);
  });
}
