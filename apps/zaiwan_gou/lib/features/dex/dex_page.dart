import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_state.dart';
import '../../core/breeds.dart';
import '../../core/festivals.dart';
import '../../core/screen_time_channel.dart';
import '../../widgets/my_avatar.dart';
import '../card/card_page.dart';
import 'breed_sheet.dart';
import 'evolution_section.dart';

/// 图鉴：解锁了的显示你的形象变成的样子、梗和变成过几天；没解锁的是剪影和解锁条件，传说「狼」带连续做人的进度。
/// 点开一种狗看详情。
class DexPage extends StatefulWidget {
  const DexPage({super.key});

  @override
  State<DexPage> createState() => _DexPageState();
}

class _DexPageState extends State<DexPage> {
  Rarity? _filter;

  @override
  void initState() {
    super.initState();
    // 换了手机、或者别的地方刚解锁了：打开图鉴时从服务端再取一次
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.read(context).refreshBreeds();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final owned = state.ownedBreeds;
    // 限定犬种：拿到了一直在，没拿到的只在节日那几天出现
    final listed = dexBreeds(owned, DateTime.now());
    final shown = listed.where((b) => _filter == null || b.rarity == _filter).toList();
    final ownedCount = listed.where((b) => owned.contains(b.key)).length;
    final rarities = [for (final r in Rarity.values) if (listed.any((b) => b.rarity == r)) r];

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              sliver: SliverList.list(children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Expanded(child: Text('图鉴', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900))),
                    Text('已收集 $ownedCount / ${listed.length}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Pop.ink, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: ownedCount / listed.length,
                    child: Container(color: Pop.yellow),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  ScreenTimeChannel.isSupported
                      ? 'iPhone 上只能变传说「狼」、稀有「金毛寻回犬」和节日限定的：苹果不让 App 知道你用的是哪类 App、什么时候用的，按刷法定的犬种暂时只有安卓能变。'
                      : '每晚按你那天怎么刷来定犬种，不看刷了多久；连着几天一天比一天刷得少变「金毛寻回犬」，连续做人 7 天变传说「狼」。${state.isLoggedIn ? '' : '登录后才会记下解锁。'}',
                  style: const TextStyle(fontSize: 13, color: Pop.muted, height: 1.5),
                ),
                const SizedBox(height: 14),
                const EvolutionSection(),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    _chip('全部', null),
                    for (final r in rarities) _chip(r.label, r),
                  ],
                ),
              ]),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverGrid.count(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.6,
                children: [
                  for (final b in shown)
                    _BreedTile(
                      breed: b,
                      owned: owned.contains(b.key),
                      days: state.breedDays(b.key).length,
                      streak: b.key == 'wolf' ? state.humanStreakNow : 0,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Rarity? r) {
    final on = _filter == r;
    return ChoiceChip(
      label: Text(label),
      selected: on,
      showCheckmark: false,
      onSelected: (_) => setState(() => _filter = r),
      labelStyle: TextStyle(fontWeight: FontWeight.w900, color: on ? Pop.white : Pop.ink),
      selectedColor: Pop.ink,
      backgroundColor: Pop.white,
      side: const BorderSide(color: Pop.ink, width: 2),
      shape: const StadiumBorder(),
    );
  }
}

class _BreedTile extends StatelessWidget {
  const _BreedTile({required this.breed, required this.owned, required this.days, required this.streak});

  final Breed breed;
  final bool owned;

  /// 手机上记下的、变成过这种狗的天数
  final int days;

  /// 只给狼：到今天为止连续做人几天
  final int streak;

  @override
  Widget build(BuildContext context) {
    final frame = CardPage.frameColor(breed.rarity);
    final tagFg = breed.rarity == Rarity.legend ? Pop.ink : Pop.white;
    return Semantics(
      button: true,
      label: '${breed.name}，${breed.rarity.label}，${owned ? '已解锁' : '未解锁'}',
      excludeSemantics: true,
      child: Material(
        color: owned ? Pop.white : Pop.gray,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: frame, width: Pop.stroke),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showBreedSheet(context, breed),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(color: frame, borderRadius: BorderRadius.circular(8)),
                    child: Text(breed.rarity.label,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: tagFg)),
                  ),
                ),
                SizedBox(
                  height: 66,
                  child: owned
                      ? MyAvatar(stage: breed.previewStage, size: 66, evolved: false)
                      : BreedSilhouette(stage: breed.previewStage, size: 66),
                ),
                Text(breed.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: owned ? Pop.ink : Pop.muted)),
                const SizedBox(height: 2),
                Expanded(
                  child: Text(
                    owned ? breed.quip : breed.rule,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Pop.muted, height: 1.4),
                  ),
                ),
                if (owned && days > 0)
                  Text('变成过 $days 天', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900))
                else if (!owned && breed.key == 'wolf')
                  WolfProgress(streak: streak, compact: true)
                else if (!owned && festivalOf(breed.key)?.daysLeft(DateTime.now()) != null)
                  Text('限时 · 还剩 ${festivalOf(breed.key)!.daysLeft(DateTime.now())} 天',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Pop.kingRed)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
