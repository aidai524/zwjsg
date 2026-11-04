import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/avatar.dart';

/// 狗群（P2）：MVP 先放入口和预告，后端接口见 docs 里的“狗群”章节。
class GroupPage extends StatelessWidget {
  const GroupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('狗群', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                decoration: Pop.card(color: Pop.yellow, radius: 24),
                child: const Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        DogAvatar(stage: 2, size: 72),
                        DogAvatar(stage: 5, size: 72),
                        DogAvatar(stage: 0, size: 72),
                      ],
                    ),
                    SizedBox(height: 14),
                    Text('拉上室友、对象、损友，一起看谁今天更狗', textAlign: TextAlign.center, style: PopText.body),
                    SizedBox(height: 4),
                    Text('下个版本上线', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
