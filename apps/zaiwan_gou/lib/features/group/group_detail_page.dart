import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';
import 'package:series_share/series_share.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/breeds.dart';
import '../../core/dog_meter.dart';
import '../../core/groups.dart';
import '../../core/screen_time_channel.dart';
import 'group_sheets.dart';
import 'king_card_page.dart';
import 'member_avatar.dart';

/// 一个群：今天谁最狗（每个人今天的样子，最狗的在前）、昨天的狗王、一起做人、邀请。
/// 点别人可以“汪一下”叫 TA 放下手机；右上角菜单里改群名（群主）、隐藏自己的狗度、关掉汪一下、退群。
class GroupDetailPage extends StatefulWidget {
  const GroupDetailPage({super.key, required this.groupId, this.sharer = const SystemTextSharer()});

  final int groupId;

  /// 发邀请用的系统分享面板；测试里换成假的
  final TextSharer sharer;

  /// 邀请时发出去的那段话：不许诺奖励，邀请码说清楚
  static String inviteText(GroupInfo g) =>
      '来「${g.name}」一起看谁今天更狗：打开「再玩我是狗」，进“群组”，用邀请码 ${g.inviteCode} 加入。';

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  GroupInfo? _group;
  String? _error;
  final _inviteKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  ApiClient get _api => AppScope.read(context).api;

  Future<void> _load() async {
    try {
      final g = await _api.group(widget.groupId);
      if (!mounted) return;
      setState(() {
        _group = g;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404) {
        _toast('这个群不在了，或者你已经不在群里');
        context.pop();
        return;
      }
      setState(() => _error = e.message);
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// 改设置、改群名：服务端返回最新的群
  Future<void> _update(Future<GroupInfo> Function() action) async {
    try {
      final g = await action();
      if (mounted) setState(() => _group = g);
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _invite() async {
    final g = _group;
    if (g == null) return;
    final box = _inviteKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final shared = await widget.sharer.share(GroupDetailPage.inviteText(g), origin: origin);
    if (!shared && mounted) await _copyCode(g);
  }

  Future<void> _copyCode(GroupInfo g) async {
    await Clipboard.setData(ClipboardData(text: GroupDetailPage.inviteText(g)));
    if (mounted) _toast('邀请码已复制，发给想拉进群的人');
  }

  Future<void> _menu(String action) async {
    final g = _group;
    if (g == null) return;
    switch (action) {
      case 'rename':
        final name = await showGroupNameSheet(context, initial: g.name, title: '改群名', action: '保存');
        if (name != null && mounted) await _update(() => _api.renameGroup(g.id, name));
      case 'hide':
        await _update(() => _api.updateMyGroupSettings(g.id, hideStatus: !g.hideStatus));
      case 'mute':
        await _update(() => _api.updateMyGroupSettings(g.id, muteNudges: !g.muteNudges));
      case 'leave':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('退出「${g.name}」？'),
            content: Text(g.isOwner && g.members.length > 1 ? '你是群主，退出后群主会交给最早进群的人。' : '退出后要重新用邀请码才能回来。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('再想想')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('退出', style: TextStyle(color: Pop.danger))),
            ],
          ),
        );
        if (ok != true || !mounted) return;
        try {
          await _api.leaveGroup(g.id);
          if (mounted) context.pop();
        } on ApiException catch (e) {
          if (mounted) _toast(e.message);
        }
    }
  }

  Future<void> _tapMember(GroupMember m) async {
    final g = _group;
    if (g == null || m.isMe) return;
    final nudged = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Pop.white,
      builder: (_) => _MemberSheet(member: m),
    );
    if (nudged != true || !mounted) return;
    try {
      final left = await _api.nudge(g.id, m.id);
      if (!mounted) return;
      _toast('汪！已经叫 ${m.nickname} 放下手机了${left > 0 ? '（今天还能汪 $left 次）' : ''}');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = _group;
    return Scaffold(
      appBar: AppBar(
        title: Text(g?.name ?? '群组'),
        actions: [
          if (g != null) ...[
            IconButton(key: _inviteKey, tooltip: '邀请', icon: const Icon(Icons.person_add_alt_1), onPressed: g.full ? null : _invite),
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: _menu,
              itemBuilder: (_) => [
                if (g.isOwner) const PopupMenuItem(value: 'rename', child: Text('改群名')),
                CheckedPopupMenuItem(value: 'hide', checked: g.hideStatus, child: const Text('隐藏我的狗度')),
                CheckedPopupMenuItem(value: 'mute', checked: g.muteNudges, child: const Text('不接收汪一下')),
                const PopupMenuItem(value: 'leave', child: Text('退出群组', style: TextStyle(color: Pop.danger))),
              ],
            ),
          ],
        ],
      ),
      body: g == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator(color: Pop.ink)
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, style: PopText.bodyMuted),
                      TextButton(onPressed: _load, child: const Text('再试一次')),
                    ]),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (ScreenTimeChannel.isSupported) ...[
                    const _Note('你用的是 iPhone：苹果不允许使用数据离开手机，群里看不到你的狗度。你照样能看别人、汪别人。'),
                    const SizedBox(height: 12),
                  ],
                  _MembersCard(group: g, onTap: _tapMember),
                  const SizedBox(height: 12),
                  _KingCard(
                    king: g.king,
                    onShare: g.king == null
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute(
                              fullscreenDialog: true,
                              builder: (_) => KingCardPage(king: g.king!, groupName: g.name),
                            )),
                  ),
                  const SizedBox(height: 12),
                  _TeamCard(team: g.team),
                  const SizedBox(height: 12),
                  _InviteCard(group: g, onShare: _invite, onCopy: () => _copyCode(g)),
                ],
              ),
            ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: Pop.softYellow, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5)),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.trailing, this.color = Pop.white});

  final String title;
  final Widget child;
  final Widget? trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Pop.ink, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// 今天谁最狗：每个人一格，最狗的在前
class _MembersCard extends StatelessWidget {
  const _MembersCard({required this.group, required this.onTap});

  final GroupInfo group;
  final void Function(GroupMember) onTap;

  @override
  Widget build(BuildContext context) {
    final leader = group.leader;
    return _Card(
      title: '今天谁最狗',
      trailing: Text('${group.members.length} / ${group.maxMembers} 人', style: PopText.small),
      child: LayoutBuilder(builder: (_, c) {
        final w = (c.maxWidth - 2 * 8) / 3;
        return Wrap(
          spacing: 8,
          runSpacing: 12,
          children: [
            for (final m in group.members)
              SizedBox(width: w, child: _MemberTile(member: m, leader: m == leader, onTap: () => onTap(m))),
          ],
        );
      }),
    );
  }
}

/// 一格：形象、名字、今天多狗
class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.leader, required this.onTap});

  final GroupMember member;
  final bool leader;
  final VoidCallback onTap;

  static String status(GroupMember m) {
    final t = m.today;
    if (t == null) return m.hidden ? '藏起来了' : '还没同步';
    return t.human ? '还是人 ${t.dogPercent}%' : '狗度 ${t.dogPercent}%';
  }

  @override
  Widget build(BuildContext context) {
    final t = member.today;
    return Semantics(
      container: true,
      button: !member.isMe,
      label: '${member.nickname}${member.isMe ? '（我）' : ''}：${status(member)}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: member.isMe ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  MemberBadge(url: member.avatarUrl, preset: member.avatarPreset, stage: t?.stage, size: 64, isMe: member.isMe, highlight: leader),
                  if (member.isMe || member.isOwner)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: member.isMe ? Pop.yellow : Pop.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Pop.ink, width: 1.5),
                        ),
                        child: Text(member.isMe ? '我' : '群主', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(member.nickname,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
              Text(status(member),
                  style: TextStyle(
                    fontSize: 12,
                    color: t != null && !t.human ? Pop.ink : Pop.muted,
                    fontWeight: t != null && !t.human ? FontWeight.w900 : FontWeight.w500,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// 点别人：TA 今天怎样，汪一下
class _MemberSheet extends StatelessWidget {
  const _MemberSheet({required this.member});

  final GroupMember member;

  @override
  Widget build(BuildContext context) {
    final t = member.today;
    final breed = breedByKey(t?.breedKey);
    final left = member.nudgesLeft ?? 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: MemberBadge(url: member.avatarUrl, preset: member.avatarPreset, stage: t?.stage, size: 96)),
            const SizedBox(height: 10),
            Text(member.nickname, textAlign: TextAlign.center, style: PopText.h2),
            const SizedBox(height: 4),
            Text(
              t == null
                  ? (member.hidden ? 'TA 把狗度藏起来了' : 'TA 今天还没同步（没打开 App，或者用的是 iPhone）')
                  : '${DogMeter.stageNames[t.stage]} · 狗度 ${t.dogPercent}%${breed == null ? '' : ' · 今天是${breed.name}'}',
              textAlign: TextAlign.center,
              style: PopText.bodyMuted,
            ),
            const SizedBox(height: 16),
            PopButton(
              label: left > 0 ? '汪一下，叫 TA 放下手机（今天还能 $left 次）' : '今天已经汪够了，明天再说',
              style: PopButtonStyle.dark,
              onPressed: left > 0 ? () => Navigator.pop(context, true) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 昨天的狗王
class _KingCard extends StatelessWidget {
  const _KingCard({required this.king, required this.onShare});

  final KingOfDay? king;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final k = king;
    return _Card(
      title: '昨天的狗王',
      color: k == null ? Pop.white : Pop.softYellow,
      trailing: k == null
          ? null
          : TextButton.icon(
              onPressed: onShare,
              icon: Icon(Icons.adaptive.share, size: 16),
              label: const Text('晒一下'),
            ),
      child: k == null
          ? const Text('昨天全员做人（或者还没人同步），没有狗王。', style: PopText.bodyMuted)
          : Row(
              children: [
                MemberBadge(url: k.avatarUrl, preset: k.avatarPreset, stage: k.stage, size: 64, highlight: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(k.nickname, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                      Text('狗度 ${k.dogPercent}% · ${DogMeter.stageNames[k.stage]}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(KingCardPage.roastFor(k.stage), style: const TextStyle(fontSize: 13, color: Pop.mutedOnYellow)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// 一起做人：全群连续几天都是人，到 7 天拿“狼群”称号
class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.team});

  final TeamStatus team;

  @override
  Widget build(BuildContext context) {
    final done = team.streak.clamp(0, team.goal);
    final today = [
      if (team.human > 0) '${team.human} 人还是人',
      if (team.dog > 0) '${team.dog} 人变狗了',
      if (team.unknown > 0) '${team.unknown} 人没同步',
    ].join(' · ');
    return _Card(
      title: '一起做人',
      trailing: team.wolfPack
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Pop.legendGold,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Pop.ink, width: 1.5),
              ),
              child: const Text('狼群', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
            )
          : (team.best > 0 ? Text('最长 ${team.best} 天', style: PopText.small) : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(TextSpan(children: [
            const TextSpan(text: '全群连续做人 '),
            TextSpan(text: '${team.streak}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            const TextSpan(text: ' 天'),
          ]), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < team.goal; i++)
                Expanded(
                  child: Container(
                    height: 10,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: i < done ? Pop.legendGold : Pop.gray,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: i < done ? Pop.ink : Pop.gray, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            team.wolfPack ? '这个群拿过「狼群」称号，最长连续 ${team.best} 天' : '连续 ${team.goal} 天全群都是人，拿「狼群」称号',
            style: PopText.small,
          ),
          if (today.isNotEmpty) Text('今天：$today', style: PopText.small),
          const Text('只算共享狗度的人：用 iPhone 的不算', style: PopText.small),
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.group, required this.onShare, required this.onCopy});

  final GroupInfo group;
  final VoidCallback onShare;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final code = group.inviteCode;
    return _Card(
      title: '邀请',
      child: group.full
          ? Text('群满了（最多 ${group.maxMembers} 人），有人退出才能再进。', style: PopText.bodyMuted)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: '邀请码 ${code.split('').join(' ')}',
                  excludeSemantics: true,
                  child: Text(
                    code.length == 8 ? '${code.substring(0, 4)} ${code.substring(4)}' : code,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 4),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: PopButton(label: '发给好友', height: 46, onPressed: onShare)),
                    const SizedBox(width: 10),
                    Expanded(child: PopButton(label: '复制', height: 46, style: PopButtonStyle.secondary, onPressed: onCopy)),
                  ],
                ),
              ],
            ),
    );
  }
}
