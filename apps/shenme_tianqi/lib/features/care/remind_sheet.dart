import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/scene.dart';

/// 发提醒：只能从 1–3 句温和的关心话里选，不能自己打字，不带吐槽
class RemindSheet extends StatefulWidget {
  const RemindSheet({super.key, required this.groupId, required this.member});

  final int groupId;
  final Member member;

  @override
  State<RemindSheet> createState() => _RemindSheetState();
}

class _RemindSheetState extends State<RemindSheet> {
  int _pick = 0;
  bool _sending = false;
  SentReminder? _sent;
  String? _error;

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final r = await AppScope.read(context).api.remind(
            groupId: widget.groupId,
            recipientId: widget.member.id,
            phraseKey: widget.member.phrases[_pick].key,
          );
      if (mounted) setState(() => _sent = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final phrases = m.phrases;
    final sent = _sent;

    String buttonText;
    if (sent == null) {
      buttonText = '发给${m.nickname}';
    } else if (sent.status == 'scheduled') {
      buttonText = '${sent.deliverAt.day == DateTime.now().day ? '今天' : '明天'} ${hm(sent.deliverAt)} 送达 ♥';
    } else {
      buttonText = '已发给${m.nickname} ♥';
    }

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Pop.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Pop.ink, width: Pop.stroke)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('提醒${m.nickname}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            if (m.city != null) Text('${m.city} · ${m.fact}', style: const TextStyle(color: Pop.muted)),
            const SizedBox(height: 16),
            const Text('选一句发给 TA', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (var i = 0; i < phrases.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Semantics(
                  button: true,
                  selected: _pick == i,
                  child: GestureDetector(
                    onTap: sent == null ? () => setState(() => _pick = i) : null,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: Pop.card(color: _pick == i ? Pop.yellow : Pop.white, shadow: _pick == i),
                      child: Text(phrases[i].text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: const TextStyle(color: Pop.danger))),
            PopButton(
              label: buttonText,
              loading: _sending,
              style: sent == null ? PopButtonStyle.primary : PopButtonStyle.secondary,
              onPressed: sent == null ? _send : () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 10),
            Text(
              '今天还能给${m.nickname}发 ${sent?.remainingToday ?? m.remainingToday ?? 0} 次 · 22 点后发的会在早上 7 点送达\n关心话都是温柔版，不带吐槽',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Pop.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
