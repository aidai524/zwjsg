import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 用户的卡通形象存在手机上：存的是贴纸（PNG），不是照片。抽成接口，测试里换成存在内存里的。
/// “再玩我是狗”（拍照做的）和“什么鬼天气”（从狗 App 导入的）共用。
abstract class AvatarStore {
  /// 没存过时返回 null
  Future<Uint8List?> load();

  Future<void> save(Uint8List png);

  Future<void> delete();
}

/// 存在 App 自己的支持目录里（不进相册、用户看不到）
class FileAvatarStore implements AvatarStore {
  const FileAvatarStore();

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/avatar/sticker.png');
  }

  @override
  Future<Uint8List?> load() async {
    final file = await _file();
    return await file.exists() ? await file.readAsBytes() : null;
  }

  @override
  Future<void> save(Uint8List png) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    // 先写临时文件再改名：写到一半 App 被关掉，也不会留下半张图
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(png, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> delete() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
