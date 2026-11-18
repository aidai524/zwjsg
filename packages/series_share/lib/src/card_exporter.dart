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

/// 分享卡片（狗 App 的结算卡、天气 App 的天气卡）的导出：截图、保存到相册、系统分享（能直接发到微信）。
/// 抽成接口，测试里换成假的。
abstract class CardExporter {
  /// 把 [boundaryKey] 对应的 RepaintBoundary 截成 PNG
  Future<Uint8List> capture(GlobalKey boundaryKey);

  Future<void> save(Uint8List png);

  /// [origin] 是分享按钮在屏幕上的位置，iPad 的分享面板要从这里弹出
  Future<void> share(Uint8List png, {Rect? origin});
}

class DefaultCardExporter implements CardExporter {
  /// [appName] 用在提示里（“去系统设置里允许 xx 添加照片”），[filePrefix] 是存下来的图片的文件名前缀
  const DefaultCardExporter({required this.appName, required this.filePrefix});

  final String appName;
  final String filePrefix;

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
    final denied = '没有相册权限，去系统设置里允许“$appName”添加照片';
    if (!await Gal.hasAccess() && !await Gal.requestAccess()) throw CardExportException(denied);
    try {
      await Gal.putImageBytes(png, name: '${filePrefix}_${DateTime.now().millisecondsSinceEpoch}');
    } on GalException catch (e) {
      throw CardExportException(switch (e.type) {
        GalExceptionType.accessDenied => denied,
        GalExceptionType.notEnoughSpace => '手机空间不够，存不下了',
        _ => '没存上，稍后再试',
      });
    }
  }

  @override
  Future<void> share(Uint8List png, {Rect? origin}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${filePrefix}_card.png');
    await file.writeAsBytes(png, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      sharePositionOrigin: origin,
    ));
  }
}
