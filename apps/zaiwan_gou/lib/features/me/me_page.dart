import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/dog_meter.dart';
import '../../core/screen_time_channel.dart';
import 'package:pop_ui/pop_ui.dart';
import '../../widgets/my_avatar.dart';
import 'export_avatar_sheet.dart';

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

  Future<void> _editNickname(BuildContext context) async {
    final state = AppScope.read(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NicknameDialog(initial: state.nickname ?? ''),
    );
    if (name != null) await state.setNickname(name);
  }

  /// 导出到“什么鬼天气”：要先登录（天气 App 从服务端取图），再生成导出码
  Future<void> _exportAvatar(BuildContext context) async {
    final state = AppScope.read(context);
    if (!state.isLoggedIn) {
      final login = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('导出要先登录'),
          content: const Text('「什么鬼天气」是从我们的服务器取你的卡通形象，所以要先登录，把形象存上去。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('算了')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('去登录')),
          ],
        ),
      );
      if (login == true && context.mounted) context.push('/login');
      return;
    }
    try {
      final export = await state.exportAvatar();
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Pop.white,
        builder: (_) => ExportAvatarSheet(code: export.code, expiresAt: export.expiresAt),
      );
    } on ApiException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _editReminder(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Pop.white,
        builder: (_) => const _ReminderSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return Scaffold(
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
                    child: const MyAvatar(stage: 0, size: 56),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          button: true,
                          hint: '改昵称',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _editNickname(context),
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    state.nickname ?? '给自己起个名字',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.edit_outlined, size: 16, color: Pop.muted),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          '${state.isLoggedIn ? '' : '还没登录 · '}图鉴 ${state.ownedBreeds.length} / 8',
                          style: PopText.small,
                        ),
                      ],
                    ),
                  ),
                  if (!state.isLoggedIn) TextButton(onPressed: () => context.push('/login'), child: const Text('登录')),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: Pop.card(color: Pop.softYellow),
              child: const Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('开通会员', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        Text('动态结算卡、周报月报、多套形象', style: TextStyle(fontSize: 12, color: Pop.mutedOnYellow)),
                      ],
                    ),
                  ),
                  Text('即将上线', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            const _Section('形象'),
            _Group(children: [
              _Row(
                title: state.photoAvatar == null ? '用自拍做形象' : '换个形象',
                trailing: state.photoAvatar == null ? '默认形象' : '拍照形象',
                onTap: () => context.push('/avatar?edit=1'),
              ),
              if (state.photoAvatar != null) _Row(title: '导出到「什么鬼天气」', onTap: () => _exportAvatar(context)),
            ]),
            const _Section('目标与提醒'),
            _Group(children: [
              _Row(
                title: '每日目标',
                trailing: DogMeter.formatMinutes(state.goalMinutes),
                onTap: () => context.push('/goal?edit=1'),
              ),
              _Row(title: '结算卡提醒', trailing: state.reminderLabel, onTap: () => _editReminder(context)),
            ]),
            const _Section('玩法'),
            _Group(children: [
              _Row(title: 'App 时间锁', trailing: '免费', onTap: () => context.push('/locks')),
              const _Row(title: '装扮商店', trailing: '即将上线'),
            ]),
            if (ScreenTimeChannel.isSupported) ...[
              const _Section('技术验证'),
              _Group(children: [
                _Row(title: '屏幕使用时间', trailing: 'iOS', onTap: () => context.push('/screen-time')),
                _Row(title: '拍照形象（本地卡通化）', trailing: 'iOS', onTap: () => context.push('/cartoon-lab')),
              ]),
            ],
            const _Section('隐私与账号'),
            _Group(children: [
              _Row(title: '隐私政策', onTap: () => context.push('/privacy')),
              if (state.isLoggedIn) _Row(title: '退出登录', onTap: state.logout),
              if (state.isLoggedIn) _Row(title: '删除我的形象和数据', danger: true, onTap: () => _confirmDelete(context)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.initial});

  final String initial;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = AppState.nicknameError(_controller.text);
    if (error != null) return setState(() => _error = error);
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('起个名字'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: AppState.nicknameMaxLength,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: '朋友平时怎么叫你', errorText: _error),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

/// 每晚提醒：开关 + 几个常用时间。打开时才问通知权限。
class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet();

  /// 可选的提醒时间（从 0 点算的分钟数）
  static const presets = [20 * 60, 21 * 60, 21 * 60 + 30, 22 * 60, 22 * 60 + 30, 23 * 60];

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  bool _denied = false;

  Future<void> _enable([int? minutesOfDay]) async {
    final ok = await AppScope.read(context).enableReminder(minutesOfDay);
    if (mounted) setState(() => _denied = !ok);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('结算卡提醒', style: PopText.h2),
            const SizedBox(height: 4),
            const Text('每晚到点提醒你看今天的结算卡，提醒在手机本地，不经过服务器。', style: PopText.small),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('每晚提醒我', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              value: state.reminderOn,
              activeThumbColor: Pop.ink,
              onChanged: (on) => on ? _enable() : state.disableReminder(),
            ),
            if (_denied)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('通知没开：去系统设置里打开“再玩我是狗”的通知，再回来打开提醒。', style: TextStyle(fontSize: 13, color: Pop.danger)),
              ),
            const Text('提醒时间', style: PopText.label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _ReminderSheet.presets)
                  ChoiceChip(
                    label: Text(AppState.formatHhmm(t)),
                    selected: state.reminderOn && state.reminderMinutes == t,
                    onSelected: (_) => _enable(t),
                  ),
              ],
            ),
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
            : Text('${trailing ?? ''}${onTap != null ? '  ›' : ''}',
                style: const TextStyle(fontSize: 14, color: Pop.muted)),
        onTap: onTap,
      );
}
