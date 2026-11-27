import 'dart:math' as math;

import 'app_lock.dart';
import 'dog_meter.dart';
import 'usage_channel.dart';

/// 一条超时来电的建议：这个 App 最近平均每天用多久，建议每天限多久
class LockAdvice {
  const LockAdvice({required this.app, required this.averageMinutes, required this.suggestedMinutes, required this.fun});

  final AppUsage app;

  /// 最近几天平均每天用了多少分钟
  final int averageMinutes;

  /// 建议的每天额度（[LockService.presets] 里的一档）
  final int suggestedMinutes;

  /// 认得出是娱乐类（短视频、游戏、社交媒体）
  final bool fun;

  String get reason => '日均 ${DogMeter.formatMinutes(averageMinutes)}';
}

/// 超时来电的建议：看最近 7 天每个 App 平均每天用多久，挑最上头的几个，建议一个每天的额度。
///
/// - 娱乐类（系统分类是视频、游戏、社交，或者在 [knownFun] 里）平均每天 [minAverage] 分钟以上就建议；
///   认不出类别的，要到 [otherMinAverage] 分钟以上；
/// - 聊天、办公、地图、支付这些离不开的（[neverSuggest]）不建议，已经设了限时的、本 App 自己也不建议；
/// - 额度取 [LockService.presets] 里不超过平均用时七成的最大一档，至少 15 分钟：先少刷三成，不一下子卡死；
/// - 最多建议 [maxSuggestions] 个，娱乐类在前。
///
/// iOS 上同样的规则写在报告扩展里（ios/ScreenTimeReport/ScreenTimeReport.swift 的 LimitAdvice），改动时两边一起改。
class LockAdvisor {
  LockAdvisor._();

  static const minAverage = 20;
  static const otherMinAverage = 45;
  static const maxSuggestions = 3;

  /// 额度按平均用时的这个比例往下取
  static const cutRatio = 0.7;

  static const selfPackage = 'com.zwjsg.zwjsg_app';

  /// 系统分类里算娱乐的
  static const funCategories = {'video', 'game', 'social'};

  /// 常见的娱乐 App：很多国内 App 在系统里不标分类
  static const knownFun = {
    'com.ss.android.ugc.aweme', // 抖音
    'com.ss.android.ugc.aweme.lite', // 抖音极速版
    'com.smile.gifmaker', // 快手
    'com.kuaishou.nebula', // 快手极速版
    'com.xingin.xhs', // 小红书
    'tv.danmaku.bili', // 哔哩哔哩
    'com.sina.weibo', // 微博
    'com.ss.android.article.video', // 西瓜视频
    'com.ss.android.article.news', // 今日头条
    'com.zhihu.android', // 知乎
    'com.tencent.qqlive', // 腾讯视频
    'com.qiyi.video', // 爱奇艺
    'com.youku.phone', // 优酷
    'com.tencent.weishi', // 微视
    'com.tencent.tmgp.sgame', // 王者荣耀
    'com.tencent.tmgp.pubgmhd', // 和平精英
    'com.miHoYo.Yuanshen', // 原神
    'com.netease.party', // 蛋仔派对
    'com.tencent.jkchess', // 金铲铲之战
  };

  /// 离不开的：聊天、办公、地图、支付
  static const neverSuggest = {
    'com.tencent.mm', // 微信
    'com.tencent.mobileqq', // QQ
    'com.tencent.wework', // 企业微信
    'com.alibaba.android.rimet', // 钉钉
    'com.ss.android.lark', // 飞书
    'com.autonavi.minimap', // 高德地图
    'com.baidu.BaiduMap', // 百度地图
    'com.eg.android.AlipayGphone', // 支付宝
  };

  /// 不超过平均用时七成的最大一档，至少最小的一档
  static int suggestedMinutes(int averageMinutes) {
    final target = averageMinutes * cutRatio;
    var best = LockService.presets.first;
    for (final p in LockService.presets) {
      if (p <= target) best = p;
    }
    return best;
  }

  static bool isFun(AppUsage app) => knownFun.contains(app.package) || funCategories.contains(app.category);

  /// [week]：最近几天每个 App 的总用时（用时多的在前）；[days]：这几天里有数据的天数
  static List<LockAdvice> suggest(List<AppUsage> week, {required int days, Iterable<AppLock> existing = const []}) {
    final locked = {for (final l in existing) ...l.packages};
    final fun = <LockAdvice>[];
    final others = <LockAdvice>[];
    for (final app in week) {
      if (locked.contains(app.package) || neverSuggest.contains(app.package) || app.package == selfPackage) continue;
      final average = (app.minutes / math.max(1, days)).round();
      final isFunApp = isFun(app);
      if (average < (isFunApp ? minAverage : otherMinAverage)) continue;
      (isFunApp ? fun : others).add(LockAdvice(
        app: app,
        averageMinutes: average,
        suggestedMinutes: suggestedMinutes(average),
        fun: isFunApp,
      ));
    }
    int byAverage(LockAdvice a, LockAdvice b) => b.averageMinutes.compareTo(a.averageMinutes);
    fun.sort(byAverage);
    others.sort(byAverage);
    return [...fun, ...others].take(maxSuggestions).toList();
  }
}
