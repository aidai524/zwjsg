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
    final w = AppScope.of(context).weatherOf(locationId);
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
          if (decisionKey == 'umbrella' || decisionKey == 'laundry') _PopChart(w.hourly),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: Pop.card(color: Pop.gray, shadow: false),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('怎么判断的', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(decisionRules[decisionKey] ?? '', style: const TextStyle(height: 1.6)),
              ],
            ),
          ),
          SourceNote(w.attribution),
        ],
      ),
    );
  }
}

/// 逐小时降水概率柱状图；≥ 50% 的柱子标蓝并写数字
class _PopChart extends StatelessWidget {
  const _PopChart(this.hours);
  final List<HourItem> hours;

  @override
  Widget build(BuildContext context) {
    final list = hours.take(16).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: Pop.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('每小时下雨的概率', style: TextStyle(fontWeight: FontWeight.w900)),
          const Text('虚线 = 50%', style: TextStyle(fontSize: 12, color: Pop.muted)),
          const SizedBox(height: 12),
          SizedBox(
            // 柱子最高 120 + 数字 + 底部小时 20，150 放不下会溢出
            height: 160,
            child: Stack(
              children: [
                const Positioned(left: 0, right: 0, bottom: 20 + 60, child: _DashedLine()),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final h in list)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if ((h.pop ?? 0) >= 50)
                              Text('${h.pop}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                            Container(
                              height: ((h.pop ?? 0) * 1.2).clamp(2.0, 120.0),
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: (h.pop ?? 0) >= 50 ? Pop.rareBlue : const Color(0xFFC9D7F2),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                              ),
                            ),
                            SizedBox(
                              height: 20,
                              child: Text('${h.time.toLocal().hour}', style: const TextStyle(fontSize: 10)),
                            ),
                          ],
                        ),
                      ),
                  ],
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
