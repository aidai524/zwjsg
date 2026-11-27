import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_lock.dart';
import '../../core/app_state.dart';
import '../../core/dog_meter.dart';
import 'package:pop_ui/pop_ui.dart';
import '../../core/screen_time_channel.dart';
import '../../core/usage_channel.dart';

import 'stage_ring.dart';
import 'today_cards.dart';
import '../../widgets/my_avatar.dart';

class TodayPage extends StatefulWidget {
  /// [rankingLoader]、[lockService] 只在测试里传，代替原生层的今日排行和单个 App 限时
  const TodayPage({super.key, this.rankingLoader, this.lockService});

  final Future<List<AppUsage>> Function()? rankingLoader;
  final LockService? lockService;

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
            // 头部：形象和狗度，直接放在页面的奶油底上
            Padding(
              padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 12, 20, 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${now.month} 月 ${now.day} 日 周${weekdays[now.weekday - 1]}',
                                style: PopText.small),
                            const Text('今天的你', style: PopText.h2),
                          ],
                        ),
                      ),
                      // 随时都能晒：打开的是此刻的卡片，到了每晚提醒的时间才是“今日结算”。
                      // 还没拿到真实数据时没什么可晒的，不显示
                      if (state.hasUsageData) _ShareChip(onTap: () => context.push('/card')),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 狗头外面一圈就是今天刷了多少：转满一圈是最后一个阶段，刻度是每个阶段的门槛
                  StageRing(
                    percent: state.hasUsageData ? state.percent : null,
                    semanticsLabel: state.hasUsageData
                        ? '今日已刷 ${state.minutesUsedLabel}，目标 ${DogMeter.formatMinutes(state.goalMinutes)}'
                        : '还没拿到今天的使用数据',
                    child: MyAvatar(stage: stage, size: 168),
                  ),
                  const SizedBox(height: 12),
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
                    child: Text(state.hasUsageData ? DogMeter.stageNames[stage] : '还没开始统计',
                        style: const TextStyle(color: Pop.yellow, fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 8),
                  Text(state.hasUsageData ? DogMeter.quips[stage] : '开了权限，才知道你今天有多狗',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  if (state.hasUsageData) ...[
                    const SizedBox(height: 12),
                    _UsageLine(used: state.minutesUsedLabel, goal: state.goalMinutes, hint: _hint(state)),
                  ],
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
                  // 卡片上直接露出前五名和这周 7 天，点开再看全部。超时来电不单独占一张卡：
                  // 设了限时的 App 在排行里带上电话标记，卡片底下一行说限时用到哪了
                  TimeSpentCard(loader: widget.rankingLoader, lockService: widget.lockService),
                  const SizedBox(height: 12),
                  const WeekCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 头部右上角的“晒一下”，打开结算卡
class _ShareChip extends StatelessWidget {
  const _ShareChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Pop.yellow,
      shape: const StadiumBorder(side: BorderSide(color: Pop.ink, width: 2)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.adaptive.share, size: 16, color: Pop.ink),
              const SizedBox(width: 4),
              const Text('晒一下', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
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

/// 圈下面一行：今日已刷多久、目标多少，再一句离下一阶段还差多少
class _UsageLine extends StatelessWidget {
  const _UsageLine({required this.used, required this.goal, required this.hint});

  /// 已刷时长的显示文字（iOS 上是“至少 …”或“不到 …”）
  final String used;
  final int goal;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
      decoration: BoxDecoration(color: Pop.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: '今日已刷 '),
              TextSpan(text: used, style: const TextStyle(fontWeight: FontWeight.w900)),
              TextSpan(text: '  ·  目标 ${DogMeter.formatMinutes(goal)}', style: const TextStyle(color: Pop.muted)),
            ]),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(hint, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Pop.muted)),
        ],
      ),
    );
  }
}
