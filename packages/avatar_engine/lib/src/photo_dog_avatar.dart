import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import 'photo_sticker.dart';

/// 照片形象（[PhotoSticker] 画出来的平涂墨线贴纸）+ 变狗图层，带硬阴影。
///
/// 现在只叠到阶段 2：阶段 1 狗耳朵，阶段 2 再加狗鼻子，画法和颜色照搬设计稿的 [DogAvatar]。
/// 阶段 3 以后的狗毛、舌头、尾巴要等美术按 288 的对齐模板画素材。
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

  /// 硬阴影往右下错开的距离（贴纸画布的像素）
  static const _shadow = 7.0;

  /// 半张脸的宽度按 75 像素算（288 头像里），耳朵、鼻子的大小和位置按设计稿的比例从它推出来
  static const _halfFace = 75.0;

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
    canvas.scale(size.width / PhotoSticker.canvasSize);
    const quality = FilterQuality.medium;
    canvas.drawImage(
      sticker,
      const Offset(_shadow, _shadow),
      Paint()
        ..colorFilter = const ColorFilter.mode(Pop.ink, BlendMode.srcIn)
        ..filterQuality = quality,
    );
    canvas.drawImage(sticker, Offset.zero, Paint()..filterQuality = quality);

    final origin = Offset(PhotoSticker.offsetX.toDouble(), PhotoSticker.offsetY.toDouble());
    final fill = Paint()..isAntiAlias = true;
    final stroke = Paint()
      ..color = Pop.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..isAntiAlias = true;

    // 狗耳朵：在两眼中点左右各 0.9 个半脸宽、眼睛上方 0.3 个半脸宽，往外撇 18 度垂下来
    if (stage >= 1) {
      final cx = (PhotoSticker.leftEye.dx + PhotoSticker.rightEye.dx) / 2;
      final eyeY = (PhotoSticker.leftEye.dy + PhotoSticker.rightEye.dy) / 2;
      for (final (side, deg) in [(-1.0, 18.0), (1.0, -18.0)]) {
        final center = origin + Offset(cx + side * 0.9 * _halfFace, eyeY - 0.3 * _halfFace);
        _ellipse(canvas, center, 0.3 * _halfFace, 0.66 * _halfFace, fill..color = _brown, rotateDeg: deg);
        _ellipse(canvas, center, 0.3 * _halfFace, 0.66 * _halfFace, stroke, rotateDeg: deg);
      }
    }

    // 狗鼻子：盖住对齐后的鼻尖，加一点高光
    if (stage >= 2) {
      final nose = origin + PhotoSticker.nose;
      _ellipse(canvas, nose, 0.21 * _halfFace, 0.15 * _halfFace, fill..color = Pop.ink);
      _ellipse(canvas, nose + const Offset(0.07 * _halfFace, -0.05 * _halfFace), 0.06 * _halfFace, 0.035 * _halfFace,
          fill..color = Pop.white);
    }
  }

  @override
  bool shouldRepaint(_PhotoDogPainter old) => old.sticker != sticker || old.stage != stage;
}
