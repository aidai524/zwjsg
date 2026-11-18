import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一张 320x320 的白色方块，当作照片贴纸
Future<ui.Image> whiteSticker() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 320, 320), Paint()..color = Colors.white);
  return recorder.endRecording().toImage(320, 320);
}

/// 图片上 (x, y) 处的不透明度
int alphaAt(ByteData rgba, int width, int x, int y) => rgba.getUint8((y * width + x) * 4 + 3);

void main() {
  test('衣服档和天气状态的名字和服务端一致，来回转换不丢', () {
    for (final t in WeatherTemp.values) {
      expect(weatherTempFromKey(weatherTempKey(t)), t);
    }
    for (final c in WeatherCond.values) {
      expect(weatherCondFromKey(weatherCondKey(c)), c);
    }
    expect(weatherCondKey(WeatherCond.lightRain), 'light_rain');
    expect(weatherCondKey(WeatherCond.heavyRain), 'heavy_rain');
    expect(WeatherTemp.values.map(weatherTempKey), ['hot', 'warm', 'mild', 'cool', 'cold', 'freezing']);
  });

  testWidgets('不经过 Widget 树也能把形象画成图片：背景透明，人画在中间', (tester) async {
    final result = await tester.runAsync(() async {
      final sticker = await whiteSticker();
      final out = <String, (int, int, int, int)>{};
      for (final photo in [false, true]) {
        for (final temp in WeatherTemp.values) {
          for (final cond in WeatherCond.values) {
            final image = await renderWeatherAvatar(temp: temp, cond: cond, sticker: photo ? sticker : null, pixels: 180);
            final rgba = (await image.toByteData())!;
            out['$photo $temp $cond'] = (image.width, image.height, alphaAt(rgba, 180, 2, 178), alphaAt(rgba, 180, 90, 120));
            image.dispose();
          }
        }
      }
      sticker.dispose();
      return out;
    });

    expect(result, hasLength(2 * WeatherTemp.values.length * WeatherCond.values.length));
    for (final MapEntry(:key, value: (w, h, corner, middle)) in result!.entries) {
      expect((w, h), (180, 180), reason: key);
      // 左下角留空（透明），脸的位置是实心的
      expect(corner, 0, reason: key);
      expect(middle, 255, reason: key);
    }
  });
}
