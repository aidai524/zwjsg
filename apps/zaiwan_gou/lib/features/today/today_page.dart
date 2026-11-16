import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/dog_meter.dart';
import 'package:pop_ui/pop_ui.dart';
import '../../core/screen_time_channel.dart';
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

  /// iOS 的开启和重启会弹系统页面，出错时给个提示
  Future<void> _runScreenTime(Future<void> Function() action) async {
    try {
      await action();
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? '出错了，稍后再试')));
      }
    }
  }

  /// 进度卡下面的一句话。iOS 拿不到准确分钟数，只能说用满多少会进入下一阶段
  String _hint(AppState state) {
    final stage = state.stage;
    if (stage >= DogMeter.stageThresholds.length) return '已经到底了，再刷也还是狗';
    if (state.usage.stageOnly) {
      final next = ScreenTimeChannel.thresholdMinutes(state.goalMinutes)[stage];
      return '今天用满 ${DogMeter.formatMinutes(next)}，你就会${DogMeter.nextChange[stage]}';
    }
    final toNext = DogMeter.minutesToNextStage(state.minutesUsed, state.goalMinutes) ?? 0;
    return '再刷 ${DogMeter.formatMinutes(toNext)}，你就会${DogMeter.nextChange[stage]}';
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final stage = state.stage;
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
                      Text(state.percentLabel,
                          style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w900, height: 1)),
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
                    const _PermissionBanner(
                      title: '还差一步：打开“使用情况访问权限”',
                      body: '只用来算你今天刷了多久，数据只在手机上，不上传 app 记录。',
                      action: '去打开',
                      onOpen: UsageChannel.openPermissionSettings,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (ScreenTimeChannel.isSupported && !state.screenTimeActive) ...[
                    _PermissionBanner(
                      title: '还差一步：打开“屏幕使用时间”',
                      body: 'iOS 只告诉我们你到了哪个阶段，拿不到具体时长。想统计整台手机，选 App 时把类别全部选上。数据只在手机上，不上传。',
                      action: '去开启',
                      onOpen: () => _runScreenTime(state.enableScreenTime),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (state.screenTimeGoalMismatch) ...[
                    _PermissionBanner(
                      title: '正在按测试目标统计',
                      body: '验证页按 ${DogMeter.formatMinutes(state.screenTime!.goalMinutes)} 的目标在统计，和你的每日目标不一样。',
                      action: '改回每日目标',
                      onOpen: () => _runScreenTime(state.restartScreenTime),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _ProgressCard(
                    used: state.minutesUsedLabel,
                    goal: state.goalMinutes,
                    percent: state.percent,
                    hint: _hint(state),
                  ),
                  const SizedBox(height: 12),
                  if (state.usage.stageOnly)
                    const Text('iOS 只告诉 App 用量到了哪个阶段，拿不到准确时长、拿起次数和 23 点后的用时。', style: PopText.small)
                  else
                    Row(
                      children: [
                        Expanded(child: _Stat(label: '拿起手机', value: '${state.usage.pickups} 次')),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _Stat(label: '23 点后', value: DogMeter.formatMinutes(state.usage.lateNightMinutes))),
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
                  _EntryCard(
                    icon: Icons.leaderboard_outlined,
                    title: '今日 App 排行',
                    subtitle: '看看时间都花在哪了',
                    onTap: () => context.push('/ranking'),
                  ),
                  const SizedBox(height: 10),
                  _EntryCard(
                    icon: Icons.calendar_month_outlined,
                    title: '历史记录',
                    subtitle: '这周变狗了几天',
                    onTap: () => context.push('/history'),
                  ),
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

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Pop.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Pop.ink, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: Pop.ink),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                    Text(subtitle, style: PopText.small),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Pop.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.title, required this.body, required this.action, required this.onOpen});

  final String title;
  final String body;
  final String action;
  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: Pop.card(color: Pop.softYellow, shadow: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(body, style: const TextStyle(fontSize: 13, height: 1.5)),
          const SizedBox(height: 10),
          PopButton(label: action, style: PopButtonStyle.dark, height: 46, onPressed: onOpen),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.used, required this.goal, required this.percent, required this.hint});

  /// 已刷时长的显示文字（iOS 上是“至少 …”或“不到 …”）
  final String used;
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // iOS 上是“至少 …”，文字更长，放不下时换行，不挤掉右边的目标
              Expanded(child: Text('今日已刷 $used', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
              const SizedBox(width: 8),
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
