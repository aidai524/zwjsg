import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/weather_avatars.dart';
import '../settings/import_avatar_sheet.dart';

/// 引导页。首版不要定位权限，手动选城市；以后接定位也只取区县级。
/// 玩过“再玩我是狗”的可以顺手导入形象（可选，以后也能在设置里导）。
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('什么\n鬼天气', style: TextStyle(fontSize: 52, height: 1.05, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              const Text('天气准不准？准。\n嘴毒不毒？你说了算。',
                  style: TextStyle(fontSize: 17, height: 1.5, fontWeight: FontWeight.w700, color: Pop.muted)),
              const Spacer(),
              const Center(child: MyWeatherAvatar(temp: WeatherTemp.warm, cond: WeatherCond.lightRain, size: 220)),
              const SizedBox(height: 8),
              const Center(child: Text('出门前看一眼，省得淋成这样', style: TextStyle(fontWeight: FontWeight.w700))),
              Center(
                child: TextButton(
                  onPressed: () async {
                    if (await showImportAvatarSheet(context) == true && context.mounted) showToast(context, '导入好了');
                  },
                  child: Text(
                    AppScope.of(context).avatar == null ? '玩过「再玩我是狗」？导入你的形象' : '换一个导出码重新导入',
                    style: const TextStyle(color: Pop.ink, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                  ),
                ),
              ),
              const Spacer(),
              PopButton(
                label: '选个城市，开始',
                onPressed: () => context.push('/city-search?onboarding=1'),
              ),
              const SizedBox(height: 12),
              const Text('不用定位、不用注册就能看。位置只到城市，不记录你去过哪。',
                  textAlign: TextAlign.center, style: PopText.small),
            ],
          ),
        ),
      ),
    );
  }
}
