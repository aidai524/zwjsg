import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('所有衣服档 × 天气状态的形象都能画出来', (tester) async {
    for (final t in WeatherTemp.values) {
      for (final c in WeatherCond.values) {
        await tester.pumpWidget(MaterialApp(home: Center(child: WeatherAvatar(temp: t, cond: c, size: 120))));
        expect(tester.takeException(), isNull, reason: '$t / $c');
      }
    }
  });

  test('接口里的字符串能映射到形象状态', () {
    expect(weatherCondFromKey('heavy_rain'), WeatherCond.heavyRain);
    expect(weatherCondFromKey('unknown'), WeatherCond.sunny);
    expect(weatherTempFromKey('freezing'), WeatherTemp.freezing);
  });
}
