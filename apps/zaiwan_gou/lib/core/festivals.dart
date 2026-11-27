/// 节日限定犬种（2026-11-27 用户定）：节日那几天里变狗（狗度到 30%），那天的犬种就是这个节日的限定犬种，
/// 比稀有的金毛寻回犬、串串还先判。和普通犬种一样变狗才有，看的是哪天，不看怎么刷、刷了多久。
/// 没变狗就没有；过了那几天没拿到的，图鉴里不再出现，明年再来；拿到了一直在。只看日期和阶段，iPhone 也能拿（在手机上判定）。
///
/// 农历节日的日子按年写死（用系统的农历算的，2027–2030），过了 2030 年要往后补；元旦每年都是 1 月 1 日。
/// 和狗后端 config/dog.php 的 festival_breeds 一致（Flutter 测试会读 PHP 配置对一遍），改动时两边一起改
class Festival {
  const Festival({
    required this.breedKey,
    required this.name,
    required this.when,
    this.everyYear,
    this.windows = const {},
  });

  /// 这个节日的限定犬种
  final String breedKey;

  /// 节日名：元旦、春节……
  final String name;

  /// 哪几天，给人看的：“1 月 1 日”“除夕到正月初六”
  final String when;

  /// 每年都在公历的这一天（月、日）
  final (int, int)? everyYear;

  /// 农历节日：每年的第一天和最后一天（含），yyyy-MM-dd
  final Map<int, (String, String)> windows;

  /// [year] 年这个节日的第一天和最后一天；表里没有那一年时是 null
  (DateTime, DateTime)? window(int year) {
    final fixed = everyYear;
    if (fixed != null) {
      final day = DateTime(year, fixed.$1, fixed.$2);
      return (day, day);
    }
    final w = windows[year];
    if (w == null) return null;
    return (DateTime.parse(w.$1), DateTime.parse(w.$2));
  }

  /// [day]（只看年月日）在不在这个节日里
  bool contains(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final w = window(d.year);
    return w != null && !d.isBefore(w.$1) && !d.isAfter(w.$2);
  }

  /// 在节日里的话，算上今天还剩几天；不在节日里是 null
  int? daysLeft(DateTime today) {
    if (!contains(today)) return null;
    final d = DateTime(today.year, today.month, today.day);
    return window(d.year)!.$2.difference(d).inDays + 1;
  }
}

const kFestivals = [
  Festival(breedKey: 'flag', name: '元旦', when: '1 月 1 日', everyYear: (1, 1)),
  Festival(breedKey: 'wangcai', name: '春节', when: '除夕到正月初六', windows: {
    2027: ('2027-02-05', '2027-02-11'),
    2028: ('2028-01-25', '2028-01-31'),
    2029: ('2029-02-12', '2029-02-18'),
    2030: ('2030-02-02', '2030-02-08'),
  }),
  Festival(breedKey: 'single', name: '七夕', when: '农历七月初七', windows: {
    2027: ('2027-08-08', '2027-08-08'),
    2028: ('2028-08-26', '2028-08-26'),
    2029: ('2029-08-16', '2029-08-16'),
    2030: ('2030-08-05', '2030-08-05'),
  }),
  Festival(breedKey: 'tiangou', name: '中秋', when: '农历八月十五', windows: {
    2027: ('2027-09-15', '2027-09-15'),
    2028: ('2028-10-03', '2028-10-03'),
    2029: ('2029-09-22', '2029-09-22'),
    2030: ('2030-09-12', '2030-09-12'),
  }),
];

/// [day] 是哪个节日（不是节日是 null）
Festival? festivalOn(DateTime day) {
  for (final f in kFestivals) {
    if (f.contains(day)) return f;
  }
  return null;
}

/// 限定犬种 → 它的节日；不是限定犬种是 null
Festival? festivalOf(String? breedKey) {
  for (final f in kFestivals) {
    if (f.breedKey == breedKey) return f;
  }
  return null;
}
