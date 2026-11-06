import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/dog_meter.dart';
import 'package:pop_ui/pop_ui.dart';
import '../../core/usage_channel.dart';
import 'package:avatar_engine/avatar_engine.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => AppScope.read(context).refreshUsage());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从后台回来（比如刚去系统设置开了权限）时刷新
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && mounted) AppScope.read(context).refreshUsage();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final stage = state.stage;
    final toNext = DogMeter.minutesToNextStage(state.minutesUsed, state.goalMinutes);
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: state.refreshUsage,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // 黄色头部
            Container(
              decoration: const BoxDecoration(
                color: Pop.yellow,
                border: Border(bottom: BorderSide(color: Pop.ink, width: Pop.stroke)),
              ),
              padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 12, 20, 22),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${now.month} 月 ${now.day} 日 周${weekdays[now.weekday - 1]}',
                                style: const TextStyle(fontSize: 13, color: Pop.mutedOnYellow)),
                            const Text('今天的你', style: PopText.h2),
                          ],
                        ),
                      ),
                      if (state.usage.isDemo)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Pop.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Pop.ink, width: 2),
                          ),
                          child: const Text('演示数据', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 200,
                    height: 200,
                    decoration: const BoxDecoration(
                      color: Pop.white,
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(BorderSide(color: Pop.ink, width: Pop.stroke)),
                      boxShadow: [BoxShadow(color: Pop.ink, offset: Offset(5, 5))],
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.bottomCenter,
                    child: DogAvatar(stage: stage, size: 184),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text('狗度 ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text('${state.percent}%', style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w900, height: 1)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(color: Pop.ink, borderRadius: BorderRadius.circular(16)),
                    child: Text(DogMeter.stageNames[stage],
                        style: const TextStyle(color: Pop.yellow, fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 8),
                  Text(DogMeter.quips[stage], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (UsageChannel.isSupported && !state.hasUsagePermission) ...[
                    _PermissionBanner(onOpen: UsageChannel.openPermissionSettings),
                    const SizedBox(height: 12),
                  ],
                  _ProgressCard(
                    used: state.minutesUsed,
                    goal: state.goalMinutes,
                    percent: state.percent,
                    hint: toNext == null
                        ? '已经到底了，再刷也还是狗'
                        : '再刷 ${DogMeter.formatMinutes(toNext)}，你就会${DogMeter.nextChange[stage]}',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _Stat(label: '拿起手机', value: '${state.usage.pickups} 次')),
                      const SizedBox(width: 10),
                      Expanded(child: _Stat(label: '23 点后', value: DogMeter.formatMinutes(state.usage.lateNightMinutes))),
                    ],
                  ),
                  if (state.usage.isDemo) ...[
                    const SizedBox(height: 12),
                    Text('演示：拖动看看不同时长的样子（${DogMeter.formatMinutes(state.demoMinutes)}）', style: PopText.small),
                    Slider(
                      value: state.demoMinutes.toDouble(),
                      min: 0,
                      max: 330,
                      activeColor: Pop.ink,
                      onChanged: (v) => state.setDemoMinutes(v.round()),
                    ),
                  ],
                  const SizedBox(height: 12),
                  PopButton(
                    label: '提前看今晚的结算卡',
                    style: PopButtonStyle.secondary,
                    height: 52,
                    onPressed: () => context.push('/card'),
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

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.onOpen});

  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: Pop.card(color: Pop.softYellow, shadow: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('还差一步：打开“使用情况访问权限”', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('只用来算你今天刷了多久，数据只在手机上，不上传 app 记录。', style: TextStyle(fontSize: 13, height: 1.5)),
          const SizedBox(height: 10),
          PopButton(label: '去打开', style: PopButtonStyle.dark, height: 46, onPressed: onOpen),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.used, required this.goal, required this.percent, required this.hint});

  final int used;
  final int goal;
  final int percent;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final fill = (percent / 150).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: Pop.card(shadow: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('今日已刷 ${DogMeter.formatMinutes(used)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              Text('目标 ${DogMeter.formatMinutes(goal)}', style: PopText.small),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 18,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Pop.ink, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(widthFactor: fill, child: Container(color: Pop.yellow)),
          ),
          const SizedBox(height: 8),
          Text(hint, style: const TextStyle(fontSize: 13, color: Color(0xFF3C4043))),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Pop.gray, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Pop.muted)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
