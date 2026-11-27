import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_state.dart';
import '../../widgets/my_avatar.dart';

/// 群里一个人的形象：TA 用着拍照形象，就下载下来叠上 TA 今天的变狗图层；不然画 TA 挑的预设形象（没挑过是呆毛）。
/// 自己用自己的
class MemberAvatar extends StatefulWidget {
  const MemberAvatar({
    super.key,
    required this.url,
    required this.stage,
    required this.size,
    this.preset,
    this.isMe = false,
  });

  final String? url;
  final AvatarPreset? preset;
  final int stage;
  final double size;
  final bool isMe;

  /// 同一个地址只下载、解码一次
  static final Map<String, Future<ui.Image?>> _cache = {};

  @visibleForTesting
  static void clearCache() => _cache.clear();

  @override
  State<MemberAvatar> createState() => _MemberAvatarState();
}

class _MemberAvatarState extends State<MemberAvatar> {
  ui.Image? _image;
  String? _loaded;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(MemberAvatar old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _load();
  }

  Future<void> _load() async {
    final url = widget.url;
    if (widget.isMe || url == null || url == _loaded) return;
    _loaded = url;
    final api = AppScope.read(context).api;
    final image = await MemberAvatar._cache.putIfAbsent(url, () async {
      try {
        final codec = await ui.instantiateImageCodec(await api.downloadAvatar(url));
        return (await codec.getNextFrame()).image;
      } catch (_) {
        // 下载不了（比如本机调试时形象地址手机访问不到）就用默认形象
        return null;
      }
    });
    if (mounted && widget.url == url) setState(() => _image = image);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isMe) return MyAvatar(stage: widget.stage, size: widget.size);
    final image = widget.url == null ? null : _image;
    return image == null
        ? DogAvatar(stage: widget.stage, size: widget.size, preset: widget.preset ?? AvatarPreset.fallback)
        : PhotoDogAvatar(sticker: image, stage: widget.stage, size: widget.size);
  }
}

/// 圆框里的形象。[stage] 为 null（没同步、藏起来了）时是灰底问号
class MemberBadge extends StatelessWidget {
  const MemberBadge({
    super.key,
    required this.url,
    required this.stage,
    required this.size,
    this.preset,
    this.isMe = false,
    this.highlight = false,
  });

  final String? url;
  final AvatarPreset? preset;
  final int? stage;
  final double size;
  final bool isMe;

  /// 狗王、今天最狗的：黄底
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final s = stage;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: s == null ? Pop.gray : (highlight ? Pop.softYellow : Pop.white),
        shape: BoxShape.circle,
        border: Border.all(color: Pop.ink, width: size >= 56 ? 2.5 : 2),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: s == null ? Alignment.center : Alignment.bottomCenter,
      child: s == null
          ? Text('?', style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w900, color: Pop.muted))
          : MemberAvatar(url: url, preset: preset, stage: s, size: size - 6, isMe: isMe),
    );
  }
}
