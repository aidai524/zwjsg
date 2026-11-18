import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';

/// 弹出“从再玩我是狗导入形象”；导入成功返回 true
Future<bool?> showImportAvatarSheet(BuildContext context) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pop.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const ImportAvatarSheet(),
    );

/// 填“再玩我是狗”给的导出码，一次性导入卡通形象。两个 App 账号不互通，只复制一次图片
class ImportAvatarSheet extends StatefulWidget {
  const ImportAvatarSheet({super.key});

  @override
  State<ImportAvatarSheet> createState() => _ImportAvatarSheetState();
}

class _ImportAvatarSheetState extends State<ImportAvatarSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.isEmpty) return setState(() => _error = '先填导出码');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).importAvatar(code);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('从「再玩我是狗」导入形象', style: PopText.h2),
            const SizedBox(height: 10),
            const Text('1. 打开「再玩我是狗」› 我的 › 形象 › 导出到「什么鬼天气」', style: PopText.body),
            const SizedBox(height: 4),
            const Text('2. 把 8 位导出码填在下面，10 分钟内有效', style: PopText.body),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              autofocus: true,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              maxLength: 12,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2),
              decoration: InputDecoration(hintText: 'ABCD-EFGH', errorText: _error, errorMaxLines: 3, counterText: ''),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            PopButton(label: '导入', style: PopButtonStyle.dark, loading: _busy, onPressed: _busy ? null : _submit),
            const SizedBox(height: 10),
            const Text(
              '只导入卡通形象，不是照片。导进来以后两边互不影响；登录后会存到服务器，换手机能找回来，关心群里的家人也能看到。',
              style: PopText.small,
            ),
          ],
        ),
      ),
    );
  }
}
