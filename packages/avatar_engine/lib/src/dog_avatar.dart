import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:pop_ui/pop_ui.dart';

import 'avatar_preset.dart';
import 'evolution.dart';
import 'widget_images.dart';

/// 变狗形象画法的版本：改了画法（默认形象、照片形象的变狗图层，包括换成美术素材）就加 1（2：2026-11-23 改得更可爱、更有冲击力），
/// 桌面小组件用的形象图是 App 预先画好存在手机上的，版本变了才会重画
const dogAvatarArtVersion = 2;

/// 不经过 Widget 树，把代码画的形象画成 [pixels] x [pixels] 的图片（背景透明），和 [DogAvatar] 一样。
/// 给桌面小组件用，返回的图片用完要 dispose
Future<ui.Image> renderDogAvatar({
  required int stage,
  int pixels = 360,
  Evolution? evolution,
  AvatarPreset preset = AvatarPreset.fallback,
}) =>
    paintToImage(_AvatarPainter(stage.clamp(0, 5), evolution, preset), pixels);

/// 卡通形象：按变狗阶段 0–5 分层叠加；做人（阶段 0）时可以穿上进化形态 [evolution]。
/// 脸是挑的那张预设形象 [preset]（发型、发色、肤色），没挑过是原来的默认形象（呆毛）。
/// 现在是代码画的示意图；美术素材到位后，每一层换成对应的图片图层即可（层的顺序和开关逻辑不变）。
class DogAvatar extends StatelessWidget {
  const DogAvatar({super.key, required this.stage, this.size = 200, this.evolution, this.preset = AvatarPreset.fallback});

  final int stage;
  final double size;

  /// 进化形态：只在阶段 0 画，变狗了就不穿
  final Evolution? evolution;

  /// 哪张预设形象
  final AvatarPreset preset;

  @override
  Widget build(BuildContext context) {
    final s = stage.clamp(0, 5);
    return Semantics(
      label: '卡通形象，变狗阶段 $s',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _AvatarPainter(s, evolution, preset)),
      ),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  _AvatarPainter(this.stage, [this.evolution, this.preset = AvatarPreset.fallback]);

  final int stage;
  final Evolution? evolution;
  final AvatarPreset preset;

  // 配色：亮黄卫衣（Pop.yellow）、焦糖色狗毛、深一点的耳朵和眼圈斑、奶白的嘴筒；皮肤和头发的颜色跟着预设形象走
  static const _fur = Color(0xFFE3A869);
  static const _furDark = Color(0xFFB8743A);
  static const _ear = Color(0xFFA8652E);
  static const _earInner = Color(0xFFF0A98A);
  static const _cream = Color(0xFFFFF4E6);
  static const _blush = Color(0xFFFF8FA8);
  static const _blushLine = Color(0xFFF06A8C);
  static const _mouth = Color(0xFFB5304A);
  static const _tongue = Color(0xFFFF6F8E);
  static const _tongueLine = Color(0xFFD9486B);
  static const _screen = Color(0xFF8BE0FF);

  /// 外轮廓的墨线粗细（200 的画布）：粗一点才有冲击力
  static const _outline = 5.0;

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

  /// 先填色再描墨线
  void _shape(Canvas c, Path path, Color fill, {double outline = _outline}) {
    c.drawPath(path, _fill(fill));
    c.drawPath(path, _stroke(Pop.ink, outline));
  }

  /// 左右对称的形状：给左边的，右边照着翻过来
  Path _mirror(Path left) => left.transform(Float64List.fromList([-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 200, 0, 0, 1]));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / 200, size.height / 200);
    final ink = Pop.ink;
    final dog = stage >= 3;
    // 进化形态只在做人时穿
    final wear = stage == 0 ? evolution : null;

    // 头顶光环：身边先冒几颗金光（在人后面）
    if (wear == Evolution.halo) {
      for (final (c, r) in const [(Offset(24, 58), 11.0), (Offset(178, 44), 9.0), (Offset(184, 134), 7.0), (Offset(16, 128), 6.0)]) {
        EvolutionArt.sparkle(canvas, c, r, 1);
      }
    }

    // 披在身后的长头发（还没完全变狗时），卫衣盖住下面
    if (stage < 5) PresetArt.backHair(canvas, preset);

    // 尾巴（阶段 4+）：在身子后面摇，带两道动感线
    if (stage >= 4) {
      final tail = Path()
        ..moveTo(148, 196)
        ..cubicTo(168, 194, 182, 180, 178, 158);
      canvas.drawPath(tail, _stroke(ink, 24));
      canvas.drawPath(tail, _stroke(_fur, 15));
      for (final (a, b) in const [(Offset(186, 150), Offset(193, 143)), (Offset(190, 164), Offset(198, 162))]) {
        canvas.drawLine(a, b, _stroke(ink, 3.5));
      }
    }

    // 身子：亮黄卫衣；完全变狗（阶段 5）是一身狗毛和奶白的肚皮
    final body = Path()
      ..moveTo(38, 208)
      ..cubicTo(38, 174, 64, 160, 100, 160)
      ..cubicTo(136, 160, 162, 174, 162, 208)
      ..close();
    _shape(canvas, body, stage >= 5 ? _fur : (wear == Evolution.elite ? EvolutionArt.suit : Pop.yellow));
    if (stage >= 5) {
      _ellipse(canvas, const Offset(100, 200), 30, 22, _fill(_cream));
    } else if (wear == Evolution.elite) {
      // 西装精英：白衬衫露出一个 V，翻领两道线，左胸口袋插一角黄色方巾，红领带
      final shirt = Path()
        ..moveTo(80, 160)
        ..lineTo(120, 160)
        ..lineTo(100, 200)
        ..close();
      _shape(canvas, shirt, Pop.white, outline: 3.5);
      for (final (a, b) in const [(Offset(80, 160), Offset(93, 199)), (Offset(120, 160), Offset(107, 199))]) {
        canvas.drawLine(a, b, _stroke(EvolutionArt.suitDark, 7));
        canvas.drawLine(a, b, _stroke(ink, 3.5));
      }
      final square = Path()
        ..moveTo(55, 184)
        ..lineTo(60, 176)
        ..lineTo(64, 181)
        ..lineTo(69, 175)
        ..lineTo(72, 184)
        ..close();
      _shape(canvas, square, Pop.yellow, outline: 2.5);
      canvas.drawLine(const Offset(53, 185), const Offset(74, 185), _stroke(ink, 3));
      EvolutionArt.tie(canvas, const Offset(100, 168), 34, 1);
    } else {
      // 卫衣的两根抽绳
      for (final (top, end) in const [(Offset(90, 168), Offset(87, 186)), (Offset(110, 168), Offset(113, 186))]) {
        canvas.drawLine(top, end, _stroke(ink, 3.5));
        canvas.drawCircle(end, 3.5, _fill(ink));
      }
    }

    // 项圈（阶段 3+）：红色，挂一个黄色牌子
    if (stage >= 3) {
      final collar = Path()
        ..moveTo(66, 165)
        ..quadraticBezierTo(100, 182, 134, 165);
      canvas.drawPath(collar, _stroke(ink, 15));
      canvas.drawPath(collar, _stroke(Pop.kingRed, 9));
      canvas.drawCircle(const Offset(100, 181), 8.5, _fill(Pop.yellow));
      canvas.drawCircle(const Offset(100, 181), 8.5, _stroke(ink, 3.5));
    }

    // 头：大一点、扁一点的团子脸
    final head = Path()..addOval(Rect.fromCenter(center: const Offset(100, 98), width: 140, height: 128));
    _shape(canvas, head, dog ? _fur : preset.skin);

    // 眼圈斑（阶段 3+）：右眼一圈深色毛
    if (dog) _ellipse(canvas, const Offset(127, 110), 21, 19, _fill(_furDark), rotateDeg: 12);

    // 嘴筒（阶段 5）
    if (stage >= 5) {
      final muzzle = Path()..addOval(Rect.fromCenter(center: const Offset(100, 134), width: 68, height: 46));
      _shape(canvas, muzzle, _cream, outline: 3.5);
    }

    // 头发（阶段 0–4），按预设形象的发型画；阶段 5 变成一撮狗毛
    if (stage < 5) {
      PresetArt.frontHair(canvas, preset);
    } else {
      PresetArt.dogTuft(canvas, preset);
    }

    // 记号：一直都在，变成狗也认得出是你（呆毛、丸子、星星发夹）
    PresetArt.mark(canvas, preset, stage, capped: wear == Evolution.scholar);

    // 学霸：头顶扣一顶学士帽
    if (wear == Evolution.scholar) EvolutionArt.mortarboard(canvas, const Offset(100, 30), 60, 1);

    // 狗耳朵（阶段 1+）：两只大垂耳，里面一层粉；刚冒出来的阶段 1 带“砰”的线条
    if (stage >= 1) {
      final ear = Path()
        ..moveTo(48, 58)
        ..cubicTo(20, 60, 8, 102, 20, 136)
        ..cubicTo(28, 156, 52, 146, 54, 122)
        ..cubicTo(56, 100, 62, 76, 48, 58)
        ..close();
      final inner = Path()
        ..moveTo(44, 74)
        ..cubicTo(28, 80, 22, 108, 28, 128)
        ..cubicTo(34, 140, 46, 134, 47, 118)
        ..cubicTo(48, 102, 52, 86, 44, 74)
        ..close();
      for (final (outer, inside) in [(ear, inner), (_mirror(ear), _mirror(inner))]) {
        _shape(canvas, outer, _ear);
        canvas.drawPath(inside, _fill(_earInner));
      }
      if (stage == 1) {
        for (final (a, b) in const [
          (Offset(18, 54), Offset(8, 44)),
          (Offset(12, 72), Offset(2, 70)),
          (Offset(30, 44), Offset(26, 32)),
        ]) {
          canvas.drawLine(a, b, _stroke(ink, 4));
          canvas.drawLine(Offset(200 - a.dx, a.dy), Offset(200 - b.dx, b.dy), _stroke(ink, 4));
        }
      }
    }

    // 腮红：一直都在，带几道斜线
    for (final cx in const [54.0, 146.0]) {
      _ellipse(canvas, Offset(cx, 134), 12, 7, _fill(_blush.withValues(alpha: 0.9)));
      for (var i = 0; i < 3; i++) {
        final x = cx - 7 + i * 6;
        canvas.drawLine(Offset(x, 137), Offset(x + 4, 131), _stroke(_blushLine, 2));
      }
    }

    // 眉毛（露额头的发型；寸头的粗眉毛变成狗也留着）
    PresetArt.brows(canvas, preset, stage);

    // 眼睛：又大又亮，两点高光；阶段 4+ 激动得多一颗星星
    for (final x in const [74.0, 126.0]) {
      _ellipse(canvas, Offset(x, 112), 11, 13.5, _fill(ink));
      canvas.drawCircle(Offset(x + 4, 106.5), 4.5, _fill(Pop.white));
      canvas.drawCircle(Offset(x - 3.5, 117.5), 2, _fill(Pop.white));
      if (stage >= 4) canvas.drawCircle(Offset(x + 5, 116), 1.6, _fill(Pop.white));
    }
    PresetArt.lashes(canvas, preset);

    // 学霸：圆框眼镜
    if (wear == Evolution.scholar) {
      EvolutionArt.glasses(canvas, const Offset(74, 112), const Offset(126, 112), 19, 31, 169, 1);
    }

    // 舌头（阶段 4+）：长长地吐出来，中间一道线
    if (stage >= 4) {
      final tongue = Path()
        ..moveTo(91, 138)
        ..lineTo(109, 138)
        ..lineTo(109, 154)
        ..arcToPoint(const Offset(91, 154), radius: const Radius.circular(9))
        ..close();
      _shape(canvas, tongue, _tongue, outline: 3.5);
      canvas.drawLine(const Offset(100, 141), const Offset(100, 152), _stroke(_tongueLine, 2.5));
    }

    if (stage < 2) {
      // 人：小鼻子，张嘴笑
      canvas.drawPath(
        Path()
          ..moveTo(97, 123)
          ..quadraticBezierTo(100, 127, 103, 123),
        _stroke(ink, 3),
      );
      final mouth = Path()
        ..moveTo(90, 132)
        ..quadraticBezierTo(100, 150, 110, 132)
        ..close();
      canvas.drawPath(mouth, _fill(_mouth));
      canvas.save();
      canvas.clipPath(mouth);
      _ellipse(canvas, const Offset(100, 143), 6, 4, _fill(_tongue));
      canvas.restore();
      canvas.drawPath(mouth, _stroke(ink, 3.5));
    } else {
      // 狗：亮晶晶的鼻子，ω 嘴
      final nose = Path()
        ..moveTo(87, 119)
        ..quadraticBezierTo(100, 111, 113, 119)
        ..quadraticBezierTo(113, 126, 100, 131)
        ..quadraticBezierTo(87, 126, 87, 119)
        ..close();
      canvas.drawPath(nose, _fill(ink));
      _ellipse(canvas, const Offset(95, 118), 4.5, 2.6, _fill(Pop.white));
      final mouth = Path()
        ..moveTo(100, 130)
        ..lineTo(100, 135)
        ..quadraticBezierTo(92, 143, 85, 136)
        ..moveTo(100, 135)
        ..quadraticBezierTo(108, 143, 115, 136);
      canvas.drawPath(mouth, _stroke(ink, 4));
    }

    // 完全体（阶段 5）：爪子里捧着亮着屏的手机，刷成狗了还在刷
    if (stage >= 5) {
      canvas.save();
      canvas.translate(62, 168);
      canvas.rotate(-14 * math.pi / 180);
      final phone = RRect.fromRectAndRadius(const Rect.fromLTWH(-15, -26, 30, 48), const Radius.circular(6));
      canvas.drawRRect(phone, _fill(ink));
      canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(-11, -21, 22, 36), const Radius.circular(3)), _fill(_screen));
      for (final (a, b) in const [(Offset(-22, -30), Offset(-28, -36)), (Offset(0, -34), Offset(0, -42)), (Offset(22, -30), Offset(28, -36))]) {
        canvas.drawLine(a, b, _stroke(ink, 3.5));
      }
      canvas.restore();
      for (final c in const [Offset(52, 188), Offset(74, 186)]) {
        canvas.drawCircle(c, 10, _fill(_fur));
        canvas.drawCircle(c, 10, _stroke(ink, 3.5));
      }
    }

    // 养生大师：手里捧着泡枸杞的保温杯（完全体捧的是手机）
    if (wear == Evolution.wellness) EvolutionArt.thermos(canvas, const Offset(58, 184), 1.12, skin: preset.skin);

    // 头顶光环
    if (wear == Evolution.halo) EvolutionArt.halo(canvas, const Offset(100, 13), 40, 1);
  }

  @override
  bool shouldRepaint(_AvatarPainter old) => old.stage != stage || old.evolution != evolution || old.preset != preset;
}
