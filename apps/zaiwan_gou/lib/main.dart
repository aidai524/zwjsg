import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  final state = AppState(prefs);
  // 先读出拍照形象，第一帧就是自己的样子
  await state.loadAvatar();
  runApp(AppScope(state: state, child: ZwjsgApp(state: state)));
}
