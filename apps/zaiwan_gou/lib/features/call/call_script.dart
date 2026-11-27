import 'dart:math' as math;

/// 超时来电里“狗版的你”说的话（2026-11-23 定稿）。
///
/// 打电话来的是用户自己越刷越像狗的那个身份，不叫“你的狗”。损友语气，只拿卡通狗的变化开玩笑，
/// 不拿身材、长相、成绩开玩笑。
/// - 字幕和念出来的一字不差。App 名称、今天用了多久只写在来电界面的标题下面，不念
///   （安卓的系统语音引擎可能是第三方的）
/// - 括号里的英文是 MiniMax 的语气词：(pant) 喘气、(sniffs) 吸鼻子、(chuckle) 轻笑、(laughs) 笑。
///   每句台词都提前用 MiniMax 生成了语音（见 CallVoice，改了台词要跑 tools/voice/make_voice.py）；
///   字幕、系统语音（语音放不了时才用）用 [plain] 去掉语气词
/// - 说“十分钟”的句子跟着 `LockService.snoozeMinutes` 走，改了分钟数这里也要改（测试会对一遍）
abstract final class CallScript {
  /// 接通后第一句，随机挑一句
  static const open = [
    '(pant)喂？喂？是我，狗版的你！时间到了，先别挂！',
    '喂，这里是狗版的你。你定的时间，用完了。',
    '(sniffs)喂？我闻到了，时间都用完了，你还在刷。',
    '喂？我是来催债的，说好的时间，一分钟都不剩了。',
  ];

  /// 半夜（[isNight]）打来的第一句
  static const openNight = '喂？大半夜的，狗都睡了，你还在刷？';

  /// “试一下来电”的第一句
  static const openDrill = '喂？这是演习，这是演习，不会真锁你。';

  /// 按今天的阶段（0–5）吐槽一句，跟 DogMeter.stageNames 一一对应
  static const stage = [
    '你今天还是个人，别为这几分钟变成我。',
    '耳朵都竖起来了，自己摸摸，毛茸茸的。',
    '鼻子都湿了，再刷就该趴地上闻拖鞋了。',
    '脸上毛都长齐了，再刷就得带你打疫苗了。',
    '舌头都耷拉出来了，哈——哈——跟我一样。(pant)',
    '恭喜，你已经彻底变成我了。我们狗都不刷这么久。',
  ];

  /// 提条件
  static const ask = [
    '想再玩十分钟？学两声狗叫，我就放你进去。',
    '规矩你懂的：汪两声，再玩十分钟。',
  ];

  /// 提完条件 [CallScreen.nudgeAfter] 还没动静，催一句
  static const nudge = [
    '不想叫？那就挂了，干点正事去。',
    '愣着干嘛？叫啊，又没人听见。',
  ];

  /// 听到第一声
  static const barkOne = [
    '(chuckle)有内味儿了！再来一声！',
    '不错不错，还差一声！',
  ];

  /// 没叫对的几种（要等听狗叫能分出这几种以后才用得上）
  static const tooQuiet = '这是蚊子叫吧？大点声。';
  static const notVoice = '拍手不算，张嘴叫！';
  static const tooLong = '别跟我讲道理，叫就完事了。';

  /// 听了 [CallScreen.listenFor] 还没听到两声
  static const missed = '害羞了？没事，就咱俩，再来一次。';

  /// 叫得特别像狗
  static const veryDog = '(laughs)这声太像了，不愧是我。';

  /// 放行
  static const granted = [
    '汪汪！好狗！十分钟，我掐着表呢。',
    '叫得不错，赏你十分钟。到点我还打给你。',
  ];

  /// 23 点到早上 5 点算半夜
  static bool isNight(DateTime t) => t.hour >= 23 || t.hour < 5;

  /// 去掉语气词，给字幕和系统语音用
  static String plain(String line) => line.replaceAll(RegExp(r'\([a-z-]+\)'), '').trim();

  /// 随机挑一句（原文，带语气词：放语音按原文找文件，字幕和系统语音再用 [plain] 去掉）
  static String pick(List<String> lines, math.Random random) => lines[random.nextInt(lines.length)];

  /// 全部台词，测试用来检查有没有 App 名称、旧称呼之类
  static List<String> get all => [
        ...open,
        openNight,
        openDrill,
        ...stage,
        ...ask,
        ...nudge,
        ...barkOne,
        tooQuiet,
        notVoice,
        tooLong,
        missed,
        veryDog,
        ...granted,
      ];
}
