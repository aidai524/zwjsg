import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../widgets/common.dart';

class CitySearchPage extends StatefulWidget {
  const CitySearchPage({super.key, this.onboarding = false});

  final bool onboarding;

  @override
  State<CitySearchPage> createState() => _CitySearchPageState();
}

class _CitySearchPageState extends State<CitySearchPage> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<CityHit> _hits = [];
  bool _loading = false;
  String? _error;

  static const _hot = ['北京', '上海', '广州', '深圳', '成都', '杭州', '武汉', '西安', '重庆', '哈尔滨'];

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String q) async {
    q = q.trim();
    if (q.isEmpty) {
      setState(() => _hits = []);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hits = await AppScope.read(context).api.searchCities(q);
      if (mounted) setState(() => _hits = hits);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(CityHit hit) async {
    final state = AppScope.read(context);
    // 引导里加的第一个城市是常驻城市，直接长期关注；之后加的问一句：长期关注，还是临时看几天
    int? tempDays;
    final alreadyThere = state.cities.any((c) => c.locationId == hit.locationId);
    if (!widget.onboarding && state.cities.isNotEmpty && !alreadyThere) {
      final choice = await showFollowSheet(context, hit.name);
      if (choice == null || !mounted) return;
      tempDays = choice == 0 ? null : choice;
    }
    try {
      await state.addCity(hit, makeHome: widget.onboarding, tempDays: tempDays);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
      return;
    }
    if (!mounted) return;
    if (widget.onboarding) {
      await state.completeOnboarding();
      if (mounted) context.go('/');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.onboarding ? '你在哪个城市？' : '加个城市')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            decoration: Pop.card(shadow: false),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _onChanged,
              onSubmitted: _search,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: '搜城市或区县，比如“南山”',
                border: InputBorder.none,
                icon: Icon(Icons.search, color: Pop.ink),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_loading) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
          if (_error != null) Text(_error!, style: const TextStyle(color: Pop.danger)),
          if (_ctrl.text.trim().isEmpty) ...[
            const Text('热门城市', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final name in _hot)
                  ActionChip(
                    label: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    side: const BorderSide(color: Pop.ink, width: 2),
                    backgroundColor: Pop.white,
                    onPressed: () {
                      _ctrl.text = name;
                      _search(name);
                    },
                  ),
              ],
            ),
          ],
          for (final h in _hits)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: h.subtitle.isEmpty ? null : Text(h.subtitle),
              trailing: const Icon(Icons.add_circle_outline, color: Pop.ink),
              onTap: () => _pick(h),
            ),
          if (!_loading && _hits.isEmpty && _ctrl.text.trim().isNotEmpty && _error == null)
            const Padding(padding: EdgeInsets.all(16), child: Text('没找到，换个叫法试试', textAlign: TextAlign.center)),
          const SizedBox(height: 16),
          const QWeatherCredit(),
        ],
      ),
    );
  }
}

/// 临时城市能看几天
const tempCityDays = [1, 3, 7];

/// 怎么关注这个城市：返回 0 是长期关注，1 / 3 / 7 是临时看几天，关掉弹层是 null
Future<int?> showFollowSheet(BuildContext context, String name) => showModalBottomSheet<int>(
      context: context,
      backgroundColor: Pop.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('怎么关注「$name」？', style: PopText.h2),
              const SizedBox(height: 4),
              const Text('出差、旅行只看几天的，选临时：到点自动移除，不用自己删。', style: PopText.small),
              const SizedBox(height: 14),
              PopButton(label: '长期关注', onPressed: () => Navigator.pop(c, 0)),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final d in tempCityDays) ...[
                    if (d != tempCityDays.first) const SizedBox(width: 8),
                    Expanded(
                      child: PopButton(
                        label: '临时 $d 天',
                        style: PopButtonStyle.secondary,
                        height: 48,
                        onPressed: () => Navigator.pop(c, d),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
