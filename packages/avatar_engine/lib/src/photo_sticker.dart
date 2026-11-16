import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// 照片形象的“日漫 + 平涂墨线”贴纸（2026-11-16 定的画风）。
///
/// 输入是手机本地卡通化的结果：288x288 的日漫头像（RGBA）和同样大小的人像蒙版（每像素 1 字节，255 是人），
/// 两者都按对齐模板摆好，五官在固定位置。处理分三步：
/// 1. 保边平滑三遍，再在 Lab 色彩空间里用 k-means 压成 [render] 的 `colors` 种平涂色块；
/// 2. 原图里比周围暗的细线描成墨线（眼睛、眉毛、发丝）；
/// 3. 按蒙版抠出人像，外面加白边、再加黑描边，放进 320x320 的透明画布，底边贴着画布底，像半身贴纸。
///
/// 纯 Dart 计算，iOS 和安卓共用；在后台 isolate 里跑（[renderInBackground]），不卡界面。
/// 原型是 Python + OpenCV 写的，参数照搬（见 apps/zaiwan_gou/tools/cartoon/README.md）。
class PhotoSticker {
  PhotoSticker._();

  /// 输入头像的边长
  static const inputSize = 288;

  /// 输出画布的边长
  static const canvasSize = 320;

  /// 288 头像在画布里的左上角：两边各留 16、上面留 32，底边贴着画布底
  static const offsetX = 16;
  static const offsetY = 32;

  /// 对齐模板里五官的位置（288 头像里的像素坐标），和 iOS 的 CartoonLab.swift 一致
  static const leftEye = ui.Offset(111.8, 137.6);
  static const rightEye = ui.Offset(179.7, 137.3);
  static const nose = ui.Offset(146.0, 176.3);

  static const _ink = [0x1B, 0x1B, 0x1F];

  /// 白边宽 5 像素，白边外再描 4 像素黑边（到人像的距离 9 像素以内）
  static const _whiteRing = 5;
  static const _inkRing = 9;

  /// 返回 320x320 的 RGBA（透明度已预乘）。蒙版里没有人时抛 [StateError]。
  static Uint8List render(Uint8List cartoonRgba, Uint8List mask, {int colors = 12}) {
    const n = inputSize;
    if (cartoonRgba.length != n * n * 4 || mask.length != n * n) {
      throw ArgumentError('需要 ${n}x$n 的卡通图和蒙版');
    }
    final solid = _cleanMask(mask, n);
    if (!solid.contains(1)) throw StateError('没抠出人像');

    final rgb = Uint8List(n * n * 3);
    for (var i = 0; i < n * n; i++) {
      rgb[i * 3] = cartoonRgba[i * 4];
      rgb[i * 3 + 1] = cartoonRgba[i * 4 + 1];
      rgb[i * 3 + 2] = cartoonRgba[i * 4 + 2];
    }
    var smooth = rgb;
    for (var i = 0; i < 3; i++) {
      smooth = _bilateral(smooth, n);
    }
    final flat = _median5(_quantize(smooth, solid, n, colors), n);
    final lines = _inkLines(rgb, solid, n);
    for (var i = 0; i < n * n; i++) {
      if (lines[i] == 1) flat.setRange(i * 3, i * 3 + 3, _ink);
    }
    return _compose(flat, solid, n);
  }

  /// 在后台 isolate 里跑 [render]
  static Future<Uint8List> renderInBackground(Uint8List cartoonRgba, Uint8List mask) =>
      compute(_renderEntry, (cartoonRgba, mask));

  /// [render] 的结果转成可以直接画的图片
  static Future<ui.Image> toImage(Uint8List rgba) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, canvasSize, canvasSize, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  // MARK: 蒙版

  /// 二值化 → 闭运算、开运算去掉毛刺和小洞 → 只留最大的一块
  static Uint8List _cleanMask(Uint8List mask, int n) {
    var b = Uint8List(n * n);
    for (var i = 0; i < n * n; i++) {
      b[i] = mask[i] > 127 ? 1 : 0;
    }
    b = _erode(_dilate(b, n, n, 3), n, n, 3);
    b = _dilate(_erode(b, n, n, 3), n, n, 3);
    return _keepLargest(b, n, n);
  }

  static Uint8List _dilate(Uint8List b, int w, int h, int r) {
    final d = _sqDist(b, w, h);
    final limit = (r + 0.5) * (r + 0.5);
    return Uint8List.fromList([for (final v in d) v <= limit ? 1 : 0]);
  }

  /// 图像边界外不算背景，贴边的部分不会被腐蚀（和 OpenCV 一样）
  static Uint8List _erode(Uint8List b, int w, int h, int r) {
    final d = _sqDist(Uint8List.fromList([for (final v in b) 1 - v]), w, h);
    final limit = (r + 0.5) * (r + 0.5);
    return Uint8List.fromList([for (final v in d) v > limit ? 1 : 0]);
  }

  /// 每个像素到最近前景像素的距离的平方（Felzenszwalb 的精确欧氏距离变换）
  static Float64List _sqDist(Uint8List fg, int w, int h) {
    const far = 1e20;
    final m = math.max(w, h);
    final f = Float64List(m), d = Float64List(m), z = Float64List(m + 1);
    final v = Int32List(m);
    final out = Float64List(w * h);
    for (var x = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        f[y] = fg[y * w + x] != 0 ? 0 : far;
      }
      _dt1d(f, h, d, v, z);
      for (var y = 0; y < h; y++) {
        out[y * w + x] = d[y];
      }
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        f[x] = out[y * w + x];
      }
      _dt1d(f, w, d, v, z);
      for (var x = 0; x < w; x++) {
        out[y * w + x] = d[x];
      }
    }
    return out;
  }

  static void _dt1d(Float64List f, int n, Float64List d, Int32List v, Float64List z) {
    var k = 0;
    v[0] = 0;
    z[0] = double.negativeInfinity;
    z[1] = double.infinity;
    double cross(int q, int p) => ((f[q] + q * q) - (f[p] + p * p)) / (2 * q - 2 * p);
    for (var q = 1; q < n; q++) {
      var s = cross(q, v[k]);
      while (s <= z[k]) {
        k--;
        s = cross(q, v[k]);
      }
      k++;
      v[k] = q;
      z[k] = s;
      z[k + 1] = double.infinity;
    }
    k = 0;
    for (var q = 0; q < n; q++) {
      while (z[k + 1] < q) {
        k++;
      }
      final dq = q - v[k];
      d[q] = dq * dq + f[v[k]];
    }
  }

  /// 8 连通的连通块编号；返回每个像素的块号（0 是背景）和各块面积
  static (Int32List, List<int>) _components(Uint8List b, int w, int h) {
    final labels = Int32List(w * h);
    final areas = <int>[0];
    final queue = Queue<int>();
    for (var start = 0; start < w * h; start++) {
      if (b[start] == 0 || labels[start] != 0) continue;
      final id = areas.length;
      var area = 0;
      labels[start] = id;
      queue.add(start);
      while (queue.isNotEmpty) {
        final p = queue.removeFirst();
        area++;
        final px = p % w, py = p ~/ w;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final x = px + dx, y = py + dy;
            if (x < 0 || y < 0 || x >= w || y >= h) continue;
            final q = y * w + x;
            if (b[q] == 0 || labels[q] != 0) continue;
            labels[q] = id;
            queue.add(q);
          }
        }
      }
      areas.add(area);
    }
    return (labels, areas);
  }

  static Uint8List _keepLargest(Uint8List b, int w, int h) {
    final (labels, areas) = _components(b, w, h);
    if (areas.length <= 1) return b;
    var best = 1;
    for (var i = 2; i < areas.length; i++) {
      if (areas[i] > areas[best]) best = i;
    }
    return Uint8List.fromList([for (final l in labels) l == best ? 1 : 0]);
  }

  // MARK: 平涂

  static int _reflect(int i, int n) => i < 0 ? -i : (i >= n ? 2 * n - 2 - i : i);

  /// 双边滤波（和 OpenCV 的 bilateralFilter(d=9, sigmaColor=40, sigmaSpace=7) 一样）：抹平渐变、保留边缘
  static Uint8List _bilateral(Uint8List src, int n) {
    const radius = 4, sigmaColor = 40.0, sigmaSpace = 7.0;
    final dxs = <int>[], dys = <int>[], ws = <double>[];
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        final r2 = dx * dx + dy * dy;
        if (r2 > radius * radius) continue;
        dxs.add(dx);
        dys.add(dy);
        ws.add(math.exp(-r2 / (2 * sigmaSpace * sigmaSpace)));
      }
    }
    final colorWeight = Float64List(256 * 3);
    for (var i = 0; i < colorWeight.length; i++) {
      colorWeight[i] = math.exp(-i * i / (2 * sigmaColor * sigmaColor));
    }
    final out = Uint8List(src.length);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final c = (y * n + x) * 3;
        final cr = src[c], cg = src[c + 1], cb = src[c + 2];
        var sw = 0.0, sr = 0.0, sg = 0.0, sb = 0.0;
        for (var k = 0; k < ws.length; k++) {
          final q = (_reflect(y + dys[k], n) * n + _reflect(x + dxs[k], n)) * 3;
          final r = src[q], g = src[q + 1], b = src[q + 2];
          final w = ws[k] * colorWeight[(r - cr).abs() + (g - cg).abs() + (b - cb).abs()];
          sw += w;
          sr += w * r;
          sg += w * g;
          sb += w * b;
        }
        out[c] = (sr / sw).round();
        out[c + 1] = (sg / sw).round();
        out[c + 2] = (sb / sw).round();
      }
    }
    return out;
  }

  static final _linear = Float64List.fromList([
    for (var i = 0; i < 256; i++)
      i / 255 <= 0.04045 ? i / 255 / 12.92 : math.pow((i / 255 + 0.055) / 1.055, 2.4).toDouble(),
  ]);

  static double _labF(double t) => t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;

  /// sRGB → Lab，按 OpenCV 8 位图的刻度（L 乘 2.55，a、b 加 128），k-means 的距离和原型一致
  static void _toLab(int r8, int g8, int b8, Float64List out, int o) {
    final r = _linear[r8], g = _linear[g8], b = _linear[b8];
    final x = (0.412453 * r + 0.357580 * g + 0.180423 * b) / 0.950456;
    final y = 0.212671 * r + 0.715160 * g + 0.072169 * b;
    final z = (0.019334 * r + 0.119193 * g + 0.950227 * b) / 1.088754;
    final fy = _labF(y);
    final l = y > 0.008856 ? 116 * fy - 16 : 903.3 * y;
    out[o] = l * 255 / 100;
    out[o + 1] = 500 * (_labF(x) - fy) + 128;
    out[o + 2] = 200 * (fy - _labF(z)) + 128;
  }

  static List<int> _fromLab(double l8, double a8, double b8) {
    final l = l8 * 100 / 255, a = a8 - 128, bb = b8 - 128;
    final fy = (l + 16) / 116, fx = fy + a / 500, fz = fy - bb / 200;
    double inv(double t) => t * t * t > 0.008856 ? t * t * t : (t - 16 / 116) / 7.787;
    final x = inv(fx) * 0.950456;
    final y = l > 7.9996 ? fy * fy * fy : l / 903.3;
    final z = inv(fz) * 1.088754;
    final lin = [
      3.240479 * x - 1.53715 * y - 0.498535 * z,
      -0.969256 * x + 1.875991 * y + 0.041556 * z,
      0.055648 * x - 0.204043 * y + 1.057311 * z,
    ];
    return [
      for (final c in lin)
        (255 * (c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(math.max(c, 0), 1 / 2.4) - 0.055))
            .round()
            .clamp(0, 255),
    ];
  }

  /// 在 Lab 里用 k-means 压成 [k] 种颜色：只用人像里的像素（隔行隔列取样）找颜色，再给整张图上色
  static Uint8List _quantize(Uint8List rgb, Uint8List solid, int n, int k) {
    final lab = Float64List(n * n * 3);
    for (var i = 0; i < n * n; i++) {
      _toLab(rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2], lab, i * 3);
    }
    final samples = <int>[
      for (var y = 0; y < n; y += 2)
        for (var x = 0; x < n; x += 2)
          if (solid[y * n + x] == 1) y * n + x,
    ];
    final centers = Float64List(k * 3);
    double dist(int p, int c) {
      final d0 = lab[p * 3] - centers[c * 3];
      final d1 = lab[p * 3 + 1] - centers[c * 3 + 1];
      final d2 = lab[p * 3 + 2] - centers[c * 3 + 2];
      return d0 * d0 + d1 * d1 + d2 * d2;
    }

    // k-means++ 选初始中心，种子固定，同一张图每次结果一样
    final random = math.Random(7);
    final nearest = Float64List(samples.length)..fillRange(0, samples.length, double.infinity);
    var first = samples[random.nextInt(samples.length)];
    centers.setRange(0, 3, lab, first * 3);
    for (var c = 1; c < k; c++) {
      var total = 0.0;
      for (var i = 0; i < samples.length; i++) {
        nearest[i] = math.min(nearest[i], dist(samples[i], c - 1));
        total += nearest[i];
      }
      var target = random.nextDouble() * total;
      var pick = samples.last;
      for (var i = 0; i < samples.length; i++) {
        target -= nearest[i];
        if (target <= 0) {
          pick = samples[i];
          break;
        }
      }
      centers.setRange(c * 3, c * 3 + 3, lab, pick * 3);
    }

    final assign = Int32List(samples.length);
    for (var iter = 0; iter < 40; iter++) {
      final sums = Float64List(k * 3), counts = Int32List(k);
      for (var i = 0; i < samples.length; i++) {
        var best = 0;
        var bestD = double.infinity;
        for (var c = 0; c < k; c++) {
          final d = dist(samples[i], c);
          if (d < bestD) {
            bestD = d;
            best = c;
          }
        }
        assign[i] = best;
        counts[best]++;
        for (var j = 0; j < 3; j++) {
          sums[best * 3 + j] += lab[samples[i] * 3 + j];
        }
      }
      var moved = 0.0;
      for (var c = 0; c < k; c++) {
        if (counts[c] == 0) continue; // 空簇保留原来的中心
        for (var j = 0; j < 3; j++) {
          final next = sums[c * 3 + j] / counts[c];
          moved = math.max(moved, (next - centers[c * 3 + j]).abs());
          centers[c * 3 + j] = next;
        }
      }
      if (moved < 0.5) break;
    }

    final palette = [for (var c = 0; c < k; c++) _fromLab(centers[c * 3], centers[c * 3 + 1], centers[c * 3 + 2])];
    final out = Uint8List(n * n * 3);
    for (var p = 0; p < n * n; p++) {
      var best = 0;
      var bestD = double.infinity;
      for (var c = 0; c < k; c++) {
        final d = dist(p, c);
        if (d < bestD) {
          bestD = d;
          best = c;
        }
      }
      out.setRange(p * 3, p * 3 + 3, palette[best]);
    }
    return out;
  }

  /// 5x5 中值滤波（每个通道分开），去掉色块边上的碎点
  static Uint8List _median5(Uint8List src, int n) {
    final out = Uint8List(src.length);
    final window = Int32List(25);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        for (var ch = 0; ch < 3; ch++) {
          var m = 0;
          for (var dy = -2; dy <= 2; dy++) {
            final yy = (y + dy).clamp(0, n - 1);
            for (var dx = -2; dx <= 2; dx++) {
              final xx = (x + dx).clamp(0, n - 1);
              window[m++] = src[(yy * n + xx) * 3 + ch];
            }
          }
          window.sort();
          out[(y * n + x) * 3 + ch] = window[12];
        }
      }
    }
    return out;
  }

  // MARK: 墨线

  /// 3x3 高斯（1 2 1）
  static Float64List _gauss3(Float64List src, int n) {
    final tmp = Float64List(n * n), out = Float64List(n * n);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        tmp[y * n + x] =
            (src[y * n + _reflect(x - 1, n)] + 2 * src[y * n + x] + src[y * n + _reflect(x + 1, n)]) / 4;
      }
    }
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        out[y * n + x] =
            (tmp[_reflect(y - 1, n) * n + x] + 2 * tmp[y * n + x] + tmp[_reflect(y + 1, n) * n + x]) / 4;
      }
    }
    return out;
  }

  /// 比周围 11x11 的平均亮度暗 9 以上的点算线（自适应阈值），只留人像里面、面积 18 像素以上的线
  static Uint8List _inkLines(Uint8List rgb, Uint8List solid, int n) {
    final gray = Float64List(n * n);
    for (var i = 0; i < n * n; i++) {
      gray[i] = (0.299 * rgb[i * 3] + 0.587 * rgb[i * 3 + 1] + 0.114 * rgb[i * 3 + 2]).roundToDouble();
    }
    final blurred = _gauss3(gray, n);
    for (var i = 0; i < n * n; i++) {
      blurred[i] = blurred[i].roundToDouble();
    }
    // 积分图算 11x11 平均（边上按最近的像素补）
    const r = 5;
    final w = n + 2 * r;
    final integral = Float64List((w + 1) * (w + 1));
    for (var y = 0; y < w; y++) {
      var row = 0.0;
      for (var x = 0; x < w; x++) {
        row += blurred[(y - r).clamp(0, n - 1) * n + (x - r).clamp(0, n - 1)];
        integral[(y + 1) * (w + 1) + x + 1] = integral[y * (w + 1) + x + 1] + row;
      }
    }
    final inner = _erode(solid, n, n, 2);
    final lines = Uint8List(n * n);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final sum = integral[(y + 2 * r + 1) * (w + 1) + x + 2 * r + 1] -
            integral[y * (w + 1) + x + 2 * r + 1] -
            integral[(y + 2 * r + 1) * (w + 1) + x] +
            integral[y * (w + 1) + x];
        final mean = (sum / ((2 * r + 1) * (2 * r + 1))).roundToDouble();
        if (inner[y * n + x] == 1 && blurred[y * n + x] - mean <= -9) lines[y * n + x] = 1;
      }
    }
    final (labels, areas) = _components(lines, n, n);
    for (var i = 0; i < n * n; i++) {
      if (labels[i] != 0 && areas[labels[i]] < 18) lines[i] = 0;
    }
    return lines;
  }

  // MARK: 贴纸

  static Uint8List _compose(Uint8List flat, Uint8List solid, int n) {
    const c = canvasSize;
    final placed = Uint8List(c * c);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        placed[(y + offsetY) * c + x + offsetX] = solid[y * n + x];
      }
    }
    final dist2 = _sqDist(placed, c, c);
    // 人像边缘柔一点，和白边自然过渡
    final soft = _gauss3(Float64List.fromList([for (final v in solid) v.toDouble()]), n);
    final out = Uint8List(c * c * 4);
    for (var y = 0; y < c; y++) {
      for (var x = 0; x < c; x++) {
        final d = math.sqrt(dist2[y * c + x]);
        if (d >= _inkRing + 1) continue;
        final alpha = (_inkRing + 1 - d).clamp(0.0, 1.0);
        final t = (_whiteRing + 1 - d).clamp(0.0, 1.0); // 1 白边，0 黑描边
        final color = [for (final ink in _ink) 255 * t + ink * (1 - t)];
        final fx = x - offsetX, fy = y - offsetY;
        if (fx >= 0 && fy >= 0 && fx < n && fy < n) {
          final a = soft[fy * n + fx];
          for (var j = 0; j < 3; j++) {
            color[j] = flat[(fy * n + fx) * 3 + j] * a + color[j] * (1 - a);
          }
        }
        final o = (y * c + x) * 4;
        for (var j = 0; j < 3; j++) {
          out[o + j] = (color[j] * alpha).round().clamp(0, 255);
        }
        out[o + 3] = (255 * alpha).round();
      }
    }
    return out;
  }
}

Uint8List _renderEntry((Uint8List, Uint8List) args) => PhotoSticker.render(args.$1, args.$2);
