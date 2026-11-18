import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// 不经过 Widget 树，把 [painter] 画成 [pixels] x [pixels] 的图片（背景透明）。返回的图片用完要 dispose
Future<ui.Image> paintToImage(CustomPainter painter, int pixels) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Size.square(pixels.toDouble()));
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(pixels, pixels);
  } finally {
    picture.dispose();
  }
}

/// 桌面小组件用的形象图。小组件跑不了 Flutter，App 预先把要用的几张图画好，放进小组件能读的目录
/// （iOS 是 App Group 共享目录，安卓是 App 自己的 files 目录）。
///
/// 目录里记下这批图是按哪个签名画的（[versionFile]）：签名一样、图也都在，就不重画。
/// 签名一般是“画法版本 + 形象原图的指纹”（[fingerprint]），形象换了或者画法改了才重画。
class WidgetImages {
  WidgetImages._();

  /// 记录签名的文件
  static const versionFile = 'avatars.version';

  /// 按 [images]（文件名 → 怎么画）把图画进 [dir]。
  /// 画了返回 true；签名没变、图都在，不用画，返回 false。
  /// 画到一半 [stale] 变成 true（比如形象又换了）就停下、不写签名，返回 false，下次再画。
  static Future<bool> sync({
    required String dir,
    required String signature,
    required Map<String, Future<ui.Image> Function()> images,
    bool Function()? stale,
  }) async {
    final version = File('$dir/$versionFile');
    if (await version.exists() && await version.readAsString() == signature && await _allExist(dir, images.keys)) {
      return false;
    }

    await Directory(dir).create(recursive: true);
    for (final MapEntry(key: name, value: render) in images.entries) {
      if (stale?.call() ?? false) return false;
      await _write(dir, name, await _png(await render()));
    }
    await version.writeAsString(signature, flush: true);
    return true;
  }

  /// 32 位 FNV-1a 加上长度：只用来判断形象原图换没换
  static String fingerprint(Uint8List bytes) {
    var h = 0x811c9dc5;
    for (final b in bytes) {
      h = ((h ^ b) * 0x01000193) & 0xffffffff;
    }
    return '${bytes.length}-${h.toRadixString(16)}';
  }

  static Future<bool> _allExist(String dir, Iterable<String> names) async {
    for (final name in names) {
      if (!await File('$dir/$name').exists()) return false;
    }
    return true;
  }

  static Future<Uint8List> _png(ui.Image image) async {
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// 先写临时文件再改名：小组件正好在读时，读到的是旧图或新图，不会是写了一半的图
  static Future<void> _write(String dir, String name, Uint8List bytes) async {
    final tmp = File('$dir/$name.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename('$dir/$name');
  }
}
