import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:pop_ui/pop_ui.dart';

import 'photo_sticker.dart';

/// 衣服档（按体感温度），和后端 config/weather.php 的 outfit_bands 一致。
enum WeatherTemp { hot, warm, mild, cool, cold, freezing }

/// 天气状态（形象叠加层），和后端 WeatherInterpreter::cond 一致。
enum WeatherCond { sunny, cloudy, lightRain, heavyRain, thunder, snow, wind, smog, dust, humid, serious }

WeatherTemp weatherTempFromKey(String? key) => switch (key) {
      'hot' => WeatherTemp.hot,
      'mild' => WeatherTemp.mild,
      'cool' => WeatherTemp.cool,
      'cold' => WeatherTemp.cold,
      'freezing' => WeatherTemp.freezing,
      _ => WeatherTemp.warm,
    };

WeatherCond weatherCondFromKey(String? key) => switch (key) {
      'cloudy' => WeatherCond.cloudy,
      'light_rain' => WeatherCond.lightRain,
      'heavy_rain' => WeatherCond.heavyRain,
      'thunder' => WeatherCond.thunder,
      'snow' => WeatherCond.snow,
      'wind' => WeatherCond.wind,
      'smog' => WeatherCond.smog,
      'dust' => WeatherCond.dust,
      'humid' => WeatherCond.humid,
      'serious' => WeatherCond.serious,
      _ => WeatherCond.sunny,
    };

const _condNames = {
  WeatherCond.sunny: '晴',
  WeatherCond.cloudy: '多云',
  WeatherCond.lightRain: '小雨',
  WeatherCond.heavyRain: '大雨',
  WeatherCond.thunder: '雷阵雨',
  WeatherCond.snow: '雪',
  WeatherCond.wind: '大风',
  WeatherCond.smog: '雾霾',
  WeatherCond.dust: '沙尘',
  WeatherCond.humid: '回南天',
  WeatherCond.serious: '预警中',
};

/// “什么鬼天气”的卡通形象：衣服按体感温度换，表情和道具按天气叠加。
/// 和设计稿 WeatherAvatar 组件逐层对应；美术素材到位后，每一层换成图片图层即可。
class WeatherAvatar extends StatelessWidget {
  const WeatherAvatar({super.key, required this.temp, required this.cond, this.size = 220});

  final WeatherTemp temp;
  final WeatherCond cond;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '天气形象：${_condNames[cond]}',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _WeatherAvatarPainter(temp, cond)),
      ),
    );
  }
}

const _gray = Color(0xFF9CA3AF);
const _rainBlue = Color(0xFF2F6BFF);
const _drop = Color(0xFF6FB7FF);
const _frost = Color(0xFF9FD3FF);
const _blush = Color(0xFFFF8FA8);
const _dust = Color(0xFFA8814A);
const _red = Color(0xFFE5484D);

const _bodyFills = {
  WeatherTemp.hot: Color(0xFFFFFFFF),
  WeatherTemp.warm: Color(0xFFFFD23F),
  WeatherTemp.mild: Color(0xFF8EC5FF),
  WeatherTemp.cool: Color(0xFF4A6FA5),
  WeatherTemp.cold: _red,
  WeatherTemp.freezing: _red,
};

/// 两种天气形象共用的画法：画笔工具、背景层（雾霾、太阳）、前景天气层（雨云、雪花、风……）和严肃模式的伞
abstract class _WeatherLayers extends CustomPainter {
  _WeatherLayers(this.t, this.c);

  final WeatherTemp t;
  final WeatherCond c;

  late Canvas _c;

  bool get _serious => c == WeatherCond.serious;

  // ---- 画笔工具 ----

  Paint _fill(Color color, [double opacity = 1]) => Paint()
    ..color = color.withAlpha((opacity * 255).round())
    ..style = PaintingStyle.fill;

  Paint _stroke(double w, [Color color = Pop.ink, double opacity = 1]) => Paint()
    ..color = color.withAlpha((opacity * 255).round())
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _path(String d, {Color? fill, double? stroke, Color strokeColor = Pop.ink, double opacity = 1}) {
    final p = _svgPath(d);
    if (fill != null) _c.drawPath(p, _fill(fill, opacity));
    if (stroke != null) _c.drawPath(p, _stroke(stroke, strokeColor, opacity));
  }

  void _circle(double x, double y, double r, {Color? fill, double? stroke, double opacity = 1}) {
    if (fill != null) _c.drawCircle(Offset(x, y), r, _fill(fill, opacity));
    if (stroke != null) _c.drawCircle(Offset(x, y), r, _stroke(stroke));
  }

  void _rrect(double x, double y, double w, double h, double r, {Color? fill, double? stroke}) {
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));
    if (fill != null) _c.drawRRect(rr, _fill(fill));
    if (stroke != null) _c.drawRRect(rr, _stroke(stroke));
  }

  void _ellipse(double cx, double cy, double rx, double ry, Color fill) {
    _c.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2), _fill(fill));
  }

  /// 背景：雾霾团、太阳
  void _background() {
    if (c == WeatherCond.smog) {
      _circle(40, 70, 34, fill: _gray, opacity: .35);
      _circle(164, 120, 40, fill: _gray, opacity: .35);
      _circle(150, 40, 26, fill: _gray, opacity: .3);
    }
    if (c == WeatherCond.sunny || (t == WeatherTemp.hot && !_serious && c != WeatherCond.humid)) {
      _path('M168 6 V12 M168 48 V54 M144 30 H150 M186 30 H192 M151 13 L155 17 M181 43 L185 47 M151 47 L155 43 M181 17 L185 13', stroke: 3);
      _circle(168, 30, 13, fill: Pop.yellow, stroke: 3);
    }
  }

  /// 大风时人整体被吹歪 8°
  void _windTilt(Canvas canvas) {
    if (c != WeatherCond.wind) return;
    canvas.translate(100, 150);
    canvas.rotate(8 * math.pi / 180);
    canvas.translate(-100, -150);
  }

  /// 严肃模式：举着伞
  void _umbrella() {
    _path('M100 40 V150 Q100 160 92 158', stroke: 4);
    _path('M36 46 Q100 -14 164 46 Q148 38 132 46 Q116 38 100 46 Q84 38 68 46 Q52 38 36 46 Z', fill: _rainBlue, stroke: 3);
  }

  /// 前景天气。[umbrella] 为 false 时不画严肃模式的伞（照片形象把伞画在人后面）
  void _foreground({bool umbrella = true}) {
    if (c == WeatherCond.lightRain || c == WeatherCond.heavyRain || c == WeatherCond.thunder) {
      final cloudFill = switch (c) {
        WeatherCond.lightRain => Colors.white,
        WeatherCond.thunder => const Color(0xFF4B5160),
        _ => const Color(0xFF8A93A3),
      };
      _path('M62 40 Q60 22 78 22 Q84 8 102 12 Q118 4 128 20 Q144 20 142 38 Q142 46 132 46 H70 Q62 46 62 40 Z', fill: cloudFill, stroke: 3);
      _path('M80 54 L76 64 M100 54 L96 64 M120 54 L116 64', stroke: 4, strokeColor: _rainBlue);
    }
    if (c == WeatherCond.heavyRain) {
      _path('M30 70 L24 84 M170 80 L164 94 M24 120 L18 134 M178 130 L172 144 M40 160 L34 174 M166 170 L160 184 M150 56 L144 70 M48 50 L42 64',
          stroke: 3.5, strokeColor: _rainBlue);
    }
    if (c == WeatherCond.thunder) {
      _path('M112 46 L98 72 L110 72 L100 94 L126 64 L114 64 L122 46 Z', fill: Pop.yellow, stroke: 2.5);
      _circle(56, 24, 8, fill: _gray, opacity: .7);
      _circle(44, 34, 6, fill: _gray, opacity: .6);
    }
    if (c == WeatherCond.snow) {
      for (final f in const [[30.0, 40.0, 5.0], [170.0, 56.0, 6.0], [20.0, 110.0, 4.0], [182.0, 120.0, 5.0], [160.0, 18.0, 4.0], [44.0, 160.0, 4.0]]) {
        _circle(f[0], f[1], f[2], fill: Colors.white, stroke: 1.5);
      }
    }
    if (c == WeatherCond.dust) {
      for (final d in const [[30.0, 50.0, 3.0], [50.0, 30.0, 2.5], [160.0, 40.0, 3.0], [176.0, 90.0, 2.5], [22.0, 130.0, 3.0], [170.0, 150.0, 3.0], [88.0, 80.0, 2.0], [118.0, 118.0, 2.0], [74.0, 124.0, 2.0]]) {
        _circle(d[0], d[1], d[2], fill: _dust);
      }
    }
    if (c == WeatherCond.wind) {
      _path('M8 72 H38 Q46 72 44 64 M2 116 H40 M12 160 H44 Q52 160 50 168', stroke: 4);
    }
    if (_serious && umbrella) _umbrella();
  }

  @override
  bool shouldRepaint(_WeatherLayers old) => old.t != t || old.c != c;
}

class _WeatherAvatarPainter extends _WeatherLayers {
  _WeatherAvatarPainter(super.t, super.c);

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / 200, size.height / 200);

    final cold = t == WeatherTemp.cold || t == WeatherTemp.freezing;
    final serious = _serious;
    final skin = t == WeatherTemp.hot ? const Color(0xFFFFC2A0) : const Color(0xFFFFD9B8);

    _background();

    // 人（大风时整体被吹歪 8°）
    canvas.save();
    _windTilt(canvas);

    _path('M42 204 Q46 156 100 154 Q154 156 158 204 Z', fill: _bodyFills[t], stroke: 4);
    if (cold) _path('M56 174 Q100 166 144 174 M50 190 Q100 182 150 190', stroke: 2.5, opacity: .55);
    if (t == WeatherTemp.cool) _path('M100 158 V204', stroke: 3);
    if (t == WeatherTemp.hot) _path('M72 160 V204 M128 160 V204', stroke: 3);
    if (cold) {
      _rrect(64, 142, 72, 18, 9, fill: Pop.yellow, stroke: 3);
      _path('M118 156 L126 182 L112 180 Z', fill: Pop.yellow, stroke: 3);
    }

    _circle(100, 100, 54, fill: skin, stroke: 4);
    if (t == WeatherTemp.hot && !serious) {
      _path('M62 142 Q60 160 67 162 Q74 160 72 144 Z M128 146 Q128 166 134 167 Q140 164 137 144 Z', fill: skin, stroke: 2.5);
    }

    // 头发 / 帽子
    if (c == WeatherCond.thunder) {
      _path('M46 96 L50 52 L64 66 L72 38 L86 58 L100 30 L114 58 L128 38 L136 66 L150 52 L154 96 Q140 72 100 72 Q60 72 46 96 Z', fill: Pop.ink);
    } else {
      _path('M46 96 Q46 44 100 44 Q154 44 154 96 Q140 68 100 68 Q62 68 46 96 Z', fill: Pop.ink);
    }
    if (c == WeatherCond.wind) _path('M150 62 Q176 52 196 60 M152 76 Q178 72 196 84 M148 50 Q168 36 190 40', stroke: 7);
    if (t == WeatherTemp.freezing) {
      _path('M48 88 Q50 40 100 38 Q150 40 152 88 Z', fill: _red, stroke: 3);
      _rrect(44, 78, 112, 16, 8, fill: Colors.white, stroke: 3);
      _circle(100, 34, 9, fill: Colors.white, stroke: 3);
      _path('M72 86 Q80 81 88 86 M112 86 Q120 81 128 86', stroke: 4, strokeColor: _frost);
    }
    if (c == WeatherCond.snow && t != WeatherTemp.freezing) {
      _path('M50 72 Q58 38 100 36 Q142 38 150 72 Q126 60 100 64 Q74 60 50 72 Z', fill: Colors.white, stroke: 3);
    }

    // 眼睛
    if (c == WeatherCond.sunny) {
      _rrect(64, 88, 30, 18, 7, fill: Pop.ink);
      _rrect(106, 88, 30, 18, 7, fill: Pop.ink);
      _path('M94 95 H106', stroke: 4);
      _path('M70 93 L78 93', stroke: 2.5, strokeColor: Colors.white);
    } else if (c == WeatherCond.dust) {
      _path('M73 93 L84 98 L73 103 M127 93 L116 98 L127 103', stroke: 3.5);
    } else {
      _circle(80, 98, 6.5, fill: Pop.ink);
      _circle(120, 98, 6.5, fill: Pop.ink);
      _circle(82, 96, 2, fill: Colors.white);
      _circle(122, 96, 2, fill: Colors.white);
    }

    if (c != WeatherCond.smog && !serious) {
      _ellipse(72, 116, 8, 4.5, _blush);
      _ellipse(128, 116, 8, 4.5, _blush);
    }
    _path('M100 106 L96 114 L103 114', stroke: 2.5);

    // 嘴
    switch (c) {
      case WeatherCond.sunny || WeatherCond.cloudy || WeatherCond.snow:
        _path('M86 126 Q100 136 114 126', stroke: 3.5);
      case WeatherCond.heavyRain || WeatherCond.dust:
        _path('M86 132 Q100 122 114 132', stroke: 3.5);
      case WeatherCond.humid:
        _path('M84 128 Q90 122 96 128 Q102 134 108 128 Q114 122 118 128', stroke: 3);
      case WeatherCond.lightRain || WeatherCond.serious:
        _path('M88 128 H112', stroke: 3.5);
      case WeatherCond.thunder || WeatherCond.wind:
        _ellipse(100, 128, 7, 9, Pop.ink);
      case WeatherCond.smog:
        // 戴口罩，不画嘴
        _path('M72 114 L48 104 M128 114 L152 104', stroke: 2.5);
        _rrect(72, 106, 56, 32, 12, fill: Colors.white, stroke: 3);
        _path('M80 118 H120 M80 127 H120', stroke: 2, opacity: .5);
    }

    if ((t == WeatherTemp.hot || c == WeatherCond.humid) && !serious) {
      _path('M146 72 Q153 84 146 89 Q139 84 146 72 Z M56 82 Q61 91 56 95 Q51 91 56 82 Z', fill: _drop, stroke: 2);
    }
    if (c == WeatherCond.heavyRain) {
      _path('M68 70 Q73 79 68 83 Q63 79 68 70 Z M130 62 Q135 71 130 75 Q125 71 130 62 Z M112 112 Q116 119 112 122 Q108 119 112 112 Z',
          fill: _drop, stroke: 2);
    }
    canvas.restore();

    _foreground();
  }
}

/// 极简 SVG path 解析：只支持设计稿里用到的绝对坐标命令 M L H V Q Z。
Path _svgPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MLHVQZ]|-?\d*\.?\d+').allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  var cmd = 'M';
  var x = 0.0, y = 0.0;
  double n() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    if (RegExp(r'^[MLHVQZ]$').hasMatch(tokens[i])) {
      cmd = tokens[i++];
      if (cmd == 'Z') {
        path.close();
        continue;
      }
    }
    switch (cmd) {
      case 'M':
        x = n();
        y = n();
        path.moveTo(x, y);
        cmd = 'L'; // M 后面连着的坐标按 L 处理
      case 'L':
        x = n();
        y = n();
        path.lineTo(x, y);
      case 'H':
        x = n();
        path.lineTo(x, y);
      case 'V':
        y = n();
        path.lineTo(x, y);
      case 'Q':
        final cx = n(), cy = n();
        x = n();
        y = n();
        path.quadraticBezierTo(cx, cy, x, y);
      default:
        i++;
    }
  }
  return path;
}

/// 导入了照片形象（[PhotoSticker] 贴纸）的人在“什么鬼天气”里的样子：贴纸代替代码画的人，穿戴和天气照常叠加。
///
/// 和 [WeatherAvatar] 一样画在 200x200 的画布上：背景 → 贴纸（大风时被吹歪）→ 贴纸上的穿戴 → 前景天气。
/// 贴纸缩到 160x160，左右居中、底边贴着画布底，头顶上留出画雨云、伞的地方。
/// 照片里的衣服没法换，衣服档改成看得出冷热的穿戴：热了冒汗，冷了围围巾，冻成狗再戴毛线帽。
/// 穿戴按对齐模板的五官位置画（照片对齐后五官离模板只差几个像素），和 [PhotoDogAvatar] 一样；
/// 现在是代码画的示意，美术按 288 的对齐模板画好素材后，每一层换成图片即可。
class PhotoWeatherAvatar extends StatelessWidget {
  const PhotoWeatherAvatar({super.key, required this.sticker, required this.temp, required this.cond, this.size = 220});

  /// [PhotoSticker.toImage] 得到的 320x320 贴纸
  final ui.Image sticker;
  final WeatherTemp temp;
  final WeatherCond cond;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '照片卡通形象，天气：${_condNames[cond]}',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _PhotoWeatherPainter(sticker, temp, cond)),
      ),
    );
  }
}

class _PhotoWeatherPainter extends _WeatherLayers {
  _PhotoWeatherPainter(this.sticker, super.t, super.c);

  final ui.Image sticker;

  /// 贴纸在 200 画布里的左上角和缩放：缩成 160x160，左右居中，底边贴着画布底
  static const _left = 20.0;
  static const _top = 40.0;
  static const _scale = 160 / PhotoSticker.canvasSize;

  /// 半张脸的宽度按 75 像素算（288 头像里），穿戴的大小和位置都从它推，和 PhotoDogAvatar 一样
  static const _h = 75.0;

  /// 下面这些都是贴纸画布（320）里的坐标
  static const _origin = Offset(PhotoSticker.offsetX + 0.0, PhotoSticker.offsetY + 0.0);
  static final _leftEye = _origin + PhotoSticker.leftEye;
  static final _rightEye = _origin + PhotoSticker.rightEye;
  static final _cx = (_leftEye.dx + _rightEye.dx) / 2;
  static final _eyeY = (_leftEye.dy + _rightEye.dy) / 2;
  static final _nose = _origin + PhotoSticker.nose;
  static final _mouthY = _origin.dy + (PhotoSticker.leftMouth.dy + PhotoSticker.rightMouth.dy) / 2;

  /// 以两眼中点为原点、半脸宽为单位的坐标
  Offset _at(double x, double y) => Offset(_cx + x * _h, _eyeY + y * _h);

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / 200, size.height / 200);

    _background();
    // 严肃模式举着伞：伞画在人后面，伞柄被头挡住，看起来是举在头顶
    if (_serious) _umbrella();

    canvas.save();
    _windTilt(canvas);
    canvas.translate(_left, _top);
    canvas.scale(_scale);
    _sticker(canvas);
    _tempWear();
    if (!_serious) _weatherWear();
    canvas.restore();

    _foreground(umbrella: false);
  }

  /// 贴纸带硬阴影，和 PhotoDogAvatar 一样
  void _sticker(Canvas canvas) {
    const quality = FilterQuality.medium;
    canvas.drawImage(
      sticker,
      const Offset(7, 7),
      Paint()
        ..colorFilter = const ColorFilter.mode(Pop.ink, BlendMode.srcIn)
        ..filterQuality = quality,
    );
    canvas.drawImage(sticker, Offset.zero, Paint()..filterQuality = quality);
  }

  Paint _ink(double width, [Color color = Pop.ink]) => _stroke(width, color);

  void _rounded(Offset center, double w, double h, double r, Color fill) {
    final rr = RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: w, height: h), Radius.circular(r));
    _c.drawRRect(rr, _fill(fill));
    _c.drawRRect(rr, _ink(6));
  }

  /// 水滴：尖朝上，[s] 是底下圆的半径
  void _teardrop(Offset p, double s, Color fill) {
    final drop = Path()
      ..moveTo(p.dx, p.dy - 1.7 * s)
      ..quadraticBezierTo(p.dx + 1.2 * s, p.dy - 0.2 * s, p.dx + s, p.dy + 0.3 * s)
      ..arcToPoint(Offset(p.dx - s, p.dy + 0.3 * s), radius: Radius.circular(s))
      ..quadraticBezierTo(p.dx - 1.2 * s, p.dy - 0.2 * s, p.dx, p.dy - 1.7 * s)
      ..close();
    _c.drawPath(drop, _fill(fill));
    _c.drawPath(drop, _ink(4));
  }

  /// 按体感温度的穿戴：热了冒汗；冷了围黄围巾；冻成狗围得更高，再戴红毛线帽、眉毛结霜。严肃模式也照常穿
  void _tempWear() {
    final cold = t == WeatherTemp.cold || t == WeatherTemp.freezing;
    if (cold) {
      // 围巾围在下巴下面，冻成狗时围到下巴
      final top = t == WeatherTemp.freezing ? _mouthY + 0.38 * _h : _mouthY + 0.47 * _h;
      final band = RRect.fromRectAndRadius(
        Rect.fromLTRB(_cx - 1.1 * _h, top, _cx + 1.1 * _h, top + 0.5 * _h),
        Radius.circular(0.18 * _h),
      );
      _c.drawRRect(band, _fill(Pop.yellow));
      _c.drawRRect(band, _ink(6));
    }
    if (t == WeatherTemp.freezing) {
      final hat = Path()
        ..moveTo(_at(-1.05, -0.62).dx, _at(-1.05, -0.62).dy)
        ..quadraticBezierTo(_at(-1.0, -1.8).dx, _at(-1.0, -1.8).dy, _at(0, -1.82).dx, _at(0, -1.82).dy)
        ..quadraticBezierTo(_at(1.0, -1.8).dx, _at(1.0, -1.8).dy, _at(1.05, -0.62).dx, _at(1.05, -0.62).dy)
        ..close();
      _c.drawPath(hat, _fill(_red));
      _c.drawPath(hat, _ink(6));
      _rounded(_at(0, -0.66), 2.3 * _h, 0.34 * _h, 0.17 * _h, Colors.white);
      _c.drawCircle(_at(0, -1.86), 0.2 * _h, _fill(Colors.white));
      _c.drawCircle(_at(0, -1.86), 0.2 * _h, _ink(6));
      // 眉毛结霜
      for (final e in [_leftEye, _rightEye]) {
        final frost = Path()
          ..moveTo(e.dx - 0.26 * _h, e.dy - 0.3 * _h)
          ..quadraticBezierTo(e.dx, e.dy - 0.42 * _h, e.dx + 0.26 * _h, e.dy - 0.3 * _h);
        _c.drawPath(frost, _ink(7, _frost));
      }
    }
    if ((t == WeatherTemp.hot || c == WeatherCond.humid) && !_serious) {
      _teardrop(_at(0.95, -0.72), 0.12 * _h, _drop);
      _teardrop(_at(-1.0, -0.42), 0.1 * _h, _drop);
    }
  }

  /// 按天气的遭罪效果（严肃模式不画）
  void _weatherWear() {
    switch (c) {
      case WeatherCond.sunny:
        // 戴墨镜
        for (final e in [_leftEye, _rightEye]) {
          final lens = RRect.fromRectAndRadius(Rect.fromCenter(center: e, width: 0.68 * _h, height: 0.42 * _h), Radius.circular(0.14 * _h));
          _c.drawRRect(lens, _fill(Pop.ink));
          _c.drawLine(e + Offset(-0.2 * _h, -0.07 * _h), e + Offset(-0.06 * _h, -0.07 * _h), _ink(4, Colors.white));
        }
        _c.drawLine(_leftEye + const Offset(0.34 * _h, -0.06 * _h), _rightEye + const Offset(-0.34 * _h, -0.06 * _h), _ink(6));
        _c.drawLine(_leftEye + const Offset(-0.34 * _h, -0.08 * _h), _leftEye + const Offset(-0.58 * _h, -0.14 * _h), _ink(5));
        _c.drawLine(_rightEye + const Offset(0.34 * _h, -0.08 * _h), _rightEye + const Offset(0.58 * _h, -0.14 * _h), _ink(5));
      case WeatherCond.smog:
        // 戴口罩，盖住鼻子和嘴
        final center = Offset(_cx, (_nose.dy + _mouthY) / 2 + 0.1 * _h);
        for (final side in [-1.0, 1.0]) {
          _c.drawLine(center + Offset(side * 0.74 * _h, -0.22 * _h), _at(side * 1.08, 0.04), _ink(4));
        }
        _rounded(center, 1.5 * _h, 0.86 * _h, 0.3 * _h, Colors.white);
        for (final dy in [-0.12, 0.12]) {
          _c.drawLine(center + Offset(-0.52 * _h, dy * _h), center + Offset(0.52 * _h, dy * _h), _ink(3, Pop.ink.withAlpha(110)));
        }
      case WeatherCond.dust:
        // 满脸沙子
        for (final (x, y, r) in const [(-0.62, -0.5, 5.0), (0.52, -0.74, 4.0), (-0.32, 0.62, 4.5), (0.64, 0.46, 5.0), (0.08, 0.98, 4.0), (-0.88, 0.2, 4.0), (0.92, -0.08, 4.5), (0.24, -0.3, 3.5), (-0.2, -1.1, 4.0)]) {
          _c.drawCircle(_at(x, y), r, _fill(_dust));
        }
      case WeatherCond.heavyRain:
        // 落汤鸡：头上脸上都是水
        for (final (x, y, s) in const [(-0.72, -1.02, 0.12), (0.78, -1.12, 0.13), (0.42, 0.62, 0.1), (-0.55, 0.42, 0.1)]) {
          _teardrop(_at(x, y), s * _h, _drop);
        }
      case WeatherCond.thunder:
        // 被劈得冒烟
        for (final (x, y, r) in const [(-0.55, -1.55, 0.24), (-0.18, -1.82, 0.18), (0.55, -1.62, 0.22), (0.9, -1.35, 0.14)]) {
          _c.drawCircle(_at(x, y), r * _h, _fill(_gray, .8));
        }
      case WeatherCond.snow:
        // 头顶堆了雪（冻成狗时戴着帽子，雪就不画了）
        if (t != WeatherTemp.freezing) {
          Offset p(double x, double y) => _at(x, y);
          final cap = Path()
            ..moveTo(p(-0.98, -0.95).dx, p(-0.98, -0.95).dy)
            ..quadraticBezierTo(p(-0.95, -1.45).dx, p(-0.95, -1.45).dy, p(-0.48, -1.42).dx, p(-0.48, -1.42).dy)
            ..quadraticBezierTo(p(-0.25, -1.78).dx, p(-0.25, -1.78).dy, p(0.18, -1.58).dx, p(0.18, -1.58).dy)
            ..quadraticBezierTo(p(0.62, -1.74).dx, p(0.62, -1.74).dy, p(0.72, -1.32).dx, p(0.72, -1.32).dy)
            ..quadraticBezierTo(p(1.04, -1.22).dx, p(1.04, -1.22).dy, p(0.98, -0.95).dx, p(0.98, -0.95).dy)
            ..quadraticBezierTo(p(0, -1.16).dx, p(0, -1.16).dy, p(-0.98, -0.95).dx, p(-0.98, -0.95).dy)
            ..close();
          _c.drawPath(cap, _fill(Colors.white));
          _c.drawPath(cap, _ink(6));
        }
      case WeatherCond.wind:
        // 头发被吹得往右飘
        final hair = Path()
          ..moveTo(_at(0.9, -1.05).dx, _at(0.9, -1.05).dy)
          ..quadraticBezierTo(_at(1.3, -1.3).dx, _at(1.3, -1.3).dy, _at(1.75, -1.18).dx, _at(1.75, -1.18).dy)
          ..moveTo(_at(0.98, -0.82).dx, _at(0.98, -0.82).dy)
          ..quadraticBezierTo(_at(1.4, -0.92).dx, _at(1.4, -0.92).dy, _at(1.78, -0.7).dx, _at(1.78, -0.7).dy)
          ..moveTo(_at(0.8, -1.28).dx, _at(0.8, -1.28).dy)
          ..quadraticBezierTo(_at(1.1, -1.6).dx, _at(1.1, -1.6).dy, _at(1.55, -1.58).dx, _at(1.55, -1.58).dy);
        _c.drawPath(hair, _ink(12));
      case WeatherCond.cloudy || WeatherCond.lightRain || WeatherCond.humid || WeatherCond.serious:
        break;
    }
  }

  @override
  bool shouldRepaint(_PhotoWeatherPainter old) => old.sticker != sticker || old.t != t || old.c != c;
}
