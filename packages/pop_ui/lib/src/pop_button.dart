import 'package:flutter/material.dart';

import 'theme.dart';

enum PopButtonStyle { primary, secondary, dark }

/// 波普按钮：粗描边 + 硬阴影，按下时整体下沉到阴影位置
class PopButton extends StatefulWidget {
  const PopButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = PopButtonStyle.primary,
    this.height = 56,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final PopButtonStyle style;
  final double height;
  final bool loading;

  @override
  State<PopButton> createState() => _PopButtonState();
}

class _PopButtonState extends State<PopButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final (bg, fg, shadow) = switch (widget.style) {
      PopButtonStyle.primary => (Pop.yellow, Pop.ink, true),
      PopButtonStyle.secondary => (Pop.white, Pop.ink, true),
      PopButtonStyle.dark => (Pop.ink, Pop.white, false),
    };
    final pressedShift = _down && shadow ? Pop.shadowOffset : Offset.zero;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          height: widget.height,
          transform: Matrix4.translationValues(pressedShift.dx, pressedShift.dy, 0),
          decoration: BoxDecoration(
            color: enabled ? bg : Pop.gray,
            borderRadius: BorderRadius.circular(widget.height / 2),
            border: Border.all(color: Pop.ink, width: Pop.stroke),
            boxShadow: shadow && !_down && enabled ? const [BoxShadow(color: Pop.ink, offset: Pop.shadowOffset)] : null,
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 3, color: fg))
              : Text(
                  widget.label,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: enabled ? fg : Pop.muted),
                ),
        ),
      ),
    );
  }
}
