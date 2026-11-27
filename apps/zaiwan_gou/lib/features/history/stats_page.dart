import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_state.dart';
import '../../core/breeds.dart';
import '../../core/dog_meter.dart';
import '../../core/history.dart';
import '../../core/history_stats.dart';
import '../../core/screen_time_channel.dart';
import '../../core/usage_channel.dart';
import '../../widgets/my_avatar.dart';

/// 狗度统计：最近 7 / 30 / 90 天的平均用时、做人和变狗天数、最长连续做人、最狗的一天、
/// 每天的柱状图、各阶段分布、星期几最容易变狗、变成过的犬种、最近 7 天最费时间的 App。
/// 数据只用手机上的真实记录（安卓能补上系统还留着的前几天，iOS 用监控扩展记的每天最高阶段）。
class StatsPage extends StatefulWidget {
  /// [today]、[rankingLoader] 只在测试里传
  const StatsPage({super.key, this.today, this.rankingLoader});

  final DateTime? today;

  /// 最近几天的 App 排行（安卓）；不传用系统的
  final Future<List<AppUsage>> Function(int days)? rankingLoader;

  static const ranges = [7, 30, 90];

  /// 最费时间的 App 看最近几天：系统一般只留 7–10 天的明细
  static const rankingDays = 7;

  /// 一段时间的“最长连续做人”标题下那句话
  static String streakNote(int streak) => streak >= 7 ? '够格变传说「狼」了' : '连做 7 天变传说「狼」';

  /// 和前一段比的那句话。分钟数差 5 分钟以内算“差不多”
  static String? compareLine(HistoryStats now, HistoryStats before) {
    if (now.recordedDays == 0 || before.recordedDays == 0) return null;
    final n = now.days.length;
    final String first;
    final bool same, better;
    if (now.stageOnly || before.stageOnly) {
      final diff = ((now.averageStage! - before.averageStage!) * 10).round() / 10;
      same = diff == 0;
      better = diff < 0;
      first = same ? '平均阶段和前 $n 天一样' : '平均阶段比前 $n 天${diff > 0 ? '高' : '低'} ${diff.abs().toStringAsFixed(1)}';
    } else {
      final diff = now.averageMinutes! - before.averageMinutes!;
      same = diff.abs() < 5;
      better = diff < 0;
      first = same ? '每天刷的和前 $n 天差不多' : '比前 $n 天每天${diff > 0 ? '多' : '少'}刷 ${DogMeter.formatMinutes(diff.abs())}';
    }
    final human = now.humanDays - before.humanDays;
    final parts = [first, if (human != 0) '做人${human > 0 ? '多' : '少'}了 ${human.abs()} 天'];
    return '${parts.join('，')}${same ? '' : (better ? '，有点人样了' : '，狗味更重了')}';
  }

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  int _range = StatsPage.ranges.first;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final all = state.history.all();
    final today = widget.today ?? DateTime.now();
    final stats = HistoryStats.lastDays(all, _range, today: today);
    final compare = StatsPage.compareLine(stats, stats.previous(all));
    final showApps = widget.rankingLoader != null || UsageChannel.isSupported || ScreenTimeChannel.isSupported;

    return Scaffold(
      appBar: AppBar(title: const Text('狗度统计')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final r in StatsPage.ranges)
                  ChoiceChip(
                    label: Text('最近 $r 天'),
                    selected: _range == r,
                    onSelected: (_) => setState(() => _range = r),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (stats.recordedDays == 0)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: Pop.card(color: Pop.softYellow, shadow: false),
                child: Text(
                  state.hasUsageData ? '这 $_range 天还没有记录。每天打开看一眼，这里就有数了。' : '还没拿到数据。回“今天”页开了权限，这里就开始记。',
                  style: PopText.body,
                ),
              )
            else ...[
              _Overview(stats: stats, goal: state.goalMinutes),
              if (compare != null) ...[
                const SizedBox(height: 12),
                Text(compare, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ],
              _Section(
                title: stats.stageOnly ? '每天到了第几阶段' : '每天刷了多久',
                child: _DailyBars(stats: stats, goal: state.goalMinutes, today: today),
              ),
              _Section(title: '变狗程度分布', child: _StageDistribution(stats: stats)),
              _Section(title: '星期几最容易变狗', child: _WeekdayBars(stats: stats)),
              _Section(title: '变成过的犬种', child: _Breeds(stats: stats)),
            ],
            if (showApps)
              _Section(
                title: '最近 ${StatsPage.rankingDays} 天最费时间的 App',
                child: ScreenTimeChannel.isSupported
                    ? _IosTopApps(authorized: state.screenTime?.authorized ?? false)
                    : _AndroidTopApps(loader: widget.rankingLoader ?? (d) => UsageChannel.ranking(days: d)),
              ),
            const SizedBox(height: 20),
            Material(
              color: Pop.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Pop.ink, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                title: const Text('每天的记录', style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: const Text('按周、按月看每一天'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/history'),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              ScreenTimeChannel.isSupported
                  ? '只用手机上的记录，不上传。iOS 只知道每天到了第几阶段，时长是下限，判断不了犬种。'
                  : '只用手机上的记录。没打开 App 的日子，从系统补上最近 ${AppState.backfillDays} 天的数据；更早的只有打开过的日子。',
              style: PopText.small,
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: PopText.h2),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// 总览四格：平均每天、做人 / 变狗、最长连续做人、最狗的一天
class _Overview extends StatelessWidget {
  const _Overview({required this.stats, required this.goal});

  final HistoryStats stats;
  final int goal;

  static String _short(int stage) => DogMeter.stageNames[stage].split(' · ').last;

  @override
  Widget build(BuildContext context) {
    final worst = stats.worstDay!;
    final worstDate = DateTime.parse(worst.date);
    final average = stats.stageOnly
        ? ('阶段 ${stats.averageStage!.toStringAsFixed(1)}', '按阶段算，iOS 拿不到时长')
        : (
            '${stats.minutesAreLowerBound ? '至少 ' : ''}${DogMeter.formatMinutes(stats.averageMinutes!)}',
            '每天的额度 ${DogMeter.formatMinutes(goal)}',
          );
    final tiles = [
      _Tile(title: '平均每天', value: average.$1, note: average.$2),
      _Tile(title: '做人 / 变狗', value: '${stats.humanDays} / ${stats.dogDays} 天', note: '记录了 ${stats.recordedDays} 天'),
      _Tile(
        title: '最长连续做人',
        value: '${stats.longestHumanStreak} 天',
        note: StatsPage.streakNote(stats.longestHumanStreak),
      ),
      _Tile(
        title: '最狗的一天',
        value: '${worstDate.month} 月 ${worstDate.day} 日',
        note: '${worst.percentLabel} · ${_short(worst.stage)}',
      ),
    ];
    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[row * 2]),
                const SizedBox(width: 12),
                Expanded(child: tiles[row * 2 + 1]),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.title, required this.value, required this.note});

  final String title;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: Pop.card(shadow: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: PopText.label),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 2),
          Text(note, style: PopText.small),
        ],
      ),
    );
  }
}

/// 每天一根柱子：安卓按分钟数（虚线是每天的额度），iOS 按阶段。做人白色，变狗黄色，没记录只画个点
class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.stats, required this.goal, required this.today});

  final HistoryStats stats;
  final int goal;
  final DateTime today;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  static String _date(String yyyyMmDd) {
    final d = DateTime.parse(yyyyMmDd);
    return '${d.month} 月 ${d.day} 日';
  }

  @override
  Widget build(BuildContext context) {
    final days = stats.days;
    final n = days.length;
    final worst = stats.worstDay!;
    final summary = stats.stageOnly
        ? '最近 $n 天，平均到阶段 ${stats.averageStage!.toStringAsFixed(1)}'
        : '最近 $n 天，平均每天 ${DogMeter.formatMinutes(stats.averageMinutes!)}，最多的是 ${_date(worst.date)}，${DogMeter.formatMinutes(worst.minutes)}';
    String label(int i) {
      final d = days[i];
      if (i == n - 1) return '今天';
      if (n <= 7) return _weekdays[d.weekday - 1];
      return '${d.month}/${d.day}';
    }

    final labelAt = n <= 7 ? [for (var i = 0; i < n; i++) i] : [0, n ~/ 2, n - 1];
    return Semantics(
      container: true,
      label: summary,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        decoration: Pop.card(shadow: false),
        child: Column(
          children: [
            SizedBox(
              height: 140,
              child: CustomPaint(
                size: Size.infinite,
                painter: _BarsPainter(records: stats.perDay, goal: goal, byStage: stats.stageOnly),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < labelAt.length; i++) ...[
                  if (i > 0) const Spacer(),
                  Text(label(labelAt[i]), style: PopText.small),
                ],
              ],
            ),
            if (!stats.stageOnly) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  CustomPaint(size: const Size(18, 2), painter: _DashPainter()),
                  const SizedBox(width: 6),
                  Text('每天的额度 ${DogMeter.formatMinutes(goal)}', style: PopText.small),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.records, required this.goal, required this.byStage});

  final List<DayRecord?> records;
  final int goal;
  final bool byStage;

  @override
  void paint(Canvas canvas, Size size) {
    final n = records.length;
    final gap = n <= 7 ? 10.0 : (n <= 30 ? 3.0 : 1.0);
    final width = math.max(1.0, (size.width - gap * (n - 1)) / n);
    final maxMinutes = records.fold<int>(0, (m, r) => math.max(m, r?.minutes ?? 0));
    final top = byStage ? 5.0 : math.max(goal * 1.5, maxMinutes.toDouble());
    final ink = Paint()
      ..color = Pop.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = n <= 30 ? 1.5 : 0.8;
    for (var i = 0; i < n; i++) {
      final r = records[i];
      final x = i * (width + gap);
      if (r == null) {
        canvas.drawCircle(Offset(x + width / 2, size.height - 2), math.min(2, width / 2), Paint()..color = Pop.gray);
        continue;
      }
      final value = byStage ? r.stage.toDouble() : r.minutes.toDouble();
      final h = math.max(3.0, value / top * size.height);
      final rect = Rect.fromLTWH(x, size.height - h, width, h);
      final rr = RRect.fromRectAndCorners(rect,
          topLeft: Radius.circular(math.min(4, width / 2)), topRight: Radius.circular(math.min(4, width / 2)));
      canvas.drawRRect(rr, Paint()..color = r.stage == 0 ? Pop.white : Pop.yellow);
      canvas.drawRRect(rr, ink);
    }
    if (!byStage) {
      // 每天的额度：虚线
      final y = size.height - goal / top * size.height;
      final dash = Paint()
        ..color = Pop.ink
        ..strokeWidth = 1.5;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), dash);
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.records != records || old.goal != goal || old.byStage != byStage;
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Pop.ink
      ..strokeWidth = size.height;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(math.min(x + 4, size.width), size.height / 2), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => false;
}

/// 0–5 每个阶段各有几天
class _StageDistribution extends StatelessWidget {
  const _StageDistribution({required this.stats});

  final HistoryStats stats;

  @override
  Widget build(BuildContext context) {
    final counts = stats.stageCounts;
    final most = counts.reduce(math.max);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
      decoration: Pop.card(shadow: false),
      child: Column(
        children: [
          for (var s = 0; s < counts.length; s++)
            Semantics(
              container: true,
              label: '${_Overview._short(s)}：${counts[s]} 天',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    MyAvatar(stage: s, size: 32, evolved: false),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 52,
                      child:
                          Text(_Overview._short(s), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: most == 0 ? 0 : math.max(0.02, counts[s] / most),
                          child: Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: s == 0 ? Pop.white : Pop.yellow,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Pop.ink, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 40,
                      child: Text('${counts[s]} 天', textAlign: TextAlign.right, style: PopText.small),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 周一到周日的平均：安卓按分钟数，iOS 按阶段。最高的那天标黄
class _WeekdayBars extends StatelessWidget {
  const _WeekdayBars({required this.stats});

  final HistoryStats stats;

  static const _names = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final values = stats.stageOnly ? stats.weekdayStages : stats.weekdayMinutes;
    final known = [
      for (final v in values)
        if (v != null) v
    ];
    final top = known.isEmpty ? 1.0 : math.max(known.reduce(math.max), 1.0);
    final worst = known.isEmpty ? null : values.indexOf(known.reduce(math.max));
    String show(double v) => stats.stageOnly ? '阶段 ${v.toStringAsFixed(1)}' : DogMeter.formatMinutes(v.round());
    final line = worst == null || known.length < 2
        ? '记录再多几天，就能看出星期几最容易变狗'
        : '周${_names[worst]}最狗，平均${stats.stageOnly ? '到' : '刷'} ${show(values[worst]!)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: Pop.card(shadow: false),
      child: Column(
        children: [
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var w = 0; w < 7; w++)
                  Expanded(
                    child: Semantics(
                      container: true,
                      label: '周${_names[w]}：${values[w] == null ? '没有记录' : '平均 ${show(values[w]!)}'}',
                      excludeSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: values[w] == null
                            ? const SizedBox.shrink()
                            : Container(
                                height: math.max(4, values[w]! / top * 96),
                                decoration: BoxDecoration(
                                  color: w == worst ? Pop.yellow : Pop.white,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                                  border: Border.all(color: Pop.ink, width: 1.5),
                                ),
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final name in _names) Expanded(child: Text(name, textAlign: TextAlign.center, style: PopText.small)),
            ],
          ),
          const SizedBox(height: 8),
          Text(line, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Breeds extends StatelessWidget {
  const _Breeds({required this.stats});

  final HistoryStats stats;

  @override
  Widget build(BuildContext context) {
    final counts = stats.breedCounts;
    if (counts.isEmpty) {
      final text = stats.dogDays == 0 ? '这段时间天天做人，一次狗都没变' : (stats.stageOnly ? 'iOS 只知道阶段，判断不了犬种' : '还没有犬种记录');
      return Text(text, style: PopText.bodyMuted);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final MapEntry(key: key, value: count) in counts)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Pop.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Pop.ink, width: 2),
            ),
            child: Text('${breedByKey(key)?.name ?? key} × $count',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}

/// 安卓：最近 7 天最费时间的 5 个 App。名称和图标只在手机上显示，不上传
class _AndroidTopApps extends StatefulWidget {
  const _AndroidTopApps({required this.loader});

  final Future<List<AppUsage>> Function(int days) loader;

  @override
  State<_AndroidTopApps> createState() => _AndroidTopAppsState();
}

class _AndroidTopAppsState extends State<_AndroidTopApps> {
  late final Future<List<AppUsage>> _apps = widget.loader(StatsPage.rankingDays);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AppUsage>>(
      future: _apps,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(color: Pop.ink)));
        }
        if (snap.hasError) {
          final noPermission = snap.error is PlatformException;
          return Text(noPermission ? '开了“使用情况访问权限”才能看' : '没读出来，稍后再试', style: PopText.bodyMuted);
        }
        final apps = (snap.data ?? const []).take(5).toList();
        if (apps.isEmpty) return const Text('这几天还没有用满 1 分钟的 App', style: PopText.bodyMuted);
        final most = apps.first.minutes;
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          decoration: Pop.card(shadow: false),
          child: Column(
            children: [
              for (var i = 0; i < apps.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(width: 20, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900))),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: apps[i].icon == null
                            ? Container(width: 32, height: 32, color: Pop.gray)
                            : Image.memory(apps[i].icon!, width: 32, height: 32),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(apps[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            FractionallySizedBox(
                              widthFactor: (apps[i].minutes / most).clamp(0.04, 1.0),
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
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(DogMeter.formatMinutes(apps[i].minutes),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// iOS：系统的报告扩展画最近 7 天的排行，App 读不到这些数字
class _IosTopApps extends StatelessWidget {
  const _IosTopApps({required this.authorized});

  final bool authorized;

  @override
  Widget build(BuildContext context) {
    if (!authorized) return const Text('授权“屏幕使用时间”后才能看', style: PopText.bodyMuted);
    return Container(
      height: 380,
      decoration: Pop.card(shadow: false),
      clipBehavior: Clip.antiAlias,
      child: const UiKitView(
        viewType: 'zwjsg/screen_time_report',
        creationParams: {'days': StatsPage.rankingDays},
        creationParamsCodec: StandardMessageCodec(),
      ),
    );
  }
}
