import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/temp_unit.dart';
import '../../widgets/common.dart';

/// 关注的城市，不限个数。常驻城市决定早安推送、关心群里家人看到的天气和桌面小组件；
/// 临时城市（出差、旅行看几天）到点自动移除，不能当常驻。
class CitiesPage extends StatelessWidget {
  const CitiesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cities = state.cities;

    return Scaffold(
      appBar: AppBar(title: const Text('我的城市')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (var i = 0; i < cities.length; i++) ...[
            _CityRow(
              city: cities[i],
              weatherText: _brief(state.weatherOf(cities[i].locationId), state.tempUnit),
              onTap: () {
                state.currentCity = i;
                context.pop();
              },
              onHome: () => state.setHome(cities[i]),
              onPermanent: () => state.makePermanent(cities[i]),
              onDelete: cities.length > 1 ? () => state.removeCity(cities[i]) : null,
            ),
            const SizedBox(height: 12),
          ],
          PopButton(label: '+ 加个城市', style: PopButtonStyle.secondary, onPressed: () => context.push('/city-search')),
          const SourceNote('常驻城市用于早安推送、关心群和桌面小组件 · 临时城市到点自动移除\n位置只到城市，不记录你去过哪'),
          const QWeatherCredit(),
        ],
      ),
    );
  }

  static String _brief(WeatherData? w, TempUnit unit) => w == null ? '' : '${unit.deg(w.temp)} ${w.text}';
}

class _CityRow extends StatelessWidget {
  const _CityRow({
    required this.city,
    required this.weatherText,
    required this.onTap,
    required this.onHome,
    required this.onPermanent,
    this.onDelete,
  });

  final City city;
  final String weatherText;
  final VoidCallback onTap;
  final VoidCallback onHome;
  final VoidCallback onPermanent;
  final VoidCallback? onDelete;

  static String tempLabel(City city, DateTime now) {
    final days = city.daysLeft(now);
    return days <= 1 ? '临时 · 今天最后一天' : '临时 · 还剩 $days 天';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        decoration: Pop.card(color: city.isHome ? Pop.yellow : Pop.white),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(city.name,
                          overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    ),
                    if (city.isHome) ...[const SizedBox(width: 6), const Chip2('常驻')],
                  ]),
                  if (city.adm != null) Text(city.adm!, style: const TextStyle(fontSize: 12)),
                  if (city.isTemporary)
                    Text(tempLabel(city, DateTime.now()),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Pop.muted)),
                ],
              ),
            ),
            Text(weatherText, style: const TextStyle(fontWeight: FontWeight.w800)),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Pop.ink),
              onSelected: (v) => switch (v) {
                'home' => onHome(),
                'permanent' => onPermanent(),
                _ => onDelete?.call(),
              },
              itemBuilder: (_) => [
                // 临时城市不能当常驻，要先改成长期关注
                if (city.isTemporary) const PopupMenuItem(value: 'permanent', child: Text('改成长期关注')),
                if (!city.isHome && !city.isTemporary) const PopupMenuItem(value: 'home', child: Text('设为常驻城市')),
                if (onDelete != null) const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
