import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/groups.dart';
import 'group_sheets.dart';
import 'member_avatar.dart';

/// 群组（原“狗群”，2026-11-20 改名）：2–10 人的熟人小群，互相看今天谁更狗、一起做人。
/// 群里只共享每天的狗度、阶段和犬种，不共享任何 App。要登录。
class GroupPage extends StatefulWidget {
  const GroupPage({super.key});

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  List<GroupInfo>? _groups;
  String? _error;
  bool? _wasLoggedIn;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在别的地方登录、退出了：跟着刷新
    final loggedIn = AppScope.of(context).isLoggedIn;
    if (loggedIn == _wasLoggedIn) return;
    _wasLoggedIn = loggedIn;
    if (loggedIn) {
      _load();
    } else {
      _groups = null;
    }
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    try {
      final groups = await api.groups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _open(GroupInfo g) async {
    await context.push('/group/${g.id}');
    if (mounted) await _load();
  }

  Future<void> _create() async {
    final name = await showGroupNameSheet(context);
    if (name == null || !mounted) return;
    await _act(() => AppScope.read(context).api.createGroup(name));
  }

  Future<void> _join() async {
    final code = await showJoinSheet(context);
    if (code == null || !mounted) return;
    await _act(() => AppScope.read(context).api.joinGroup(code));
  }

  /// 建群、加群：成功了直接进群
  Future<void> _act(Future<GroupInfo> Function() action) async {
    try {
      final g = await action();
      if (mounted) await _open(g);
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final groups = _groups;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: state.isLoggedIn ? _load : () async {},
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              const Text('群组', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              if (!state.isLoggedIn)
                _Intro(onLogin: () => context.push('/login'))
              else if (groups == null)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Center(
                    child: _error == null
                        ? const CircularProgressIndicator(color: Pop.ink)
                        : Column(children: [
                            Text(_error!, style: PopText.bodyMuted),
                            TextButton(onPressed: _load, child: const Text('再试一次')),
                          ]),
                  ),
                )
              else if (groups.isEmpty)
                _Intro(onCreate: _create, onJoin: _join)
              else ...[
                for (final g in groups) ...[_GroupCard(group: g, onTap: () => _open(g)), const SizedBox(height: 12)],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: PopButton(label: '再建一个群', height: 48, onPressed: _create)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: PopButton(
                            label: '用邀请码加入', height: 48, style: PopButtonStyle.secondary, onPressed: _join)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 还没群（或者还没登录）：说清楚群组是干什么的、共享什么
class _Intro extends StatelessWidget {
  const _Intro({this.onLogin, this.onCreate, this.onJoin});

  final VoidCallback? onLogin;
  final VoidCallback? onCreate;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: Pop.card(color: Pop.softYellow, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            // 三个不一样的人：一个有点狗、一个完全变狗、一个还是人
            children: [
              DogAvatar(stage: 2, size: 72, preset: AvatarPreset.bun),
              DogAvatar(stage: 5, size: 72, preset: AvatarPreset.curly),
              DogAvatar(stage: 0, size: 72, preset: AvatarPreset.parted),
            ],
          ),
          const SizedBox(height: 14),
          const Text('拉上室友、对象、损友，一起看谁今天更狗',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          for (final line in const [
            '每天谁最狗，大家都看得到；昨天最狗的封“狗王”',
            '全群一起做人，连续 7 天拿“狼群”称号',
            '谁刷太久了，就“汪一下”叫 TA 放下手机',
            '只共享狗度、阶段和犬种，不共享你用了哪些 App',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('· $line', style: const TextStyle(fontSize: 14, height: 1.5)),
            ),
          const SizedBox(height: 12),
          if (onLogin != null)
            PopButton(label: '登录后建群', style: PopButtonStyle.dark, onPressed: onLogin)
          else ...[
            PopButton(label: '建个群', style: PopButtonStyle.dark, onPressed: onCreate),
            const SizedBox(height: 10),
            PopButton(label: '用邀请码加入', style: PopButtonStyle.secondary, onPressed: onJoin),
          ],
        ],
      ),
    );
  }
}

/// 群列表里的一张卡：群名、一起做人、每个人今天的样子、今天最狗的是谁
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onTap});

  final GroupInfo group;
  final VoidCallback onTap;

  static const shown = 6;

  @override
  Widget build(BuildContext context) {
    final team = group.team;
    final leader = group.leader;
    final synced = group.members.where((m) => m.today != null).length;
    final String line;
    if (leader != null) {
      line = '今天最狗：${leader.nickname} ${leader.today!.dogPercent}%';
    } else if (synced > 0) {
      line = '今天大家都还是人，保持住';
    } else {
      line = '今天还没人同步狗度';
    }

    return Material(
      color: Pop.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Pop.ink, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  ),
                  _Chip(text: team.wolfPack ? '狼群' : '一起做人 ${team.streak} 天', gold: team.wolfPack),
                  const Icon(Icons.chevron_right, size: 20, color: Pop.muted),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final m in group.members.take(shown)) ...[
                    MemberBadge(url: m.avatarUrl, preset: m.avatarPreset, stage: m.today?.stage, size: 40, isMe: m.isMe, highlight: m == leader),
                    const SizedBox(width: 6),
                  ],
                  if (group.members.length > shown)
                    Text('+${group.members.length - shown}', style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 10),
              Text('${group.members.length} 人 · $line', style: PopText.small),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.gold = false});

  final String text;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: gold ? Pop.legendGold : Pop.paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Pop.ink, width: 1.5),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
    );
  }
}
