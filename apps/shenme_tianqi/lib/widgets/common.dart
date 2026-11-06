import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

/// 带描边的圆形图标按钮
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({super.key, required this.icon, required this.label, required this.onTap, this.badge = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Pop.white,
                shape: BoxShape.circle,
                border: Border.all(color: Pop.ink, width: Pop.stroke),
              ),
              child: Icon(icon, size: 22, color: Pop.ink),
            ),
            if (badge)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Pop.kingRed,
                    shape: BoxShape.circle,
                    border: Border.all(color: Pop.ink, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 小标签：如“常驻”
class Chip2 extends StatelessWidget {
  const Chip2(this.text, {super.key, this.color = Pop.white});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Pop.ink, width: 2),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}

/// 页尾的数据来源说明（合规要求：注明来源）
class SourceNote extends StatelessWidget {
  const SourceNote(this.text, {super.key, this.color = Pop.muted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: color, height: 1.5)),
    );
  }
}

void showToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}
