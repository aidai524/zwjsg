import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_state.dart';
import '../../core/evolution.dart';
import '../../widgets/my_avatar.dart';
import 'breed_sheet.dart' show breedDateLabel;

/// 图鉴最上面的“进化形态”（2026-11-26）：连续做人解锁的人样，四种排成一行。
/// 解锁了的是你穿上它的样子，正穿着的描黄边；没解锁的是剪影和要连续做人几天。点开看详情、挑做人时穿哪一种
class EvolutionSection extends StatelessWidget {
  const EvolutionSection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final unlocked = state.unlockedEvolutions;
    final worn = state.wornEvolution;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: Pop.card(color: Pop.softYellow, radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(child: Text('进化形态', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              Text('已解锁 ${unlocked.length} / ${kEvolutions.length}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            state.hasUsageData
                ? evolutionLine(state.humanStreakDone, unlocked, humanToday: state.stage == 0)
                : '连续做人解锁的人样，做人时穿上，变狗就脱掉',
            style: const TextStyle(fontSize: 12.5, color: Pop.mutedOnYellow, height: 1.4),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final info in kEvolutions)
                Expanded(
                  child: _EvolutionTile(
                    info: info,
                    owned: unlocked.contains(info.evolution),
                    worn: worn == info.evolution,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EvolutionTile extends StatelessWidget {
  const _EvolutionTile({required this.info, required this.owned, required this.worn});

  final EvolutionInfo info;
  final bool owned;
  final bool worn;

  @override
  Widget build(BuildContext context) {
    final status = worn ? '正穿着' : (owned ? '已解锁' : '连续做人 ${info.days} 天解锁');
    return Semantics(
      button: true,
      label: '${info.name}，$status',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showEvolutionSheet(context, info),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            children: [
              EvolutionBadge(info: info, owned: owned, worn: worn, size: 60),
              const SizedBox(height: 4),
              Text(info.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: owned ? Pop.ink : Pop.muted)),
              Text(worn ? '正穿着' : (owned ? '已解锁' : '${info.days} 天'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: worn ? FontWeight.w900 : FontWeight.w500,
                    color: worn ? Pop.ink : Pop.mutedOnYellow,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// 圆角方框里的形象（方框才露得出衣服）：解锁了是穿上这种进化形态的你（正穿着的描黄边），没解锁的是剪影
class EvolutionBadge extends StatelessWidget {
  const EvolutionBadge({super.key, required this.info, required this.owned, this.worn = false, required this.size});

  final EvolutionInfo info;
  final bool owned;
  final bool worn;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatar = MyAvatar(stage: 0, size: size * 0.94, evolution: info.evolution);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: owned ? Pop.white : Pop.gray,
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(color: worn ? Pop.yellow : Pop.ink, width: worn ? 4 : 2),
        boxShadow: worn ? const [BoxShadow(color: Pop.ink, offset: Offset(2, 2))] : null,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.bottomCenter,
      child: owned
          ? avatar
          : Opacity(
              opacity: 0.22,
              child: ColorFiltered(colorFilter: const ColorFilter.mode(Pop.ink, BlendMode.srcIn), child: avatar),
            ),
    );
  }
}

Future<void> showEvolutionSheet(BuildContext context, EvolutionInfo info) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Pop.white,
      isScrollControlled: true,
      builder: (_) => EvolutionSheet(info: info),
    );

/// 点开一种进化形态：样子（没解锁是剪影）、梗、穿的是什么、怎么解锁；解锁了能挑做人时穿它，或者不穿
class EvolutionSheet extends StatelessWidget {
  const EvolutionSheet({super.key, required this.info});

  final EvolutionInfo info;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final unlockedOn = state.evolutions[info.evolution];
    final owned = unlockedOn != null;
    final worn = state.wornEvolution == info.evolution;
    final streak = state.humanStreakDone;
    final String how;
    if (owned) {
      how = '${breedDateLabel(unlockedOn)}解锁 · 连续做人 ${info.days} 天';
    } else {
      how = '连续做人 ${info.days} 天解锁 · 到昨天为止连续做人 $streak 天';
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('进化形态', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                const Spacer(),
                Text(worn ? '正穿着' : (owned ? '已解锁' : '未解锁'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: owned ? Pop.ink : Pop.muted)),
              ],
            ),
            const SizedBox(height: 12),
            Center(child: EvolutionBadge(info: info, owned: owned, worn: worn, size: 168)),
            const SizedBox(height: 12),
            Text(info.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(owned ? info.quip : '还没解锁：${info.look}',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(how, textAlign: TextAlign.center, style: PopText.small),
            const SizedBox(height: 4),
            const Text('只在做人（狗度不到 30%）时穿着，一变狗就脱掉，第二天 0 点变回人再穿上',
                textAlign: TextAlign.center, style: PopText.small),
            const SizedBox(height: 16),
            if (owned && !worn)
              PopButton(
                label: '做人时穿这个',
                style: PopButtonStyle.dark,
                height: 50,
                onPressed: () async {
                  await state.wearEvolution(info.evolution);
                  if (context.mounted) Navigator.pop(context);
                },
              )
            else if (worn)
              PopButton(
                label: '不穿了',
                height: 50,
                onPressed: () async {
                  await state.wearEvolution(null);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}
