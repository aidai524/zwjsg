import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/models.dart';
import '../../core/scene.dart';
import '../../widgets/common.dart';

/// 严肃模式：黄色及以上预警。吐槽暂停，预警原文照登（标题、正文、发布单位、时间都不改）。
class SeriousView extends StatelessWidget {
  const SeriousView({super.key, required this.city, required this.weather});

  final City city;
  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final w = weather;
    final umbrella = w.decision('umbrella');

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final warn in w.seriousWarnings) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: Pop.card(color: warningColor(warn.color)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(warn.title,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: onWarningColor(warn.color))),
                const SizedBox(height: 6),
                Text('${warn.sender} · ${_time(warn.pubTime)} 发布',
                    style: TextStyle(fontSize: 13, color: onWarningColor(warn.color))),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(14),
          decoration: Pop.card(),
          child: Row(
            children: [
              const WeatherAvatar(temp: WeatherTemp.mild, cond: WeatherCond.serious, size: 92),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('吐槽暂停，注意安全', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    SizedBox(height: 4),
                    Text('预警解除后，我们再恢复嘴贫', style: TextStyle(color: Pop.muted)),
                  ],
                ),
              ),
              Text('${w.temp}°\n${w.text}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final warn in w.seriousWarnings)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: Pop.card(shadow: false),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('预警原文', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                SelectableText(warn.text, style: const TextStyle(height: 1.6)),
              ],
            ),
          ),
        GestureDetector(
          onTap: () => context.push('/decision/umbrella?city=${city.locationId}'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: Pop.card(color: umbrella.isAction ? Pop.yellow : Pop.white),
            child: Row(
              children: [
                const Text('带不带伞', style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(umbrella.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
        SourceNote('预警信息来源：${w.seriousWarnings.map((e) => e.sender).toSet().join('、')}\n${w.attribution}'),
      ],
    );
  }

  static String _time(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    return t == null ? iso : '${t.month} 月 ${t.day} 日 ${hm(t)}';
  }
}
