import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/cartoon_lab_channel.dart';

/// 把卡通图画成平涂墨线贴纸；测试里可以换掉
typedef StickerRenderer = Future<ui.Image> Function(CartoonLabResult result);

/// 在后台 isolate 里画贴纸，再转成图片
Future<ui.Image> renderPhotoSticker(CartoonLabResult r) async =>
    PhotoSticker.toImage(await PhotoSticker.renderInBackground(r.cartoonRgba, r.mask));

/// 拍照形象的技术验证页（iOS）：在手机本地把照片变成定下来的“日漫 + 平涂墨线”贴纸，
/// 看效果、速度，以及按固定位置叠上去的狗耳朵、狗鼻子准不准。
class CartoonLabPage extends StatefulWidget {
  const CartoonLabPage({super.key, this.renderSticker = renderPhotoSticker});

  final StickerRenderer renderSticker;

  @override
  State<CartoonLabPage> createState() => _CartoonLabPageState();
}

class _CartoonLabPageState extends State<CartoonLabPage> {
  CartoonLabResult? _result;
  ui.Image? _sticker;
  String? _stickerError;
  double? _stickerMs;
  bool _busy = false;

  @override
  void dispose() {
    _sticker?.dispose();
    super.dispose();
  }

  Future<void> _run(Future<CartoonLabResult?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await action();
      if (r == null || !mounted) return;
      _sticker?.dispose();
      setState(() {
        _result = r;
        _sticker = null;
        _stickerError = null;
        _stickerMs = null;
      });
      final watch = Stopwatch()..start();
      try {
        final image = await widget.renderSticker(r);
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() {
          _sticker = image;
          _stickerMs = watch.elapsedMicroseconds / 1000;
        });
      } on StateError catch (e) {
        if (mounted) setState(() => _stickerError = e.message);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? '出错了，换一张试试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      backgroundColor: Pop.gray,
      appBar: AppBar(title: const Text('拍照形象（验证）')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text(
              '照片只在这台手机的内存里处理，不存盘、不上传。画风是定下来的“日漫 + 平涂墨线”：'
              '先用 DCT-Net 日漫头像模型（阿里达摩院开源，可商用）卡通化，再压成平涂色块、描墨线，抠成贴纸。'
              '狗耳朵、狗鼻子按对齐后的固定位置叠，换不同照片看位置准不准。',
              style: PopText.small,
            ),
            const SizedBox(height: 16),
            if (r == null)
              Container(
                height: 200,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Pop.white, borderRadius: BorderRadius.circular(18)),
                child: Text(_busy ? '处理中…' : '先用样图试一下，再换自己的照片', style: PopText.small),
              )
            else ...[
              _StickerCard(sticker: _sticker, error: _stickerError),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _Picture(bytes: r.aligned, label: '对齐后的照片')),
                  const SizedBox(width: 12),
                  Expanded(child: _Picture(bytes: r.cartoon, label: '卡通化（处理前）')),
                ],
              ),
              const SizedBox(height: 12),
              _Timings(result: r, stickerMs: _stickerMs),
            ],
            const SizedBox(height: 16),
            PopButton(label: _busy ? '处理中…' : '用样图试', onPressed: _busy ? null : () => _run(CartoonLabChannel.runSample)),
            const SizedBox(height: 12),
            PopButton(
              label: '从相册选一张',
              style: PopButtonStyle.secondary,
              onPressed: _busy ? null : () => _run(CartoonLabChannel.runLibrary),
            ),
            const SizedBox(height: 8),
            const Text('选正脸、光线亮、头顶没被裁掉的照片效果最好。选图用的是系统选图器，App 只拿到你选的那一张。', style: PopText.small),
          ],
        ),
      ),
    );
  }
}

/// 黄底卡片上并排放“人”和“变狗”两个形象
class _StickerCard extends StatelessWidget {
  const _StickerCard({required this.sticker, required this.error});

  final ui.Image? sticker;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final image = sticker;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: Pop.card(color: Pop.yellow),
      child: image == null
          ? SizedBox(
              height: 160,
              child: Center(
                child: Text(error == null ? '正在画平涂墨线贴纸…' : '贴纸没画出来：$error', style: PopText.small),
              ),
            )
          : LayoutBuilder(
              builder: (context, box) {
                final size = (box.maxWidth - 12) / 2;
                Widget avatar(int stage, String label) => Column(
                      children: [
                        PhotoDogAvatar(sticker: image, stage: stage, size: size),
                        const SizedBox(height: 6),
                        Text(label, style: const TextStyle(fontSize: 13, color: Pop.mutedOnYellow)),
                      ],
                    );
                return Row(
                  children: [avatar(0, '人'), const SizedBox(width: 12), avatar(2, '变狗（阶段 2）')],
                );
              },
            ),
    );
  }
}

class _Picture extends StatelessWidget {
  const _Picture({required this.bytes, required this.label});

  final Uint8List bytes;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(aspectRatio: 1, child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)),
        ),
        const SizedBox(height: 6),
        Text(label, textAlign: TextAlign.center, style: PopText.small),
      ],
    );
  }
}

class _Timings extends StatelessWidget {
  const _Timings({required this.result, required this.stickerMs});

  final CartoonLabResult result;
  final double? stickerMs;

  static String _ms(double v) => '${v.round()} ms';

  @override
  Widget build(BuildContext context) {
    final r = result;
    final rows = <(String, String)>[
      if (r.photoSize.isNotEmpty) ('参与计算的照片', r.photoSize),
      if (r.faces > 1) ('找到的脸', '${r.faces} 张，用了最大的那张'),
      ('鼻尖离模板位置', '${r.noseOffsetPx.round()} 像素'),
      ('五官离模板最远', '${r.maxOffsetPx.round()} 像素'),
      ('解码照片', _ms(r.decodeMs)),
      ('找五官（Vision）', _ms(r.visionMs)),
      ('对齐裁剪', _ms(r.alignMs)),
      if (r.loadMs > 0) ('加载模型（只有第一次）', _ms(r.loadMs)),
      ('卡通化（Core ML）', _ms(r.modelMs)),
      ('抠出人像（Vision）', _ms(r.segmentMs)),
      ('原生部分合计', _ms(r.totalMs)),
      if (stickerMs != null) ('平涂墨线贴纸（Flutter）', _ms(stickerMs!)),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Pop.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          for (final (name, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
                  Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
