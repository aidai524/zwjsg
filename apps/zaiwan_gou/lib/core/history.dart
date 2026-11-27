import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 某一天的结果。只存在手机上，不上传（登录后上传的是另一份：只有狗度、分钟数、犬种）。
class DayRecord {
  const DayRecord({
    required this.date,
    required this.goalMinutes,
    required this.minutes,
    required this.percent,
    required this.percentLabel,
    required this.stage,
    this.breedKey,
    this.stageOnly = false,
  });

  factory DayRecord.fromJson(Map<String, dynamic> m) => DayRecord(
        date: m['d'] as String,
        goalMinutes: (m['goal'] as num).toInt(),
        minutes: (m['min'] as num).toInt(),
        percent: (m['pct'] as num).toInt(),
        percentLabel: m['label'] as String,
        stage: (m['stage'] as num).toInt(),
        breedKey: m['breed'] as String?,
        stageOnly: m['stageOnly'] as bool? ?? false,
      );

  Map<String, Object?> toJson() => {
        'd': date,
        'goal': goalMinutes,
        'min': minutes,
        'pct': percent,
        'label': percentLabel,
        'stage': stage,
        'breed': breedKey,
        'stageOnly': stageOnly,
      };

  /// yyyy-MM-dd，用户本地日期
  final String date;
  final int goalMinutes;

  /// 用了多少分钟（iOS 是下限）
  final int minutes;
  final int percent;

  /// 当时显示的狗度，iOS 是“≥60%”这种
  final String percentLabel;
  final int stage;
  final String? breedKey;

  /// iOS：只知道到了哪个阶段
  final bool stageOnly;
}

/// yyyy-MM-dd
String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 从 [today] 的前一天往前数，连续做人（有记录、阶段 0）的天数。没打开 App、没有记录的那天算断了
int humanStreakBefore(Map<String, DayRecord> records, DateTime today) {
  var n = 0;
  while (true) {
    final r = records[_dateKey(DateTime(today.year, today.month, today.day - n - 1))];
    if (r == null || r.stage != 0) return n;
    n++;
  }
}

/// [day] 之前 [n] 天的记录，旧的在前；没记录的那天是 null
List<DayRecord?> daysBefore(Map<String, DayRecord> records, DateTime day, int n) => [
      for (var i = n; i >= 1; i--) records[_dateKey(DateTime(day.year, day.month, day.day - i))],
    ];

/// 每天一条，按日期存在 SharedPreferences 里；同一天反复刷新只留最后一次
class HistoryStore {
  HistoryStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'history';

  /// 读出来的那份留着，改了再换：界面上算犬种、连续做人时会常读
  Map<String, DayRecord>? _cache;

  /// 最多留多少天
  static const keepDays = 400;

  /// 全部记录（给出去的是一份拷贝，改了不影响存着的）
  Map<String, DayRecord> all() => Map.of(_cache ??= _read());

  Map<String, DayRecord> _read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in map.entries) e.key: DayRecord.fromJson(e.value as Map<String, dynamic>)};
    } on FormatException {
      return {};
    }
  }

  DayRecord? day(String date) => (_cache ??= _read())[date];

  /// SharedPreferences 被整个清掉以后（退出登录、注销）调一下，下次重新读
  void forget() => _cache = null;

  Future<void> put(DayRecord record) => putAll([record]);

  Future<void> putAll(Iterable<DayRecord> list) async {
    if (list.isEmpty) return;
    final records = all();
    for (final r in list) {
      records[r.date] = r;
    }
    // 日期是 yyyy-MM-dd，按字符串排序就是按日期排序
    final dates = records.keys.toList()..sort();
    for (final old in dates.take((dates.length - keepDays).clamp(0, dates.length))) {
      records.remove(old);
    }
    _cache = records;
    await _prefs.setString(_key, jsonEncode({for (final e in records.entries) e.key: e.value.toJson()}));
  }
}
