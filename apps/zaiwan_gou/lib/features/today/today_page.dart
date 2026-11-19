import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_lock.dart';
import '../../core/app_state.dart';
import '../../core/dog_meter.dart';
import 'package:pop_ui/pop_ui.dart';
import '../../core/screen_time_channel.dart';
import '../../core/usage_channel.dart';

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
                    child: MyAvatar(stage: stage, size: 184),
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
                    child: Text(state.hasUsageData ? DogMeter.stageNames[stage] : '还没开始统计',
                        style: const TextStyle(color: Pop.yellow, fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 8),
                  Text(state.hasUsageData ? DogMeter.quips[stage] : '开了权限，才知道你今天有多狗',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
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
                  if (state.hasUsageData) ...[
                    _ProgressCard(
                      used: state.minutesUsedLabel,
                      goal: state.goalMinutes,
                      percent: state.percent,
                      hint: _hint(state),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // 单个 App 限时（超时来电）放在前面，比排行更显眼
                  LimitsCard(service: widget.lockService),
                  const SizedBox(height: 12),
                  // 卡片上直接露出前三名和这周 7 天，点开再看全部
                  TimeSpentCard(loader: widget.rankingLoader),
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
