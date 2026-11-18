import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';
import 'package:series_share/series_share.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/scene.dart';
import '../../widgets/weather_avatars.dart';
import '../../widgets/common.dart';
import 'remind_sheet.dart';

/// 群详情：每个人的城市天气 + 一句事实 + “提醒 TA”；拉人进群
class GroupPage extends StatefulWidget {
  /// [sharer] 只在测试里传
  const GroupPage({super.key, required this.groupId, this.sharer = const SystemTextSharer()});

  final int groupId;
  final TextSharer sharer;

  /// 邀请的话：怎么加入写清楚。只有邀请码，不带链接（还没有下载页；微信邀请卡片等开放平台账号）
  static String inviteText(GroupDetail g) => '我在“什么鬼天气”建了个关心群「${g.name}」，进来互相看看各自城市的天气。'
      '打开 App 点“关心群”，再点“用邀请码加入”，填 ${g.inviteCode}。'
      '还没装的话，在应用商店搜“什么鬼天气”。';

  /// 群满了（2–8 人）就不再显示邀请
  static bool canInvite(GroupDetail g) => g.maxMembers <= 0 || g.members.length < g.maxMembers;

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
      final state = AppScope.read(context);
      final g = await state.api.group(widget.groupId, unit: state.tempUnit.key);
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

  /// 弹系统分享面板发邀请（发到微信、短信都行，由用户选）；面板打不开时复制下来让 TA 自己粘贴。
  /// [button] 是点的那个按钮，iPad 的分享面板从它的位置弹出
  Future<void> _invite(BuildContext button) async {
    final g = _group!;
    final text = GroupPage.inviteText(g);
    final box = button.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
    if (await widget.sharer.share(text, origin: origin)) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showToast(context, '邀请的话已复制，发到微信给 TA');
  }

  /// 只复制邀请码：当面念给家人，或者 TA 已经装了 App
  Future<void> _copyCode() async {
    final code = _group!.inviteCode;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) showToast(context, '邀请码 $code 已复制');
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
          if (g != null && GroupPage.canInvite(g))
            Builder(
              builder: (button) => TextButton(
                onPressed: () => _invite(button),
                child: const Text('+ 邀请', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
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
                  if (GroupPage.canInvite(g)) ...[
                    if (g.members.length < 2)
                      Builder(builder: (button) => PopButton(label: '发邀请，拉家人进来', onPressed: () => _invite(button))),
                    _InviteCode(code: g.inviteCode, onTap: _copyCode),
                  ],
                  const SourceNote('只能发天气关心，不能聊天 · 只显示城市，不共享位置'),
                  QWeatherCredit(attributions: {for (final m in g.members) ...m.attributions}.toList()),
                ],
              ),
            ),
    );
  }
}

/// 邀请码，点一下复制
class _InviteCode extends StatelessWidget {
  const _InviteCode({required this.code, required this.onTap});

  final String code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '邀请码 $code，点一下复制',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: '邀请码 '),
              TextSpan(text: code, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              const TextSpan(text: ' · 点一下复制'),
            ]),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13),
          ),
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
    final unit = AppScope.of(context).tempUnit;
    final temp = m.temp == null ? '' : '${unit.deg(m.temp!)} ';
    final avatarTemp = weatherTempFromKey(hasWeather ? m.outfit : null);
    final avatarCond = weatherCondFromKey(hasWeather ? m.cond : 'cloudy');
    final bg = !hasWeather ? Pop.white : (m.alert != null ? const Color(0xFFFFF4C2) : sceneColor(m.cond, m.outfit).withAlpha(110));
    final remaining = m.remainingToday ?? 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: Pop.card(color: Color.alphaBlend(bg, Pop.white)),
      child: Row(
        children: [
          // 自己用手机上的形象；别人导入过形象的，从服务端下载
          m.isMe
              ? MyWeatherAvatar(temp: avatarTemp, cond: avatarCond, size: 72)
              : MemberWeatherAvatar(avatarUrl: m.avatarUrl, temp: avatarTemp, cond: avatarCond, size: 72),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.nickname, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                Text(m.city == null ? '还没设置常驻城市' : '${m.city}${hasWeather ? ' · $temp${m.weatherText}' : ''}'),
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
