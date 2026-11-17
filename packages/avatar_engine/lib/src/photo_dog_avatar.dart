import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import 'photo_sticker.dart';

/// 照片形象（[PhotoSticker] 画出来的平涂墨线贴纸）+ 变狗图层，带硬阴影。
///
/// 图层按阶段叠加，画法和颜色照搬设计稿的 [DogAvatar]：
/// 阶段 1 狗耳朵；2 狗鼻子；3 额头和两颊长狗毛；4 吐舌头、身后冒出尾巴；5 套上狗嘴筒，完全变成狗。
/// 位置按对齐模板的固定坐标算（照片对齐后五官离模板只差几个像素）。
/// 现在是代码画的示意，美术按 288 的对齐模板画好素材后，每一层换成图片即可。
class PhotoDogAvatar extends StatelessWidget {
  const PhotoDogAvatar({super.key, required this.sticker, required this.stage, this.size = 200});

  /// [PhotoSticker.toImage] 得到的 320x320 贴纸
  final ui.Image sticker;
  final int stage;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = stage.clamp(0, 5);
    return Semantics(
      label: '照片卡通形象，变狗阶段 $s',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _PhotoDogPainter(sticker, s)),
      ),
    );
  }
}

class _PhotoDogPainter extends CustomPainter {
  _PhotoDogPainter(this.sticker, this.stage);

  final ui.Image sticker;
  final int stage;

  static const _brown = Color(0xFFA86B32);
  static const _snout = Color(0xFFFFF4E6);
  static const _tongue = Color(0xFFFF7A9A);

  /// 硬阴影往右下错开的距离（贴纸画布的像素）
  static const _shadow = 7.0;

  /// 半张脸的宽度按 75 像素算（288 头像里），各图层的大小和位置按设计稿的比例从它推出来
  static const _h = 75.0;

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

    const quality = FilterQuality.medium;
    canvas.drawImage(
      sticker,
      const Offset(_shadow, _shadow),
      Paint()
        ..colorFilter = const ColorFilter.mode(Pop.ink, BlendMode.srcIn)
        ..filterQuality = quality,
    );
    canvas.drawImage(sticker, Offset.zero, Paint()..filterQuality = quality);

    // 尾巴（阶段 4+）：从右下角的肩膀后面翘起来。画在贴纸上面，长头发也挡不住
    if (stage >= 4) {
      final tail = Path()
        ..moveTo(262, 324)
        ..quadraticBezierTo(306, 298, 290, 240);
      canvas.drawPath(tail, _stroke(Pop.ink, 20));
      canvas.drawPath(tail, _stroke(_brown, 12));
    }

    // 狗耳朵（阶段 1+）：在两眼中点左右各 0.9 个半脸宽、眼睛上方 0.3 个半脸宽，往外撇 18 度垂下来
    if (stage >= 1) {
      for (final (side, deg) in [(-1.0, 18.0), (1.0, -18.0)]) {
        final center = at(cx + side * 0.9 * _h, eyeY - 0.3 * _h);
        _ellipse(canvas, center, 0.3 * _h, 0.66 * _h, _fill(_brown), rotateDeg: deg);
        _ellipse(canvas, center, 0.3 * _h, 0.66 * _h, _stroke(Pop.ink, 4), rotateDeg: deg);
      }
    }

    // 狗毛（阶段 3+）：额头一撮，两颊往外各炸出一撮
    if (stage >= 3) {
      _ellipse(canvas, at(cx, eyeY - 0.6 * _h), 0.36 * _h, 0.19 * _h, _fill(_brown));
      final tufts = Path();
      for (final side in [-1.0, 1.0]) {
        final base = at(cx + side * 0.98 * _h, nose.dy);
        tufts
          ..moveTo(base.dx, base.dy - 0.13 * _h)
          ..lineTo(base.dx + side * 0.22 * _h, base.dy + 0.05 * _h)
          ..lineTo(base.dx - side * 0.02 * _h, base.dy + 0.13 * _h)
          ..close();
      }
      canvas.drawPath(tufts, _fill(_brown));
      canvas.drawPath(tufts, _stroke(Pop.ink, 3));
    }

    // 狗嘴筒（阶段 5）：盖住鼻子和嘴
    if (stage >= 5) {
      final snout = at(cx, (nose.dy + mouthY) / 2 + 4);
      _ellipse(canvas, snout, 0.6 * _h, 0.42 * _h, _fill(_snout));
      _ellipse(canvas, snout, 0.6 * _h, 0.42 * _h, _stroke(Pop.ink, 4));
    }

    // 舌头（阶段 4+）：从嘴中间吐出来
    if (stage >= 4) {
      final top = at(cx, nose.dy + 0.48 * _h);
      final w = 0.16 * _h, len = 0.26 * _h;
      final tongue = Path()
        ..moveTo(top.dx - w, top.dy)
        ..lineTo(top.dx + w, top.dy)
        ..lineTo(top.dx + w, top.dy + len)
        ..arcToPoint(Offset(top.dx - w, top.dy + len), radius: Radius.circular(w))
        ..close();
      canvas.drawPath(tongue, _fill(_tongue));
      canvas.drawPath(tongue, _stroke(Pop.ink, 4));
    }

    // 狗鼻子（阶段 2+）：盖住对齐后的鼻尖，加一点高光
    if (stage >= 2) {
      final n = origin + nose;
      _ellipse(canvas, n, 0.21 * _h, 0.15 * _h, _fill(Pop.ink));
      _ellipse(canvas, n + const Offset(0.07 * _h, -0.05 * _h), 0.06 * _h, 0.035 * _h, _fill(Pop.white));
    }

    // 狗嘴（阶段 5）：鼻子下面一竖，再往两边弯
    if (stage >= 5) {
      final n = origin + nose;
      final split = n + const Offset(0, 0.34 * _h);
      final mouth = Path()
        ..moveTo(n.dx, n.dy + 0.15 * _h)
        ..lineTo(split.dx, split.dy)
        ..moveTo(split.dx, split.dy)
        ..quadraticBezierTo(split.dx - 0.2 * _h, split.dy + 0.2 * _h, split.dx - 0.38 * _h, split.dy + 0.02 * _h)
        ..moveTo(split.dx, split.dy)
        ..quadraticBezierTo(split.dx + 0.2 * _h, split.dy + 0.2 * _h, split.dx + 0.38 * _h, split.dy + 0.02 * _h);
      canvas.drawPath(mouth, _stroke(Pop.ink, 4.5));
    }
  }

  @override
  bool shouldRepaint(_PhotoDogPainter old) => old.sticker != sticker || old.stage != stage;
}
