import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/models.dart';
import '../../core/scene.dart';
import '../../widgets/common.dart';

/// 普通模式：形象 + 吐槽 + 温度 + 四张决策卡 + 逐小时 + 7 天
class WeatherView extends StatelessWidget {
  const WeatherView({super.key, required this.city, required this.weather});

  final City city;
  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final w = weather;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final b in w.bannerWarnings) _WarningBanner(b),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            WeatherAvatar(temp: weatherTempFromKey(w.outfitKey), cond: weatherCondFromKey(w.cond), size: 170),
            const SizedBox(width: 8),
            Expanded(child: _QuipBubble(w.quip ?? w.outfitLabel)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${w.temp}°', style: const TextStyle(fontSize: 76, height: 1, fontWeight: FontWeight.w900)),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(w.text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    Text('体感 ${w.feelsLike}°'
                        '${w.todayMax != null ? ' · ${w.todayMax}° / ${w.todayMin}°' : ''}'),
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
        const SizedBox(height: 20),
        _HourlyStrip(w.hourly.take(12).toList()),
        const SizedBox(height: 16),
        _DailyList(w.daily),
        const SizedBox(height: 16),
        _Extras(w),
        SourceNote('${w.attribution}${w.obsTime != null ? ' · ${hm(DateTime.parse(w.obsTime!).toLocal())} 更新' : ''}\n'
            '吐槽是我们说的，天气是气象台说的'),
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner(this.w);
  final Warning w;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: Pop.card(color: warningColor(w.color), shadow: false, radius: 14),
      child: Text(w.title, style: TextStyle(fontWeight: FontWeight.w800, color: onWarningColor(w.color))),
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

class _HourlyStrip extends StatelessWidget {
  const _HourlyStrip(this.hours);
  final List<HourItem> hours;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: Pop.card(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('接下来 12 小时', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: hours.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (_, i) {
                final h = hours[i];
                return Column(
                  children: [
                    Text(i == 0 ? '现在' : '${h.time.toLocal().hour}时', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(h.text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('${h.temp}°', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    Text((h.pop ?? 0) > 0 ? '${h.pop}%' : '',
                        style: const TextStyle(fontSize: 11, color: Pop.rareBlue, fontWeight: FontWeight.w800)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyList extends StatelessWidget {
  const _DailyList(this.days);
  final List<DayItem> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final lo = days.map((d) => d.min).reduce((a, b) => a < b ? a : b);
    final hi = days.map((d) => d.max).reduce((a, b) => a > b ? a : b);
    final span = (hi - lo).clamp(1, 100);

    return Container(
      decoration: Pop.card(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('未来 ${days.length} 天', style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          for (var i = 0; i < days.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(width: 44, child: Text(dayLabel(days[i].date, i), style: const TextStyle(fontWeight: FontWeight.w700))),
                  SizedBox(width: 64, child: Text(days[i].text, overflow: TextOverflow.ellipsis)),
                  SizedBox(width: 34, child: Text('${days[i].min}°', textAlign: TextAlign.right)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LayoutBuilder(builder: (_, c) {
                      final left = (days[i].min - lo) / span * c.maxWidth;
                      final width = ((days[i].max - days[i].min) / span * c.maxWidth).clamp(6.0, c.maxWidth);
                      return Stack(children: [
                        Container(height: 8, decoration: BoxDecoration(color: Pop.gray, borderRadius: BorderRadius.circular(4))),
                        Positioned(
                          left: left.clamp(0.0, c.maxWidth - width),
                          child: Container(
                            width: width,
                            height: 8,
                            decoration: BoxDecoration(color: Pop.ink, borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                      ]);
                    }),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 34, child: Text('${days[i].max}°', style: const TextStyle(fontWeight: FontWeight.w900))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Extras extends StatelessWidget {
  const _Extras(this.w);
  final WeatherData w;

  @override
  Widget build(BuildContext context) {
    final air = w.air;
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: Pop.card(),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('空气质量', style: TextStyle(fontSize: 12)),
                Text(air == null ? '--' : '${air['aqi']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                Text(air == null ? '暂无' : '${air['category']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            decoration: Pop.card(),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('湿度 ${w.humidity}%', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('风 ${w.wind}', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(w.outfitLabel, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
