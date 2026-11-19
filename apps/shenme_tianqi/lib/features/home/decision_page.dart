import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/scene.dart';
import '../../widgets/common.dart';

/// 决策详情：结论 + 依据（逐小时降水概率）+ 判断规则，让用户知道我们不是瞎说的
class DecisionPage extends StatelessWidget {
  const DecisionPage({super.key, required this.decisionKey, required this.locationId});

  final String decisionKey;
  final String locationId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final w = state.weatherOf(locationId);
    final title = decisionTitles[decisionKey] ?? '';
    if (w == null) {
      return Scaffold(appBar: AppBar(title: Text(title)), body: const Center(child: Text('天气还没加载好')));
    }
    final d = w.decision(decisionKey);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: Pop.card(color: d.isAction ? Pop.yellow : Pop.white),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.label, style: const TextStyle(fontSize: 48, height: 1, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(d.reason, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (decisionKey == 'umbrella' || decisionKey == 'laundry') PopChart(w.hourly),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: Pop.card(color: Pop.gray, shadow: false),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('怎么判断的', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(decisionRule(decisionKey, state.tempUnit), style: const TextStyle(height: 1.6)),
              ],
            ),
          ),
          SourceNote(w.attribution),
        ],
      ),
    );
  }
}

/// 逐小时降水概率柱状图：每根柱子都写百分比，≥ 50% 的标蓝；上面一句话说结论。
/// 晴天时每小时都是 0%，只画柱子的话一片空白，看着像没数据（2026-11-19 用户反馈），所以要写清楚
class PopChart extends StatelessWidget {
  const PopChart(this.hours, {super.key});
  final List<HourItem> hours;

  /// 最多画几个小时
  static const shown = 16;

  /// 图上面那句话
  static String summary(List<HourItem> hours) {
    final list = hours.take(shown).toList();
    final known = [for (final h in list) if (h.pop != null) h.pop!];
    if (known.isEmpty) return '暂时拿不到逐小时的降水概率';
    final top = known.reduce((a, b) => a > b ? a : b);
    if (top == 0) return '接下来 ${list.length} 小时都不会下雨（概率都是 0%）';
    final wet = known.where((p) => p >= 50).length;
    if (wet == 0) return '最高 $top%，下雨的可能不大';
    return '有 $wet 个小时下雨概率过半，最高 $top%';
  }

  @override
  Widget build(BuildContext context) {
    final list = hours.take(shown).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: Pop.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('每小时下雨的概率', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(summary(hours), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SizedBox(
            // 数字 14 + 柱子最高 120 + 底线 + 小时 18
            height: 160,
            child: Stack(
              children: [
                // 50% 的虚线：柱子底部在小时文字上面 20 处，50% 是 60 高
                const Positioned(left: 0, right: 26, bottom: 20 + 60, child: _DashedLine()),
                const Positioned(
                  right: 0,
                  bottom: 20 + 60 - 7,
                  child: Text('50%', style: TextStyle(fontSize: 10, color: Pop.muted)),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 26),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final h in list)
                        Expanded(
                          child: Semantics(
                            container: true,
                            label: '${h.time.toLocal().hour} 点：${h.pop == null ? '没有数据' : '${h.pop}%'}',
                            excludeSemantics: true,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(h.pop == null ? '--' : '${h.pop}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: (h.pop ?? 0) >= 50 ? Pop.rareBlue : Pop.muted,
                                      fontWeight: (h.pop ?? 0) >= 50 ? FontWeight.w900 : FontWeight.w600,
                                    )),
                                const SizedBox(height: 2),
                                Container(
                                  height: ((h.pop ?? 0) * 1.2).clamp(2.0, 120.0),
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                    color: h.pop == null
                                        ? Pop.gray
                                        : ((h.pop ?? 0) >= 50 ? Pop.rareBlue : const Color(0xFFC9D7F2)),
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                  ),
                                ),
                                // 底线：0% 的柱子也看得出是“有数据、是 0”
                                Container(height: 1.5, color: Pop.ink),
                                SizedBox(
                                  height: 18,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text('${h.time.toLocal().hour}', style: const TextStyle(fontSize: 10)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final n = (c.maxWidth / 8).floor();
      return Row(
        children: List.generate(n, (i) => Container(width: 4, height: 1.5, margin: const EdgeInsets.only(right: 4), color: Pop.ink)),
      );
    });
  }
}
