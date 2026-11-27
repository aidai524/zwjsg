import 'package:avatar_engine/avatar_engine.dart';

/// 一种进化形态：叫什么、连续做人几天解锁、梗文案、长什么样（画法在 avatar_engine 的 [Evolution]）
class EvolutionInfo {
  const EvolutionInfo(this.evolution, {required this.name, required this.days, required this.quip, required this.look});

  final Evolution evolution;
  final String name;

  /// 连续做人几天解锁
  final int days;
  final String quip;
  final String look;

  /// 放进解锁弹窗队列（和新犬种共用一个队列）时的名字
  String get unlockKey => '$unlockPrefix${evolution.name}';

  static const unlockPrefix = 'evo:';
}

/// 进化形态（需求文档“做回人”，2026-11-26 用户定）：连续做人 3 / 7 / 14 / 30 天各解锁一种，越往后越难；
/// 解锁了就一直在，中断只清零连续天数。只在做人（狗度 < 30%、阶段 0）时穿上，一变狗就脱掉，第二天 0 点变回人再穿上。
/// 连续做人按手机上的记录算（history.dart 的 humanStreakBefore：从昨天往前数，没打开 App、没有记录的那天算断），
/// 今天还没过完不算，所以第 3 天守住了，第 4 天打开 App 时解锁。解锁了几种可以自己挑穿哪一种，默认穿最新解锁的。
/// 存在手机上（和每天的记录一样，换手机不带过去），服务端不知道
const kEvolutions = [
  EvolutionInfo(Evolution.scholar, name: '学霸', days: 3, quip: '三天没变狗，脑子都清醒了', look: '圆框眼镜、学士帽'),
  EvolutionInfo(Evolution.elite, name: '西装精英', days: 7, quip: '人模人样，可以去面试了', look: '西装、白衬衫、红领带'),
  EvolutionInfo(Evolution.wellness, name: '养生大师', days: 14, quip: '保温杯里泡枸杞，手机早扔一边了', look: '捧着泡枸杞的保温杯'),
  EvolutionInfo(Evolution.halo, name: '头顶光环', days: 30, quip: '做人做到头顶冒光', look: '头顶光环，身边冒金光'),
];

EvolutionInfo evolutionInfo(Evolution e) => kEvolutions.firstWhere((i) => i.evolution == e);

/// 解锁弹窗队列里的名字 → 哪种进化形态；不是进化形态的（犬种）是 null
EvolutionInfo? evolutionByUnlockKey(String key) {
  if (!key.startsWith(EvolutionInfo.unlockPrefix)) return null;
  final e = Evolution.byName(key.substring(EvolutionInfo.unlockPrefix.length));
  return e == null ? null : evolutionInfo(e);
}

/// 连续做人 [streak] 天（不算今天）够格解锁的
List<Evolution> evolutionsFor(int streak) => [for (final i in kEvolutions) if (streak >= i.days) i.evolution];

/// 下一个要解锁的（按天数从少到多，第一个还没解锁的）；都解锁了是 null
EvolutionInfo? nextEvolution(Set<Evolution> unlocked) {
  for (final i in kEvolutions) {
    if (!unlocked.contains(i.evolution)) return i;
  }
  return null;
}

/// “这周”卡片和图鉴里的进度那句话。[streak] 是到昨天为止连续做人几天，[humanToday] 是今天到现在还是人
String evolutionLine(int streak, Set<Evolution> unlocked, {required bool humanToday}) {
  final next = nextEvolution(unlocked);
  if (next == null) return '四种进化形态都解锁了，做人做到头顶冒光';
  if (!humanToday) return '明天起连续做人 ${next.days} 天，解锁进化形态「${next.name}」';
  final left = next.days - streak;
  if (left <= 0) return '够格解锁进化形态「${next.name}」了';
  return left == 1 ? '今天守住，明天解锁进化形态「${next.name}」' : '再做人 $left 天（算上今天），解锁进化形态「${next.name}」';
}
