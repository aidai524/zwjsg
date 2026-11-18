import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pop_ui/pop_ui.dart';

/// 导出码：把卡通形象一次性导给“什么鬼天气”。8 位，10 分钟内有效，只能用一次
class ExportAvatarSheet extends StatefulWidget {
  const ExportAvatarSheet({super.key, required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;

  /// 中间加个连字符好念：ABCD-EFGH。天气 App 那边填的时候连字符、大小写都不讲究
  static String display(String code) => code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

  @override
  State<ExportAvatarSheet> createState() => _ExportAvatarSheetState();
}

class _ExportAvatarSheetState extends State<ExportAvatarSheet> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.expiresAt.toLocal();
    final until = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('导出到「什么鬼天气」', style: PopText.h2),
            const SizedBox(height: 4),
            Text('$until 前有效，只能用一次', style: PopText.small),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              decoration: Pop.card(color: Pop.yellow),
              child: SelectableText(
                ExportAvatarSheet.display(widget.code),
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 4),
              ),
            ),
            const SizedBox(height: 12),
            PopButton(label: _copied ? '复制好了' : '复制导出码', style: PopButtonStyle.dark, onPressed: _copy),
            const SizedBox(height: 14),
            const Text('打开「什么鬼天气」› 设置 › 我的形象 › 导入，把这个码填进去。', style: PopText.body),
            const SizedBox(height: 6),
            const Text('只导出卡通形象，不是照片。导过去以后两边互不影响：这边换了形象，那边不会跟着变。', style: PopText.small),
          ],
        ),
      ),
    );
  }
}
