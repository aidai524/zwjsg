import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import 'evolution.dart';
import 'photo_sticker.dart';
import 'widget_images.dart';

/// 不经过 Widget 树，把照片形象画成 [pixels] x [pixels] 的图片（背景透明），和 [PhotoDogAvatar] 一样。
/// 给桌面小组件用，返回的图片用完要 dispose
Future<ui.Image> renderPhotoDogAvatar({required ui.Image sticker, required int stage, int pixels = 360, Evolution? evolution}) =>
    paintToImage(_PhotoDogPainter(sticker, stage.clamp(0, 5), evolution), pixels);

/// 照片形象（[PhotoSticker] 画出来的平涂墨线贴纸）+ 变狗图层，带硬阴影。
///
/// 图层按阶段叠加，画法和颜色照搬 [DogAvatar]（2026-11-23 改得更可爱、更有冲击力）：
/// 阶段 1 大垂耳（刚冒出来带“砰”的线条）；2 亮晶晶的狗鼻子；3 额头和两颊长狗毛；4 吐长舌头、身后摇尾巴；
/// 5 套上狗嘴筒、ω 嘴，爪子里还捧着手机，完全变成狗。
/// 做人（阶段 0）时可以穿上进化形态 [evolution]：眼镜和学士帽、领子和领带（照片里的衣服换不了）、保温杯、光环。
/// 位置按对齐模板的固定坐标算（照片对齐后五官离模板只差几个像素）。
/// 现在是代码画的示意，美术按 288 的对齐模板画好素材后，每一层换成图片即可。
class PhotoDogAvatar extends StatelessWidget {
  const PhotoDogAvatar({super.key, required this.sticker, required this.stage, this.size = 200, this.evolution});

  /// [PhotoSticker.toImage] 得到的 320x320 贴纸
  final ui.Image sticker;
  final int stage;
  final double size;

  /// 进化形态：只在阶段 0 画，变狗了就不穿
  final Evolution? evolution;

  @override
  Widget build(BuildContext context) {
    final s = stage.clamp(0, 5);
    return Semantics(
      label: '照片卡通形象，变狗阶段 $s',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _PhotoDogPainter(sticker, s, evolution)),
      ),
    );
  }
}

class _PhotoDogPainter extends CustomPainter {
  _PhotoDogPainter(this.sticker, this.stage, [this.evolution]);

  final ui.Image sticker;
  final int stage;
  final Evolution? evolution;

  // 和默认形象（DogAvatar）同一套配色
  static const _ear = Color(0xFFA86B32);
  static const _earInner = Color(0xFFF0A98A);
  static const _fur = Color(0xFFE3A869);
  static const _cream = Color(0xFFFFF4E6);
  static const _tongue = Color(0xFFFF6F8E);
  static const _tongueLine = Color(0xFFD9486B);
  static const _screen = Color(0xFF8BE0FF);

  /// 硬阴影往右下错开的距离（贴纸画布的像素）
  static const _shadow = 7.0;

  /// 半张脸的宽度按 75 像素算（288 头像里），各图层的大小和位置按设计稿的比例从它推出来
  static const _h = 75.0;

  /// 默认形象的头半宽是 70：默认形象里画好的耳朵、手机，按这个比例搬到照片脸上
  static const _k = _h / 70;

  static const _outline = 5.0;

  void _ellipse(Canvas c, Offset center, double rx, double ry, Paint p, {double rotateDeg = 0}) {
    c.save();
    c.translate(center.dx, center.dy);
    if (rotateDeg != 0) c.rotate(rotateDeg * math.pi / 180);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), p);
    c.restore();
  }

  Paint _fill(Color color) => Paint()
    ..color = color
    ..isAntiAlias = true;

  Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  void _shape(Canvas c, Path path, Color fill, {double outline = _outline}) {
    c.drawPath(path, _fill(fill));
    c.drawPath(path, _stroke(Pop.ink, outline));
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / PhotoSticker.canvasSize);

    // 288 头像里的坐标 → 贴纸画布的坐标
    const origin = Offset(PhotoSticker.offsetX + 0.0, PhotoSticker.offsetY + 0.0);
    Offset at(double x, double y) => origin + Offset(x, y);
    final cx = (PhotoSticker.leftEye.dx + PhotoSticker.rightEye.dx) / 2;
    final eyeY = (PhotoSticker.leftEye.dy + PhotoSticker.rightEye.dy) / 2;
    const nose = PhotoSticker.nose;
    final mouthY = (PhotoSticker.leftMouth.dy + PhotoSticker.rightMouth.dy) / 2;

    /// 默认形象 200 画布里的坐标（眼睛在 y=112、脸中线 x=100）→ 照片上同一个位置；[mirror] 把左边的翻到右边
    Offset m(double x, double y, {bool mirror = false}) =>
        at(cx + ((mirror ? 200 - x : x) - 100) * _k, eyeY + (y - 112) * _k);

    const quality = FilterQuality.medium;
    canvas.drawImage(
      sticker,
      const Offset(_shadow, _shadow),
      Paint()
        ..colorFilter = const ColorFilter.mode(Pop.ink, BlendMode.srcIn)
        ..filterQuality = quality,
    );
    canvas.drawImage(sticker, Offset.zero, Paint()..filterQuality = quality);

    // 进化形态（只在做人时穿）：配饰按眼睛、嘴的位置放，线条按两眼的距离放大
    final wear = stage == 0 ? evolution : null;
    if (wear != null) {
      final left = origin + PhotoSticker.leftEye, right = origin + PhotoSticker.rightEye;
      final s = (right.dx - left.dx) / 52;
      switch (wear) {
        case Evolution.scholar:
          EvolutionArt.mortarboard(canvas, at(cx, eyeY - 1.38 * _h), 0.95 * _h, s * 0.9);
          EvolutionArt.glasses(canvas, left, right, 0.36 * (right.dx - left.dx), at(cx - 1.02 * _h, 0).dx,
              at(cx + 1.02 * _h, 0).dx, s * 0.9);
        case Evolution.elite:
          EvolutionArt.tie(canvas, at(cx, mouthY + 0.56 * _h), 0.5 * _h, s);
        case Evolution.wellness:
          EvolutionArt.thermos(canvas, m(36, 224), _k * 1.1);
        case Evolution.halo:
          for (final (x, y, r) in const [(-1.55, -1.0, 11.0), (1.6, -1.3, 9.0), (1.75, 0.5, 7.0), (-1.8, 0.35, 6.0)]) {
            EvolutionArt.sparkle(canvas, at(cx + x * _h, eyeY + y * _h), r * _k, _k);
          }
          EvolutionArt.halo(canvas, at(cx, eyeY - 1.62 * _h), 0.62 * _h, _k);
      }
    }

    // 尾巴（阶段 4+）：从右下角的肩膀后面翘起来，带两道动感线。画在贴纸上面，长头发也挡不住
    if (stage >= 4) {
      final tail = Path()
        ..moveTo(262, 324)
        ..quadraticBezierTo(306, 298, 290, 240);
      canvas.drawPath(tail, _stroke(Pop.ink, 22));
      canvas.drawPath(tail, _stroke(_fur, 13));
      canvas.drawLine(const Offset(298, 226), const Offset(306, 214), _stroke(Pop.ink, 4));
      canvas.drawLine(const Offset(306, 246), const Offset(316, 242), _stroke(Pop.ink, 4));
    }

    // 狗耳朵（阶段 1+）：和默认形象一样的大垂耳，里面一层粉；刚冒出来的阶段 1 带“砰”的线条
    if (stage >= 1) {
      for (final mirror in [false, true]) {
        Offset e(double x, double y) => m(x, y, mirror: mirror);
        final ear = Path()
          ..moveTo(e(48, 58).dx, e(48, 58).dy)
          ..cubicTo(e(20, 60).dx, e(20, 60).dy, e(8, 102).dx, e(8, 102).dy, e(20, 136).dx, e(20, 136).dy)
          ..cubicTo(e(28, 156).dx, e(28, 156).dy, e(52, 146).dx, e(52, 146).dy, e(54, 122).dx, e(54, 122).dy)
          ..cubicTo(e(56, 100).dx, e(56, 100).dy, e(62, 76).dx, e(62, 76).dy, e(48, 58).dx, e(48, 58).dy)
          ..close();
        final inner = Path()
          ..moveTo(e(44, 74).dx, e(44, 74).dy)
          ..cubicTo(e(28, 80).dx, e(28, 80).dy, e(22, 108).dx, e(22, 108).dy, e(28, 128).dx, e(28, 128).dy)
          ..cubicTo(e(34, 140).dx, e(34, 140).dy, e(46, 134).dx, e(46, 134).dy, e(47, 118).dx, e(47, 118).dy)
          ..cubicTo(e(48, 102).dx, e(48, 102).dy, e(52, 86).dx, e(52, 86).dy, e(44, 74).dx, e(44, 74).dy)
          ..close();
        _shape(canvas, ear, _ear);
        canvas.drawPath(inner, _fill(_earInner));
        if (stage == 1) {
          for (final (a, b) in const [((18.0, 54.0), (8.0, 44.0)), ((12.0, 72.0), (2.0, 70.0)), ((30.0, 44.0), (26.0, 32.0))]) {
            canvas.drawLine(e(a.$1, a.$2), e(b.$1, b.$2), _stroke(Pop.ink, 4.5));
          }
        }
      }
    }

    // 狗毛（阶段 3+）：额头一撮，两颊往外各炸出一撮
    if (stage >= 3) {
      _ellipse(canvas, at(cx, eyeY - 0.6 * _h), 0.36 * _h, 0.19 * _h, _fill(_ear));
      final tufts = Path();
      for (final side in [-1.0, 1.0]) {
        final base = at(cx + side * 0.98 * _h, nose.dy);
        tufts
          ..moveTo(base.dx, base.dy - 0.16 * _h)
          ..lineTo(base.dx + side * 0.26 * _h, base.dy - 0.02 * _h)
          ..lineTo(base.dx + side * 0.04 * _h, base.dy + 0.04 * _h)
          ..lineTo(base.dx + side * 0.24 * _h, base.dy + 0.16 * _h)
          ..lineTo(base.dx - side * 0.02 * _h, base.dy + 0.18 * _h)
          ..close();
      }
      _shape(canvas, tufts, _fur, outline: 3.5);
    }

    // 狗嘴筒（阶段 5）：盖住鼻子和嘴
    if (stage >= 5) {
      final snout = Path()
        ..addOval(Rect.fromCenter(center: at(cx, (nose.dy + mouthY) / 2 + 4), width: 1.2 * _h, height: 0.84 * _h));
      _shape(canvas, snout, _cream, outline: 4);
    }

    // 舌头（阶段 4+）：长长地吐出来，中间一道线
    if (stage >= 4) {
      final top = at(cx, nose.dy + 0.48 * _h);
      final w = 0.17 * _h, len = 0.32 * _h;
      final tongue = Path()
        ..moveTo(top.dx - w, top.dy)
        ..lineTo(top.dx + w, top.dy)
        ..lineTo(top.dx + w, top.dy + len)
        ..arcToPoint(Offset(top.dx - w, top.dy + len), radius: Radius.circular(w))
        ..close();
      _shape(canvas, tongue, _tongue, outline: 4);
      canvas.drawLine(top + Offset(0, 0.05 * _h), top + Offset(0, len), _stroke(_tongueLine, 3));
    }

    // 狗鼻子（阶段 2+）：亮晶晶的圆三角，盖住对齐后的鼻尖
    if (stage >= 2) {
      final n = origin + nose;
      final w = 0.3 * _h, hgt = 0.26 * _h;
      final dogNose = Path()
        ..moveTo(n.dx - w, n.dy - hgt * 0.3)
        ..quadraticBezierTo(n.dx, n.dy - hgt, n.dx + w, n.dy - hgt * 0.3)
        ..quadraticBezierTo(n.dx + w, n.dy + hgt * 0.25, n.dx, n.dy + hgt * 0.6)
        ..quadraticBezierTo(n.dx - w, n.dy + hgt * 0.25, n.dx - w, n.dy - hgt * 0.3)
        ..close();
      canvas.drawPath(dogNose, _fill(Pop.ink));
      _ellipse(canvas, n + Offset(-0.1 * _h, -0.12 * _h), 0.08 * _h, 0.045 * _h, _fill(Pop.white));
    }

    // 狗嘴（阶段 5）：ω 嘴
    if (stage >= 5) {
      final n = origin + nose;
      final split = n + const Offset(0, 0.3 * _h);
      final mouth = Path()
        ..moveTo(n.dx, n.dy + 0.15 * _h)
        ..lineTo(split.dx, split.dy)
        ..quadraticBezierTo(split.dx - 0.14 * _h, split.dy + 0.16 * _h, split.dx - 0.28 * _h, split.dy + 0.04 * _h)
        ..moveTo(split.dx, split.dy)
        ..quadraticBezierTo(split.dx + 0.14 * _h, split.dy + 0.16 * _h, split.dx + 0.28 * _h, split.dy + 0.04 * _h);
      canvas.drawPath(mouth, _stroke(Pop.ink, 5));

      // 爪子里捧着亮着屏的手机：刷成狗了还在刷
      canvas.save();
      // 放在肩膀那儿，不挡脸
      final hand = m(58, 206);
      canvas.translate(hand.dx, hand.dy);
      canvas.scale(_k);
      canvas.rotate(-14 * math.pi / 180);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-15, -26, 30, 48), const Radius.circular(6)), _fill(Pop.ink));
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-11, -21, 22, 36), const Radius.circular(3)), _fill(_screen));
      for (final (a, b) in const [(Offset(-22, -30), Offset(-28, -36)), (Offset(0, -34), Offset(0, -42)), (Offset(22, -30), Offset(28, -36))]) {
        canvas.drawLine(a, b, _stroke(Pop.ink, 3.5));
      }
      canvas.restore();
      for (final c in [m(48, 226), m(70, 224)]) {
        canvas.drawCircle(c, 10 * _k, _fill(_fur));
        canvas.drawCircle(c, 10 * _k, _stroke(Pop.ink, 4));
      }
    }
  }

  @override
  bool shouldRepaint(_PhotoDogPainter old) => old.sticker != sticker || old.stage != stage || old.evolution != evolution;
}
