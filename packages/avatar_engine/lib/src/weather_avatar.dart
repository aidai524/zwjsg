import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:pop_ui/pop_ui.dart';

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

class _WeatherAvatarPainter extends CustomPainter {
  _WeatherAvatarPainter(this.t, this.c);

  final WeatherTemp t;
  final WeatherCond c;

  static const _gray = Color(0xFF9CA3AF);
  static const _rainBlue = Color(0xFF2F6BFF);
  static const _drop = Color(0xFF6FB7FF);
  static const _frost = Color(0xFF9FD3FF);
  static const _blush = Color(0xFFFF8FA8);
  static const _dust = Color(0xFFA8814A);
  static const _red = Color(0xFFE5484D);

  static const _bodyFills = {
    WeatherTemp.hot: Color(0xFFFFFFFF),
    WeatherTemp.warm: Color(0xFFFFD23F),
    WeatherTemp.mild: Color(0xFF8EC5FF),
    WeatherTemp.cool: Color(0xFF4A6FA5),
    WeatherTemp.cold: _red,
    WeatherTemp.freezing: _red,
  };

  late Canvas _c;

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

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / 200, size.height / 200);

    final cold = t == WeatherTemp.cold || t == WeatherTemp.freezing;
    final serious = c == WeatherCond.serious;
    final skin = t == WeatherTemp.hot ? const Color(0xFFFFC2A0) : const Color(0xFFFFD9B8);

    // 背景：雾霾团、太阳
    if (c == WeatherCond.smog) {
      _circle(40, 70, 34, fill: _gray, opacity: .35);
      _circle(164, 120, 40, fill: _gray, opacity: .35);
      _circle(150, 40, 26, fill: _gray, opacity: .3);
    }
    if (c == WeatherCond.sunny || (t == WeatherTemp.hot && !serious && c != WeatherCond.humid)) {
      _path('M168 6 V12 M168 48 V54 M144 30 H150 M186 30 H192 M151 13 L155 17 M181 43 L185 47 M151 47 L155 43 M181 17 L185 13', stroke: 3);
      _circle(168, 30, 13, fill: Pop.yellow, stroke: 3);
    }

    // 人（大风时整体被吹歪 8°）
    canvas.save();
    if (c == WeatherCond.wind) {
      canvas.translate(100, 150);
      canvas.rotate(8 * math.pi / 180);
      canvas.translate(-100, -150);
    }

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

    // 前景天气
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
    if (serious) {
      // 严肃模式：举着伞，表情正经
      _path('M100 40 V150 Q100 160 92 158', stroke: 4);
      _path('M36 46 Q100 -14 164 46 Q148 38 132 46 Q116 38 100 46 Q84 38 68 46 Q52 38 36 46 Z', fill: _rainBlue, stroke: 3);
    }
  }

  @override
  bool shouldRepaint(_WeatherAvatarPainter old) => old.t != t || old.c != c;
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
