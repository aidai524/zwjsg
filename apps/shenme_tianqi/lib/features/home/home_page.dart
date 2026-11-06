import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/scene.dart';
import '../../widgets/common.dart';
import 'serious_view.dart';
import 'weather_view.dart';

/// 首页：左右滑切换关注的城市
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late PageController _pages;

  @override
  void initState() {
    super.initState();
    _pages = PageController(initialPage: AppScope.read(context).currentCity);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cities = state.cities;
    if (cities.isEmpty) return const Scaffold(); // 马上会被路由重定向到引导页
    final index = state.currentCity.clamp(0, cities.length - 1);
    final current = cities[index];
    final w = state.weatherOf(current.locationId);
    final bg = w == null ? Pop.gray : (w.serious ? Pop.gray : sceneColor(w.cond, w.outfitKey));

    // 从城市页回来时跳到选中的城市
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pages.hasClients && _pages.page?.round() != index) _pages.jumpToPage(index);
    });

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: bg,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => context.push('/cities'),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(current.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                            ),
                            const SizedBox(width: 6),
                            if (current.isHome) const Chip2('常驻'),
                            const Icon(Icons.expand_more),
                          ],
                        ),
                      ),
                    ),
                    RoundIconButton(icon: Icons.favorite_border, label: '关心群', onTap: () => context.push('/care')),
                    const SizedBox(width: 10),
                    RoundIconButton(icon: Icons.settings_outlined, label: '设置', onTap: () => context.push('/settings')),
                  ],
                ),
              ),
              if (cities.length > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < cities.length; i++)
                      Container(
                        margin: const EdgeInsets.all(3),
                        width: i == index ? 16 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == index ? Pop.ink : Pop.ink.withAlpha(70),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: cities.length,
                  onPageChanged: (i) => setState(() => state.currentCity = i),
                  itemBuilder: (_, i) => _CityPage(city: cities[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CityPage extends StatefulWidget {
  const _CityPage({required this.city});

  final City city;

  @override
  State<_CityPage> createState() => _CityPageState();
}

class _CityPageState extends State<_CityPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => AppScope.read(context).loadWeather(widget.city));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final w = state.weatherOf(widget.city.locationId);
    final err = state.errorOf(widget.city.locationId);

    Future<void> refresh() => state.loadWeather(widget.city, force: true);

    if (w == null) {
      return Center(
        child: err == null
            ? const CircularProgressIndicator(color: Pop.ink)
            : Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(err, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    PopButton(label: '再试一次', onPressed: refresh),
                  ],
                ),
              ),
      );
    }

    return RefreshIndicator(
      color: Pop.ink,
      onRefresh: refresh,
      child: w.serious ? SeriousView(city: widget.city, weather: w) : WeatherView(city: widget.city, weather: w),
    );
  }
}
