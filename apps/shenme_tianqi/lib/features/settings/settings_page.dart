import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/scene.dart';
import '../../widgets/common.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('嘴有多毒', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('只影响吐槽，不影响天气。预警时自动切成正经。', style: TextStyle(fontSize: 12, color: Pop.muted)),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < snarkLevels.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: state.snarkLevel == i,
                    child: GestureDetector(
                      onTap: () => state.setSnark(i),
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: Pop.card(color: state.snarkLevel == i ? Pop.yellow : Pop.white, shadow: state.snarkLevel == i),
                        child: Text(snarkLevels[i], style: const TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),
          const Text('我的形象', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: Pop.card(),
            child: Row(
              children: [
                const WeatherAvatar(temp: WeatherTemp.mild, cond: WeatherCond.cloudy, size: 64),
                const SizedBox(width: 12),
                const Expanded(child: Text('从「再玩我是狗」导入 ›', style: TextStyle(fontWeight: FontWeight.w800))),
                TextButton(
                  // TODO 一次性导入：狗 App 生成短时导出码 → 本 App 用导出码请求后端拉取形象（两边账号不互通）
                  onPressed: () => showToast(context, '导入功能开发中，先用默认形象'),
                  child: const Text('导入'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text('账号', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          if (!state.isLoggedIn)
            PopButton(label: '登录（关心群需要）', onPressed: () => context.push('/login'))
          else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('退出登录'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => state.logout(),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('注销账号', style: TextStyle(color: Pop.danger)),
              subtitle: const Text('删除账号、城市、关心群记录和形象，不能恢复'),
              onTap: () => _confirmDelete(context, state),
            ),
          ],
          const SourceNote('天气数据：和风天气 · 预警信息来自当地气象部门\n吐槽文案为人工撰写，不改写预报结论'),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确定注销？'),
        content: const Text('账号和所有数据会被删除，不能恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('算了')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('注销', style: TextStyle(color: Pop.danger))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await state.deleteAccount();
      if (context.mounted) showToast(context, '已注销');
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.message);
    }
  }
}
