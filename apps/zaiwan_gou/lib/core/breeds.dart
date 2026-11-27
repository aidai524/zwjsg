import 'dog_meter.dart';
import 'festivals.dart';
import 'history.dart';
import 'usage_channel.dart';

/// 普通黑框、稀有蓝框、传说金框；节日限定红框（2026-11-27）
enum Rarity { common, rare, legend, limited }

extension RarityLabel on Rarity {
  String get label => switch (this) {
        Rarity.common => '普通',
        Rarity.rare => '稀有',
        Rarity.legend => '传说',
        Rarity.limited => '限定',
      };
}

class Breed {
  const Breed({
    required this.key,
    required this.name,
    required this.rarity,
    required this.quip,
    required this.rule,
    this.previewStage = 4,
  });

  final String key;
  final String name;
  final Rarity rarity;
  final String quip;
  final String rule;

  /// 正式犬种素材出来前，用变狗阶段代替展示
  final int previewStage;
}

/// 与后端 config/dog.php 的 breeds 保持一致
const List<Breed> kBreeds = [
  Breed(key: 'corgi', name: '柯基', rarity: Rarity.common, quip: '腿短，停不下来', rule: '短视频类使用最多', previewStage: 4),
  Breed(key: 'husky', name: '哈士奇', rarity: Rarity.common, quip: '半夜不睡的拆家狗', rule: '23 点后使用占比最高', previewStage: 5),
  Breed(key: 'chihuahua', name: '吉娃娃', rarity: Rarity.common, quip: '焦虑到发抖', rule: '拿起手机次数极高', previewStage: 2),
  Breed(key: 'shiba', name: '社畜柴犬', rarity: Rarity.common, quip: '下班还在回消息', rule: '办公、通讯类使用最多', previewStage: 3),
  Breed(key: 'collie', name: '边牧', rarity: Rarity.common, quip: '太聪明了，全用在游戏上', rule: '游戏类使用最多', previewStage: 3),
  // 两种稀有犬种（2026-11-26 用户定）：一种靠罕见的刷法组合，一种靠自律
  Breed(key: 'mutt', name: '串串', rarity: Rarity.rare, quip: '血统不纯，爱好很杂', rule: '同一天里短视频、游戏、聊天办公三样各占两成以上', previewStage: 3),
  Breed(
    key: 'retriever',
    name: '金毛寻回犬',
    rarity: Rarity.rare,
    quip: '每天叼回一点自己',
    rule: '连续 4 天一天比一天刷得少（算到昨天），今天还没做回人',
    previewStage: 1,
  ),
  Breed(key: 'wolf', name: '狼', rarity: Rarity.legend, quip: '自由的野狼，不认主人', rule: '连续 7 天做人', previewStage: 0),
  // 节日限定（2026-11-27 用户定，见 festivals.dart）：节日那几天变狗就是它，每年这几天才有
  Breed(key: 'flag', name: '立flag犬', rarity: Rarity.limited, quip: '新年第一天，flag 就倒了', rule: '元旦（1 月 1 日）变狗', previewStage: 3),
  Breed(
    key: 'wangcai',
    name: '旺财',
    rarity: Rarity.limited,
    quip: '过年守着手机看家，名副其实的旺财',
    rule: '春节（除夕到正月初六）变狗',
    previewStage: 4,
  ),
  Breed(key: 'single', name: '单身狗', rarity: Rarity.limited, quip: '七夕还在刷手机，懂的都懂', rule: '七夕（农历七月初七）变狗', previewStage: 3),
  Breed(
    key: 'tiangou',
    name: '天狗',
    rarity: Rarity.limited,
    quip: '中秋不看月亮看手机，月亮都被你吃了',
    rule: '中秋（农历八月十五）变狗',
    previewStage: 5,
  ),
];

/// 图鉴里列哪些：限定犬种拿到了一直在，没拿到的只在节日那几天出现（过了不再出现，明年再来）
List<Breed> dexBreeds(Set<String> owned, DateTime today) => [
      for (final b in kBreeds)
        if (b.rarity != Rarity.limited || owned.contains(b.key) || (festivalOf(b.key)?.contains(today) ?? false)) b,
    ];

Breed? breedByKey(String? key) {
  for (final b in kBreeds) {
    if (b.key == key) return b;
  }
  return null;
}

/// 稀有「串串」：短视频、游戏、聊天办公三样，每样至少占当天用时的这么多
const muttShare = 0.2;

/// 稀有「金毛寻回犬」：今天之前连续几天一天比一天刷得少
const retrieverDays = 4;

/// 按当天的使用“模式”判定犬种。判定只看模式不看总量，避免鼓励多刷。
/// 阈值是初版，内测后按数据调整。传说犬种由服务端判定，这里不会返回。
///
/// [day] 是哪一天（默认今天）：节日那几天变狗，就是那个节日的限定犬种，最先判。
/// [before] 是那天之前 [retrieverDays] 天的记录（旧的在前，没记录的那天是 null），判稀有「金毛寻回犬」用。
/// iOS 拿不到分类、拿起次数和时段：除了限定犬种和金毛寻回犬，都落到默认的柯基
String? judgeBreed(UsageSnapshot usage, int goalMinutes, {List<DayRecord?> before = const [], DateTime? day}) {
  final percent = DogMeter.percentFor(usage.totalMinutes, goalMinutes);
  if (DogMeter.isHuman(percent)) return null; // 今天还是人，不算变成哪种狗

  // 节日限定最先判：那几天变狗就是它
  final festival = festivalOn(day ?? DateTime.now());
  if (festival != null) return festival.breedKey;

  // 稀有的先判：自律的金毛寻回犬，再是刷得杂的串串
  if (isRetrieverTrend(before)) return 'retriever';

  final total = usage.totalMinutes;
  final c = usage.categoryMinutes;
  final video = c['video'] ?? 0;
  final game = c['game'] ?? 0;
  final work = (c['social'] ?? 0) + (c['productivity'] ?? 0);
  if (total > 0 && [video, game, work].every((m) => m >= total * muttShare)) return 'mutt';

  if (total > 0 && usage.lateNightMinutes >= 30 && usage.lateNightMinutes / total >= 0.3) {
    return 'husky';
  }
  if (usage.pickups >= 120) return 'chihuahua';

  if (game >= video && game >= work && game > 0) return 'collie';
  if (work > video) return 'shiba';
  return 'corgi';
}

/// 稀有「金毛寻回犬」：今天之前连续 [retrieverDays] 天都有记录、一天比一天刷得少，最后那天（昨天）还是狗——
/// 还是狗，但在一点点变好。只看已经过完的日子：今天还没过完，拿今天比，早上谁都比昨天少。
/// 安卓比每天用了多少分钟；iOS 只知道每天到过的最高阶段，就比阶段（得一天低一个阶段，更难）
bool isRetrieverTrend(List<DayRecord?> before) {
  if (before.length != retrieverDays || before.contains(null)) return false;
  final days = before.cast<DayRecord>();
  int amount(DayRecord r) => r.stageOnly ? r.stage : r.minutes;
  for (var i = 1; i < days.length; i++) {
    if (amount(days[i]) >= amount(days[i - 1])) return false;
  }
  return days.last.stage > 0;
}
