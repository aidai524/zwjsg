import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/widgets.dart';

import '../core/app_state.dart';

/// 用户自己的形象：用着拍照形象就用照片贴纸叠变狗图层，不然用代码画的、自己挑的那张预设形象（没挑过是呆毛）。
/// 做人（阶段 0）时穿上进化形态（自己挑的，或者最新解锁的，见 core/evolution.dart）：
/// [evolution] 指定穿哪一种（图鉴里看某一种的样子）；[evolved] 为 false 时不穿（以前的日子、犬种预览）
class MyAvatar extends StatelessWidget {
  const MyAvatar({super.key, required this.stage, this.size = 200, this.evolved = true, this.evolution});

  final int stage;
  final double size;
  final bool evolved;
  final Evolution? evolution;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final sticker = state.photoAvatar;
    final wear = stage != 0 ? null : evolution ?? (evolved ? state.wornEvolution : null);
    return sticker == null
        ? DogAvatar(stage: stage, size: size, evolution: wear, preset: state.avatarPreset)
        : PhotoDogAvatar(sticker: sticker, stage: stage, size: size, evolution: wear);
  }
}
