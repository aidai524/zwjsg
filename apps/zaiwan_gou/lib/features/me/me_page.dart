import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/dog_meter.dart';
import 'package:pop_ui/pop_ui.dart';
import 'package:avatar_engine/avatar_engine.dart';

class MePage extends StatelessWidget {
  const MePage({super.key});

  Future<void> _confirmDelete(BuildContext context) async {
    final state = AppScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除形象和所有数据？'),
        content: const Text('账号、每天的记录、图鉴和卡通形象都会删除，不能恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('再想想')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除', style: TextStyle(color: Pop.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await state.deleteAccount();
    } on ApiException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return Scaffold(
      backgroundColor: Pop.gray,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            const Text('我的', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: Pop.card(shadow: false),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Pop.yellow,
                      shape: BoxShape.circle,
                      border: Border.all(color: Pop.ink, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.bottomCenter,
                    child: const DogAvatar(stage: 0, size: 56),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(state.isLoggedIn ? '[昵称]' : '还没登录',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                        Text('图鉴 ${state.ownedBreeds.length} / 8', style: PopText.small),
                      ],
                    ),
                  ),
                  if (!state.isLoggedIn)
                    TextButton(onPressed: () => context.push('/login'), child: const Text('登录')),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: Pop.card(color: Pop.yellow),
              child: const Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('开通会员', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        Text('动态结算卡、周报月报、硬核模式', style: TextStyle(fontSize: 12, color: Pop.mutedOnYellow)),
                      ],
                    ),
                  ),
                  Text('即将上线', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            const _Section('目标与提醒'),
            _Group(children: [
              _Row(
                title: '每日目标',
                trailing: DogMeter.formatMinutes(state.goalMinutes),
                onTap: () => context.push('/goal?edit=1'),
              ),
              const _Row(title: '结算卡提醒', trailing: '22:00'),
            ]),
            const _Section('玩法'),
            _Group(children: [
              _Row(title: '硬核模式', trailing: '会员', onTap: () => context.push('/hardcore')),
              const _Row(title: '装扮商店', trailing: '即将上线'),
            ]),
            const _Section('隐私与账号'),
            _Group(children: [
              const _Row(title: '隐私政策'),
              if (state.isLoggedIn) _Row(title: '退出登录', onTap: state.logout),
              if (state.isLoggedIn) _Row(title: '删除我的形象和数据', danger: true, onTap: () => _confirmDelete(context)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(title, style: PopText.label),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: Pop.white, borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, color: Color(0xFFEDEDED)),
              children[i],
            ],
          ],
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.trailing, this.onTap, this.danger = false});

  final String title;
  final String? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => ListTile(
        minTileHeight: 48,
        title: Text(title, style: TextStyle(fontSize: 15, color: danger ? Pop.danger : Pop.ink)),
        trailing: danger
            ? null
            : Text('${trailing ?? ''}${onTap != null ? '  ›' : ''}', style: const TextStyle(fontSize: 14, color: Pop.muted)),
        onTap: onTap,
      );
}
