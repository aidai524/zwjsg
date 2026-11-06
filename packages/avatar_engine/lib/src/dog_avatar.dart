import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:pop_ui/pop_ui.dart';

/// 卡通形象：按变狗阶段 0–5 分层叠加。
/// 现在是代码画的示意图；美术素材到位后，每一层换成对应的图片图层即可（层的顺序和开关逻辑不变）。
class DogAvatar extends StatelessWidget {
  const DogAvatar({super.key, required this.stage, this.size = 200});

  final int stage;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = stage.clamp(0, 5);
    return Semantics(
      label: '卡通形象，变狗阶段 $s',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _AvatarPainter(s)),
      ),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  _AvatarPainter(this.stage);

  final int stage;

  static const _brown = Color(0xFFA86B32);
  static const _skin = Color(0xFFFFD9B8);
  static const _fur = Color(0xFFD9A066);
  static const _snout = Color(0xFFFFF4E6);
  static const _blush = Color(0xFFFF8FA8);
  static const _tongue = Color(0xFFFF7A9A);

  Paint _fill(Color c) => Paint()
    ..color = c
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  void _ellipse(Canvas c, Offset center, double rx, double ry, Paint p, {double rotateDeg = 0}) {
    c.save();
    c.translate(center.dx, center.dy);
    if (rotateDeg != 0) c.rotate(rotateDeg * math.pi / 180);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), p);
    c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / 200, size.height / 200);
    final ink = Pop.ink;

    // 尾巴（阶段 4+）
    if (stage >= 4) {
      final tail = Path()
        ..moveTo(146, 178)
        ..quadraticBezierTo(194, 164, 186, 122);
      canvas.drawPath(tail, _stroke(ink, 18));
      canvas.drawPath(tail, _stroke(_brown, 10));
    }

    // 身体
    final body = Path()
      ..moveTo(42, 202)
      ..quadraticBezierTo(46, 146, 100, 144)
      ..quadraticBezierTo(154, 146, 158, 202)
      ..close();
    canvas.drawPath(body, _fill(stage >= 5 ? _fur : Pop.white));
    canvas.drawPath(body, _stroke(ink, 4));

    // 项圈（阶段 3+）
    if (stage >= 3) {
      final collar = Path()
        ..moveTo(72, 150)
        ..quadraticBezierTo(100, 166, 128, 150);
      canvas.drawPath(collar, _stroke(Pop.kingRed, 9));
      canvas.drawCircle(const Offset(100, 166), 7, _fill(Pop.yellow));
      canvas.drawCircle(const Offset(100, 166), 7, _stroke(ink, 3));
    }

    // 头
    canvas.drawCircle(const Offset(100, 90), 60, _fill(stage >= 3 ? _fur : _skin));
    canvas.drawCircle(const Offset(100, 90), 60, _stroke(ink, 4));

    // 狗毛（阶段 3+）
    if (stage >= 3) {
      _ellipse(canvas, const Offset(100, 50), 26, 14, _fill(_brown));
      final tufts = Path()
        ..moveTo(42, 104)
        ..lineTo(30, 112)
        ..lineTo(46, 114)
        ..close()
        ..moveTo(158, 104)
        ..lineTo(170, 112)
        ..lineTo(154, 114)
        ..close();
      canvas.drawPath(tufts, _fill(_brown));
      canvas.drawPath(tufts, _stroke(ink, 2.5));
    }

    // 头发（阶段 5 消失）
    if (stage < 5) {
      final hair = Path()
        ..moveTo(40, 84)
        ..quadraticBezierTo(40, 28, 100, 28)
        ..quadraticBezierTo(160, 28, 160, 84)
        ..quadraticBezierTo(146, 54, 100, 54)
        ..quadraticBezierTo(62, 54, 40, 84)
        ..close();
      canvas.drawPath(hair, _fill(ink));
    }

    // 狗耳朵（阶段 1+）
    if (stage >= 1) {
      for (final (center, deg) in [(const Offset(46, 70), 18.0), (const Offset(154, 70), -18.0)]) {
        _ellipse(canvas, center, 18, 38, _fill(_brown), rotateDeg: deg);
        _ellipse(canvas, center, 18, 38, _stroke(ink, 4), rotateDeg: deg);
      }
    }

    // 狗嘴筒（阶段 2+）
    if (stage >= 2) {
      _ellipse(canvas, const Offset(100, 116), 30, 22, _fill(_snout));
      _ellipse(canvas, const Offset(100, 116), 30, 22, _stroke(ink, 3));
    }

    // 腮红（阶段 0–2）
    if (stage < 3) {
      _ellipse(canvas, const Offset(70, 108), 9, 5, _fill(_blush));
      _ellipse(canvas, const Offset(130, 108), 9, 5, _fill(_blush));
    }

    // 眼睛
    for (final x in [77.0, 123.0]) {
      canvas.drawCircle(Offset(x, 86), 7.5, _fill(ink));
      canvas.drawCircle(Offset(x + 2.5, 83.5), 2.4, _fill(Pop.white));
    }

    if (stage < 2) {
      // 人的鼻子和笑脸
      final nose = Path()
        ..moveTo(100, 95)
        ..lineTo(95, 104)
        ..lineTo(104, 104);
      canvas.drawPath(nose, _stroke(ink, 3));
      final smile = Path()
        ..moveTo(84, 118)
        ..quadraticBezierTo(100, 130, 116, 118);
      canvas.drawPath(smile, _stroke(ink, 3.5));
    } else {
      // 狗鼻子
      _ellipse(canvas, const Offset(100, 104), 12, 8.5, _fill(ink));
    }

    // 舌头（阶段 4+）
    if (stage >= 4) {
      final tongue = Path()
        ..moveTo(92, 128)
        ..lineTo(108, 128)
        ..lineTo(108, 141)
        ..arcToPoint(const Offset(92, 141), radius: const Radius.circular(8))
        ..close();
      canvas.drawPath(tongue, _fill(_tongue));
      canvas.drawPath(tongue, _stroke(ink, 3));
    }

    // 狗嘴（阶段 2+）
    if (stage >= 2) {
      final mouth = Path()
        ..moveTo(100, 112)
        ..lineTo(100, 121)
        ..moveTo(100, 121)
        ..quadraticBezierTo(90, 131, 81, 122)
        ..moveTo(100, 121)
        ..quadraticBezierTo(110, 131, 119, 122);
      canvas.drawPath(mouth, _stroke(ink, 3.5));
    }
  }

  @override
  bool shouldRepaint(_AvatarPainter old) => old.stage != stage;
}
