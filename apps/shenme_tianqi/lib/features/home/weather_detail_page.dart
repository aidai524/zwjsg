import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/scene.dart';
import '../../core/temp_unit.dart';
import '../../widgets/common.dart';

/// 天气详情：首页只到“今天的决定”，点“天气详情”进来看接下来 12 小时、未来 7 天、空气质量、湿度和风（2026-11-19）。
/// 数字都是接口给的，不改写；空气质量用了和风的数据，页尾原样显示接口给的来源。
class WeatherDetailPage extends StatelessWidget {
  const WeatherDetailPage({super.key, required this.locationId});

  final String locationId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final city = state.cities.where((c) => c.locationId == locationId).firstOrNull;
    final w = state.weatherOf(locationId);
    final unit = state.tempUnit;
    return Scaffold(
      appBar: AppBar(title: Text(city == null ? '天气详情' : '${city.name} · 天气详情')),
      body: w == null
          ? const Center(child: Text('天气还没加载好', style: PopText.bodyMuted))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                HourlyStrip(w.hourly.take(12).toList(), unit),
                const SizedBox(height: 16),
                DailyList(w.daily, unit),
                const SizedBox(height: 16),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: AirCard(w.air)),
                      const SizedBox(width: 12),
                      Expanded(child: HumidityWindCard(w, unit)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _NextHours(w.hourly),
                SourceNote('${w.obsTime != null ? '${hm(DateTime.parse(w.obsTime!).toLocal())} 更新 · ' : ''}${w.attribution}'),
                // 用了空气质量（和预警）就要原样显示接口给的来源；“由和风天气驱动”只放在设置页
                QWeatherCredit(attributions: w.attributions, brand: false),
              ],
            ),
    );
  }
}

/// 接下来 12 小时：时间、天气、温度、下雨概率
class HourlyStrip extends StatelessWidget {
  const HourlyStrip(this.hours, this.unit, {super.key});
  final List<HourItem> hours;
  final TempUnit unit;

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
                    Text(unit.deg(h.temp), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    Text(h.pop == null ? '' : '${h.pop}%',
                        style: TextStyle(
                          fontSize: 11,
                          color: (h.pop ?? 0) > 0 ? Pop.rareBlue : Pop.muted,
                          fontWeight: FontWeight.w800,
                        )),
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

/// 未来几天：白天的天气、最低最高温和温度条
class DailyList extends StatelessWidget {
  const DailyList(this.days, this.unit, {super.key});
  final List<DayItem> days;
  final TempUnit unit;

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
                  // 华氏度会有三位数，留宽一点
                  SizedBox(width: 40, child: Text(unit.deg(days[i].min), textAlign: TextAlign.right)),
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
                  SizedBox(width: 40, child: Text(unit.deg(days[i].max), style: const TextStyle(fontWeight: FontWeight.w900))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 空气质量：AQI、等级、首要污染物
class AirCard extends StatelessWidget {
  const AirCard(this.air, {super.key});
  final Map<String, dynamic>? air;

  @override
  Widget build(BuildContext context) {
    final a = air;
    final primary = (a?['primary'] ?? '').toString();
    return Container(
      decoration: Pop.card(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('空气质量', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(a == null ? '--' : 'AQI ${a['aqi']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          Text(a == null ? '暂无数据' : '${a['category']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (primary.isNotEmpty) Text('首要污染物：$primary', style: PopText.small),
        ],
      ),
    );
  }
}

/// 湿度和风：现在的湿度、体感、风向风力，今天白天的湿度和紫外线
class HumidityWindCard extends StatelessWidget {
  const HumidityWindCard(this.w, this.unit, {super.key});
  final WeatherData w;
  final TempUnit unit;

  @override
  Widget build(BuildContext context) {
    final today = w.daily.firstOrNull;
    return Container(
      decoration: Pop.card(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('湿度和风', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('湿度 ${w.humidity}%', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          Text('风 ${w.wind}', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('体感 ${unit.deg(w.feelsLike)}', style: PopText.small),
          if (today?.uvIndex != null) Text('今天紫外线 ${today!.uvIndex}', style: PopText.small),
        ],
      ),
    );
  }
}

/// 接下来几个整点的湿度和风力（每 3 小时一个）
class _NextHours extends StatelessWidget {
  const _NextHours(this.hours);
  final List<HourItem> hours;

  @override
  Widget build(BuildContext context) {
    final picks = [for (var i = 0; i < hours.length && i < 12; i += 3) hours[i]]
        .where((h) => h.humidity != null || h.windScale != null)
        .toList();
    if (picks.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: Pop.card(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('接下来的湿度和风力', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final h in picks)
                Expanded(
                  child: Column(
                    children: [
                      Text('${h.time.toLocal().hour}时', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(h.humidity == null ? '--' : '${h.humidity}%',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                      Text(h.windScale == null ? '' : '风 ${h.windScale} 级', style: PopText.small),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
