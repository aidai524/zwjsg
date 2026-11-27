import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:pop_ui/pop_ui.dart';

/// 进化形态（再玩我是狗，2026-11-26）：连续做人解锁的“人”的样子，只在做人（阶段 0）时穿上，一变狗就脱掉。
/// 解锁规则（连续做人几天解锁哪一种）、名字和梗文案在狗 App 里（lib/core/evolution.dart），这里只管怎么画。
/// 现在是代码画的示意，和变狗图层同一套画法（平涂 + 墨线）；美术素材到位后换成图层。
enum Evolution {
  /// 学霸：圆框眼镜 + 学士帽
  scholar,

  /// 西装精英：西装、白衬衫、红领带（照片形象换不了衣服，只在脖子下面加领子和领带）
  elite,

  /// 养生大师：双手捧着泡枸杞的保温杯，冒着热气（完全变狗时捧的是手机）
  wellness,

  /// 头顶光环：头上一圈光环，身边冒金光
  halo;

  /// 存储用的名字认不出来时是 null
  static Evolution? byName(String? name) {
    for (final e in values) {
      if (e.name == name) return e;
    }
    return null;
  }
}

/// 进化形态的配饰怎么画：默认形象（DogAvatar）和照片形象（PhotoDogAvatar）各自给位置和比例。
/// [s] 是相对默认形象 200 画布的比例，线条粗细跟着它走
abstract final class EvolutionArt {
  static const capNavy = Color(0xFF2E3354);
  static const capTop = Color(0xFF424A75);
  static const suit = Color(0xFF3B4058);
  static const suitDark = Color(0xFF2A2E40);
  static const steel = Color(0xFFBFD0DD);
  static const steelDark = Color(0xFF8EA4B6);
  static const tea = Color(0xFFE9B24C);
  static const goji = Color(0xFFE5483B);
  static const skin = Color(0xFFFFD9B8);

  static Paint _fill(Color color) => Paint()
    ..color = color
    ..isAntiAlias = true;

  static Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  static void _shape(Canvas c, Path path, Color fill, double outline) {
    c.drawPath(path, _fill(fill));
    c.drawPath(path, _stroke(Pop.ink, outline));
  }

  /// 圆框眼镜：两只镜框套在眼睛上，中间一道鼻梁，两边镜腿搭到脸边上（[faceLeft]、[faceRight] 是脸边的 x）
  static void glasses(Canvas c, Offset left, Offset right, double r, double faceLeft, double faceRight, double s) {
    final ink = _stroke(Pop.ink, 4.5 * s);
    // 镜腿
    c.drawLine(left + Offset(-r, -2 * s), Offset(faceLeft, left.dy - 6 * s), ink);
    c.drawLine(right + Offset(r, -2 * s), Offset(faceRight, right.dy - 6 * s), ink);
    // 鼻梁
    final mid = Offset((left.dx + right.dx) / 2, (left.dy + right.dy) / 2);
    c.drawPath(
      Path()
        ..moveTo(left.dx + r, left.dy - 2 * s)
        ..quadraticBezierTo(mid.dx, mid.dy - 8 * s, right.dx - r, right.dy - 2 * s),
      ink,
    );
    for (final eye in [left, right]) {
      // 镜片上一道反光（不给镜片上色，眼睛还是亮的）
      c.drawLine(eye + Offset(-r * 0.62, r * 0.08), eye + Offset(-r * 0.2, -r * 0.5), _stroke(const Color(0xB3FFFFFF), 2.5 * s));
      c.drawCircle(eye, r, ink);
    }
  }

  /// 学士帽：头顶扣一顶帽子，上面一块方板，右边垂一束黄色流苏。[board] 是方板的中心，[w] 是方板的半宽
  static void mortarboard(Canvas c, Offset board, double w, double s) {
    final h = w * 0.3;
    // 帽身：扣在头顶，比方板窄一些
    final cap = Path()
      ..moveTo(board.dx - w * 0.62, board.dy + h * 0.2)
      ..lineTo(board.dx - w * 0.58, board.dy + h * 1.55)
      ..quadraticBezierTo(board.dx, board.dy + h * 1.05, board.dx + w * 0.58, board.dy + h * 1.55)
      ..lineTo(board.dx + w * 0.62, board.dy + h * 0.2)
      ..close();
    _shape(c, cap, capNavy, 4.5 * s);
    // 方板：斜着看是一个菱形，上面亮一点
    final top = Path()
      ..moveTo(board.dx, board.dy - h)
      ..lineTo(board.dx + w, board.dy)
      ..lineTo(board.dx, board.dy + h)
      ..lineTo(board.dx - w, board.dy)
      ..close();
    _shape(c, top, capTop, 4.5 * s);
    // 流苏：从方板中间的扣子拉到右边角，再垂下来
    final corner = Offset(board.dx + w * 0.86, board.dy + h * 0.14);
    final end = Offset(corner.dx + 2 * s, corner.dy + w * 0.5);
    c.drawLine(board, corner, _stroke(Pop.yellow, 3 * s));
    c.drawLine(corner, end, _stroke(Pop.ink, 6 * s));
    c.drawLine(corner, end, _stroke(Pop.yellow, 3 * s));
    final tuft = RRect.fromRectAndRadius(
      Rect.fromCenter(center: end + Offset(0, 6 * s), width: 10 * s, height: 16 * s),
      Radius.circular(3 * s),
    );
    c.drawRRect(tuft, _fill(Pop.yellow));
    c.drawRRect(tuft, _stroke(Pop.ink, 3 * s));
    c.drawCircle(board, 3.5 * s, _fill(Pop.yellow));
    c.drawCircle(board, 3.5 * s, _stroke(Pop.ink, 2 * s));
  }

  /// 白衬衫的领子和红领带：[knot] 是领带结的中间，往下 [length] 长
  static void tie(Canvas c, Offset knot, double length, double s) {
    // 领子：左右两片白三角
    for (final side in [-1.0, 1.0]) {
      final collar = Path()
        ..moveTo(knot.dx, knot.dy + 1 * s)
        ..lineTo(knot.dx + side * 16 * s, knot.dy - 7 * s)
        ..lineTo(knot.dx + side * 13 * s, knot.dy + 9 * s)
        ..close();
      _shape(c, collar, Pop.white, 3 * s);
    }
    final blade = Path()
      ..moveTo(knot.dx - 4 * s, knot.dy + 5 * s)
      ..lineTo(knot.dx + 4 * s, knot.dy + 5 * s)
      ..lineTo(knot.dx + 7 * s, knot.dy + length - 6 * s)
      ..lineTo(knot.dx, knot.dy + length)
      ..lineTo(knot.dx - 7 * s, knot.dy + length - 6 * s)
      ..close();
    _shape(c, blade, Pop.kingRed, 3 * s);
    final knotPath = Path()
      ..moveTo(knot.dx - 6 * s, knot.dy - 4 * s)
      ..lineTo(knot.dx + 6 * s, knot.dy - 4 * s)
      ..lineTo(knot.dx + 4 * s, knot.dy + 6 * s)
      ..lineTo(knot.dx - 4 * s, knot.dy + 6 * s)
      ..close();
    _shape(c, knotPath, Pop.kingRed, 3 * s);
  }

  /// 保温杯：杯口开着，茶里泡着枸杞，冒两道热气；两只手捧着（手是 [skin] 的颜色，跟着预设形象的肤色走）。[at] 是杯身中间
  static void thermos(Canvas c, Offset at, double s, {double rotateDeg = -10, Color skin = EvolutionArt.skin}) {
    c.save();
    c.translate(at.dx, at.dy);
    c.scale(s);
    c.rotate(rotateDeg * math.pi / 180);
    // 热气
    for (final x in const [-6.0, 6.0]) {
      final steam = Path()
        ..moveTo(x, -32)
        ..cubicTo(x - 6, -38, x + 6, -44, x, -50);
      c.drawPath(steam, _stroke(Pop.ink, 3));
    }
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(-14, -24, 28, 50), const Radius.circular(7));
    c.drawRRect(body, _fill(steel));
    // 杯身上一道深色的箍
    c.drawRect(const Rect.fromLTWH(-14, 4, 28, 7), _fill(steelDark));
    c.drawRRect(body, _stroke(Pop.ink, 4));
    // 杯口：一圈金属边，里面是茶和枸杞
    final rim = Rect.fromCenter(center: const Offset(0, -24), width: 30, height: 11);
    c.drawOval(rim, _fill(steelDark));
    c.drawOval(rim.deflate(3), _fill(tea));
    for (final g in const [Offset(-5, -25), Offset(1, -23), Offset(6, -25.5)]) {
      c.drawOval(Rect.fromCenter(center: g, width: 5, height: 3.4), _fill(goji));
    }
    c.drawOval(rim, _stroke(Pop.ink, 3.5));
    c.restore();
    // 两只手捧着
    for (final h in [at + Offset(-13 * s, 12 * s), at + Offset(12 * s, 14 * s)]) {
      c.drawCircle(h, 9 * s, _fill(skin));
      c.drawCircle(h, 9 * s, _stroke(Pop.ink, 3.5 * s));
    }
  }

  /// 光环：飘在头顶的一圈金环。[center] 是环的中心，[rx] 是半宽
  static void halo(Canvas c, Offset center, double rx, double s) {
    final ring = Rect.fromCenter(center: center, width: rx * 2, height: rx * 0.46);
    c.drawOval(ring, _stroke(Pop.ink, 10 * s));
    c.drawOval(ring, _stroke(Pop.yellow, 5.5 * s));
    // 一点高光
    c.drawArc(ring.deflate(1 * s), math.pi * 1.1, math.pi * 0.35, false, _stroke(Pop.white, 2 * s));
  }

  /// 四角星的金光
  static void sparkle(Canvas c, Offset center, double size, double s) {
    final p = Path()
      ..moveTo(center.dx, center.dy - size)
      ..quadraticBezierTo(center.dx + size * 0.18, center.dy - size * 0.18, center.dx + size, center.dy)
      ..quadraticBezierTo(center.dx + size * 0.18, center.dy + size * 0.18, center.dx, center.dy + size)
      ..quadraticBezierTo(center.dx - size * 0.18, center.dy + size * 0.18, center.dx - size, center.dy)
      ..quadraticBezierTo(center.dx - size * 0.18, center.dy - size * 0.18, center.dx, center.dy - size)
      ..close();
    _shape(c, p, Pop.yellow, 3 * s);
  }
}
