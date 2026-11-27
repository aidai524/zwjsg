import 'lock_advisor.dart';
import 'usage_channel.dart';

/// 安卓选限时的 App 时，先按类整组勾（2026-11-27）：短视频、社交、游戏。iOS 用系统的选择页，本来就能选类别。
///
/// 很多国内 App 在系统里不标分类，所以先认常见的包名，认不出的再看系统分类（video / social / game）。
/// 聊天、办公这些离不开的（[LockAdvisor.neverSuggest]）即使系统标成社交也不算进来；白名单里的（电话、支付……）不算。
/// 这里的名单只给选 App 用，和超时来电的建议（lock_advisor.dart、iOS 报告扩展）是两份，不用同步。
enum AppGroup {
  shortVideo('短视频'),
  social('社交'),
  game('游戏');

  const AppGroup(this.label);

  final String label;

  /// [app] 算哪一组；哪组都不算是 null
  static AppGroup? of(AppUsage app) {
    if (app.whitelisted) return null;
    final pkg = app.package;
    if (_shortVideo.contains(pkg)) return shortVideo;
    if (_social.contains(pkg)) return social;
    if (_game.contains(pkg)) return game;
    if (LockAdvisor.neverSuggest.contains(pkg)) return null;
    return switch (app.category) {
      'video' => shortVideo,
      'social' => social,
      'game' => game,
      _ => null,
    };
  }

  static const _shortVideo = {
    'com.ss.android.ugc.aweme', // 抖音
    'com.ss.android.ugc.aweme.lite', // 抖音极速版
    'com.ss.android.ugc.live', // 抖音火山版
    'com.smile.gifmaker', // 快手
    'com.kuaishou.nebula', // 快手极速版
    'com.ss.android.article.video', // 西瓜视频
    'com.tencent.weishi', // 微视
    'com.baidu.haokan', // 好看视频
    'tv.danmaku.bili', // 哔哩哔哩
    'com.tencent.qqlive', // 腾讯视频
    'com.qiyi.video', // 爱奇艺
    'com.youku.phone', // 优酷
    'com.hunantv.imgo.activity', // 芒果TV
  };

  static const _social = {
    'com.sina.weibo', // 微博
    'com.xingin.xhs', // 小红书
    'com.zhihu.android', // 知乎
    'com.douban.frodo', // 豆瓣
    'com.baidu.tieba', // 百度贴吧
    'com.ss.android.article.news', // 今日头条
    'com.hupu.games', // 虎扑
    'com.ruguoapp.jike', // 即刻
    'cn.soulapp.android', // Soul
    'com.immomo.momo', // 陌陌
  };

  static const _game = {
    'com.tencent.tmgp.sgame', // 王者荣耀
    'com.tencent.tmgp.pubgmhd', // 和平精英
    'com.tencent.lolm', // 英雄联盟手游
    'com.tencent.tmgp.cf', // 穿越火线
    'com.tencent.jkchess', // 金铲铲之战
    'com.miHoYo.Yuanshen', // 原神
    'com.miHoYo.hkrpg', // 崩坏：星穹铁道
    'com.netease.party', // 蛋仔派对
    'com.netease.onmyoji', // 阴阳师
    'com.netease.dwrg', // 第五人格
    'com.netease.sky', // 光·遇
    'com.happyelements.AndroidAnimal', // 开心消消乐
    'com.qqgame.hlddz', // 欢乐斗地主
  };
}
