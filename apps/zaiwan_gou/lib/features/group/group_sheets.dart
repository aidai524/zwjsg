import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pop_ui/pop_ui.dart';

/// 起群名、改群名：一个输入框，几个现成的名字
Future<String?> showGroupNameSheet(
  BuildContext context, {
  String initial = '',
  String title = '给群起个名字',
  String action = '建群',
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pop.white,
      builder: (_) => _NameSheet(initial: initial, title: title, action: action),
    );

/// 用邀请码加入
Future<String?> showJoinSheet(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pop.white,
      builder: (_) => const _JoinSheet(),
    );

class _NameSheet extends StatefulWidget {
  const _NameSheet({required this.initial, required this.title, required this.action});

  final String initial;
  final String title;
  final String action;

  static const suggestions = ['宿舍狗窝', '相亲相爱一家狗', '打工狗互助会', '饭桌不刷手机'];

  /// 群名最长 16 个字，和后端一致
  static const maxLength = 16;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return setState(() => _error = '起个名字');
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      children: [
        Text(widget.title, style: PopText.h2),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: _NameSheet.maxLength,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: '比如：宿舍狗窝', errorText: _error),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _NameSheet.suggestions)
              ActionChip(
                label: Text(s),
                onPressed: () => setState(() {
                  _controller.text = s;
                  _error = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        PopButton(label: widget.action, onPressed: _submit),
      ],
    );
  }
}

class _JoinSheet extends StatefulWidget {
  const _JoinSheet();

  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _controller.text.trim().toUpperCase();
    if (code.length < 6) return setState(() => _error = '邀请码是 8 位字母和数字');
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      children: [
        const Text('用邀请码加入', style: PopText.h2),
        const SizedBox(height: 4),
        const Text('让群里的人把邀请码发给你，念给你也行。', style: PopText.small),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 8,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]'))],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4),
          decoration: InputDecoration(hintText: 'ABCD2345', errorText: _error),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        PopButton(label: '加入', onPressed: _submit),
      ],
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}
