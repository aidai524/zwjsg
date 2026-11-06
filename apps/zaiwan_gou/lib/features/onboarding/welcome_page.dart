import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:pop_ui/pop_ui.dart';
import 'package:avatar_engine/avatar_engine.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pop.yellow,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Pop.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Pop.ink, width: 2),
                ),
                child: const Text('[品牌名] 出品', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 20),
              const Text('再玩\n我是狗', style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, height: 1.02)),
              const SizedBox(height: 14),
              const Text('手机刷得越多，你就越像一只狗。\n少刷一点，才能做回人。',
                  style: TextStyle(fontSize: 17, height: 1.6, fontWeight: FontWeight.w500)),
              Expanded(
                child: Center(
                  child: Transform.rotate(
                    angle: -0.035,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 20, 10, 18),
                      decoration: Pop.card(radius: 28),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _Stage(stage: 0, label: '早上 · 是人'),
                              _Stage(stage: 2, label: '下午 · 半狗'),
                              _Stage(stage: 5, label: '半夜 · 汪'),
                            ],
                          ),
                          SizedBox(height: 14),
                          Text('每天 0 点重置成人，晚上看看你变成了哪种狗',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              PopButton(label: '开始变身', style: PopButtonStyle.dark, height: 60, onPressed: () => context.go('/login')),
              const SizedBox(height: 14),
              const Center(
                child: Text('使用时长只在你的手机上计算，不上传任何 app 记录',
                    style: TextStyle(fontSize: 12, color: Pop.mutedOnYellow)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({required this.stage, required this.label});

  final int stage;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DogAvatar(stage: stage, size: 92),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
