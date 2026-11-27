import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_state.dart';
import '../../core/breeds.dart';
import '../../core/dog_meter.dart';
import '../../core/festivals.dart';
import '../../core/screen_time_channel.dart';
import '../../widgets/my_avatar.dart';
import '../card/card_page.dart';

extension BreedDisplay on Breed {
  /// iOS 拿不到 App 类别、拿起次数和时段，只能在手机上判定传说「狼」（连续做人）、稀有「金毛寻回犬」（一天比一天刷得少）
  /// 和节日限定的（只看日期和阶段）
  bool get judgedOnIos => key == 'wolf' || key == 'retriever' || rarity == Rarity.limited;

  /// 怎么判：狼看连续做人的进度，不用写
  String? get howJudged => switch (key) {
        'wolf' => null,
        'retriever' => '看前 $retrieverDays 天的记录：安卓比每天刷了多久，iPhone 比每天到过的最高阶段',
        _ when rarity == Rarity.limited => '只看那天是不是节日、变没变狗，不看怎么刷、刷了多久；比别的犬种都先判',
        _ => '按你那天怎么刷来定，不看刷了多久',
      };

  /// 限定犬种什么时候有：在节日里写还剩几天，不然写下一回是哪几天
  String? limitedWhen(DateTime today) {
    final f = festivalOf(key);
    if (f == null) return null;
    final left = f.daysLeft(today);
    if (left != null) return '就是这几天，还剩 $left 天；过了没拿到的不再出现，明年再来';
    for (var year = today.year; year <= today.year + 1; year++) {
      final w = f.window(year);
      if (w != null && !w.$2.isBefore(DateTime(today.year, today.month, today.day))) {
        final days = w.$1 == w.$2 ? breedDateLabel(_date(w.$1)) : '${breedDateLabel(_date(w.$1))}到${breedDateLabel(_date(w.$2))}';
        return '每年${f.name}才有，下一回是 $days';
      }
    }
    return '每年${f.name}才有';
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// “11 月 17 日”；不是今年的带上年份
String breedDateLabel(String date) {
  final d = DateTime.tryParse(date);
  if (d == null) return date;
  return d.year == DateTime.now().year ? '${d.month} 月 ${d.day} 日' : '${d.year} 年 ${d.month} 月 ${d.day} 日';
}

/// 没解锁的犬种：用自己的形象画一个剪影
class BreedSilhouette extends StatelessWidget {
  const BreedSilhouette({super.key, required this.stage, required this.size});

  final int stage;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.22,
      child: ColorFiltered(
        colorFilter: const ColorFilter.mode(Pop.ink, BlendMode.srcIn),
        child: MyAvatar(stage: stage, size: size, evolved: false),
      ),
    );
  }
}

Future<void> showBreedSheet(BuildContext context, Breed breed) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Pop.white,
      isScrollControlled: true,
      builder: (_) => BreedSheet(breed: breed),
    );

/// 图鉴里点开一种狗：形象（没解锁是剪影）、梗、怎么变成、第一次是哪天、变成过几天；狼还没解锁时看连续做人的进度
class BreedSheet extends StatelessWidget {
  const BreedSheet({super.key, required this.breed});

  final Breed breed;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final owned = state.ownedBreeds.contains(breed.key);
    final days = state.breedDays(breed.key);
    final firstOn = state.unlockedOn(breed.key);
    final frame = CardPage.frameColor(breed.rarity);
    final tagFg = breed.rarity == Rarity.legend ? Pop.ink : Pop.white;
    final iosOnly = ScreenTimeChannel.isSupported && !breed.judgedOnIos && !owned;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: frame, borderRadius: BorderRadius.circular(10)),
                  child: Text(breed.rarity.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: tagFg)),
                ),
                const Spacer(),
                Text(owned ? '已解锁' : '未解锁',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: owned ? Pop.ink : Pop.muted)),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 168,
                height: 168,
                decoration: BoxDecoration(
                  color: owned ? Pop.softYellow : Pop.gray,
                  shape: BoxShape.circle,
                  border: Border.all(color: frame, width: Pop.stroke),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.bottomCenter,
                child: owned
                    ? MyAvatar(stage: breed.previewStage, size: 156, evolved: false)
                    : BreedSilhouette(stage: breed.previewStage, size: 156),
              ),
            ),
            const SizedBox(height: 12),
            Text(breed.name,
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            if (owned) ...[
              const SizedBox(height: 4),
              Text('“${breed.quip}”',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 16),
            _InfoRow(label: '怎么变成', value: breed.rule),
            if (breed.howJudged != null) _InfoRow(label: '怎么判', value: breed.howJudged!),
            if (breed.limitedWhen(DateTime.now()) != null) _InfoRow(label: '什么时候有', value: breed.limitedWhen(DateTime.now())!),
            if (firstOn != null) _InfoRow(label: '第一次', value: breedDateLabel(firstOn)),
            if (days.isNotEmpty)
              _InfoRow(label: '变成过', value: '${days.length} 天 · 最近一次 ${breedDateLabel(days.first.date)}'),
            if (!owned && breed.key == 'wolf') ...[
              const SizedBox(height: 8),
              WolfProgress(streak: state.humanStreakNow),
            ],
            if (iosOnly) ...[
              const SizedBox(height: 12),
              const Text('iPhone 不让 App 知道你用的是哪类 App、什么时候用的，这种狗暂时只能在安卓上变。',
                  style: TextStyle(fontSize: 13, color: Pop.muted, height: 1.5)),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(label, style: PopText.label)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14, height: 1.4))),
        ],
      ),
    );
  }
}

/// 离传说「狼」还差几天：一排 7 格
class WolfProgress extends StatelessWidget {
  const WolfProgress({super.key, required this.streak, this.compact = false});

  /// 到今天为止连续做人几天
  final int streak;

  /// 图鉴格子里的小号：只有一句话
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const goal = DogMeter.legendStreakDays;
    final done = streak.clamp(0, goal);
    final text = '连续做人 $done / $goal 天';
    if (compact) return Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < goal; i++)
              Expanded(
                child: Container(
                  height: 10,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: i < done ? Pop.legendGold : Pop.gray,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: i < done ? Pop.ink : Pop.gray, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        const Text('中间有一天没有记录（比如权限关了），也算断了', style: PopText.small),
      ],
    );
  }
}
