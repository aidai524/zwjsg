import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/dog_meter.dart';
import '../../core/usage_channel.dart';

/// 安卓：选要锁的 App。App 名称和图标只在手机上显示，不上传。
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
      if (mounted) setState(() => _apps = apps);
    });
  }

  void _done() {
    final apps = _apps ?? const <AppUsage>[];
    Navigator.pop(context, [for (final a in apps) if (_selected.contains(a.package)) a]);
  }

  @override
  Widget build(BuildContext context) {
    final apps = _apps;
    final shown = apps?.where((a) => _query.isEmpty || a.label.toLowerCase().contains(_query.toLowerCase())).toList();
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
                            secondary: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: app.icon == null
                                  ? const SizedBox(width: 36, height: 36, child: Icon(Icons.apps, color: Pop.muted))
                                  : Image.memory(app.icon!, width: 36, height: 36, gaplessPlayback: true),
                            ),
                            title: Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: app.minutes > 0 ? Text('今天用了 ${DogMeter.formatMinutes(app.minutes)}') : null,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
