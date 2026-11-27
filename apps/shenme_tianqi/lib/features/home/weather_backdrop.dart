import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

/// 首页底色上的天气动画（2026-11-19）：晴天太阳光圈慢慢转，高温再加热浪；多云云朵飘；下雨雨丝；
/// 雷阵雨偶尔闪一下；下雪雪花飘；大风风线；雾霾、沙尘颗粒；闷热水汽。
/// 只是背景，不抢内容：颜色淡、数量少，画在卡片和文字下面。严肃模式不画（首页不放这个组件）；
/// 系统开了“减弱动态效果”时只画静止的一帧。
class WeatherBackdrop extends StatefulWidget {
  const WeatherBackdrop({super.key, required this.cond, required this.outfitKey});

  final String cond;
  final String outfitKey;

  /// 一圈动画多长。雨、雪、云、闪电都按整数圈数走，循环时接得上
  static const period = Duration(seconds: 60);

  /// 测试里关掉：一直在动的动画会让 pumpAndSettle 等不完（见 test/flutter_test_config.dart）
  @visibleForTesting
  static bool animate = true;

  /// 这种天气画什么；不认识的天气不画
  static BackdropKind? kindFor(String cond, String outfitKey) => switch (cond) {
        'sunny' => outfitKey == 'hot' ? BackdropKind.hot : BackdropKind.sunny,
        'cloudy' => BackdropKind.cloudy,
        'light_rain' => BackdropKind.lightRain,
        'heavy_rain' => BackdropKind.heavyRain,
        'thunder' => BackdropKind.thunder,
        'snow' => BackdropKind.snow,
        'wind' => BackdropKind.wind,
        'smog' => BackdropKind.smog,
        'dust' => BackdropKind.dust,
        'humid' => BackdropKind.humid,
        _ => null,
      };

  @override
  State<WeatherBackdrop> createState() => _WeatherBackdropState();
}

enum BackdropKind { sunny, hot, cloudy, lightRain, heavyRain, thunder, snow, wind, smog, dust, humid }

class _WeatherBackdropState extends State<WeatherBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: WeatherBackdrop.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = !WeatherBackdrop.animate || MediaQuery.of(context).disableAnimations;
    if (still) {
      _clock
        ..stop()
        ..value = 0.13; // 静止时也有雨丝、雪花在半空，不是空白
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = WeatherBackdrop.kindFor(widget.cond, widget.outfitKey);
    if (kind == null) return const SizedBox.shrink();
    return RepaintBoundary(
      child: CustomPaint(painter: BackdropPainter(kind, _clock), size: Size.infinite),
    );
  }
}

/// 按动画进度画一帧。粒子的位置都由编号算出来，不存状态，每帧不分配新对象以外的东西
class BackdropPainter extends CustomPainter {
  BackdropPainter(this.kind, this.clock) : super(repaint: clock);

  final BackdropKind kind;
  final Animation<double> clock;

  static const _rain = Color(0xFF2F6BFF);
  static const _heat = Color(0xFFFF9F45);
  static const _dust = Color(0xFFB08A4F);

  /// 第 i 个粒子的第 k 个随机数，0–1，同一个 i、k 永远一样
  static double rand(int i, int k) {
    final x = math.sin(i * 12.9898 + k * 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    switch (kind) {
      case BackdropKind.sunny:
        _sun(canvas, size, t, big: false);
      case BackdropKind.hot:
        _sun(canvas, size, t, big: true);
        _heatWaves(canvas, size, t);
      case BackdropKind.cloudy:
        _clouds(canvas, size, t, count: 4, color: Pop.white);
      case BackdropKind.lightRain:
        _clouds(canvas, size, t, count: 2, color: const Color(0xFFEFF3FA));
        _rainDrops(canvas, size, t, count: 34, length: 14, alpha: 0.35, laps: 45);
      case BackdropKind.heavyRain:
        _clouds(canvas, size, t, count: 3, color: const Color(0xFFE3E9F3));
        _rainDrops(canvas, size, t, count: 80, length: 22, alpha: 0.45, laps: 70);
      case BackdropKind.thunder:
        _clouds(canvas, size, t, count: 3, color: const Color(0xFFDCD8EE));
        _rainDrops(canvas, size, t, count: 60, length: 20, alpha: 0.4, laps: 65);
        _lightning(canvas, size, t);
      case BackdropKind.snow:
        _snowflakes(canvas, size, t);
      case BackdropKind.wind:
        _windStreaks(canvas, size, t);
      case BackdropKind.smog:
        _haze(canvas, size, t, color: Pop.ink, alpha: 0.12);
      case BackdropKind.dust:
        _haze(canvas, size, t, color: _dust, alpha: 0.28);
      case BackdropKind.humid:
        _mist(canvas, size, t);
    }
  }

  /// 右上角的太阳：光芒一圈 60 秒转 30°（12 道光芒，转完正好接上），外圈光晕 4 秒一呼吸
  void _sun(Canvas canvas, Size size, double t, {required bool big}) {
    final r = size.width * (big ? 0.2 : 0.16);
    final c = Offset(size.width * 0.86, size.height * 0.11);
    final breathe = 1 + 0.06 * math.sin(2 * math.pi * t * 15);
    canvas.drawCircle(c, r * 1.9 * breathe, Paint()..color = Pop.yellow.withValues(alpha: big ? 0.22 : 0.16));
    final ray = Paint()
      ..color = Pop.yellow.withValues(alpha: 0.8)
      ..strokeWidth = big ? 8 : 6
      ..strokeCap = StrokeCap.round;
    final turn = t * 2 * math.pi / 12;
    for (var i = 0; i < 12; i++) {
      final a = turn + i * 2 * math.pi / 12;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r * 1.22), c + d * (r * 1.55), ray);
    }
    canvas.drawCircle(c, r, Paint()..color = Pop.yellow.withValues(alpha: 0.9));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = Pop.ink.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  /// 高温：下半屏几道往上飘的热浪
  void _heatWaves(Canvas canvas, Size size, double t) {
    final p = Paint()
      ..color = _heat.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final rise = ((rand(i, 1) + t * 6) % 1.0);
      final y = size.height * (0.95 - 0.45 * rise);
      final x0 = size.width * (0.08 + 0.8 * rand(i, 2));
      final path = Path()..moveTo(x0, y);
      for (var k = 1; k <= 6; k++) {
        path.relativeQuadraticBezierTo(8, k.isOdd ? -8 : 8, 16, 0);
      }
      canvas.drawPath(path, p..color = _heat.withValues(alpha: 0.3 * (1 - rise)));
    }
  }

  /// 一朵云的外形（宽 100、高 42）：三个圆加一个圆角底合成一个轮廓，只描外边。
  /// 不合并的话每个圆的边都会描出来，叠在一起很乱（2026-11-19 真机上看到的）。只算一次，每帧平移缩放
  static final Path _cloudShape = () {
    const w = 100.0, h = 42.0;
    var shape = Path()
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, h * 0.45, w, h * 0.55), const Radius.circular(h * 0.28)));
    for (final (cx, cy, r) in const [(0.3, 0.55, 0.36), (0.55, 0.4, 0.45), (0.76, 0.6, 0.3)]) {
      shape = Path.combine(
          PathOperation.union, shape, Path()..addOval(Rect.fromCircle(center: Offset(w * cx, h * cy), radius: h * r)));
    }
    return shape;
  }();

  /// 云：白底细墨线，一圈 60 秒从左飘到右（每朵正好飘整数圈，接得上）
  void _clouds(Canvas canvas, Size size, double t, {required int count, required Color color}) {
    final fill = Paint()..color = color.withValues(alpha: 0.9);
    for (var i = 0; i < count; i++) {
      final w = size.width * (0.32 + 0.16 * rand(i, 1));
      final span = size.width + w;
      final laps = i.isEven ? 1 : 2; // 近的云快一点
      final x = ((rand(i, 2) + t * laps) % 1.0) * span - w;
      final y = size.height * (0.04 + 0.22 * rand(i, 3));
      final scale = w / 100;
      canvas
        ..save()
        ..translate(x, y)
        ..scale(scale)
        ..drawPath(_cloudShape, fill)
        // 缩放后线宽也被放大，按比例缩回 2 像素
        ..drawPath(
          _cloudShape,
          Paint()
            ..color = Pop.ink.withValues(alpha: 0.16)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 / scale,
        )
        ..restore();
    }
  }

  /// 雨丝：每滴一圈落 [laps] 次左右（整数，接得上），稍微斜一点
  void _rainDrops(Canvas canvas, Size size, double t,
      {required int count, required double length, required double alpha, required int laps}) {
    final p = Paint()
      ..color = _rain.withValues(alpha: alpha)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final fall = size.height + length * 2;
    for (var i = 0; i < count; i++) {
      final speed = laps + (rand(i, 3) * 12).floor();
      final y = ((rand(i, 2) + t * speed) % 1.0) * fall - length;
      final x = rand(i, 1) * (size.width + 30);
      canvas.drawLine(Offset(x, y), Offset(x - length * 0.22, y + length), p);
    }
  }

  /// 闪电：一圈 8 次，每次一瞬间整屏发白，再落一道黄色闪电
  void _lightning(Canvas canvas, Size size, double t) {
    final phase = (t * 8) % 1.0;
    if (phase > 0.035) return;
    final strength = 1 - phase / 0.035;
    canvas.drawRect(Offset.zero & size, Paint()..color = Pop.white.withValues(alpha: 0.35 * strength));
    final n = (t * 8).floor();
    final x = size.width * (0.2 + 0.6 * rand(n, 7));
    final top = size.height * 0.12;
    final s = size.width * 0.05;
    final bolt = Path()
      ..moveTo(x, top)
      ..lineTo(x - s, top + s * 3)
      ..lineTo(x + s * 0.2, top + s * 3)
      ..lineTo(x - s * 0.8, top + s * 6.5)
      ..lineTo(x + s * 1.2, top + s * 2.4)
      ..lineTo(x + s * 0.1, top + s * 2.4)
      ..lineTo(x + s * 0.9, top)
      ..close();
    canvas.drawPath(bolt, Paint()..color = Pop.yellow.withValues(alpha: strength));
    canvas.drawPath(
      bolt,
      Paint()
        ..color = Pop.ink.withValues(alpha: 0.6 * strength)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  /// 雪花：慢慢落，左右晃
  void _snowflakes(Canvas canvas, Size size, double t) {
    final fill = Paint()..color = Pop.white;
    final line = Paint()
      ..color = Pop.ink.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < 46; i++) {
      final r = 2.5 + 3 * rand(i, 1);
      final laps = 3 + (rand(i, 2) * 3).floor();
      final y = ((rand(i, 3) + t * laps) % 1.0) * (size.height + 20) - 10;
      final sway = math.sin(2 * math.pi * (t * laps * 2 + rand(i, 4))) * 12;
      final c = Offset(rand(i, 5) * size.width + sway, y);
      canvas.drawCircle(c, r, fill);
      canvas.drawCircle(c, r, line);
    }
  }

  /// 风：一道道弯弯的风线从左往右刮
  void _windStreaks(Canvas canvas, Size size, double t) {
    final p = Paint()
      ..color = Pop.ink.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 10; i++) {
      final len = size.width * (0.22 + 0.18 * rand(i, 1));
      final laps = 6 + (rand(i, 2) * 6).floor();
      final x = ((rand(i, 3) + t * laps) % 1.0) * (size.width + len * 1.4) - len;
      final y = size.height * (0.08 + 0.85 * rand(i, 4));
      final path = Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(x + len * 0.5, y - 10, x + len, y)
        ..relativeQuadraticBezierTo(14, 6, 6, 14);
      canvas.drawPath(path, p);
    }
  }

  /// 雾霾、沙尘：细小颗粒慢慢往右飘，再加两条慢慢移动的浅色雾带
  void _haze(Canvas canvas, Size size, double t, {required Color color, required double alpha}) {
    final band = Paint()..color = Pop.white.withValues(alpha: 0.14);
    for (var b = 0; b < 2; b++) {
      final y = size.height * (0.25 + 0.4 * b) + math.sin(2 * math.pi * (t * 2 + b * 0.5)) * 18;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-20, y, size.width + 40, size.height * 0.12), const Radius.circular(40)),
        band,
      );
    }
    final dot = Paint()..color = color.withValues(alpha: alpha);
    for (var i = 0; i < 56; i++) {
      final laps = 2 + (rand(i, 1) * 2).floor();
      final x = ((rand(i, 2) + t * laps) % 1.0) * (size.width + 10) - 5;
      final y = rand(i, 3) * size.height + math.sin(2 * math.pi * (t * laps * 3 + rand(i, 4))) * 6;
      canvas.drawCircle(Offset(x, y), 1.5 + 2 * rand(i, 5), dot);
    }
  }

  /// 闷热：大团水汽慢慢漂，小水珠慢慢往上冒
  void _mist(Canvas canvas, Size size, double t) {
    final mist = Paint()..color = Pop.white.withValues(alpha: 0.2);
    for (var i = 0; i < 6; i++) {
      final r = size.width * (0.18 + 0.12 * rand(i, 1));
      final x = ((rand(i, 2) + t) % 1.0) * (size.width + r * 2) - r;
      final y = size.height * (0.15 + 0.7 * rand(i, 3)) + math.sin(2 * math.pi * (t * 3 + rand(i, 4))) * 10;
      canvas.drawCircle(Offset(x, y), r, mist);
    }
    final drop = Paint()..color = _rain.withValues(alpha: 0.18);
    for (var i = 0; i < 22; i++) {
      final laps = 3 + (rand(i, 6) * 3).floor();
      final y = size.height - ((rand(i, 7) + t * laps) % 1.0) * (size.height + 20) + 10;
      canvas.drawCircle(Offset(rand(i, 8) * size.width, y), 2 + 2 * rand(i, 9), drop);
    }
  }

  @override
  bool shouldRepaint(BackdropPainter old) => old.kind != kind || old.clock != clock;
}
