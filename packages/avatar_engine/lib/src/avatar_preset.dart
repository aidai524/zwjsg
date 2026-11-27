import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:pop_ui/pop_ui.dart';

const _skinLight = Color(0xFFFFD9B8);
const _skinWheat = Color(0xFFEDB58A);
const _skinDeep = Color(0xFFB0744C);

/// 预设形象（2026-11-27 用户定：不做捏脸，开头多一步、用起来太复杂；改成预设几张捏好的脸给用户挑）。
/// 没拍照做形象的人从这几张里挑；没挑过就是 [ahoge]（原来的默认形象，一笔没改）。
///
/// 每张脸的发型、发色、肤色不一样，变狗的图层（耳朵、狗毛、鼻子、嘴筒……）大家都一样；
/// 完全变狗（阶段 5）以后头发没了，但每张都留一个认得出是谁的记号：呆毛、丸子、星星发夹、卷毛、粗眉毛、粉毛、中分。
/// 存储和传给服务端用的是 [name]：改名字、加减预设要和狗后端 config/dog.php 的 avatar_presets 一起改（Flutter 测试会对一遍）。
/// 现在是代码画的示意，和变狗图层同一套画法（平涂 + 墨线）；美术素材到位后换成图层。
enum AvatarPreset {
  /// 呆毛短发：原来的默认形象
  ahoge('呆毛', hair: Pop.ink, skin: _skinLight),

  /// 丸子头：头发扎上去，露出额头，扎一圈黄发圈，两缕鬓发
  bun('丸子头', hair: Color(0xFF4A3328), skin: _skinLight),

  /// 黑长直：齐刘海，头发披到肩膀，别一个星星发夹
  long('长发', hair: Pop.ink, skin: _skinLight),

  /// 蓬蓬的卷毛
  curly('卷毛', hair: Color(0xFF6B4226), skin: _skinDeep),

  /// 寸头，粗眉毛
  buzz('寸头', hair: Color(0xFF2A2A30), skin: _skinWheat),

  /// 粉色波波头
  bob('粉色短发', hair: Color(0xFFF59BBE), skin: _skinLight),

  /// 中分，两边的刘海往外翻
  parted('中分', hair: Color(0xFF8A5530), skin: _skinWheat);

  const AvatarPreset(this.label, {required this.hair, required this.skin});

  /// 叫什么（读屏、“我的”页上显示）
  final String label;
  final Color hair;
  final Color skin;

  /// 没挑过的人用这张
  static const fallback = ahoge;

  /// 存储用的名字认不出来时是 null
  static AvatarPreset? byName(String? name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// 预设形象的头发、眉毛、睫毛和记号怎么画（默认形象 [DogAvatar] 的 200 画布）。
/// 画的顺序在 DogAvatar 里：后面的长头发 → 身子 → 头 → 前面的头发（阶段 5 换成一撮狗毛）→ 记号 → 狗耳朵 → 眉毛、眼睛和睫毛
abstract final class PresetArt {
  static const _outline = 5.0;

  /// 黑头发上的那道亮光（和原来的默认形象一样）
  static const _inkShine = Color(0xFF5C5C6A);

  /// 呆毛完全变狗后头顶那撮狗毛的颜色（和 DogAvatar 的深色狗毛一样）
  static const _furDark = Color(0xFFB8743A);

  static Paint _fill(Color color) => Paint()
    ..color = color
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  static Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  /// 头发：黑头发只填色（墨线和发色一样，原来的默认形象就是这么画的）；别的颜色再描一圈墨线
  static void _hair(Canvas c, Path path, Color color) {
    c.drawPath(path, _fill(color));
    if (color != Pop.ink) c.drawPath(path, _stroke(Pop.ink, _outline));
  }

  static Color _shine(Color hair) => hair == Pop.ink ? _inkShine : Color.lerp(hair, Pop.white, 0.42)!;

  /// 比发色深一点：发丝、眉毛
  static Color _shade(Color hair) => hair == Pop.ink ? Pop.ink : Color.lerp(hair, Pop.ink, 0.5)!;

  /// 左右对称的线：给左边的点，右边照着翻过来
  static Offset _flip(Offset p) => Offset(200 - p.dx, p.dy);

  /// 披在身后的长头发（阶段 0–4，画在身子前面一步，让卫衣盖住下面）
  static void backHair(Canvas c, AvatarPreset p) {
    if (p != AvatarPreset.long) return;
    final back = Path()
      ..moveTo(100, 26)
      ..cubicTo(46, 26, 20, 62, 22, 116)
      ..lineTo(22, 176)
      ..quadraticBezierTo(38, 188, 58, 178)
      ..lineTo(142, 178)
      ..quadraticBezierTo(162, 188, 178, 176)
      ..lineTo(178, 116)
      ..cubicTo(180, 62, 154, 26, 100, 26)
      ..close();
    _hair(c, back, p.hair);
  }

  /// 前面的头发（阶段 0–4）
  static void frontHair(Canvas c, AvatarPreset p) {
    switch (p) {
      case AvatarPreset.ahoge:
        // 尖尖的刘海，头顶一道亮光（原来的默认形象）
        final hair = Path()
          ..moveTo(28, 104)
          ..cubicTo(22, 52, 58, 26, 100, 26)
          ..cubicTo(142, 26, 178, 52, 172, 104)
          ..quadraticBezierTo(166, 84, 152, 78)
          ..quadraticBezierTo(148, 94, 132, 92)
          ..quadraticBezierTo(124, 72, 114, 74)
          ..quadraticBezierTo(110, 96, 94, 92)
          ..quadraticBezierTo(86, 72, 74, 76)
          ..quadraticBezierTo(70, 94, 54, 90)
          ..quadraticBezierTo(40, 86, 28, 104)
          ..close();
        c.drawPath(hair, _fill(Pop.ink));
        _shineArc(c, p);
      case AvatarPreset.bun:
        // 头发往上扎，露出额头；两鬓垂下一缕
        final cap = Path()
          ..moveTo(30, 104)
          ..cubicTo(22, 52, 58, 28, 100, 28)
          ..cubicTo(142, 28, 178, 52, 170, 104)
          ..quadraticBezierTo(166, 78, 146, 66)
          ..quadraticBezierTo(124, 54, 100, 57)
          ..quadraticBezierTo(76, 54, 54, 66)
          ..quadraticBezierTo(34, 78, 30, 104)
          ..close();
        _hair(c, cap, p.hair);
        for (final left in [true, false]) {
          Offset q(double x, double y) => left ? Offset(x, y) : _flip(Offset(x, y));
          final a = q(47, 72), ctl = q(33, 96), b = q(40, 124);
          final wisp = Path()
            ..moveTo(a.dx, a.dy)
            ..quadraticBezierTo(ctl.dx, ctl.dy, b.dx, b.dy);
          c.drawPath(wisp, _stroke(Pop.ink, 10));
          c.drawPath(wisp, _stroke(p.hair, 4.5));
        }
        _shineArc(c, p, from: const Offset(54, 60), ctl: const Offset(66, 42), to: const Offset(90, 38));
      case AvatarPreset.long:
        // 齐刘海，两边的头发垂到下巴
        final front = Path()
          ..moveTo(26, 150)
          ..cubicTo(14, 64, 52, 26, 100, 26)
          ..cubicTo(148, 26, 186, 64, 174, 150)
          ..quadraticBezierTo(167, 157, 160, 150)
          ..quadraticBezierTo(162, 112, 154, 86)
          ..quadraticBezierTo(100, 93, 46, 86)
          ..quadraticBezierTo(38, 112, 40, 150)
          ..quadraticBezierTo(33, 157, 26, 150)
          ..close();
        _hair(c, front, p.hair);
        _shineArc(c, p);
      case AvatarPreset.curly:
        // 一团团的卷：头顶一圈，额头上一排
        final base = Path()
          ..moveTo(34, 112)
          ..cubicTo(24, 52, 60, 30, 100, 30)
          ..cubicTo(140, 30, 176, 52, 166, 112)
          ..lineTo(150, 80)
          ..quadraticBezierTo(100, 66, 50, 80)
          ..close();
        const n = 10;
        _curls(c, p.hair, base: base, curls: [
          for (var i = 0; i < n; i++)
            (
              Offset(100 + 68 * math.cos((200 - i * 220 / (n - 1)) * math.pi / 180),
                  94 - 64 * math.sin((200 - i * 220 / (n - 1)) * math.pi / 180)),
              17.0,
            ),
          for (final (x, y) in const [(54.0, 77.0), (77.0, 73.0), (100.0, 71.0), (123.0, 73.0), (146.0, 77.0)])
            (Offset(x, y), 15.0),
        ]);
      case AvatarPreset.buzz:
        // 贴着头皮的一层短发，额头露出来
        final cap = Path()
          ..moveTo(32, 98)
          ..cubicTo(28, 54, 60, 31, 100, 31)
          ..cubicTo(140, 31, 172, 54, 168, 98)
          ..quadraticBezierTo(164, 76, 150, 68)
          ..quadraticBezierTo(132, 58, 100, 60)
          ..quadraticBezierTo(68, 58, 50, 68)
          ..quadraticBezierTo(36, 76, 32, 98)
          ..close();
        _hair(c, cap, p.hair);
        _shineArc(c, p, from: const Offset(56, 54), ctl: const Offset(70, 42), to: const Offset(90, 39));
      case AvatarPreset.bob:
        // 圆圆的波波头，刘海往一边斜
        final bob = Path()
          ..moveTo(34, 150)
          ..cubicTo(10, 118, 16, 28, 100, 26)
          ..cubicTo(184, 28, 190, 118, 166, 150)
          ..quadraticBezierTo(159, 156, 152, 148)
          ..quadraticBezierTo(158, 112, 150, 88)
          ..quadraticBezierTo(126, 94, 106, 80)
          ..quadraticBezierTo(78, 93, 50, 88)
          ..quadraticBezierTo(42, 112, 48, 148)
          ..quadraticBezierTo(41, 156, 34, 150)
          ..close();
        _hair(c, bob, p.hair);
        _shineArc(c, p, from: const Offset(46, 64), ctl: const Offset(60, 42), to: const Offset(88, 36));
      case AvatarPreset.parted:
        // 中分：从头顶分开，两边的刘海往外翻，额头露出一个三角
        final hair = Path()
          ..moveTo(28, 110)
          ..cubicTo(20, 52, 58, 26, 100, 26)
          ..cubicTo(142, 26, 180, 52, 172, 110)
          ..quadraticBezierTo(168, 86, 150, 80)
          ..quadraticBezierTo(116, 72, 102, 46)
          ..lineTo(98, 46)
          ..quadraticBezierTo(84, 72, 50, 80)
          ..quadraticBezierTo(32, 86, 28, 110)
          ..close();
        _hair(c, hair, p.hair);
        final strand = _stroke(_shade(p.hair), 3);
        c.drawLine(const Offset(100, 30), const Offset(100, 46), strand);
        for (final left in [true, false]) {
          Offset q(double x, double y) => left ? Offset(x, y) : _flip(Offset(x, y));
          final a = q(94, 52), ctl = q(80, 72), b = q(58, 78);
          c.drawPath(
            Path()
              ..moveTo(a.dx, a.dy)
              ..quadraticBezierTo(ctl.dx, ctl.dy, b.dx, b.dy),
            strand,
          );
        }
        _shineArc(c, p, from: const Offset(46, 64), ctl: const Offset(58, 42), to: const Offset(84, 36));
    }
  }

  static void _shineArc(Canvas c, AvatarPreset p,
      {Offset from = const Offset(52, 56), Offset ctl = const Offset(68, 40), Offset to = const Offset(92, 38)}) {
    c.drawPath(
      Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(ctl.dx, ctl.dy, to.dx, to.dy),
      _stroke(_shine(p.hair), 5),
    );
  }

  /// 一团团的卷：先把每团描粗一圈墨线，再填色，叠在一起只剩外面一圈轮廓；每团里一道小弯
  static void _curls(Canvas c, Color color, {required List<(Offset, double)> curls, Path? base}) {
    final ink = _stroke(Pop.ink, 8);
    if (base != null) c.drawPath(base, ink);
    for (final (o, r) in curls) {
      c.drawCircle(o, r, ink);
    }
    final fill = _fill(color);
    if (base != null) c.drawPath(base, fill);
    for (final (o, r) in curls) {
      c.drawCircle(o, r, fill);
    }
    final curl = _stroke(_shade(color), 2.5);
    for (final (o, r) in curls) {
      c.drawArc(Rect.fromCircle(center: o + Offset(r * 0.08, r * 0.1), radius: r * 0.48), math.pi * 0.85, math.pi * 1.3,
          false, curl);
    }
  }

  /// 完全变狗（阶段 5）以后头顶剩下的一撮毛，按发型来
  static void dogTuft(Canvas c, AvatarPreset p) {
    // 原来的默认形象：一撮深色狗毛
    final lens = Path()
      ..moveTo(70, 44)
      ..quadraticBezierTo(100, 26, 130, 44)
      ..quadraticBezierTo(118, 60, 100, 56)
      ..quadraticBezierTo(82, 60, 70, 44)
      ..close();
    switch (p) {
      case AvatarPreset.ahoge:
        c.drawPath(lens, _fill(_furDark));
      case AvatarPreset.bun:
      case AvatarPreset.bob:
        // 头发的颜色留在这撮毛上：丸子头的上面还顶着丸子，粉毛还是粉的
        _hair(c, lens, p.hair);
      case AvatarPreset.long:
        // 一排齐刘海
        final fringe = Path()
          ..moveTo(64, 56)
          ..quadraticBezierTo(66, 30, 100, 30)
          ..quadraticBezierTo(134, 30, 136, 56)
          ..quadraticBezierTo(100, 62, 64, 56)
          ..close();
        _hair(c, fringe, p.hair);
      case AvatarPreset.curly:
        _curls(c, p.hair, curls: const [
          (Offset(78, 46), 10),
          (Offset(122, 46), 10),
          (Offset(89, 53), 9),
          (Offset(111, 53), 9),
          (Offset(100, 38), 12),
        ]);
      case AvatarPreset.buzz:
        // 寸头本来就没几根头发，记号是粗眉毛（见 [brows]）
        break;
      case AvatarPreset.parted:
        // 还是中分的两撮
        final swoops = Path()
          ..moveTo(100, 34)
          ..quadraticBezierTo(74, 34, 64, 56)
          ..quadraticBezierTo(86, 54, 100, 42)
          ..quadraticBezierTo(114, 54, 136, 56)
          ..quadraticBezierTo(126, 34, 100, 34)
          ..close();
        _hair(c, swoops, p.hair);
    }
  }

  /// 一直都在、变成狗也认得出是你的记号（画在头发后面一步、学士帽前面一步）。
  /// [capped]：戴着学士帽（进化形态「学霸」），丸子被帽子压住就不画了
  static void mark(Canvas c, AvatarPreset p, int stage, {bool capped = false}) {
    switch (p) {
      case AvatarPreset.ahoge:
        // 呆毛
        final ahoge = Path()
          ..moveTo(100, 28)
          ..cubicTo(97, 8, 124, 4, 117, 22);
        c.drawPath(ahoge, _stroke(Pop.ink, 5));
      case AvatarPreset.bun:
        if (capped) return;
        // 头顶的丸子，扎一圈黄发圈
        const o = Offset(100, 24);
        c.drawCircle(o, 16, _fill(p.hair));
        c.drawCircle(o, 16, _stroke(Pop.ink, _outline));
        c.drawArc(Rect.fromCircle(center: o, radius: 9.5), math.pi * 1.05, math.pi * 0.45, false, _stroke(_shine(p.hair), 3.5));
        final tie = RRect.fromRectAndRadius(
            Rect.fromCenter(center: const Offset(100, 39), width: 26, height: 8), const Radius.circular(4));
        c.drawRRect(tie, _fill(Pop.yellow));
        c.drawRRect(tie, _stroke(Pop.ink, 3));
      case AvatarPreset.long:
        // 星星发夹：做人时别在刘海上，变成狗了别在那撮毛上
        final star = _star(stage >= 5 ? const Offset(121, 42) : const Offset(125, 61), 12);
        c.drawPath(star, _fill(Pop.yellow));
        c.drawPath(star, _stroke(Pop.ink, 3));
      case AvatarPreset.curly:
      case AvatarPreset.buzz:
      case AvatarPreset.bob:
      case AvatarPreset.parted:
        break;
    }
  }

  static Path _star(Offset center, double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rr = i.isEven ? r : r * 0.48;
      final pt = center + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    return path..close();
  }

  /// 眉毛（画在腮红后面一步、眼睛前面一步）：露额头的丸子头、中分是细眉，变成狗就没了；
  /// 寸头是粗眉毛，完全变狗也留着，是它的记号
  static void brows(Canvas c, AvatarPreset p, int stage) {
    switch (p) {
      case AvatarPreset.bun:
      case AvatarPreset.parted:
        if (stage >= 5) return;
        final brow = _stroke(_shade(p.hair), 3.5);
        for (final x in const [74.0, 126.0]) {
          c.drawPath(
            Path()
              ..moveTo(x - 10, 93)
              ..quadraticBezierTo(x, 86.5, x + 10, 93),
            brow,
          );
        }
      case AvatarPreset.buzz:
        for (final (x, deg) in const [(73.0, -3.0), (127.0, 3.0)]) {
          c.save();
          c.translate(x, 91);
          c.rotate(deg * math.pi / 180);
          c.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 25, height: 8.5), const Radius.circular(4.25)),
            _fill(p.hair),
          );
          c.restore();
        }
      case AvatarPreset.ahoge:
      case AvatarPreset.long:
      case AvatarPreset.curly:
      case AvatarPreset.bob:
        break;
    }
  }

  /// 睫毛（画在眼睛后面）：丸子头、长发、粉色短发，变成狗也留着
  static void lashes(Canvas c, AvatarPreset p) {
    if (p != AvatarPreset.bun && p != AvatarPreset.long && p != AvatarPreset.bob) return;
    final ink = _stroke(Pop.ink, 3);
    for (final (x, dir) in const [(74.0, -1.0), (126.0, 1.0)]) {
      c.drawLine(Offset(x + dir * 8.5, 104), Offset(x + dir * 14.5, 99), ink);
      c.drawLine(Offset(x + dir * 10.5, 109), Offset(x + dir * 17, 106.5), ink);
    }
  }
}
