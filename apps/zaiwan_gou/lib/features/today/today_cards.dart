import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_lock.dart';
import '../../core/app_state.dart';
import '../../core/dog_meter.dart';
import '../../core/history.dart';
import '../../core/screen_time_channel.dart';
import '../../core/usage_channel.dart';
import '../../widgets/my_avatar.dart';
import '../locks/locks_page.dart' show limitStatus;

/// “今天”页上的白卡：标题、右上角的“全部 ›”，整张卡都能点
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.title, required this.more, required this.onTap, required this.child});

  final String title;
  final String more;
  final VoidCallback onTap;
  final Widget child;

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
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
                  Text(more, style: PopText.small),
                  const Icon(Icons.chevron_right, size: 18, color: Pop.muted),
                ],
              ),
              const SizedBox(height: 8),
              Padding(padding: const EdgeInsets.only(right: 4), child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// 超时来电：直接露出每个单个 App 限时今天到哪了，还没设的话引导去设（放在“今天”页，让限时更显眼）。
/// 限时和 App 名称只在手机上，不上传。
class LimitsCard extends StatefulWidget {
  /// [service] 只在测试里传
  const LimitsCard({super.key, this.service});

  final LockService? service;

  /// 卡片上最多列几个
  static const shown = 3;

  @override
  State<LimitsCard> createState() => _LimitsCardState();
}

class _LimitsCardState extends State<LimitsCard> with WidgetsBindingObserver {
  late final LockService? _service = widget.service ?? LockService.platform;
  List<AppLock>? _locks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从别的 App 回来时刷新：用了多久变了
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final service = _service;
    if (service == null) return;
    try {
      final locks = await service.list();
      if (mounted) setState(() => _locks = locks);
    } on PlatformException {
      if (mounted) setState(() => _locks = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_service == null) return const SizedBox.shrink();
    final locks = _locks;
    return _TodayCard(
      title: '超时来电',
      more: locks == null || locks.isEmpty ? '去设置' : '管理',
      onTap: () async {
        await context.push('/locks');
        await _load();
      },
      child: locks == null
          ? const SizedBox(height: 24)
          : locks.isEmpty
              ? const Text('给最上头的 App 设个限时：到点了，你的狗会打电话问你还玩不玩。',
                  style: TextStyle(fontSize: 14, height: 1.5))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final lock in locks.take(LimitsCard.shown)) _LimitRow(lock: lock),
                    if (locks.length > LimitsCard.shown)
                      Text('还有 ${locks.length - LimitsCard.shown} 个', style: PopText.small),
                  ],
                ),
    );
  }
}

class _LimitRow extends StatelessWidget {
  const _LimitRow({required this.lock});

  final AppLock lock;

  @override
  Widget build(BuildContext context) {
    final used = lock.usedMinutes;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(lock.locked ? Icons.phone_in_talk : Icons.timer_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(lock.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Text('每天 ${DogMeter.formatMinutes(lock.minutes)}', style: PopText.small),
            ],
          ),
          if (used != null) ...[
            const SizedBox(height: 6),
            Container(
              height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Pop.ink, width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: lock.minutes == 0 ? 1 : (used / lock.minutes).clamp(0.0, 1.0),
                child: Container(color: lock.locked ? Pop.kingRed : Pop.yellow),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(limitStatus(lock), style: PopText.small),
        ],
      ),
    );
  }
}

/// 今天时间去哪了：一句吐槽 + 前三名，点开看完整排行。
/// 隐私约定：App 名称和用时只在手机上显示，不上传。iOS 上由系统的报告扩展画，Flutter 拿不到数字。
class TimeSpentCard extends StatelessWidget {
  /// [loader] 只在测试里传，代替安卓原生层
  const TimeSpentCard({super.key, this.loader});

  final Future<List<AppUsage>> Function()? loader;

  /// 排行上面那句：最费时间的 App 占了今天多少。iOS 报告扩展里是同一个规则（ios/ScreenTimeReport/）
  static String headline(List<AppUsage> items) {
    final total = items.fold<int>(0, (sum, a) => sum + a.minutes);
    final top = items.first;
    final pct = (top.minutes * 100 / math.max(1, total)).round();
    return pct >= 40 ? '“${top.label}”一个就占了今天的 $pct%' : '最费时间的是“${top.label}”，占今天的 $pct%';
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    void openRanking() => context.push('/ranking');

    final Widget body;
    if (loader != null || UsageChannel.isSupported) {
      body = _AndroidTopApps(loader: loader ?? UsageChannel.todayRanking, refreshKey: state.minutesUsed);
    } else if (ScreenTimeChannel.isSupported) {
      body = state.screenTime?.authorized == true
          ? _IosTopApps(onTap: openRanking)
          : const Text('授权“屏幕使用时间”后，这里显示今天最费时间的 3 个 App', style: PopText.small);
    } else {
      body = const Text('这台设备拿不到使用数据', style: PopText.small);
    }

    return _TodayCard(
      title: '今天时间去哪了',
      more: '全部',
      onTap: openRanking,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          // iOS 拿不到拿起次数和 23 点后的用时
          if (!state.usage.stageOnly) ...[
            const SizedBox(height: 10),
            Text(
              '拿起手机 ${state.usage.pickups} 次 · 23 点后 ${DogMeter.formatMinutes(state.usage.lateNightMinutes)}',
              style: PopText.small,
            ),
          ],
        ],
      ),
    );
  }
}

class _AndroidTopApps extends StatefulWidget {
  const _AndroidTopApps({required this.loader, required this.refreshKey});

  final Future<List<AppUsage>> Function() loader;

  /// 今天的总分钟数，变了就重新读
  final int refreshKey;

  @override
  State<_AndroidTopApps> createState() => _AndroidTopAppsState();
}

class _AndroidTopAppsState extends State<_AndroidTopApps> with WidgetsBindingObserver {
  List<AppUsage>? _items;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(_AndroidTopApps old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey || old.loader != widget.loader) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从后台回来（比如刚去系统设置开了权限）时重新读
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.loader();
      if (!mounted) return;
      setState(() {
        _items = items;
        _message = null;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _message = e.code == 'NO_PERMISSION'
          ? '打开“使用情况访问权限”后，这里显示今天最费时间的 3 个 App'
          : '读不到使用数据，下拉刷新再试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    if (message != null) return Text(message, style: PopText.small);
    final items = _items;
    // 读本机数据很快，不放转圈动画
    if (items == null) return const SizedBox(height: 24);
    if (items.isEmpty) return const Text('今天还没有用满 1 分钟的 App', style: PopText.small);

    final top = items.take(3).toList();
    final most = math.max(1, top.first.minutes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(TimeSpentCard.headline(items), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final (i, app) in top.indexed) _MiniRankRow(rank: i + 1, app: app, fill: app.minutes / most),
      ],
    );
  }
}

class _MiniRankRow extends StatelessWidget {
  const _MiniRankRow({required this.rank, required this.app, required this.fill});

  final int rank;
  final AppUsage app;

  /// 进度条长度：和第一名相比
  final double fill;

  @override
  Widget build(BuildContext context) {
    final icon = app.icon;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 16, child: Text('$rank', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900))),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: icon == null
                ? const SizedBox(width: 22, height: 22, child: Icon(Icons.apps, size: 18, color: Pop.muted))
                : Image.memory(icon, width: 22, height: 22, gaplessPlayback: true),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              app.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FractionallySizedBox(
              widthFactor: fill.clamp(0.04, 1.0),
              alignment: Alignment.centerLeft,
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Pop.yellow,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Pop.ink, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(DogMeter.formatMinutes(app.minutes), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// iOS：系统报告扩展画的精简版（一句话 + 前三名），嵌在卡片里。
/// 上面盖一层透明的点击区域，点哪里都是打开完整排行，报告视图本身不接触摸。
class _IosTopApps extends StatelessWidget {
  const _IosTopApps({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 116,
      child: Stack(
        children: [
          const UiKitView(
            viewType: 'zwjsg/screen_time_report',
            creationParams: {'compact': true},
            creationParamsCodec: StandardMessageCodec(),
          ),
          Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap)),
        ],
      ),
    );
  }
}

/// 这周：一排 7 天的小形象，加上连续做人几天。
/// 连续做人 7 天变传说犬种“狼”，最终由服务端判定，这里只按手机上的记录给个进度。
class WeekCard extends StatelessWidget {
  /// [today] 只在测试里传
  const WeekCard({super.key, this.today});

  final DateTime? today;

  /// 连续做人多少天变狼，和 breeds.dart、后端 config/dog.php 里的规则一致
  static const wolfDays = 7;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// 从昨天往前数，连续做人（有记录、阶段 0）的天数。没打开 App 的那天没有记录，算断了
  static int humanStreak(Map<String, DayRecord> records, DateTime today) {
    var n = 0;
    while (true) {
      final r = records[AppState.localDate(DateTime(today.year, today.month, today.day - n - 1))];
      if (r == null || r.stage != 0) return n;
      n++;
    }
  }

  /// 进度那句话。[humanToday]：今天到现在还是人
  static String streakLine(int streak, {required bool humanToday, bool knownToday = true}) {
    if (!knownToday) return streak == 0 ? '开了权限，才开始数连续做人' : '连续做人 $streak 天，今天的数据还没拿到';
    if (!humanToday) return streak == 0 ? '今天已经变狗了，明天重新做人' : '连续做人 $streak 天，今天破功了，明天重新数';
    if (streak >= wolfDays) return '已经连续做人 $streak 天，够格变传说「狼」了';
    if (streak == 0) return '今天守住，就是连续做人第 1 天';
    return '连续做人 $streak 天，今天守住就是 ${streak + 1} 天';
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final records = state.history.all();
    final now = today ?? DateTime.now();
    final day0 = DateTime(now.year, now.month, now.day);
    final monday = DateTime(day0.year, day0.month, day0.day - (day0.weekday - 1));
    // 还没拿到今天的真实数据时，今天那格空着，不算做人也不算变狗
    final knownToday = state.hasUsageData;
    final humanToday = knownToday && state.stage == 0;
    final streak = humanStreak(records, day0);
    // 今天变狗了，进度清零；今天还是人，下一格是今天
    final filled = humanToday ? math.min(streak, wolfDays) : 0;

    _DayCell cell(int i) {
      final day = DateTime(monday.year, monday.month, monday.day + i);
      final weekday = '周${_weekdays[i]}';
      if (day == day0) {
        return _DayCell(label: '今天', weekday: weekday, stage: knownToday ? state.stage : null, isToday: true);
      }
      if (day.isAfter(day0)) return _DayCell(label: _weekdays[i], weekday: weekday, future: true);
      return _DayCell(label: _weekdays[i], weekday: weekday, stage: records[AppState.localDate(day)]?.stage);
    }

    return _TodayCard(
      title: '这周',
      more: '看统计',
      onTap: () => context.push('/stats'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [for (var i = 0; i < 7; i++) Expanded(child: cell(i))]),
          const SizedBox(height: 10),
          Text(streakLine(streak, humanToday: humanToday, knownToday: knownToday),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < wolfDays; i++)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < filled ? Pop.ink : (humanToday && i == filled ? Pop.yellow : null),
                    border: Border.all(
                      color: i < filled || (humanToday && i == filled) ? Pop.ink : const Color(0xFFC4C4C4),
                      width: 1.5,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              const Expanded(child: Text('连做 $wolfDays 天变传说「狼」', style: PopText.small)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一天一格：做人是黄底，变狗是白底，没记录是灰的，还没到的只有一圈浅色边
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.label,
    required this.weekday,
    this.stage,
    this.isToday = false,
    this.future = false,
  });

  final String label;
  final String weekday;
  final int? stage;
  final bool isToday;
  final bool future;

  @override
  Widget build(BuildContext context) {
    final s = stage;
    final String meaning;
    if (future) {
      meaning = '还没到';
    } else if (s == null) {
      meaning = '没有记录';
    } else {
      meaning = s == 0 ? '做人' : '变狗（阶段 $s）';
    }
    const faint = Color(0xFFD6D6D6);
    // 每天单独一个节点，读屏时一天一天念，不和卡片标题连成一句
    return Semantics(
      container: true,
      label: '${isToday ? '今天' : weekday}：$meaning',
      excludeSemantics: true,
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isToday ? Pop.ink : Pop.muted,
              fontWeight: isToday ? FontWeight.w900 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: future ? null : (s == null ? Pop.gray : (s == 0 ? Pop.yellow : Pop.white)),
              border: Border.all(
                color: future || s == null ? faint : Pop.ink,
                width: isToday ? 3 : (future || s == null ? 1.5 : 2),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.bottomCenter,
            child: s == null || future ? null : MyAvatar(stage: s, size: 28),
          ),
        ],
      ),
    );
  }
}
