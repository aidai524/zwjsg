import 'dart:async';

import 'package:shenme_tianqi/features/home/weather_backdrop.dart';

/// 所有测试共用：首页的天气动画一直在动，pumpAndSettle 会等不完，测试里先关掉（weather_backdrop_test 里单独打开测）
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WeatherBackdrop.animate = false;
  await testMain();
}
