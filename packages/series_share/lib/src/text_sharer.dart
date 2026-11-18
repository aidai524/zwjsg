import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// 用手机系统的分享面板发一段文字（比如关心群的邀请）：发给谁、用哪个 App（微信、短信……）由用户在面板里选，我们不经手。
/// 抽成接口，测试里换成假的。
abstract class TextSharer {
  /// 弹出分享面板。面板打不开（平台不支持、出错）时返回 false，调用方再想别的办法，比如复制到剪贴板。
  /// [origin] 是按钮在屏幕上的位置，iPad 的分享面板要从这里弹出
  Future<bool> share(String text, {Rect? origin});
}

class SystemTextSharer implements TextSharer {
  const SystemTextSharer();

  @override
  Future<bool> share(String text, {Rect? origin}) async {
    try {
      // 用户在面板里点了取消也算打开过：不再走复制的备用办法
      await SharePlus.instance.share(ShareParams(text: text, sharePositionOrigin: origin));
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
