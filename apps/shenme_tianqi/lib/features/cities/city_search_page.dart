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
    try {
      await state.addCity(hit, makeHome: widget.onboarding);
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
        ],
      ),
    );
  }
}
