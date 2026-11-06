import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../widgets/common.dart';

/// 关注的城市（最多 5 个）。常驻城市决定早安推送和关心群里家人看到的天气。
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
              weatherText: _brief(state.weatherOf(cities[i].locationId)),
              onTap: () {
                state.currentCity = i;
                context.pop();
              },
              onHome: () => state.setHome(cities[i]),
              onDelete: cities.length > 1 ? () => state.removeCity(cities[i]) : null,
            ),
            const SizedBox(height: 12),
          ],
          if (cities.length < AppState.maxCities)
            PopButton(label: '+ 加个城市', style: PopButtonStyle.secondary, onPressed: () => context.push('/city-search')),
          const SourceNote('最多关注 5 个城市 · 常驻城市用于早安推送和关心群\n位置只到城市，不记录你去过哪'),
        ],
      ),
    );
  }

  static String _brief(WeatherData? w) => w == null ? '' : '${w.temp}° ${w.text}';
}

class _CityRow extends StatelessWidget {
  const _CityRow({required this.city, required this.weatherText, required this.onTap, required this.onHome, this.onDelete});

  final City city;
  final String weatherText;
  final VoidCallback onTap;
  final VoidCallback onHome;
  final VoidCallback? onDelete;

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
                    Text(city.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    if (city.isHome) ...[const SizedBox(width: 6), const Chip2('常驻')],
                  ]),
                  if (city.adm != null) Text(city.adm!, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Text(weatherText, style: const TextStyle(fontWeight: FontWeight.w800)),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Pop.ink),
              onSelected: (v) => v == 'home' ? onHome() : onDelete?.call(),
              itemBuilder: (_) => [
                if (!city.isHome) const PopupMenuItem(value: 'home', child: Text('设为常驻城市')),
                if (onDelete != null) const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
