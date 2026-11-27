/// 狗度规则。后端有一份相同的实现（api/app/Services/DogMeter.php + config/dog.php），改动时两边一起改。
class DogMeter {
  DogMeter._();

  /// 达到即进入对应阶段 1–5
  static const List<int> stageThresholds = [30, 60, 90, 120, 150];

  /// 低于这个狗度算“做回人”
  static const int humanBelow = 30;

  /// 连续做人多少天变传说犬种「狼」（后端 config/dog.php 的 legend_streak_days）
  static const int legendStreakDays = 7;

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

  /// 一天里第 [stage] 阶段（1–5）从用满多少分钟开始
  static int stageStartMinutes(int stage, int goalMinutes) => (goalMinutes * stageThresholds[stage - 1] / 100).round();

  static String formatMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m 分钟';
    if (m == 0) return '$h 小时';
    return '$h 小时 $m 分';
  }
}

/// 每日目标按使用程度分三档，时长是预设的，不让用户自己填小时数（2026-11-19 定）。
/// 后端 config/dog.php 的 goal_tiers 有一份相同的分钟数，改动时两边一起改。
enum GoalTier {
  normal(180, '正常使用', '偶尔刷刷，一天 3 小时就该放下了'),
  heavy(300, '重度使用', '通勤刷、饭桌刷、睡前也在刷'),
  hooked(480, '无可自拔', '手机长在手上了，先从一天 8 小时开始戒');

  const GoalTier(this.minutes, this.label, this.description);

  final int minutes;
  final String label;
  final String description;

  /// 旧版本能自己设小时数：换成最接近的一档，正好在两档中间时取严的那档
  static GoalTier nearest(int minutes) {
    var best = GoalTier.normal;
    for (final t in GoalTier.values) {
      if ((t.minutes - minutes).abs() < (best.minutes - minutes).abs()) best = t;
    }
    return best;
  }
}
