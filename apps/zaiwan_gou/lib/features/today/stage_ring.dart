import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/dog_meter.dart';

/// 狗头外面的一圈：今天刷了多少。
///
/// 转满一圈是狗度 150%（最后一个阶段），圈上的刻度是每个阶段的门槛（30% / 60% / 90% / 120%），
/// 没超过每日目标的部分是黄的，超过目标的部分是红的。iOS 只知道到了哪个阶段，[percent] 传那个阶段的下限；
/// 还没拿到数据时传 null，只画底圈。
class StageRing extends StatelessWidget {
  const StageRing({super.key, required this.percent, required this.child, this.size = 236, this.semanticsLabel});

  /// 狗度（%）；null = 还没拿到今天的数据
  final int? percent;

  /// 圈里面的形象
  final Widget child;
  final double size;
  final String? semanticsLabel;

  /// 转满一圈对应的狗度，和最后一个阶段的门槛一样
  static const fullPercent = 150;

  /// 圈的粗细
  static const thickness = 16.0;

  /// 圈和里面白色圆盘之间的空隙
  static const gap = 8.0;

  /// 转到哪了（0–1）
  static double fractionFor(int percent) => (percent / fullPercent).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final p = percent;
    final target = p == null ? 0.0 : fractionFor(p);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: target),
          duration: still ? Duration.zero : const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, value, disc) => CustomPaint(
            painter: StageRingPainter(value: value, hasData: p != null),
            child: disc,
          ),
          child: Padding(
            padding: const EdgeInsets.all(thickness + gap + 2),
            child: Container(
              decoration: const BoxDecoration(
                color: Pop.white,
                shape: BoxShape.circle,
                border: Border.fromBorderSide(BorderSide(color: Pop.ink, width: Pop.stroke)),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class StageRingPainter extends CustomPainter {
  StageRingPainter({required this.value, required this.hasData});

  /// 转到哪了（0–1，1 = 狗度 150%）
  final double value;
  final bool hasData;

  /// 每日目标（狗度 100%）在圈上的位置
  static const goalFraction = 100 / StageRing.fullPercent;

  static double _angle(double fraction) => -math.pi / 2 + 2 * math.pi * fraction;

  @override
  void paint(Canvas canvas, Size size) {
    const t = StageRing.thickness;
    final c = size.center(Offset.zero);
    final r = size.width / 2 - t / 2 - 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    Paint band(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = t;

    canvas.drawCircle(c, r, band(Pop.gray));
    if (hasData && value > 0) {
      final yellow = math.min(value, goalFraction);
      canvas.drawArc(rect, _angle(0), 2 * math.pi * yellow, false, band(Pop.yellow));
      if (value > goalFraction) {
        canvas.drawArc(rect, _angle(goalFraction), 2 * math.pi * (value - goalFraction), false, band(Pop.kingRed));
      }
    }

    final line = Paint()
      ..color = Pop.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(c, r + t / 2, line);
    canvas.drawCircle(c, r - t / 2, line);
    // 起点和每个阶段的门槛各一道刻度
    for (final p in [0, ...DogMeter.stageThresholds.take(DogMeter.stageThresholds.length - 1)]) {
      final a = _angle(p / StageRing.fullPercent);
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (r - t / 2), c + dir * (r + t / 2), line);
    }

    // 转到的地方放一个白色小圆钮
    if (hasData && value > 0) {
      final a = _angle(value);
      final knob = c + Offset(math.cos(a), math.sin(a)) * r;
      canvas.drawCircle(knob, t / 2 + 3, Paint()..color = Pop.white);
      canvas.drawCircle(knob, t / 2 + 3, line..strokeWidth = 2.5);
    }
  }

  @override
  bool shouldRepaint(StageRingPainter old) => old.value != value || old.hasData != hasData;
}
