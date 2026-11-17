import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/widgets.dart';

import '../core/app_state.dart';

/// 用户自己的形象：拍照做过形象就用照片贴纸叠变狗图层，没做过就用代码画的默认形象
class MyAvatar extends StatelessWidget {
  const MyAvatar({super.key, required this.stage, this.size = 200});

  final int stage;
  final double size;

  @override
  Widget build(BuildContext context) {
    final sticker = AppScope.of(context).photoAvatar;
    return sticker == null
        ? DogAvatar(stage: stage, size: size)
        : PhotoDogAvatar(sticker: sticker, stage: stage, size: size);
  }
}
