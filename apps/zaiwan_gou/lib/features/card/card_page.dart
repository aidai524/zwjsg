import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/aigc_label.dart';
import '../../core/app_state.dart';
import '../../core/breeds.dart';
import '../../core/card_exporter.dart';
import 'package:pop_ui/pop_ui.dart';
import '../../widgets/ai_tag.dart';
import '../../widgets/my_avatar.dart';

/// 每日结算卡。卡片包在 RepaintBoundary 里，保存/分享时截成 3:4 图片。
/// 白天随时能晒，晒的是“此刻”的样子；到了每晚提醒的时间（默认 22:00）才叫“今日结算”。
class CardPage extends StatefulWidget {
  /// [exporter]、[now] 只在测试里传
  const CardPage({super.key, this.exporter = const DefaultCardExporter(), this.now});

  final CardExporter exporter;
  final DateTime? now;

  static Color frameColor(Rarity r) => switch (r) {
        Rarity.common => Pop.ink,
        Rarity.rare => Pop.rareBlue,
        Rarity.legend => Pop.legendGold,
      };

  @override
  State<CardPage> createState() => _CardPageState();
}

class _CardPageState extends State<CardPage> {
  final GlobalKey _cardKey = GlobalKey();
  final GlobalKey _shareKey = GlobalKey();
  bool _busy = false;

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _export(Future<void> Function(Uint8List png) action, {String? done, required String failed}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final aiAvatar = AppScope.read(context).photoAvatar != null;
    try {
      var png = await widget.exporter.capture(_cardKey);
      // 拍照形象是 AI 生成的：导出的图片文件里还要写上隐式标识
      if (aiAvatar) png = AigcLabel.embed(png);
      await action(png);
      if (done != null) _toast(done);
    } on CardExportException catch (e) {
      _toast(e.message);
    } on PlatformException {
      _toast(failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _export(widget.exporter.save, done: '已保存到相册', failed: '没存上，稍后再试');

  Future<void> _share() {
    // iPad 的分享面板要从按钮的位置弹出
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    return _export((png) => widget.exporter.share(png, origin: origin), failed: '分享面板没打开，稍后再试');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final breed = breedByKey(state.breedKey);
    final rarity = breed?.rarity ?? Rarity.common;
    final now = widget.now ?? DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final settled = nowMinutes >= state.reminderMinutes;
    final String note;
    if (settled) {
      note = breed == null ? '今天还是个人，值得晒一晒' : '今天变成了${breed.name}';
    } else {
      note = '${breed == null ? '此刻还是个人' : '此刻是${breed.name}'} · ${AppState.formatHhmm(state.reminderMinutes)} 结算';
    }

    return Scaffold(
      backgroundColor: Pop.ink,
      appBar: AppBar(
        systemOverlayStyle: Pop.overlayOnDark,
        foregroundColor: Pop.white,
        title: Text(settled ? '今日结算' : '此刻的我',
            style: const TextStyle(color: Pop.white, fontSize: 16, fontWeight: FontWeight.w900)),
        centerTitle: true,
        leading: IconButton(
          tooltip: '关闭',
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 4, 28, 24),
          child: Column(
            children: [
              Text(note, style: const TextStyle(color: Color(0xFFD6D6D6), fontSize: 13)),
              const SizedBox(height: 14),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: RepaintBoundary(
                      key: _cardKey,
                      // 深色底：导出的图片四角是深色，不是透明（发到微信会变黑或变白）
                      child: LayoutBuilder(
                        builder: (context, card) => ColoredBox(
                          color: Pop.ink,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                            decoration: BoxDecoration(
                              color: Pop.yellow,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: CardPage.frameColor(rarity), width: 6),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              settled
                                                  ? '${now.month} 月 ${now.day} 日 · 今日狗度'
                                                  : '${now.month} 月 ${now.day} 日 ${AppState.formatHhmm(nowMinutes)} · 此刻狗度',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                          Text(state.percentLabel,
                                              style: const TextStyle(
                                                  fontSize: 48, fontWeight: FontWeight.w900, height: 1)),
                                        ],
                                      ),
                                    ),
                                    if (breed != null) _RarityTag(rarity: rarity),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Pop.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Pop.ink, width: Pop.stroke),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    alignment: Alignment.bottomCenter,
                                    child: LayoutBuilder(
                                      builder: (_, c) =>
                                          MyAvatar(stage: state.stage, size: c.maxHeight.clamp(80.0, 190.0)),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(breed?.name ?? '人',
                                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(breed?.quip ?? '今天守住了，明天继续',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.only(top: 10),
                                  decoration: const BoxDecoration(
                                    border: Border(top: BorderSide(color: Pop.ink, width: 2)),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('再玩我是狗',
                                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                                            Text(
                                              state.nickname == null ? '刷得越多，越像狗' : '@${state.nickname} · 刷得越多，越像狗',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (state.photoAvatar != null) ...[
                                        // 拍照形象是 AI 生成的，导出的图片要有显式标识：放在卡片右下角，
                                        // 文字高度不低于卡片短边（宽）的 5%，这里取 5.5% 留点余量
                                        AiTag(fontSize: math.max(15, card.maxWidth * 0.055)),
                                        const SizedBox(width: 8),
                                      ],
                                      // 还没上架，没有下载二维码，先放 App 图标
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: Pop.ink, width: 2),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Image.asset('assets/icon/icon_full.png', fit: BoxFit.cover),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Pop.white,
                        side: const BorderSide(color: Pop.white, width: Pop.stroke),
                        minimumSize: const Size.fromHeight(54),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      onPressed: _busy ? null : _save,
                      child: const Text('保存图片'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PopButton(key: _shareKey, label: '晒给朋友', height: 54, onPressed: _busy ? null : _share),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RarityTag extends StatelessWidget {
  const _RarityTag({required this.rarity});

  final Rarity rarity;

  @override
  Widget build(BuildContext context) {
    final bg = switch (rarity) {
      Rarity.common => Pop.white,
      Rarity.rare => Pop.rareBlue,
      Rarity.legend => Pop.legendGold,
    };
    final fg = rarity == Rarity.rare ? Pop.white : Pop.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Pop.ink, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rarity != Rarity.common) ...[Icon(Icons.auto_awesome, size: 12, color: fg), const SizedBox(width: 4)],
          Text(rarity.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: fg)),
        ],
      ),
    );
  }
}
