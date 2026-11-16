import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 拍照形象的技术验证（iOS）：照片在手机本地卡通化（Vision 找五官 → 对齐 → Core ML 跑 DCT-Net → Vision 抠出人像）。
/// 照片只在原生层的内存里处理，这里只拿到 288x288 的结果和耗时，不存盘、不上传。
/// 平涂墨线贴纸在 Flutter 里画（avatar_engine 的 PhotoSticker）。
class CartoonLabResult {
  const CartoonLabResult({
    required this.aligned,
    required this.cartoon,
    required this.cartoonRgba,
    required this.mask,
    this.faces = 1,
    this.photoSize = '',
    this.noseOffsetPx = 0,
    this.maxOffsetPx = 0,
    this.decodeMs = 0,
    this.visionMs = 0,
    this.alignMs = 0,
    this.loadMs = 0,
    this.modelMs = 0,
    this.outputMs = 0,
    this.segmentMs = 0,
    this.totalMs = 0,
  });

  factory CartoonLabResult.fromMap(Map<dynamic, dynamic> m) {
    double ms(String key) => (m[key] as num? ?? 0).toDouble();
    return CartoonLabResult(
      aligned: m['aligned'] as Uint8List,
      cartoon: m['cartoon'] as Uint8List,
      cartoonRgba: m['cartoonRgba'] as Uint8List,
      mask: m['mask'] as Uint8List,
      faces: (m['faces'] as num? ?? 1).toInt(),
      photoSize: m['photoSize'] as String? ?? '',
      noseOffsetPx: ms('noseOffsetPx'),
      maxOffsetPx: ms('maxOffsetPx'),
      decodeMs: ms('decodeMs'),
      visionMs: ms('visionMs'),
      alignMs: ms('alignMs'),
      loadMs: ms('loadMs'),
      modelMs: ms('modelMs'),
      outputMs: ms('outputMs'),
      segmentMs: ms('segmentMs'),
      totalMs: ms('totalMs'),
    );
  }

  /// 对齐裁好的 288x288 头像（还是照片，PNG）
  final Uint8List aligned;

  /// 卡通化结果（PNG）
  final Uint8List cartoon;

  /// 卡通化结果的原始像素：288x288 RGBA，第一行在最上面
  final Uint8List cartoonRgba;

  /// 人像蒙版：288x288，每像素 1 字节，255 是人
  final Uint8List mask;

  /// 照片里找到几张脸（多张时用最大的那张）
  final int faces;

  /// 缩小后参与计算的照片尺寸，比如 1280x960
  final String photoSize;

  /// 对齐后真实鼻尖离模板鼻尖多少像素（288 头像里）
  final double noseOffsetPx;

  /// 对齐后 5 个点里离模板最远的那个差多少像素；差得少，正式美术素材就能按固定坐标叠
  final double maxOffsetPx;

  final double decodeMs;
  final double visionMs;
  final double alignMs;

  /// 第一次用时加载模型的耗时，之后是 0
  final double loadMs;
  final double modelMs;
  final double outputMs;
  final double segmentMs;

  /// 原生层从解码到抠图的合计，不含 Flutter 里画贴纸
  final double totalMs;
}

class CartoonLabChannel {
  static const _channel = MethodChannel('zwjsg/cartoon_lab');

  static bool get isSupported => defaultTargetPlatform == TargetPlatform.iOS;

  /// 用包里的样图（DCT-Net 官方示例图）跑一遍
  static Future<CartoonLabResult> runSample() async {
    final m = await _channel.invokeMapMethod<String, Object?>('runSample');
    return CartoonLabResult.fromMap(m!);
  }

  /// 系统选图器选一张（不需要相册权限）；没选就返回 null
  static Future<CartoonLabResult?> runLibrary() async {
    final m = await _channel.invokeMapMethod<String, Object?>('runLibrary');
    return m == null ? null : CartoonLabResult.fromMap(m);
  }
}
