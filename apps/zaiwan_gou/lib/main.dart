import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/app_state.dart';
import 'core/call_channel.dart';
import 'core/home_widget.dart';
import 'core/licenses.dart';
import 'features/call/call_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // 开源许可页：Dart 包以外、打包进 App 的模型和运行库（打开那一页时才读）
  AppLicenses.register();
  final prefs = await SharedPreferences.getInstance();
  final state = AppState(prefs);
  // 先读出拍照形象，第一帧就是自己的样子
  await state.loadAvatar();
  runApp(AppScope(state: state, child: ZwjsgApp(state: state)));
  // 桌面小组件：等首页画出来再同步（要画形象图，别和首屏抢）
  WidgetsBinding.instance.addPostFrameCallback((_) => HomeWidgetSync(state).start());
}

/// 安卓超时来电页（CallReminderActivity）的入口：单独的 Flutter 引擎，只画来电界面，不走首页、不连网。
/// 原生那边一打开就先响铃，这里准备好了再接着管。
@pragma('vm:entry-point')
Future<void> callMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(await SharedPreferences.getInstance());
  await state.loadAvatar();
  const backend = PlatformCallBackend();
  final call = await backend.pending();
  if (call == null) {
    await backend.close(granted: false);
    return;
  }
  runApp(AppScope(state: state, child: CallApp(call: call, backend: backend)));
}
