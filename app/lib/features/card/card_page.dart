import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/breeds.dart';
import '../../core/theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/pop_button.dart';

/// 每日结算卡。卡片包在 RepaintBoundary 里，保存/分享时截成 3:4 图片。
class CardPage extends StatelessWidget {
  CardPage({super.key});

  final GlobalKey _cardKey = GlobalKey();

  static Color frameColor(Rarity r) => switch (r) {
        Rarity.common => Pop.ink,
        Rarity.rare => Pop.rareBlue,
        Rarity.legend => Pop.legendGold,
      };

  void _todo(BuildContext context, String what) {
    // TODO 用 _cardKey 截图（RenderRepaintBoundary.toImage）后保存相册 / 调微信分享 SDK
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what 功能接入中')));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final breed = breedByKey(state.breedKey);
    final rarity = breed?.rarity ?? Rarity.common;
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: Pop.ink,
      appBar: AppBar(
        systemOverlayStyle: Pop.overlayOnDark,
        foregroundColor: Pop.white,
        title: const Text('今日结算', style: TextStyle(color: Pop.white, fontSize: 16, fontWeight: FontWeight.w900)),
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
              Text(breed == null ? '今天还是个人，值得晒一晒' : '今天变成了${breed.name}',
                  style: const TextStyle(color: Color(0xFFD6D6D6), fontSize: 13)),
              const SizedBox(height: 14),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: RepaintBoundary(
                      key: _cardKey,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                        decoration: BoxDecoration(
                          color: Pop.yellow,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: frameColor(rarity), width: 6),
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
                                      Text('${now.month} 月 ${now.day} 日 · 今日狗度',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                      Text('${state.percent}%',
                                          style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, height: 1)),
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
                                  builder: (_, c) => DogAvatar(stage: state.stage, size: c.maxHeight.clamp(80.0, 190.0)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(breed?.name ?? '人', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
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
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('再玩我是狗', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                                        Text('扫码看看你今天是什么狗 · [品牌名]', style: TextStyle(fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Pop.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Pop.ink, width: 2),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Text('[码]', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
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
                      onPressed: () => _todo(context, '保存图片'),
                      child: const Text('保存图片'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: PopButton(label: '晒给朋友', height: 54, onPressed: () => _todo(context, '分享'))),
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
