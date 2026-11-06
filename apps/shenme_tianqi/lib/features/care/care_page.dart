import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../widgets/common.dart';

/// 关心群入口：我的群 / 收到的提醒
class CarePage extends StatelessWidget {
  const CarePage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('关心群')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('和家人、TA 建个群', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              const Text('看到对方城市要下雨、降温，点一下就能提醒 TA。\n'
                  '只能发几句固定的关心话，不能聊天；每天最多提醒同一个人 2 次；晚上发的早上 7 点才送到。',
                  style: TextStyle(height: 1.6)),
              const Spacer(),
              PopButton(label: '登录后开始', onPressed: () => context.push('/login?next=/care')),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('关心群'),
          bottom: const TabBar(
            labelColor: Pop.ink,
            indicatorColor: Pop.ink,
            labelStyle: TextStyle(fontWeight: FontWeight.w900),
            tabs: [Tab(text: '我的群'), Tab(text: '收到的')],
          ),
        ),
        body: const TabBarView(children: [_GroupsTab(), _InboxTab()]),
      ),
    );
  }
}

class _GroupsTab extends StatefulWidget {
  const _GroupsTab();

  @override
  State<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<_GroupsTab> {
  late Future<List<GroupBrief>> _future = AppScope.read(context).api.groups();

  void _reload() => setState(() => _future = AppScope.read(context).api.groups());

  Future<void> _create() async {
    final name = await _ask(context, '给群起个名', '比如：我们家');
    if (name == null || !mounted) return;
    try {
      final g = await AppScope.read(context).api.createGroup(name);
      if (mounted) await context.push('/care/${g.id}');
      _reload();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  Future<void> _join() async {
    final code = await _ask(context, '输入邀请码', '8 位字母');
    if (code == null || !mounted) return;
    try {
      final g = await AppScope.read(context).api.joinGroup(code);
      if (mounted) await context.push('/care/${g.id}');
      _reload();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GroupBrief>>(
      future: _future,
      builder: (context, snap) {
        final groups = snap.data ?? const [];
        return RefreshIndicator(
          color: Pop.ink,
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (snap.connectionState == ConnectionState.waiting) const LinearProgressIndicator(color: Pop.ink),
              if (snap.hasError) Text('${snap.error}', style: const TextStyle(color: Pop.danger)),
              for (final g in groups) ...[
                GestureDetector(
                  onTap: () async {
                    await context.push('/care/${g.id}');
                    _reload();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: Pop.card(),
                    child: Row(
                      children: [
                        Expanded(child: Text(g.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                        Text('${g.membersCount} 人'),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              PopButton(label: '建一个群', onPressed: _create),
              const SizedBox(height: 12),
              PopButton(label: '用邀请码加入', style: PopButtonStyle.secondary, onPressed: _join),
              const SourceNote('一个群 2–8 人 · 只显示城市，不共享位置'),
            ],
          ),
        );
      },
    );
  }
}

class _InboxTab extends StatefulWidget {
  const _InboxTab();

  @override
  State<_InboxTab> createState() => _InboxTabState();
}

class _InboxTabState extends State<_InboxTab> {
  late Future<List<InboxItem>> _future = AppScope.read(context).api.inbox();
  final Set<int> _acked = {};

  void _reload() => setState(() => _future = AppScope.read(context).api.inbox());

  Future<void> _ack(InboxItem item) async {
    try {
      await AppScope.read(context).api.ack(item.id);
      if (mounted) setState(() => _acked.add(item.id));
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  Future<void> _mute(InboxItem item) async {
    if (item.senderId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('静音${item.sender}？'),
        content: const Text('TA 不会知道。之后 TA 的提醒不再推送给你，随时可以取消。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('算了')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('静音')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppScope.read(context).api.muteUser(item.senderId!);
      if (mounted) showToast(context, '已静音');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InboxItem>>(
      future: _future,
      builder: (context, snap) {
        final items = snap.data ?? const [];
        return RefreshIndicator(
          color: Pop.ink,
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (snap.connectionState == ConnectionState.waiting) const LinearProgressIndicator(color: Pop.ink),
              if (snap.hasError) Text('${snap.error}', style: const TextStyle(color: Pop.danger)),
              if (snap.connectionState == ConnectionState.done && items.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Text('还没人提醒你，说明天气挺好', textAlign: TextAlign.center)),
              for (final item in items) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: Pop.card(color: const Color(0xFFFFF4C2)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text('${item.sender}提醒你', style: const TextStyle(fontWeight: FontWeight.w700))),
                        Text('${item.deliveredAt.month}/${item.deliveredAt.day} ${item.deliveredAt.hour}:${item.deliveredAt.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 12)),
                      ]),
                      const SizedBox(height: 6),
                      Text(item.text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: PopButton(
                              height: 44,
                              label: item.acked || _acked.contains(item.id) ? '已告诉 TA 你收到了' : '收到 ♥',
                              style: item.acked || _acked.contains(item.id) ? PopButtonStyle.secondary : PopButtonStyle.primary,
                              onPressed: item.acked || _acked.contains(item.id) ? null : () => _ack(item),
                            ),
                          ),
                          IconButton(
                            tooltip: '静音这个人',
                            onPressed: () => _mute(item),
                            icon: const Icon(Icons.notifications_off_outlined),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );
  }
}

Future<String?> _ask(BuildContext context, String title, String hint) async {
  final ctrl = TextEditingController();
  final v = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, autofocus: true, maxLength: 16, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('好')),
      ],
    ),
  );
  // 不在这里 dispose：对话框关闭动画还在用它
  return (v == null || v.isEmpty) ? null : v;
}
