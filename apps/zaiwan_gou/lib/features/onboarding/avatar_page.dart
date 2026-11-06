import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:pop_ui/pop_ui.dart';

/// 形象创建。
/// TODO 技术验证完成后接入：拍照/相册（image_picker）→ 手机本地卡通化 → 上传卡通图（POST /me/avatar）。
/// 原图只在手机内存里处理，不落盘、不上传。
class AvatarPage extends StatelessWidget {
  const AvatarPage({super.key});

  void _next(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('形象生成还在接入中，先用默认形象')),
    );
    context.go('/goal');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('先做一个你', style: PopText.title),
              const SizedBox(height: 8),
              const Text('拍张自拍，我们把你画成卡通。之后你刷多少，它就变多狗。', style: PopText.bodyMuted),
              Expanded(
                child: Center(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      color: Pop.softYellow,
                      shape: BoxShape.circle,
                      border: Border.all(color: Pop.ink, width: Pop.stroke),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_camera_outlined, size: 52, color: Pop.ink),
                        SizedBox(height: 10),
                        Text('正脸，光线亮一点', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        SizedBox(height: 4),
                        Text('别戴口罩，狗不戴口罩', style: PopText.small),
                      ],
                    ),
                  ),
                ),
              ),
              PopButton(label: '拍一张自拍', onPressed: () => _next(context)),
              const SizedBox(height: 14),
              PopButton(
                label: '从相册选一张',
                style: PopButtonStyle.secondary,
                height: 52,
                onPressed: () => _next(context),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('不想露脸？', style: PopText.small),
                  TextButton(
                    onPressed: () => _next(context),
                    child: const Text('捏一个卡通的我',
                        style: TextStyle(fontWeight: FontWeight.w900, color: Pop.ink, decoration: TextDecoration.underline)),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Pop.gray, borderRadius: BorderRadius.circular(16)),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('照片只在你手机上变成卡通，原图不上传。请只用本人照片。',
                          style: TextStyle(fontSize: 13, height: 1.6, color: Color(0xFF3C4043))),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
