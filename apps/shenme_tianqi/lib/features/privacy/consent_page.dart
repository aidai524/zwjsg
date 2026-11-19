import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_state.dart';

/// 第一次打开先看隐私政策（国内商店的要求）：同意之前不查天气、不请求任何权限。
/// 同意后由路由带去欢迎页或首页。
class ConsentPage extends StatelessWidget {
  const ConsentPage({super.key});

  static const points = [
    '不用定位、不用注册就能看天气，城市只存在你手机上。',
    '查天气只把城市编号发给服务器，不带你的个人信息。',
    '登录后同步城市和设置；关心群里，家人只看得到你的昵称、导入的卡通形象和常驻城市名。',
    '不做广告，不卖数据，不和第三方共享。',
  ];

  Future<void> _disagree(BuildContext context) async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('不同意就没法用了'),
        content: const Text('查天气要先经过你同意。可以再看看隐私政策，有问题随时改主意。'),
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          children: [
            const Text('用之前，先说清楚', style: PopText.title),
            const SizedBox(height: 8),
            const Text('我们只为了给你看天气、发关心提醒用你的数据：', style: PopText.bodyMuted),
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
              onPressed: () => AppScope.read(context).acceptPrivacy(),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => _disagree(context),
                child: const Text('不同意', style: TextStyle(color: Pop.muted)),
              ),
            ),
            const Text(
              '点“同意并继续”，表示你已阅读并同意《隐私政策》。',
              textAlign: TextAlign.center,
              style: PopText.small,
            ),
          ],
        ),
      ),
    );
  }
}
