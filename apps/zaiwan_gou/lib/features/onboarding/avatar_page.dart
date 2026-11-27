import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';
import 'package:series_share/series_share.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/cartoonizer.dart';

/// 把卡通图画成平涂墨线贴纸；测试里可以换掉
typedef FaceStickerRenderer = Future<ui.Image> Function(CartoonFace face);

/// 在后台 isolate 里画贴纸，再转成图片
Future<ui.Image> renderFaceSticker(CartoonFace face) async =>
    PhotoSticker.toImage(await PhotoSticker.renderInBackground(face.rgba, face.mask));

/// 形象创建（也用来换形象）：从几张预设好的脸里挑一张（2026-11-27 用户定：不做捏脸，开头多一步、太复杂，影响转化），
/// 或者拍自拍、从相册选一张 → 手机本地卡通化 → 画成平涂墨线贴纸 → 就用这个。
/// 默认选中现在用的那张（没挑过是呆毛），引导里点一下“就用这个”就能往下走。
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
  /// 新做好、还没确认的拍照形象
  ui.Image? _candidate;
  int _faces = 1;
  bool _busy = false;
  bool _saving = false;

  /// 选中的预设形象；选中的是拍照形象（新做的，或者手机上原来的）时是 null
  AvatarPreset? _preset;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    // 先选中现在用的：用着拍照形象就选照片，不然选挑过的那张（没挑过是呆毛）
    final state = AppScope.read(context);
    _preset = state.photoAvatar != null ? null : state.avatarPreset;
  }

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

  /// 用照片做一个：先同意（第一次），再选拍照还是从相册选
  Future<void> _choosePhoto() async {
    if (_busy || _saving) return;
    if (!await _ensureConsent() || !mounted) return;
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      backgroundColor: Pop.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const PhotoSourceSheet(),
    );
    if (source == null || !mounted) return;
    await _pick(source);
  }

  Future<void> _pick(PhotoSource source) async {
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
        _preset = null;
      });
    } on PlatformException catch (e) {
      if (mounted) _toast(e.message ?? '没弄好，换一张试试');
    } on StateError {
      if (mounted) _toast('没抠出人像，换一张正脸、背景干净点的照片');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 点照片那一格：有照片形象（新做的或者原来的）就选中它，没有就去做一个
  void _tapPhoto(ui.Image? photo) {
    if (photo == null) {
      _choosePhoto();
    } else {
      setState(() => _preset = null);
    }
  }

  Future<void> _confirm() async {
    if (_saving || _busy) return;
    final state = AppScope.read(context);
    final preset = _preset;
    final candidate = _candidate;
    setState(() => _saving = true);
    try {
      if (preset != null) {
        await state.setAvatarPreset(preset);
      } else if (candidate != null) {
        final data = await candidate.toByteData(format: ui.ImageByteFormat.png);
        if (!mounted) return;
        await state.setPhotoAvatar(data!.buffer.asUint8List());
      } else if (state.usesPreset) {
        // 换回手机上原来的拍照形象
        await state.setAvatarPreset(null);
      }
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
    final photo = _candidate ?? state.savedPhotoAvatar;
    final preset = _preset;
    final photoPicked = preset == null && photo != null;
    final supported = widget.cartoonizer.isSupported;
    // 换掉已有的拍照形象才算次数（服务端管），第一次做不算
    final regenLeft = state.savedPhotoAvatar != null ? state.avatarRegenLeft : null;
    final usedUp = regenLeft != null && regenLeft <= 0;
    final idle = !_busy && !_saving;

    final String title;
    final String subtitle;
    if (photoPicked && _candidate != null) {
      title = '这就是你';
      subtitle = '刷得越多，它就越像狗。不满意就换一张。';
    } else {
      title = widget.editing ? '换个形象' : '先挑一个你';
      subtitle = supported ? '挑一张顺眼的脸，或者拍张自拍画成卡通。刷得越多，它就越像狗。' : '挑一张顺眼的脸。刷得越多，它就越像狗。';
    }

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: PopText.title),
              const SizedBox(height: 6),
              Text(subtitle, style: PopText.bodyMuted),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    // 小屏手机上整体缩小，不溢出
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _busy
                          ? const _Working()
                          : _Preview(
                              preset: photoPicked ? null : (preset ?? state.avatarPreset),
                              sticker: photoPicked ? photo : null,
                              faces: photoPicked && identical(photo, _candidate) ? _faces : 1,
                            ),
                    ),
                  ),
                ),
              ),
              LayoutBuilder(builder: (context, c) {
                // 一行四格；屏幕宽（平板、横屏）时格子不再变大
                const gap = 10.0;
                final tile = math.min((c.maxWidth - gap * 3) / 4, 88.0);
                return Center(
                  child: SizedBox(
                    width: tile * 4 + gap * 3,
                    child: Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final p in AvatarPreset.values)
                          _FaceTile(
                            size: tile,
                            label: '形象：${p.label}',
                            selected: preset == p,
                            onTap: idle ? () => setState(() => _preset = p) : null,
                            child: DogAvatar(stage: 0, size: tile * 0.94, preset: p),
                          ),
                        if (supported)
                          _FaceTile(
                            size: tile,
                            label: photo == null ? '用照片做形象' : '拍照形象',
                            selected: photoPicked,
                            onTap: idle ? () => _tapPhoto(photo) : null,
                            child: photo == null
                                ? const _AddPhoto()
                                : PhotoDogAvatar(sticker: photo, stage: 0, size: tile * 0.94),
                          ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 10),
              if (!supported)
                const Text('这台手机做不了拍照形象，挑一张预设的脸吧。', textAlign: TextAlign.center, style: PopText.small)
              else if (photoPicked)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: idle && !usedUp ? _choosePhoto : null,
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('换一张照片', style: TextStyle(fontWeight: FontWeight.w900)),
                      style: TextButton.styleFrom(foregroundColor: Pop.ink),
                    ),
                    if (regenLeft != null) Text(usedUp ? '换形象的次数用完了' : '还能换 $regenLeft 次', style: PopText.small),
                  ],
                ),
              const SizedBox(height: 10),
              PopButton(label: '就用这个', loading: _saving, onPressed: idle ? _confirm : null),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一格：预设的脸，或者照片形象。选中的是亮黄底、粗墨线、硬阴影
class _FaceTile extends StatelessWidget {
  const _FaceTile(
      {required this.size, required this.label, required this.selected, required this.onTap, required this.child});

  final double size;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: selected ? Pop.yellow : Pop.white,
            borderRadius: BorderRadius.circular(size * 0.24),
            border: Border.all(color: Pop.ink, width: selected ? 3 : 2),
            boxShadow: selected ? const [BoxShadow(color: Pop.ink, offset: Offset(3, 3))] : null,
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
    );
  }
}

/// 照片那一格还没有照片形象时：相机图标 + “用照片”
class _AddPhoto extends StatelessWidget {
  const _AddPhoto();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_a_photo_outlined, size: 26, color: Pop.ink),
          SizedBox(height: 4),
          Text('用照片', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

/// 选拍照还是从相册选
class PhotoSourceSheet extends StatelessWidget {
  const PhotoSourceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('用照片做形象', style: PopText.h2),
            const SizedBox(height: 6),
            const Text('正脸，光线亮一点。别戴口罩，狗不戴口罩。', style: PopText.small),
            const SizedBox(height: 18),
            PopButton(label: '拍一张自拍', onPressed: () => Navigator.pop(context, PhotoSource.camera)),
            const SizedBox(height: 14),
            PopButton(
              label: '从相册选一张',
              style: PopButtonStyle.secondary,
              height: 52,
              onPressed: () => Navigator.pop(context, PhotoSource.library),
            ),
            const SizedBox(height: 14),
            const _Note(icon: Icons.lock_outline, text: '照片只在你手机上变成卡通，原图不保存、不上传。请只用本人照片。'),
          ],
        ),
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

/// 选中的形象：大图是现在的样子，下面一排是刷多了会变成的样子。拍照形象标“AI生成”
class _Preview extends StatelessWidget {
  const _Preview({this.preset, this.sticker, this.faces = 1});

  /// 预设形象；是拍照形象时为 null，用 [sticker]
  final AvatarPreset? preset;
  final ui.Image? sticker;
  final int faces;

  Widget _avatar(int stage, double size) {
    final s = sticker;
    return s != null
        ? PhotoDogAvatar(sticker: s, stage: stage, size: size)
        : DogAvatar(stage: stage, size: size, preset: preset ?? AvatarPreset.fallback);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: Pop.card(color: Pop.softYellow, radius: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              _avatar(0, 196),
              if (sticker != null) const Positioned(right: 0, top: 0, child: AiTag()),
            ],
          ),
          const SizedBox(height: 10),
          const Text('刷多了会变成这样', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Pop.mutedOnYellow)),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final stage in [1, 2, 3, 4, 5]) _avatar(stage, 50)
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
