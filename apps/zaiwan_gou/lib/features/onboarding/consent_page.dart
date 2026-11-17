import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_state.dart';

/// 第一次打开先看隐私政策（国内商店的要求）：同意之前不读使用数据、不读应用列表、不请求权限。
/// 同意后由路由带去欢迎页或首页。
class ConsentPage extends StatelessWidget {
  const ConsentPage({super.key});

  static const points = [
    '使用时长只在你手机上算，具体用了哪些 App 不上传。',
    '登录后只同步每天的狗度、分钟数和犬种，以及昵称、目标和提醒时间。',
    '自拍只在手机上变成卡通，原图不上传、不保存。',
    '不做广告，不卖数据，不和第三方共享。',
  ];

  Future<void> _disagree(BuildContext context) async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('不同意就没法用了'),
        content: const Text('算狗度要用到手机的使用时长，得先经过你同意。可以再看看隐私政策，有问题随时改主意。'),
        actions: [
          // 苹果不允许 App 自己退出，iOS 上只能留在这一页
          if (Platform.isAndroid) TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('退出 App')),
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('我再看看')),
        ],
      ),
    );
    if (quit == true) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pop.yellow,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          children: [
            const Text('用之前，先说清楚', style: PopText.title),
            const SizedBox(height: 8),
            const Text('我们只为了算出“你今天有多狗”用你的数据：', style: TextStyle(fontSize: 15, color: Pop.mutedOnYellow)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: Pop.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in points)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('·  ', style: PopText.body),
                          Expanded(child: Text(p, style: PopText.body)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => context.push('/privacy'),
                child: const Text('看完整的《隐私政策》',
                    style: TextStyle(color: Pop.ink, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
              ),
            ),
            const SizedBox(height: 16),
            PopButton(
              label: '同意并继续',
              style: PopButtonStyle.dark,
              onPressed: () => AppScope.read(context).acceptPrivacy(),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => _disagree(context),
                child: const Text('不同意', style: TextStyle(color: Pop.mutedOnYellow)),
              ),
            ),
            const Text(
              '点“同意并继续”，表示你已阅读并同意《隐私政策》。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Pop.mutedOnYellow),
            ),
          ],
        ),
      ),
    );
  }
}
