/// 狗度规则。后端有一份相同的实现（api/app/Services/DogMeter.php + config/dog.php），改动时两边一起改。
class DogMeter {
  DogMeter._();

  /// 达到即进入对应阶段 1–5
  static const List<int> stageThresholds = [30, 60, 90, 120, 150];

  /// 低于这个狗度算“做回人”
  static const int humanBelow = 30;

  static const List<String> stageNames = [
    '阶段 0 · 还是人',
    '阶段 1 · 冒耳朵',
    '阶段 2 · 狗鼻子',
    '阶段 3 · 长毛了',
    '阶段 4 · 吐舌头',
    '阶段 5 · 完全体',
  ];

  static const List<String> quips = [
    '今天还是个人，保持住',
    '耳朵冒出来了，自己摸摸',
    '鼻子湿了，闻到短视频的味了吧',
    '毛都长出来了，还刷？',
    '舌头已经收不回去了',
    '汪！明天 0 点再做人吧',
  ];

  static const List<String> nextChange = [
    '长出狗耳朵',
    '变出狗鼻子',
    '脸上长毛',
    '吐舌头',
    '完全变成狗',
  ];

  static int percentFor(int minutesUsed, int goalMinutes) {
    if (goalMinutes <= 0) return 0;
    return (minutesUsed / goalMinutes * 100).round();
  }

  static int stageFor(int percent) {
    var stage = 0;
    for (var i = 0; i < stageThresholds.length; i++) {
      if (percent >= stageThresholds[i]) stage = i + 1;
    }
    return stage;
  }

  static bool isHuman(int percent) => percent < humanBelow;

  /// 距离下一阶段还差多少分钟；已是完全体时返回 null
  static int? minutesToNextStage(int minutesUsed, int goalMinutes) {
    final stage = stageFor(percentFor(minutesUsed, goalMinutes));
    if (stage >= stageThresholds.length) return null;
    final targetMinutes = (stageThresholds[stage] * goalMinutes / 100).ceil();
    return (targetMinutes - minutesUsed).clamp(0, 24 * 60);
  }

  static String formatMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m 分钟';
    if (m == 0) return '$h 小时';
    return '$h 小时 $m 分';
  }
}
