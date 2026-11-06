import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/scene.dart';
import '../../widgets/common.dart';
import 'remind_sheet.dart';

/// 群详情：每个人的城市天气 + 一句事实 + “提醒 TA”
class GroupPage extends StatefulWidget {
  const GroupPage({super.key, required this.groupId});

  final int groupId;

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  GroupDetail? _group;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final g = await AppScope.read(context).api.group(widget.groupId);
      if (mounted) setState(() => _group = g);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _remind(Member m) async {
    final g = _group!;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RemindSheet(groupId: g.id, member: m),
    );
    if (sent == true) _load();
  }

  Future<void> _invite() async {
    final code = _group!.inviteCode;
    // TODO 接入微信分享：发一张带邀请码的卡片
    await Clipboard.setData(ClipboardData(text: '来“什么鬼天气”的关心群「${_group!.name}」，邀请码 $code'));
    if (mounted) showToast(context, '邀请码 $code 已复制，发到微信给 TA');
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出这个群？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('算了')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppScope.read(context).api.leaveGroup(widget.groupId);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = _group;
    // 推荐提醒的人：有话题、今天还有次数的第一个人
    final suggest = g?.members.where((m) => !m.isMe && m.phrases.isNotEmpty && (m.remainingToday ?? 0) > 0 && m.weather?['care_topic'] != null).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(g?.name ?? '关心群'),
        actions: [
          if (g != null) TextButton(onPressed: _invite, child: const Text('+ 微信拉人', style: TextStyle(fontWeight: FontWeight.w900))),
          if (g != null)
            PopupMenuButton<String>(
              onSelected: (_) => _leave(),
              itemBuilder: (_) => const [PopupMenuItem(value: 'leave', child: Text('退出群'))],
            ),
        ],
      ),
      body: g == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator(color: Pop.ink))
          : RefreshIndicator(
              color: Pop.ink,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (suggest != null)
                    GestureDetector(
                      onTap: () => _remind(suggest),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: Pop.card(color: Pop.yellow),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('${suggest.nickname}那边${suggest.fact}，提醒 TA 一下？',
                                  style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                            const Text('提醒 ›', style: TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ),
                  for (final m in g.members) ...[
                    _MemberCard(member: m, onRemind: () => _remind(m)),
                    const SizedBox(height: 12),
                  ],
                  if (g.members.length < 2)
                    PopButton(label: '复制邀请码，拉家人进来', onPressed: _invite),
                  const SourceNote('只能发天气关心，不能聊天 · 只显示城市，不共享位置'),
                ],
              ),
            ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.onRemind});

  final Member member;
  final VoidCallback onRemind;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final hasWeather = m.weather != null;
    final bg = !hasWeather ? Pop.white : (m.alert != null ? const Color(0xFFFFF4C2) : sceneColor(m.cond, m.outfit).withAlpha(110));
    final remaining = m.remainingToday ?? 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: Pop.card(color: Color.alphaBlend(bg, Pop.white)),
      child: Row(
        children: [
          WeatherAvatar(
            temp: weatherTempFromKey(hasWeather ? m.outfit : null),
            cond: weatherCondFromKey(hasWeather ? m.cond : 'cloudy'),
            size: 72,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.nickname, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                Text(m.city == null ? '还没设置常驻城市' : '${m.city}${hasWeather ? ' · ${m.temp}° ${m.weatherText}' : ''}'),
                if (m.alert != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(m.alert!, style: const TextStyle(fontWeight: FontWeight.w900, color: Pop.danger)),
                  ),
                if (hasWeather && m.fact.isNotEmpty) Text(m.fact, style: const TextStyle(fontSize: 12)),
                if (m.lastAckAt != null)
                  const Text('说收到了 ♥', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          if (m.isMe)
            const Chip2('这是我')
          else
            SizedBox(
              width: 92,
              child: PopButton(
                height: 44,
                label: '提醒 ${2 - remaining}/2',
                style: remaining > 0 ? PopButtonStyle.primary : PopButtonStyle.secondary,
                onPressed: remaining > 0 && m.phrases.isNotEmpty ? onRemind : null,
              ),
            ),
        ],
      ),
    );
  }
}
