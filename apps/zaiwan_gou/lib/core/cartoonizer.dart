import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 照片从哪来
enum PhotoSource { camera, library }

/// 手机本地卡通化的结果：288x288 的日漫头像（RGBA，第一行在最上面）和同样大小的人像蒙版（每像素 1 字节，255 是人）。
/// 两者都按对齐模板摆好，五官在固定位置。照片本身不出原生层，这里拿到的已经是卡通图。
class CartoonFace {
  const CartoonFace({required this.rgba, required this.mask, this.faces = 1});

  final Uint8List rgba;
  final Uint8List mask;

  /// 照片里找到几张脸；多张时用的是最大的那张
  final int faces;
}

/// 拍照形象：打开相机或系统选图器，照片在手机本地变成卡通。抽成接口，测试里换成假的。
abstract class Cartoonizer {
  /// 这台手机能不能做（iOS 2026-11-16 起，安卓 2026-11-27 起）
  bool get isSupported;

  /// 用户没拍、没选时返回 null。失败时抛 [PlatformException]，message 可以直接给用户看
  Future<CartoonFace?> cartoonize(PhotoSource source);
}

class NativeCartoonizer implements Cartoonizer {
  const NativeCartoonizer();

  static const _channel = MethodChannel('zwjsg/cartoon');

  @override
  bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<CartoonFace?> cartoonize(PhotoSource source) async {
    final m = await _channel.invokeMapMethod<String, Object?>(source.name);
    if (m == null) return null;
    return CartoonFace(
      rgba: m['cartoonRgba']! as Uint8List,
      mask: m['mask']! as Uint8List,
      faces: (m['faces'] as num? ?? 1).toInt(),
    );
  }
}
