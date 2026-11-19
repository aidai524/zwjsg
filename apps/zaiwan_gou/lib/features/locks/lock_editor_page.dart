import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_lock.dart';
import '../../core/dog_meter.dart';

/// 新建或修改一个限时：选 App、选每天最多用多久，用满了来电
class LockEditorPage extends StatefulWidget {
  const LockEditorPage({super.key, required this.service, this.lock});

  final LockService service;

  /// null 表示新建
  final AppLock? lock;

  /// 每天额度可选的分钟数
  static const presets = [15, 30, 45, 60, 90, 120, 180];

  @override
  State<LockEditorPage> createState() => _LockEditorPageState();
}

class _LockEditorPageState extends State<LockEditorPage> {
  late final LockDraft _draft = widget.lock == null ? LockDraft() : LockDraft.of(widget.lock!);
  bool _busy = false;
  bool _saved = false;

  /// 这次打开后重新选过 App：预览要显示刚选的，而不是已保存的
  bool _picked = false;

  /// 每选一次加 1，让预览重建
  int _pickVersion = 0;

  @override
  void dispose() {
    // iOS 选好的 App 暂存在原生层，没保存就丢掉
    if (!_saved) widget.service.discardDraft();
    super.dispose();
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pick() async {
    try {
      final changed = await widget.service.pickApps(context, _draft);
      if (changed && mounted) {
        setState(() {
          _picked = true;
          _pickVersion++;
        });
      }
    } on PlatformException catch (e) {
      if (mounted) _toast(e.message ?? '选择页没打开，稍后再试');
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.service.save(_draft);
      _saved = true;
      if (mounted) Navigator.pop(context, true);
    } on PlatformException catch (e) {
      if (mounted) _toast(e.message ?? '没保存上，稍后再试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final preview = _draft.hasApps ? service.selectionPreview(lockId: widget.lock?.id, draft: _picked) : null;
    final hint = service.pickHint;
    return Scaffold(
      appBar: AppBar(title: Text(widget.lock == null ? '新的限时' : '改限时')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text('锁哪些 App', style: PopText.label),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              decoration: BoxDecoration(color: Pop.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _draft.summary,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _draft.hasApps ? Pop.ink : Pop.muted,
                          ),
                        ),
                      ),
                      TextButton(onPressed: _busy ? null : _pick, child: Text(_draft.hasApps ? '重新选' : '选择 App')),
                    ],
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: 6),
                    KeyedSubtree(key: ValueKey(_pickVersion), child: preview),
                  ],
                ],
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(hint, style: PopText.small),
            ],
            if (_draft.categories > 0) ...[
              const SizedBox(height: 8),
              const Text(
                '你选了整个类别：这一类的 App 都会被锁。只想锁某一个，就点“重新选”，在选择页里点开类别单独勾。',
                style: TextStyle(fontSize: 13, height: 1.5, color: Pop.danger, fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 20),
            const Text('每天最多用', style: PopText.label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in LockEditorPage.presets)
                  ChoiceChip(
                    label: Text(DogMeter.formatMinutes(m)),
                    selected: _draft.minutes == m,
                    onSelected: (_) => setState(() => _draft.minutes = m),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(service.limitNote, style: PopText.small),
            const SizedBox(height: 24),
            PopButton(label: '保存', loading: _busy, onPressed: _draft.hasApps && !_busy ? _save : null),
          ],
        ),
      ),
    );
  }
}
