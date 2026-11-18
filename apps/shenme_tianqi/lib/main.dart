import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/app_state.dart';
import 'core/home_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  final state = AppState(prefs);
  await state.loadAvatar();
  runApp(AppScope(state: state, child: ShenmeTianqiApp(state: state)));
  // 桌面小组件：等首页画出来再同步（要画形象图，别和首屏抢）
  WidgetsBinding.instance.addPostFrameCallback((_) => HomeWidgetSync(state).start());
}
