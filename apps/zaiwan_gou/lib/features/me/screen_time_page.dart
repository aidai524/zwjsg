import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_state.dart';
import '../../core/dog_meter.dart';
import '../../core/screen_time_channel.dart';
import '../../widgets/my_avatar.dart';

/// iOS 屏幕使用时间的技术验证页：授权 → 选 App → 开始监控 → 看阈值通知来得准不准。
/// 验证通过后，再决定“今天”页怎么用这个阶段。
class ScreenTimePage extends StatefulWidget {
  const ScreenTimePage({super.key});

  /// 测试用的小目标，十几分钟就能走完 5 个阶段
  static const testGoalMinutes = 10;

  @override
  State<ScreenTimePage> createState() => _ScreenTimePageState();
}

class _ScreenTimePageState extends State<ScreenTimePage> with WidgetsBindingObserver {
  ScreenTimeStatus _status = const ScreenTimeStatus();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 阶段是监控扩展在后台写的，用完别的 App 回来时刷新
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final s = await ScreenTimeChannel.status();
      if (mounted) setState(() => _status = s);
    } on PlatformException {
      // 刷新失败就保留上一次的状态
    } on MissingPluginException {
      // 不是 iOS
    }
  }

  Future<void> _run(Future<ScreenTimeStatus> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final s = await action();
      if (mounted) setState(() => _status = s);
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? '出错了，稍后再试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = AppScope.of(context).goalMinutes;
    final s = _status;
    final canStart = s.authorized && s.hasSelection && !_busy;

    return Scaffold(
      appBar: AppBar(title: const Text('屏幕使用时间（验证）')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text(
              'iOS 只告诉 App 用量到了哪个阈值，拿不到准确分钟数。这页用来在真机上看阈值通知准不准，可以对照系统“设置 › 屏幕使用时间”。',
              style: PopText.small,
            ),
            const SizedBox(height: 16),
            _StageCard(status: s, onRefresh: _busy ? null : _refresh),
            const SizedBox(height: 12),
            _Step(
              index: 1,
              title: '授权',
              detail: switch (s.authorization) {
                'approved' => '已授权',
                'denied' => '被拒绝了，可以到系统设置里重新打开',
                _ => '还没授权，系统会要你用面容 ID 或密码确认',
              },
              action: s.authorized ? null : '授权',
              onAction: _busy ? null : () => _run(ScreenTimeChannel.requestAuthorization),
            ),
            _Step(
              index: 2,
              title: '选要统计的 App',
              detail: s.hasSelection
                  ? '已选 ${s.apps} 个 App、${s.categories} 个类别、${s.webDomains} 个网站'
                  : '还没选。想统计整台手机，就把类别全部选上',
              action: s.hasSelection ? '重选' : '选择',
              onAction: s.authorized && !_busy ? () => _run(ScreenTimeChannel.pickActivities) : null,
            ),
            _Step(
              index: 3,
              title: '开始监控',
              detail: s.monitoring
                  ? '监控中：目标 ${DogMeter.formatMinutes(s.goalMinutes)}，阈值 ${s.thresholds.join(' / ')} 分钟'
                  : '还没开始。中途换目标会从今天 0 点重新算',
              action: s.monitoring ? '停止' : null,
              onAction: _busy ? null : () => _run(ScreenTimeChannel.stopMonitoring),
            ),
            const SizedBox(height: 4),
            PopButton(
              label: '按每日目标（${DogMeter.formatMinutes(goal)}）开始',
              onPressed: canStart ? () => _run(() => ScreenTimeChannel.startMonitoring(goal)) : null,
            ),
            const SizedBox(height: 12),
            PopButton(
              label: '测试：按 ${ScreenTimePage.testGoalMinutes} 分钟目标开始',
              style: PopButtonStyle.secondary,
              onPressed:
                  canStart ? () => _run(() => ScreenTimeChannel.startMonitoring(ScreenTimePage.testGoalMinutes)) : null,
            ),
            const SizedBox(height: 20),
            const Text('记录（新的在上面）', style: PopText.label),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Pop.white, borderRadius: BorderRadius.circular(18)),
              child: s.log.isEmpty
                  ? const Text('还没有记录', style: PopText.small)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in s.log.reversed)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(line, style: const TextStyle(fontSize: 13, height: 1.4)),
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

class _StageCard extends StatelessWidget {
  const _StageCard({required this.status, required this.onRefresh});

  final ScreenTimeStatus status;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final stage = status.stage.clamp(0, DogMeter.stageNames.length - 1);
    final summary = stage == 0 ? '狗度还没到 ${DogMeter.stageThresholds.first}%' : '狗度至少 ${status.minPercent}%';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: Pop.card(color: Pop.softYellow),
      child: Row(
        children: [
          MyAvatar(stage: stage, size: 88),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('今天', style: TextStyle(fontSize: 13, color: Pop.mutedOnYellow)),
                Text(DogMeter.stageNames[stage], style: PopText.h2),
                const SizedBox(height: 2),
                Text(summary, style: const TextStyle(fontSize: 13, color: Pop.mutedOnYellow)),
              ],
            ),
          ),
          IconButton(onPressed: onRefresh, tooltip: '刷新', icon: const Icon(Icons.refresh)),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.title, required this.detail, this.action, this.onAction});

  final int index;
  final String title;
  final String detail;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(color: Pop.white, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: Pop.ink,
            child: Text('$index', style: const TextStyle(color: Pop.white, fontSize: 13, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(detail, style: PopText.small),
              ],
            ),
          ),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}
