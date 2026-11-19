import 'app_state.dart';
import 'history.dart';

/// 一段时间（含首尾两天）的历史统计，给“狗度统计”页用。
/// 只用手机上的真实记录：没有记录的日子不算进平均，也不当成做人。
class HistoryStats {
  HistoryStats(Map<String, DayRecord> all, {required DateTime from, required DateTime to})
      : days = [
          for (var d = _dateOnly(from); !d.isAfter(_dateOnly(to)); d = DateTime(d.year, d.month, d.day + 1)) d,
        ] {
    perDay = [for (final d in days) all[AppState.localDate(d)]];
  }

  /// 最近 [count] 天（含今天）
  factory HistoryStats.lastDays(Map<String, DayRecord> all, int count, {required DateTime today}) {
    final end = _dateOnly(today);
    return HistoryStats(all, from: DateTime(end.year, end.month, end.day - count + 1), to: end);
  }

  /// 紧挨着的前一段（天数一样），用来比较
  HistoryStats previous(Map<String, DayRecord> all) {
    final first = days.first;
    return HistoryStats(all,
        from: DateTime(first.year, first.month, first.day - days.length),
        to: DateTime(first.year, first.month, first.day - 1));
  }

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  /// 这段时间的每一天，旧的在前
  final List<DateTime> days;

  /// 和 [days] 一一对应，没有记录的日子是 null
  late final List<DayRecord?> perDay;

  List<DayRecord> get recorded => [
        for (final r in perDay)
          if (r != null) r
      ];

  int get recordedDays => recorded.length;
  int get humanDays => recorded.where((r) => r.stage == 0).length;
  int get dogDays => recordedDays - humanDays;

  /// 有 iOS 的记录：分钟数只是下限（系统只告诉到了哪个阶段）
  bool get minutesAreLowerBound => recorded.any((r) => r.stageOnly);

  /// 全是 iOS 的记录：只能按阶段看
  bool get stageOnly => recorded.isNotEmpty && recorded.every((r) => r.stageOnly);

  /// 有记录的日子平均每天用了多少分钟
  int? get averageMinutes {
    final r = recorded;
    if (r.isEmpty) return null;
    return (r.fold<int>(0, (sum, d) => sum + d.minutes) / r.length).round();
  }

  /// 有记录的日子平均到了第几阶段（保留一位小数）
  double? get averageStage {
    final r = recorded;
    if (r.isEmpty) return null;
    return (r.fold<int>(0, (sum, d) => sum + d.stage) / r.length * 10).round() / 10;
  }

  /// 最狗的一天：阶段最高，同阶段比狗度、再比分钟数，都一样取后面的
  DayRecord? get worstDay {
    DayRecord? worst;
    for (final r in recorded) {
      if (worst == null ||
          r.stage > worst.stage ||
          (r.stage == worst.stage && r.percent > worst.percent) ||
          (r.stage == worst.stage && r.percent == worst.percent && r.minutes >= worst.minutes)) {
        worst = r;
      }
    }
    return worst;
  }

  /// 这段时间里最长连着做人几天（中间没记录就断了）
  int get longestHumanStreak {
    var best = 0, run = 0;
    for (final r in perDay) {
      run = r != null && r.stage == 0 ? run + 1 : 0;
      if (run > best) best = run;
    }
    return best;
  }

  /// 每个阶段（0–5）各有几天
  List<int> get stageCounts {
    final counts = List.filled(6, 0);
    for (final r in recorded) {
      counts[r.stage.clamp(0, 5)]++;
    }
    return counts;
  }

  /// 变成过的犬种和次数，多的在前；一样多按先出现的
  List<MapEntry<String, int>> get breedCounts {
    final counts = <String, int>{};
    for (final r in recorded) {
      final key = r.breedKey;
      if (key != null && r.stage > 0) counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// 周一到周日，有记录的日子平均用了多少分钟；那天一次记录都没有是 null
  List<double?> get weekdayMinutes => _byWeekday((r) => r.minutes.toDouble());

  /// 周一到周日，平均到了第几阶段
  List<double?> get weekdayStages => _byWeekday((r) => r.stage.toDouble());

  List<double?> _byWeekday(double Function(DayRecord) value) {
    final sums = List.filled(7, 0.0), counts = List.filled(7, 0);
    for (var i = 0; i < days.length; i++) {
      final r = perDay[i];
      if (r == null) continue;
      final w = days[i].weekday - 1;
      sums[w] += value(r);
      counts[w]++;
    }
    return [for (var w = 0; w < 7; w++) counts[w] == 0 ? null : sums[w] / counts[w]];
  }
}
