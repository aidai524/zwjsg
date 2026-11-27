import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_lock.dart';
import '../../core/dog_meter.dart';
import '../../core/lock_advisor.dart';
import '../../core/screen_time_channel.dart';
import '../../core/usage_channel.dart';

/// 最近几天的排行和有数据的天数
typedef WeekUsage = ({List<AppUsage> apps, int days});

/// 超时来电页最上面：狗版的你帮你看了最近 7 天，最费时间的是哪几个，建议先给哪几个设限时、每天多久。
/// - 安卓：按 [LockAdvisor] 算好，勾上、改额度，一键设好（一个 App 一个限时）；
/// - iOS：Flutter 读不到每个 App 的用时，建议由报告扩展按同样的规则画出来，用户在系统的选择页里自己勾。
class LockAdviceCard extends StatefulWidget {
  const LockAdviceCard({
    super.key,
    required this.service,
    required this.locks,
    required this.ready,
    required this.onApplied,
    required this.onSetup,
    required this.onPick,
    this.loader,
  });

  final LockService service;
  final List<AppLock> locks;

  /// 拦截要的权限开了没有
  final bool ready;

  /// 一键设好以后刷新列表
  final Future<void> Function() onApplied;
  final Future<void> Function() onSetup;

  /// iOS：去系统的选择页
  final VoidCallback onPick;

  /// 测试里传，代替原生层的 7 天排行
  final Future<WeekUsage> Function()? loader;

  static const days = 7;

  static Future<WeekUsage> loadAndroid() async {
    final apps = await UsageChannel.ranking(days: days);
    final past = await UsageChannel.pastDays(days - 1);
    return (apps: apps, days: past.length + 1);
  }

  @override
  State<LockAdviceCard> createState() => _LockAdviceCardState();
}

class _LockAdviceCardState extends State<LockAdviceCard> {
  WeekUsage? _week;
  bool _noPermission = false;

  /// 勾上的 App → 每天额度
  final Map<String, int> _picked = {};
  bool _picksInitialized = false;
  bool _busy = false;

  bool get _android => widget.loader != null || UsageChannel.isSupported;

  @override
  void initState() {
    super.initState();
    if (_android) _load();
  }

  Future<void> _load() async {
    try {
      final week = await (widget.loader ?? LockAdviceCard.loadAndroid)();
      if (mounted) setState(() => _week = week);
    } on PlatformException {
      if (mounted) setState(() => _noPermission = true);
    }
  }

  List<LockAdvice> get _advice {
    final w = _week;
    if (w == null) return const [];
    return LockAdvisor.suggest(w.apps, days: w.days, existing: widget.locks);
  }

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _apply(List<LockAdvice> advice) async {
    final picks = [for (final a in advice) if (_picked.containsKey(a.app.package)) a];
    if (picks.isEmpty || _busy) return;
    final room = LockService.maxLocks - widget.locks.length;
    setState(() => _busy = true);
    try {
      for (final a in picks.take(room)) {
        await widget.service.save(LockDraft(
          minutes: _picked[a.app.package]!,
          packages: [a.app.package],
          labels: [a.app.label],
        ));
      }
      _toast('设好了：${picks.take(room).map((a) => '${a.app.label} 每天 ${DogMeter.formatMinutes(_picked[a.app.package]!)}').join('，')}');
      await widget.onApplied();
    } on PlatformException catch (e) {
      _toast(e.message ?? '没设上，稍后再试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_android) return ScreenTimeChannel.isSupported && widget.ready ? _ios() : const SizedBox.shrink();
    if (_noPermission) {
      return const _Frame(
        title: '狗版的你想帮你看看',
        child: Text('打开“使用情况访问权限”后，狗版的你才能看出最近哪几个 App 最上头。', style: PopText.small),
      );
    }
    final week = _week;
    if (week == null) return const SizedBox.shrink();
    final advice = _advice;
    if (!_picksInitialized && advice.isNotEmpty) {
      // 默认全勾上，额度用建议的
      for (final a in advice) {
        _picked[a.app.package] = a.suggestedMinutes;
      }
      _picksInitialized = true;
    }
    final first = widget.locks.isEmpty;
    if (advice.isEmpty) {
      return first
          ? const _Frame(
              title: '狗版的你帮你看了最近 7 天',
              child: Text('没有特别上头的 App，好狗。想管哪个，就点下面的“加一个限时”。', style: PopText.small),
            )
          : const SizedBox.shrink();
    }

    final top = week.apps.take(3).map((a) => a.label).join('、');
    final count = advice.where((a) => _picked.containsKey(a.app.package)).length;
    return _Frame(
      title: first ? '狗版的你帮你看了最近 7 天' : '还有几个也挺上头',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (first && top.isNotEmpty) ...[
            Text('最费时间的是：$top', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
          ],
          Text(first ? '建议先给这几个设限时，额度比你平时少三成左右：' : '这几个还没设限时：', style: PopText.small),
          const SizedBox(height: 8),
          for (final a in advice)
            _AdviceRow(
              advice: a,
              picked: _picked.containsKey(a.app.package),
              minutes: _picked[a.app.package] ?? a.suggestedMinutes,
              onToggle: (on) => setState(() {
                if (on) {
                  _picked[a.app.package] = a.suggestedMinutes;
                } else {
                  _picked.remove(a.app.package);
                }
              }),
              onMinutes: (m) => setState(() => _picked[a.app.package] = m),
            ),
          const SizedBox(height: 10),
          widget.ready
              ? PopButton(
                  label: count == 0 ? '先勾上要管的 App' : '设好这 $count 个限时',
                  height: 48,
                  loading: _busy,
                  onPressed: count == 0 ? null : () => _apply(advice),
                )
              : PopButton(label: '先打开权限，再设限时', height: 48, style: PopButtonStyle.dark, onPressed: widget.onSetup),
          const SizedBox(height: 8),
          const Text('用满了，狗版的你会打电话来；想再玩，得学两声狗叫。', style: PopText.small),
        ],
      ),
    );
  }

  /// iOS：报告扩展按同样的规则画建议，用户在系统的选择页里自己勾
  Widget _ios() {
    return _Frame(
      title: widget.locks.isEmpty ? '狗版的你帮你看了最近 7 天' : '还有哪些最上头',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            height: 232,
            child: UiKitView(
              viewType: 'zwjsg/screen_time_report',
              creationParams: {'advice': true, 'days': LockAdviceCard.days},
              creationParamsCodec: StandardMessageCodec(),
            ),
          ),
          const SizedBox(height: 8),
          const Text('iPhone 不让 App 直接替你选，下一步在系统的选择页里把它们勾上。', style: PopText.small),
          const SizedBox(height: 10),
          PopButton(label: '去设限时', height: 48, onPressed: widget.onPick),
        ],
      ),
    );
  }
}

class _AdviceRow extends StatelessWidget {
  const _AdviceRow({
    required this.advice,
    required this.picked,
    required this.minutes,
    required this.onToggle,
    required this.onMinutes,
  });

  final LockAdvice advice;
  final bool picked;
  final int minutes;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onMinutes;

  @override
  Widget build(BuildContext context) {
    final icon = advice.app.icon;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: picked,
            activeColor: Pop.ink,
            onChanged: (v) => onToggle(v ?? false),
            semanticLabel: '给${advice.app.label}设限时',
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: icon == null
                ? const SizedBox(width: 30, height: 30, child: Icon(Icons.apps, color: Pop.muted))
                : Image.memory(icon, width: 30, height: 30, gaplessPlayback: true),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(advice.app.label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                Text(advice.reason, style: PopText.small),
              ],
            ),
          ),
          PopupMenuButton<int>(
            tooltip: '每天额度',
            enabled: picked,
            initialValue: minutes,
            onSelected: onMinutes,
            itemBuilder: (_) => [
              for (final m in LockService.presets) PopupMenuItem(value: m, child: Text('每天 ${DogMeter.formatMinutes(m)}')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: picked ? Pop.softYellow : Pop.gray,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: picked ? Pop.ink : Pop.gray, width: 1.5),
              ),
              child: Text('每天 ${DogMeter.formatMinutes(minutes)} ▾',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: picked ? Pop.ink : Pop.muted)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Pop.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Pop.ink, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.pets, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
          ]),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
