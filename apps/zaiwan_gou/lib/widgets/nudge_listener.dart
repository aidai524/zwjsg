import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import '../core/api_client.dart';
import '../core/app_state.dart';
import '../core/groups.dart';

/// 群里有人“汪”了你：推送通道还没接，打开 App、回到前台时去服务端看一眼，有就弹出来，看过就标成已读
class NudgeListener extends StatefulWidget {
  const NudgeListener({super.key, required this.child});

  final Widget child;

  /// 两次检查至少隔多久（回前台很频繁）
  static const minGap = Duration(seconds: 30);

  @override
  State<NudgeListener> createState() => _NudgeListenerState();
}

class _NudgeListenerState extends State<NudgeListener> with WidgetsBindingObserver {
  bool _showing = false;
  DateTime? _lastCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (!mounted || _showing) return;
    final state = AppScope.read(context);
    if (!state.isLoggedIn) return;
    final now = DateTime.now();
    if (_lastCheck != null && now.difference(_lastCheck!) < NudgeListener.minGap) return;
    _lastCheck = now;
    try {
      final notes = await state.api.nudgeInbox();
      if (notes.isEmpty || !mounted) return;
      _showing = true;
      await showDialog<void>(context: context, builder: (_) => NudgeDialog(notes: notes));
      await state.api.markNudgesSeen([for (final n in notes) n.id]);
    } on ApiException {
      // 看不了就下次再看
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// “汪！某某叫你放下手机”
class NudgeDialog extends StatelessWidget {
  const NudgeDialog({super.key, required this.notes});

  final List<NudgeNote> notes;

  /// 同一个人汪了几次就写“汪了你 2 次”
  static List<String> lines(List<NudgeNote> notes) {
    final counts = <String, int>{};
    for (final n in notes) {
      final who = '${n.senderNickname}（${n.groupName}）';
      counts[who] = (counts[who] ?? 0) + 1;
    }
    return [for (final e in counts.entries) e.value > 1 ? '${e.key} 汪了你 ${e.value} 次' : '${e.key} 汪了你一下'];
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Pop.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Pop.ink, width: Pop.stroke),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('汪！', textAlign: TextAlign.center, style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            for (final line in lines(notes))
              Text(line, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('狗友叫你放下手机，去干点别的吧', textAlign: TextAlign.center, style: PopText.bodyMuted),
            const SizedBox(height: 16),
            PopButton(label: '放下了', style: PopButtonStyle.dark, onPressed: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}
