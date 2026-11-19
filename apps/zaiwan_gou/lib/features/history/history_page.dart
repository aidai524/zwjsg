import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_state.dart';
import '../../core/breeds.dart';
import '../../core/dog_meter.dart';
import '../../core/history.dart';
import '../../widgets/my_avatar.dart';

/// 历史记录：最近 7 天 / 按月看每天的狗度和形态。数据只在手机上。
class HistoryPage extends StatefulWidget {
  /// [today] 只在测试里传
  const HistoryPage({super.key, this.today});

  final DateTime? today;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late final DateTime _today = _dateOnly(widget.today ?? DateTime.now());
  bool _byMonth = false;
  late DateTime _month = DateTime(_today.year, _today.month);

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final records = AppScope.of(context).history.all();
    return Scaffold(
      appBar: AppBar(title: const Text('每天的记录')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(
              children: [
                ChoiceChip(
                  label: const Text('最近 7 天'),
                  selected: !_byMonth,
                  onSelected: (_) => setState(() => _byMonth = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('按月'),
                  selected: _byMonth,
                  onSelected: (_) => setState(() => _byMonth = true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_byMonth) ..._monthView(records) else ..._weekView(records),
            const SizedBox(height: 16),
            const Text('按你当天最后一次打开 App 时记录，只存在手机上。iOS 只知道到了哪个阶段。', style: PopText.small),
          ],
        ),
      ),
    );
  }

  List<Widget> _weekView(Map<String, DayRecord> records) {
    final days = [for (var i = 0; i < 7; i++) _today.subtract(Duration(days: i))];
    return [
      _Summary(records: [for (final d in days) records[AppState.localDate(d)]]),
      const SizedBox(height: 12),
      for (final d in days) _DayRow(date: d, record: records[AppState.localDate(d)], isToday: d == _today),
    ];
  }

  List<Widget> _monthView(Map<String, DayRecord> records) {
    final first = _month;
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final leading = first.weekday - 1; // 周一开头
    final isCurrent = first.year == _today.year && first.month == _today.month;
    final monthDays = [for (var i = 1; i <= daysInMonth; i++) DateTime(first.year, first.month, i)];
    return [
      Row(
        children: [
          IconButton(
            tooltip: '上个月',
            onPressed: () => setState(() => _month = DateTime(first.year, first.month - 1)),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text('${first.year} 年 ${first.month} 月', textAlign: TextAlign.center, style: PopText.h2),
          ),
          IconButton(
            tooltip: '下个月',
            onPressed: isCurrent ? null : () => setState(() => _month = DateTime(first.year, first.month + 1)),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      _Summary(records: [for (final d in monthDays) records[AppState.localDate(d)]]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Pop.white, borderRadius: BorderRadius.circular(16)),
        child: GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.72,
          children: [
            for (final w in _weekdays) Center(child: Text(w, style: PopText.label)),
            for (var i = 0; i < leading; i++) const SizedBox.shrink(),
            for (final d in monthDays)
              _MonthCell(date: d, record: records[AppState.localDate(d)], isToday: d == _today),
          ],
        ),
      ),
    ];
  }
}

/// 做人几天、变狗几天（只算有记录的日子）
class _Summary extends StatelessWidget {
  const _Summary({required this.records});

  final List<DayRecord?> records;

  @override
  Widget build(BuildContext context) {
    final recorded = records.whereType<DayRecord>().toList();
    final human = recorded.where((r) => r.stage == 0).length;
    final text = recorded.isEmpty
        ? '这段时间还没有记录'
        : '记录了 ${recorded.length} 天：做人 $human 天，变狗 ${recorded.length - human} 天';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: Pop.card(color: Pop.softYellow, shadow: false),
      child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.date, required this.record, required this.isToday});

  final DateTime date;
  final DayRecord? record;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final weekday = _HistoryPageState._weekdays[date.weekday - 1];
    final breed = breedByKey(r?.breedKey);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
      decoration: BoxDecoration(
        color: Pop.white,
        borderRadius: BorderRadius.circular(16),
        border: isToday ? Border.all(color: Pop.ink, width: 2) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              isToday ? '今天' : '${date.month}月${date.day}日\n周$weekday',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.3),
            ),
          ),
          SizedBox(width: 44, height: 44, child: r == null ? null : MyAvatar(stage: r.stage, size: 44)),
          const SizedBox(width: 10),
          Expanded(
            child: r == null
                ? const Text('没打开 App，没记录', style: PopText.small)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DogMeter.stageNames[r.stage.clamp(0, DogMeter.stageNames.length - 1)],
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                      Text(
                        breed == null ? '目标 ${DogMeter.formatMinutes(r.goalMinutes)}' : '变成了${breed.name}',
                        style: PopText.small,
                      ),
                    ],
                  ),
          ),
          if (r != null) Text(r.percentLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({required this.date, required this.record, required this.isToday});

  final DateTime date;
  final DayRecord? record;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: isToday ? Border.all(color: Pop.ink, width: 2) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${date.day}', style: TextStyle(fontSize: 12, color: r == null ? Pop.muted : Pop.ink)),
          const SizedBox(height: 2),
          SizedBox(width: 28, height: 28, child: r == null ? null : MyAvatar(stage: r.stage, size: 28)),
        ],
      ),
    );
  }
}
