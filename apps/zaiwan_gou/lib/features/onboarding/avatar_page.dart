import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/cartoonizer.dart';
import '../../widgets/ai_tag.dart';

/// 把卡通图画成平涂墨线贴纸；测试里可以换掉
typedef FaceStickerRenderer = Future<ui.Image> Function(CartoonFace face);

/// 在后台 isolate 里画贴纸，再转成图片
Future<ui.Image> renderFaceSticker(CartoonFace face) async =>
    PhotoSticker.toImage(await PhotoSticker.renderInBackground(face.rgba, face.mask));

/// 形象创建（也用来换形象）：拍自拍或从相册选一张 → 手机本地卡通化 → 画成平涂墨线贴纸 → 预览 → 就用这个。
/// 照片只在原生层的内存里处理，这里拿到的已经是卡通图；存在手机上、传到服务端的只有贴纸。
/// 第一次用照片前，要单独同意处理照片里的人脸信息。
class AvatarPage extends StatefulWidget {
  const AvatarPage({
    super.key,
    this.editing = false,
    this.cartoonizer = const NativeCartoonizer(),
    this.renderSticker = renderFaceSticker,
  });

  /// 从“我的”进来换形象：做完回到上一页。否则是引导的一步，做完去设目标
  final bool editing;

  /// [cartoonizer]、[renderSticker] 只在测试里换
  final Cartoonizer cartoonizer;
  final FaceStickerRenderer renderSticker;

  @override
  State<AvatarPage> createState() => _AvatarPageState();
}

class _AvatarPageState extends State<AvatarPage> {
  /// 新做好、还没确认的形象
  ui.Image? _candidate;
  int _faces = 1;
  bool _busy = false;
  bool _saving = false;

  @override
  void dispose() {
    _candidate?.dispose();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _done() => widget.editing ? context.pop() : context.go('/goal');

  Future<bool> _ensureConsent() async {
    final state = AppScope.read(context);
    if (state.faceConsented) return true;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pop.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const FaceConsentSheet(),
    );
    if (ok != true) return false;
    await state.acceptFaceConsent();
    return true;
  }

  Future<void> _pick(PhotoSource source) async {
    if (_busy || _saving) return;
    if (!await _ensureConsent() || !mounted) return;
    setState(() => _busy = true);
    try {
      final face = await widget.cartoonizer.cartoonize(source);
      if (face == null || !mounted) return;
      final image = await widget.renderSticker(face);
      if (!mounted) {
        image.dispose();
        return;
      }
      _candidate?.dispose();
      setState(() {
        _candidate = image;
        _faces = face.faces;
      });
    } on PlatformException catch (e) {
      if (mounted) _toast(e.message ?? '没弄好，换一张试试');
    } on StateError {
      if (mounted) _toast('没抠出人像，换一张正脸、背景干净点的照片');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _retake() {
    _candidate?.dispose();
    setState(() => _candidate = null);
  }

  Future<void> _confirm() async {
    final image = _candidate;
    if (image == null || _saving) return;
    setState(() => _saving = true);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      await AppScope.read(context).setPhotoAvatar(data!.buffer.asUint8List());
      if (mounted) _done();
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final current = state.photoAvatar;
    final candidate = _candidate;
    final supported = widget.cartoonizer.isSupported;
    // 换掉已有的拍照形象才算次数（服务端管），第一次做不算
    final regenLeft = widget.editing && current != null ? state.avatarRegenLeft : null;
    final usedUp = regenLeft != null && regenLeft <= 0;
    final idle = !_busy && !_saving;

    final String title;
    final String subtitle;
    if (candidate != null) {
      title = '这就是你';
      subtitle = '刷得越多，它就越像狗。不满意就换一张。';
    } else {
      title = widget.editing ? '换个形象' : '先做一个你';
      subtitle = '拍张自拍，我们把你画成卡通。之后你刷多少，它就变多狗。';
    }

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: PopText.title),
              const SizedBox(height: 8),
              Text(subtitle, style: PopText.bodyMuted),
              Expanded(
                child: Center(
                  // 小屏手机上整体缩小，不溢出
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _busy
                        ? const _Working()
                        : candidate != null
                            ? _Preview(sticker: candidate, faces: _faces)
                            : _Placeholder(current: current),
                  ),
                ),
              ),
              if (candidate != null) ...[
                PopButton(label: '就用这个', loading: _saving, onPressed: idle ? _confirm : null),
                const SizedBox(height: 14),
                PopButton(
                  label: '换一张',
                  style: PopButtonStyle.secondary,
                  height: 52,
                  onPressed: idle ? _retake : null,
                ),
              ] else if (supported) ...[
                if (regenLeft != null) ...[
                  Text(usedUp ? '换形象的次数用完了' : '还能换 $regenLeft 次形象',
                      textAlign: TextAlign.center, style: PopText.small),
                  const SizedBox(height: 10),
                ],
                PopButton(
                  label: '拍一张自拍',
                  onPressed: idle && !usedUp ? () => _pick(PhotoSource.camera) : null,
                ),
                const SizedBox(height: 14),
                PopButton(
                  label: '从相册选一张',
                  style: PopButtonStyle.secondary,
                  height: 52,
                  onPressed: idle && !usedUp ? () => _pick(PhotoSource.library) : null,
                ),
                if (!widget.editing) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(current == null ? '不想露脸？' : '已经有形象了？', style: PopText.small),
                      TextButton(
                        onPressed: idle ? _done : null,
                        child: Text(
                          current == null ? '先用默认形象' : '就用现在这个',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, color: Pop.ink, decoration: TextDecoration.underline),
                        ),
                      ),
                    ],
                  ),
                ] else
                  const SizedBox(height: 14),
              ] else ...[
                const _Note(icon: Icons.construction_outlined, text: '安卓版的拍照形象还在做。先用默认形象，做好了在“我的”里换。'),
                if (!widget.editing) ...[
                  const SizedBox(height: 14),
                  PopButton(label: '先用默认形象', onPressed: _done),
                ],
                const SizedBox(height: 14),
              ],
              if (candidate != null) const SizedBox(height: 14),
              const _Note(icon: Icons.lock_outline, text: '照片只在你手机上变成卡通，原图不保存、不上传。请只用本人照片。'),
            ],
          ),
        ),
      ),
    );
  }
}

/// 还没做形象时的圆框；已经有拍照形象时显示现在的形象
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.current});

  final ui.Image? current;

  @override
  Widget build(BuildContext context) {
    final image = current;
    return Container(
      width: 240,
      height: 240,
      decoration: BoxDecoration(
        color: Pop.softYellow,
        shape: BoxShape.circle,
        border: Border.all(color: Pop.ink, width: Pop.stroke),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: image == null ? Alignment.center : Alignment.bottomCenter,
      child: image != null
          ? PhotoDogAvatar(sticker: image, stage: 0, size: 220)
          : const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.photo_camera_outlined, size: 52, color: Pop.ink),
                SizedBox(height: 10),
                Text('正脸，光线亮一点', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text('别戴口罩，狗不戴口罩', style: PopText.small),
              ],
            ),
    );
  }
}

class _Working extends StatelessWidget {
  const _Working();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      height: 240,
      decoration: BoxDecoration(
        color: Pop.softYellow,
        shape: BoxShape.circle,
        border: Border.all(color: Pop.ink, width: Pop.stroke),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: Pop.ink, strokeWidth: 4)),
          SizedBox(height: 16),
          Text('正在把你画成卡通…', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text('照片只在这台手机上处理', style: PopText.small),
        ],
      ),
    );
  }
}

/// 新做好的形象：大图是现在的样子，下面一排是刷多了会变成的样子
class _Preview extends StatelessWidget {
  const _Preview({required this.sticker, required this.faces});

  final ui.Image sticker;
  final int faces;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: Pop.card(color: Pop.yellow, radius: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              PhotoDogAvatar(sticker: sticker, stage: 0, size: 196),
              const Positioned(right: 0, top: 0, child: AiTag()),
            ],
          ),
          const SizedBox(height: 10),
          const Text('刷多了会变成这样', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Pop.mutedOnYellow)),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final stage in [1, 2, 3, 4, 5]) PhotoDogAvatar(sticker: sticker, stage: stage, size: 50),
            ],
          ),
          if (faces > 1) ...[
            const SizedBox(height: 8),
            Text('照片里有 $faces 张脸，用了最大的那张', style: const TextStyle(fontSize: 12, color: Pop.mutedOnYellow)),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Pop.gray, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.6, color: Color(0xFF3C4043)))),
        ],
      ),
    );
  }
}

/// 第一次用照片做形象前的单独同意：说清楚照片怎么处理、留下什么、AI 标识、只用本人照片
class FaceConsentSheet extends StatelessWidget {
  const FaceConsentSheet({super.key});

  static const points = [
    '照片只在这台手机的内存里变成卡通，处理完就丢掉，不保存、不上传。',
    '留下的只有卡通形象：存在这台手机上；登录后会上传卡通形象（不是照片），换手机也能找回来。',
    '卡通形象是 AI 模型在手机上生成的，晒出去的结算卡会标上“AI生成”。',
    '请只用你本人的照片，别拿别人的脸变狗。',
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('用照片做形象之前', style: PopText.h2),
            const SizedBox(height: 14),
            for (final p in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 8, right: 10),
                      child: SizedBox.square(
                        dimension: 6,
                        child: DecoratedBox(decoration: BoxDecoration(color: Pop.ink, shape: BoxShape.circle)),
                      ),
                    ),
                    Expanded(child: Text(p, style: PopText.body)),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            const Text('详细说明见“我的 › 隐私政策”。', style: PopText.small),
            const SizedBox(height: 16),
            PopButton(label: '同意，开始', onPressed: () => Navigator.pop(context, true)),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('先不用了', style: TextStyle(color: Pop.muted, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
