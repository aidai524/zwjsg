import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/scene.dart';
import '../../widgets/common.dart';
import '../../widgets/weather_avatars.dart';

/// 普通模式：形象 + 吐槽 + 温度 + 四张决策卡，下面是进天气详情的入口
class WeatherView extends StatelessWidget {
  const WeatherView({super.key, required this.city, required this.weather});

  final City city;
  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final w = weather;
    final state = AppScope.of(context);
    final unit = state.tempUnit;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // 蓝色和其他颜色的预警横幅可以关掉（这一条不再显示，有新预警照样出来）；黄色及以上进严肃模式，不能关
        for (final b in w.bannerWarnings)
          if (!state.isWarningDismissed(b)) _WarningBanner(b, onClose: () => state.dismissWarning(b)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            MyWeatherAvatar(temp: weatherTempFromKey(w.outfitKey), cond: weatherCondFromKey(w.cond), size: 170),
            const SizedBox(width: 8),
            Expanded(child: _QuipBubble(w.quip ?? w.outfitLabel)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(unit.deg(w.temp), style: const TextStyle(fontSize: 76, height: 1, fontWeight: FontWeight.w900)),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(w.text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    Text('体感 ${unit.deg(w.feelsLike)}'
                        '${w.todayMax != null ? ' · ${unit.deg(w.todayMax!)} / ${unit.deg(w.todayMin!)}' : ''}'),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Row(
          children: [
            Text('今天的决定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            Spacer(),
            Text('点开看依据', style: TextStyle(fontSize: 12)),
          ],
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.45,
          children: [
            for (final k in decisionKeys)
              _DecisionCard(
                title: decisionTitles[k]!,
                decision: w.decision(k),
                onTap: () => context.push('/decision/$k?city=${city.locationId}'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // 首页只到“今天的决定”；接下来 12 小时、未来 7 天、空气质量、湿度和风都在详情页（2026-11-19）
        _DetailEntry(onTap: () => context.push('/detail/${city.locationId}')),
        SourceNote('${w.attribution}${w.obsTime != null ? ' · ${hm(DateTime.parse(w.obsTime!).toLocal())} 更新' : ''}\n'
            '吐槽是我们说的，天气是气象台说的'),
        // 页面上有预警横幅时，和风要求原样显示接口给的来源（refer.sources）；“由和风天气驱动”只放在设置页
        if (w.bannerWarnings.any((b) => !state.isWarningDismissed(b))) QWeatherCredit(attributions: w.attributions, brand: false),
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner(this.w, {required this.onClose});
  final Warning w;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final fg = onWarningColor(w.color);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
      decoration: Pop.card(color: warningColor(w.color), shadow: false, radius: 14),
      child: Row(
        children: [
          Expanded(child: Text(w.title, style: TextStyle(fontWeight: FontWeight.w800, color: fg))),
          IconButton(tooltip: '关掉这条预警', onPressed: onClose, icon: Icon(Icons.close, color: fg, size: 20)),
        ],
      ),
    );
  }
}

class _QuipBubble extends StatelessWidget {
  const _QuipBubble(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 40),
      padding: const EdgeInsets.all(14),
      decoration: Pop.card(radius: 18),
      child: Text(text, style: const TextStyle(fontSize: 16, height: 1.4, fontWeight: FontWeight.w800)),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({required this.title, required this.decision, required this.onTap});
  final String title;
  final Decision decision;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title：${decision.label}，${decision.reason}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: Pop.card(color: decision.isAction ? Pop.yellow : Pop.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(decision.label, style: const TextStyle(fontSize: 26, height: 1.1, fontWeight: FontWeight.w900)),
              Text(decision.reason, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 进天气详情的入口：一张白卡，写清楚里面有什么
class _DetailEntry extends StatelessWidget {
  const _DetailEntry({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Pop.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Pop.ink, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('天气详情', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    SizedBox(height: 2),
                    Text('接下来 12 小时、未来 7 天、空气质量、湿度和风', style: TextStyle(fontSize: 12, color: Pop.muted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
