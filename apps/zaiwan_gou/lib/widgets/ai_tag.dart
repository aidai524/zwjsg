import 'package:flutter/widgets.dart';
import 'package:pop_ui/pop_ui.dart';

/// AI 生成内容的显式标识：拍照形象是 AI 模型生成的，显示和导出时都要标出来。
/// 《人工智能生成合成内容标识办法》和 GB 45438-2025 要求文字里有“AI”和“生成”；
/// 导出的图片里，标识放在边或角上，文字高度不低于画面最短边的 5%（见结算卡）。
class AiTag extends StatelessWidget {
  const AiTag({super.key, this.fontSize = 12});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.45, vertical: fontSize * 0.12),
      decoration: BoxDecoration(
        color: Pop.white,
        borderRadius: BorderRadius.circular(fontSize * 0.5),
        border: Border.all(color: Pop.ink, width: 2),
      ),
      child: Text(
        'AI生成',
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, height: 1.15, color: Pop.ink),
      ),
    );
  }
}
