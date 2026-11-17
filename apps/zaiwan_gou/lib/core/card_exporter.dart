import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 保存或分享失败时给用户看的话
class CardExportException implements Exception {
  const CardExportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 结算卡导出：截图、保存到相册、系统分享（能直接发到微信）。抽成接口，测试里换成假的。
abstract class CardExporter {
  /// 把 [boundaryKey] 对应的 RepaintBoundary 截成 PNG
  Future<Uint8List> capture(GlobalKey boundaryKey);

  Future<void> save(Uint8List png);

  /// [origin] 是分享按钮在屏幕上的位置，iPad 的分享面板要从这里弹出
  Future<void> share(Uint8List png, {Rect? origin});
}

class DefaultCardExporter implements CardExporter {
  const DefaultCardExporter();

  @override
  Future<Uint8List> capture(GlobalKey boundaryKey) async {
    final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // 卡片在屏幕上大约 300 × 400，3 倍出图 900 × 1200，发朋友圈够清楚
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  @override
  Future<void> save(Uint8List png) async {
    if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
      throw const CardExportException('没有相册权限，去系统设置里允许“再玩我是狗”添加照片');
    }
    try {
      await Gal.putImageBytes(png, name: 'zaiwangou_${DateTime.now().millisecondsSinceEpoch}');
    } on GalException catch (e) {
      throw CardExportException(switch (e.type) {
        GalExceptionType.accessDenied => '没有相册权限，去系统设置里允许“再玩我是狗”添加照片',
        GalExceptionType.notEnoughSpace => '手机空间不够，存不下了',
        _ => '没存上，稍后再试',
      });
    }
  }

  @override
  Future<void> share(Uint8List png, {Rect? origin}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/zaiwangou_card.png');
    await file.writeAsBytes(png, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      sharePositionOrigin: origin,
    ));
  }
}
