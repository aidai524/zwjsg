import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_groups.dart';
import '../../core/dog_meter.dart';
import '../../core/usage_channel.dart';

/// 安卓：选要锁的 App。App 名称和图标只在手机上显示，不上传。
/// 上面一排按类整组勾（短视频、社交、游戏，2026-11-27），再单独增减；
/// 白名单里的（电话、短信、地图、支付、银行、系统设置）放在最后，灰的，勾不了。
class AppPickerPage extends StatefulWidget {
  const AppPickerPage({super.key, required this.loader, this.initial = const []});

  final Future<List<AppUsage>> Function() loader;

  /// 已经选中的包名
  final List<String> initial;

  @override
  State<AppPickerPage> createState() => _AppPickerPageState();
}

class _AppPickerPageState extends State<AppPickerPage> {
  List<AppUsage>? _apps;
  late final Set<String> _selected = {...widget.initial};
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.loader().then((apps) {
      if (!mounted) return;
      setState(() {
        _apps = apps;
        // 以前选进去的白名单 App 不再算
        _selected.removeAll([for (final a in apps) if (a.whitelisted) a.package]);
      });
    });
  }

  void _done() {
    final apps = _apps ?? const <AppUsage>[];
    Navigator.pop(context, [for (final a in apps) if (_selected.contains(a.package) && !a.whitelisted) a]);
  }

  /// 这一组都勾上了就整组取消，不然整组勾上
  void _toggleGroup(List<AppUsage> members) {
    final all = members.every((a) => _selected.contains(a.package));
    setState(() {
      for (final a in members) {
        all ? _selected.remove(a.package) : _selected.add(a.package);
      }
    });
  }

  Widget _icon(AppUsage app) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: app.icon == null
            ? const SizedBox(width: 36, height: 36, child: Icon(Icons.apps, color: Pop.muted))
            : Image.memory(app.icon!, width: 36, height: 36, gaplessPlayback: true),
      );

  @override
  Widget build(BuildContext context) {
    final apps = _apps;
    bool matches(AppUsage a) => _query.isEmpty || a.label.toLowerCase().contains(_query.toLowerCase());
    final shown = apps?.where((a) => !a.whitelisted && matches(a)).toList();
    final never = apps?.where((a) => a.whitelisted && matches(a)).toList() ?? const <AppUsage>[];
    final groups = {
      for (final g in AppGroup.values) g: [for (final a in apps ?? const <AppUsage>[]) if (AppGroup.of(a) == g) a],
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('选要锁的 App'),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty ? null : _done,
            child: Text('完成（${_selected.length}）'),
          ),
        ],
      ),
      body: SafeArea(
        child: shown == null
            ? const Center(child: CircularProgressIndicator(color: Pop.ink))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: '搜 App 名称',
                        prefixIcon: Icon(Icons.search),
                        filled: true,
                        fillColor: Pop.white,
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                      ),
                      onChanged: (v) => setState(() => _query = v.trim()),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('整类勾：', style: PopText.small),
                        for (final g in AppGroup.values)
                          FilterChip(
                            label: Text('${g.label} ${groups[g]!.length}'),
                            selected: groups[g]!.isNotEmpty && groups[g]!.every((a) => _selected.contains(a.package)),
                            showCheckmark: false,
                            selectedColor: Pop.yellow,
                            onSelected: groups[g]!.isEmpty ? null : (_) => _toggleGroup(groups[g]!),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      children: [
                        for (final app in shown)
                          CheckboxListTile(
                            value: _selected.contains(app.package),
                            activeColor: Pop.ink,
                            onChanged: (on) => setState(() {
                              on == true ? _selected.add(app.package) : _selected.remove(app.package);
                            }),
                            secondary: _icon(app),
                            title: Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: app.minutes > 0 ? Text('今天用了 ${DogMeter.formatMinutes(app.minutes)}') : null,
                          ),
                        if (never.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(8, 16, 8, 4),
                            child: Text('永不来电：电话、短信、地图、支付、银行和系统设置，锁不了', style: PopText.small),
                          ),
                          for (final app in never)
                            Opacity(
                              opacity: 0.5,
                              child: CheckboxListTile(
                                value: false,
                                onChanged: null,
                                secondary: _icon(app),
                                title: Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: const Text('永不来电'),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
