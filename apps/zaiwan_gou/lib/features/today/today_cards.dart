import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_lock.dart';
import '../../core/app_state.dart';
import '../../core/dog_meter.dart';
import '../../core/evolution.dart';
import '../../core/history.dart';
import '../../core/screen_time_channel.dart';
import '../../core/usage_channel.dart';
import '../../widgets/my_avatar.dart';

/// “今天”页上的白卡：标题、右上角的“全部 ›”，整张卡都能点；[footer] 是卡片底下单独能点的一行
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.title, required this.more, required this.onTap, required this.child, this.footer});

  final String title;
  final String more;
  final VoidCallback onTap;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Pop.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Pop.ink, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
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
          if (footer != null) ...[
            const Divider(height: 1.5, thickness: 1.5, color: Pop.gray),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// 今天时间去哪了：一句吐槽 + 前五名，点开看完整排行。
/// 超时来电不单独占一张卡：设了限时的 App 在排行里带一个电话标记（超时了是红的），卡片底下一行说限时用到哪了。
/// 隐私约定：App 名称和用时只在手机上显示，不上传。iOS 上由系统的报告扩展画，Flutter 拿不到数字。
class TimeSpentCard extends StatefulWidget {
  /// [loader]、[lockService] 只在测试里传，代替原生层的今日排行和超时来电
  const TimeSpentCard({super.key, this.loader, this.lockService});

  final Future<List<AppUsage>> Function()? loader;
  final LockService? lockService;

  /// 卡片上露出几名
  static const shown = 5;

  /// 排行上面那句：最费时间的 App 占了今天多少。iOS 报告扩展里是同一个规则（ios/ScreenTimeReport/）
  static String headline(List<AppUsage> items) {
    final total = items.fold<int>(0, (sum, a) => sum + a.minutes);
    final top = items.first;
    final pct = (top.minutes * 100 / math.max(1, total)).round();
    return pct >= 40 ? '“${top.label}”一个就占了今天的 $pct%' : '最费时间的是“${top.label}”，占今天的 $pct%';
  }

  /// 卡片底下那行（跟在“超时来电”后面）：限时用到哪了。先说拒接了、今天锁死的，再说正在“再玩”的，再说已经超时的，再说离限时最近的；
  /// 没设就引导去设。一行放得下，所以写得短
  static String limitsLine(List<AppLock> locks) {
    if (locks.isEmpty) return '给最上头的 App 设个限时';
    final more = locks.length > 1 ? ' · 共 ${locks.length} 个' : '';
    for (final l in locks) {
      if (l.declined) return '${l.title} 今天锁死了$more';
    }
    for (final l in locks) {
      if (l.graceActive) return '${l.title} 再玩中$more';
    }
    for (final l in locks) {
      if (l.locked) return '${l.title} ${l.byDog ? '狗度到了' : '已超时'}$more';
    }
    // 按狗度来的没有倒计时，只看按额度的
    final measured = [for (final l in locks) if (l.usedMinutes != null && !l.byDog) l]
      ..sort((a, b) => (a.minutes - a.usedMinutes!).compareTo(b.minutes - b.usedMinutes!));
    // iOS 拿不到每个限时用了多久
    if (measured.isEmpty) return '已设 ${locks.length} 个，用满了狗会打电话来';
    final soon = measured.first;
    return '${soon.title} 还剩 ${DogMeter.formatMinutes((soon.minutes - soon.usedMinutes!).clamp(0, soon.minutes))}$more';
  }

  @override
  State<TimeSpentCard> createState() => _TimeSpentCardState();
}

class _TimeSpentCardState extends State<TimeSpentCard> with WidgetsBindingObserver {
  late final LockService? _lockService = widget.lockService ?? LockService.platform;
  List<AppLock>? _locks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLocks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从别的 App 回来时刷新：限时用了多久变了
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadLocks();
  }

  Future<void> _loadLocks() async {
    final service = _lockService;
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
    final state = AppScope.of(context);
    void openRanking() => context.push('/ranking');
    final locks = _locks;

    final Widget body;
    if (widget.loader != null || UsageChannel.isSupported) {
      body = _AndroidTopApps(
        loader: widget.loader ?? UsageChannel.todayRanking,
        refreshKey: state.minutesUsed,
        locks: locks ?? const [],
      );
    } else if (ScreenTimeChannel.isSupported) {
      body = state.screenTime?.authorized == true
          ? _IosTopApps(onTap: openRanking)
          : const Text('授权“屏幕使用时间”后，这里显示今天最费时间的 ${TimeSpentCard.shown} 个 App', style: PopText.small);
    } else {
      body = const Text('这台设备拿不到使用数据', style: PopText.small);
    }

    return _TodayCard(
      title: '今天时间去哪了',
      more: '全部',
      onTap: openRanking,
      footer: _lockService == null || locks == null
          ? null
          : _LimitsFooter(
              text: TimeSpentCard.limitsLine(locks),
              alert: locks.any((l) => l.locked),
              onTap: () async {
                await context.push('/locks');
                await _loadLocks();
              },
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          // iOS 拿不到拿起次数和 23 点后的用时；还没拿到数据时也不写
          if (state.hasUsageData && !state.usage.stageOnly) ...[
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

/// 卡片底下的超时来电：一个电话图标、一句状态，点了去管理限时
class _LimitsFooter extends StatelessWidget {
  const _LimitsFooter({required this.text, required this.alert, required this.onTap});

  final String text;

  /// 有限时今天已经超时：图标标红
  final bool alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 11),
        child: Row(
          children: [
            Icon(Icons.phone_in_talk, size: 18, color: alert ? Pop.kingRed : Pop.ink),
            const SizedBox(width: 6),
            const Text('超时来电', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: alert ? Pop.kingRed : Pop.muted)),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Pop.muted),
          ],
        ),
      ),
    );
  }
}

class _AndroidTopApps extends StatefulWidget {
  const _AndroidTopApps({required this.loader, required this.refreshKey, required this.locks});

  final Future<List<AppUsage>> Function() loader;

  /// 今天的总分钟数，变了就重新读
  final int refreshKey;

  /// 超时来电：排行里设了限时的 App 带个标记
  final List<AppLock> locks;

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
          ? '打开“使用情况访问权限”后，这里显示今天最费时间的 ${TimeSpentCard.shown} 个 App'
          : '读不到使用数据，下拉刷新再试');
    }
  }

  AppLock? _lockOf(AppUsage app) {
    for (final l in widget.locks) {
      if (l.packages.contains(app.package)) return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    if (message != null) return Text(message, style: PopText.small);
    final items = _items;
    // 读本机数据很快，不放转圈动画
    if (items == null) return const SizedBox(height: 24);
    if (items.isEmpty) return const Text('今天还没有用满 1 分钟的 App', style: PopText.small);

    final top = items.take(TimeSpentCard.shown).toList();
    final most = math.max(1, top.first.minutes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(TimeSpentCard.headline(items), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final (i, app) in top.indexed)
          _MiniRankRow(rank: i + 1, app: app, fill: app.minutes / most, lock: _lockOf(app)),
      ],
    );
  }
}

class _MiniRankRow extends StatelessWidget {
  const _MiniRankRow({required this.rank, required this.app, required this.fill, this.lock});

  final int rank;
  final AppUsage app;

  /// 进度条长度：和第一名相比
  final double fill;

  /// 这个 App 设了超时来电
  final AppLock? lock;

  @override
  Widget build(BuildContext context) {
    final icon = app.icon;
    final over = lock?.locked ?? false;
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
                  color: over ? Pop.kingRed : Pop.yellow,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Pop.ink, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(DogMeter.formatMinutes(app.minutes), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          SizedBox(
            width: 22,
            child: lock == null
                ? null
                : Semantics(
                    container: true,
                    label: over ? '超时来电：今天已超时' : '设了超时来电',
                    child: Icon(Icons.phone_in_talk, size: 16, color: over ? Pop.kingRed : Pop.ink),
                  ),
          ),
        ],
      ),
    );
  }
}

/// iOS：系统报告扩展画的精简版（一句话 + 前五名），嵌在卡片里。
/// 上面盖一层透明的点击区域，点哪里都是打开完整排行，报告视图本身不接触摸。
class _IosTopApps extends StatelessWidget {
  const _IosTopApps({required this.onTap});

  final VoidCallback onTap;

  /// 报告扩展里精简版的高度：一句话 + 五行（ios/ScreenTimeReport/ScreenTimeReport.swift 的 TopAppsCompactView）
  static const height = 176.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
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

/// 这周：一句小结、每天一根柱子（头上是那天的形象），再加上连续做人几天、离传说「狼」还差几天。
/// 连续做人 7 天变传说犬种“狼”，安卓最终由服务端判定，这里只按手机上的记录给个进度。
class WeekCard extends StatelessWidget {
  /// [today] 只在测试里传
  const WeekCard({super.key, this.today});

  final DateTime? today;

  /// 连续做人多少天变狼，和后端 config/dog.php 里的规则一致
  static const wolfDays = DogMeter.legendStreakDays;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// 从昨天往前数，连续做人（有记录、阶段 0）的天数。没打开 App 的那天没有记录，算断了
  static int humanStreak(Map<String, DayRecord> records, DateTime today) => humanStreakBefore(records, today);

  /// 进度那句话。[humanToday]：今天到现在还是人
  static String streakLine(int streak, {required bool humanToday, bool knownToday = true}) {
    if (!knownToday) return streak == 0 ? '开了权限，才开始数连续做人' : '连续做人 $streak 天，今天的数据还没拿到';
    if (!humanToday) return streak == 0 ? '今天已经变狗了，明天重新做人' : '连续做人 $streak 天，今天破功了，明天重新数';
    if (streak >= wolfDays) return '已经连续做人 $streak 天，够格变传说「狼」了';
    if (streak == 0) return '今天守住，就是连续做人第 1 天';
    return '连续做人 $streak 天，今天守住就是 ${streak + 1} 天';
  }

  /// 这周到今天为止的小结：做人几天、变狗几天；有准确分钟数时（安卓）再加上日均用了多久
  static String summary(List<DayRecord> days) {
    if (days.isEmpty) return '这周还没有记录';
    final human = days.where((d) => d.stage == 0).length;
    final parts = ['做人 $human 天', '变狗 ${days.length - human} 天'];
    if (days.every((d) => !d.stageOnly)) {
      final avg = (days.fold<int>(0, (sum, d) => sum + d.minutes) / days.length).round();
      parts.add('日均 ${DogMeter.formatMinutes(avg)}');
    }
    return parts.join(' · ');
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
    final todayRecord = knownToday
        ? DayRecord(
            date: AppState.localDate(day0),
            goalMinutes: state.goalMinutes,
            minutes: state.minutesUsed,
            percent: state.percent,
            percentLabel: state.percentLabel,
            stage: state.stage,
            stageOnly: state.usage.stageOnly,
          )
        : null;

    final columns = <_DayColumn>[];
    final known = <DayRecord>[];
    for (var i = 0; i < 7; i++) {
      final day = DateTime(monday.year, monday.month, monday.day + i);
      final weekday = '周${_weekdays[i]}';
      if (day.isAfter(day0)) {
        columns.add(_DayColumn(label: _weekdays[i], weekday: weekday, future: true));
        continue;
      }
      final isToday = day == day0;
      final r = isToday ? todayRecord : records[AppState.localDate(day)];
      if (r != null) known.add(r);
      columns.add(_DayColumn(label: isToday ? '今天' : _weekdays[i], weekday: weekday, record: r, isToday: isToday));
    }

    return _TodayCard(
      title: '这周',
      more: '看统计',
      onTap: () => context.push('/stats'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(summary(known), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _WeekChart(columns: columns),
          const SizedBox(height: 12),
          Text(streakLine(streak, humanToday: humanToday, knownToday: knownToday),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < wolfDays; i++)
                Expanded(
                  child: Container(
                    height: 8,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: i < filled ? Pop.ink : (humanToday && i == filled ? Pop.yellow : Pop.gray),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: i < filled || (humanToday && i == filled) ? Pop.ink : Pop.gray,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              const Text('连做 $wolfDays 天变传说「狼」', style: PopText.small),
            ],
          ),
          // 下一种进化形态还差几天（连续做人 3 / 7 / 14 / 30 天各解锁一种）
          if (knownToday) ...[
            const SizedBox(height: 8),
            Text(evolutionLine(streak, state.unlockedEvolutions, humanToday: humanToday), style: PopText.small),
          ],
        ],
      ),
    );
  }
}

/// 一排 7 根柱子，后面一条虚线是每日目标（狗度 100%）
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.columns});

  final List<_DayColumn> columns;

  @override
  Widget build(BuildContext context) {
    // 目标线的高度：柱子区域从顶上往下 1/3 处（满格是狗度 150%）
    const goalTop = _DayColumn.avatar + _DayColumn.gap + _DayColumn.barMax * (1 - 100 / _DayColumn.fullPercent);
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: goalTop,
          child: CustomPaint(size: const Size.fromHeight(1), painter: _DashPainter()),
        ),
        const Positioned(
          right: 0,
          top: goalTop - 13,
          child: Text('目标', style: TextStyle(fontSize: 10, color: Pop.muted)),
        ),
        Row(children: [for (final c in columns) Expanded(child: c)]),
      ],
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Pop.muted
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 3, size.width), 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => false;
}

/// 一天一列：头上是那天的形象，下面柱子的高度是狗度（满格 150%），做人是黄的、变狗是黑的；
/// 没记录的只有一个灰圈，还没到的只有一圈浅色边
class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.label,
    required this.weekday,
    this.record,
    this.isToday = false,
    this.future = false,
  });

  final String label;
  final String weekday;
  final DayRecord? record;
  final bool isToday;
  final bool future;

  static const double avatar = 30;
  static const double gap = 4;
  static const double barMax = 54;
  static const fullPercent = 150;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final s = r?.stage;
    final String meaning;
    if (future) {
      meaning = '还没到';
    } else if (s == null) {
      meaning = '没有记录';
    } else {
      meaning = s == 0 ? '做人' : '变狗（阶段 $s）';
    }
    const faint = Color(0xFFD6D6D6);
    final barHeight = r == null ? 0.0 : math.max(4.0, barMax * (r.percent / fullPercent).clamp(0.0, 1.0));
    // 每天单独一个节点，读屏时一天一天念，不和卡片标题连成一句
    return Semantics(
      container: true,
      label: '${isToday ? '今天' : weekday}：$meaning',
      excludeSemantics: true,
      child: Column(
        children: [
          Container(
            width: avatar,
            height: avatar,
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
            child: s == null || future ? null : MyAvatar(stage: s, size: avatar - 6, evolved: isToday),
          ),
          const SizedBox(height: gap),
          SizedBox(
            height: barMax,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: r == null
                  ? null
                  : Container(
                      width: 14,
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: s == 0 ? Pop.yellow : Pop.ink,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        border: Border.all(color: Pop.ink, width: 1.5),
                      ),
                    ),
            ),
          ),
          Container(height: 2, color: future ? faint : Pop.ink),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isToday ? Pop.ink : Pop.muted,
              fontWeight: isToday ? FontWeight.w900 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
