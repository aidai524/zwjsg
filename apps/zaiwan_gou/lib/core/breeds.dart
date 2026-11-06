import 'usage_channel.dart';
import 'dog_meter.dart';

enum Rarity { common, rare, legend }

extension RarityLabel on Rarity {
  String get label => switch (this) {
        Rarity.common => '普通',
        Rarity.rare => '稀有',
        Rarity.legend => '传说',
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
  Breed(key: 'rare_a', name: '[稀有 A]', rarity: Rarity.rare, quip: '[待定]', rule: '两种以上模式罕见叠加'),
  Breed(key: 'rare_b', name: '[稀有 B]', rarity: Rarity.rare, quip: '[待定]', rule: '两种以上模式罕见叠加'),
  Breed(key: 'wolf', name: '狼', rarity: Rarity.legend, quip: '自由的野狼，不认主人', rule: '连续 7 天做人', previewStage: 0),
];

Breed? breedByKey(String? key) {
  for (final b in kBreeds) {
    if (b.key == key) return b;
  }
  return null;
}

/// 按当天的使用“模式”判定犬种。判定只看模式不看总量，避免鼓励多刷。
/// 阈值是初版，内测后按数据调整。传说犬种由服务端判定，这里不会返回。
String? judgeBreed(UsageSnapshot usage, int goalMinutes) {
  final percent = DogMeter.percentFor(usage.totalMinutes, goalMinutes);
  if (DogMeter.isHuman(percent)) return null; // 今天还是人，不算变成哪种狗

  if (usage.totalMinutes > 0 && usage.lateNightMinutes >= 30 && usage.lateNightMinutes / usage.totalMinutes >= 0.3) {
    return 'husky';
  }
  if (usage.pickups >= 120) return 'chihuahua';

  final c = usage.categoryMinutes;
  final video = c['video'] ?? 0;
  final game = c['game'] ?? 0;
  final work = (c['social'] ?? 0) + (c['productivity'] ?? 0);

  if (game >= video && game >= work && game > 0) return 'collie';
  if (work > video) return 'shiba';
  return 'corgi';
}
