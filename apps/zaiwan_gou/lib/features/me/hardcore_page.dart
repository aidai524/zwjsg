import 'package:flutter/material.dart';

import 'package:pop_ui/pop_ui.dart';
import 'package:avatar_engine/avatar_engine.dart';

/// 硬核模式（P2，会员）：拦截需要安卓无障碍服务 / iOS 屏幕使用时间接口，技术验证后再做。
class HardcorePage extends StatelessWidget {
  const HardcorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pop.gray,
      appBar: AppBar(title: const Text('硬核模式')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Pop.ink, borderRadius: BorderRadius.circular(20)),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('给自己拴上狗绳', style: TextStyle(color: Pop.white, fontSize: 17, fontWeight: FontWeight.w900)),
                    SizedBox(height: 4),
                    Text('狗度太高时，选中的 app 会被拦一下。下个版本上线。',
                        style: TextStyle(color: Color(0xFFD6D6D6), fontSize: 13)),
                  ],
                ),
              ),
              const Spacer(),
              const Center(child: DogAvatar(stage: 4, size: 180)),
              const SizedBox(height: 12),
              const Text('汪？你已经是柯基了', textAlign: TextAlign.center, style: PopText.h2),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
