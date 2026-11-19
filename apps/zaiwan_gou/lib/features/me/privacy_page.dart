import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

/// 隐私政策。内容要和 App 实际的数据处理一致：改了收集、上传或权限，这里一起改。
/// 上架前还要请法务看一遍，并补上运营者名称和联系方式。
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  static const updated = '2026 年 11 月 19 日';

  static const summary = '我们只为了算出“你今天有多狗”使用你的数据。具体用了哪些 App 只在你手机上计算，不上传；'
      '自拍只在手机上变成卡通，原图不上传。';

  static const sections = <(String, List<String>)>[
    (
      '我们收集哪些信息',
      [
        '不登录也能用：使用时长、昵称、使用程度、提醒时间、单个 App 限时和历史记录都只存在你的手机上，我们收不到。',
        '登录时：手机号，用来登录和找回账号。',
        '登录后同步：昵称、每日目标和提醒时间，换手机时能恢复。',
        '每天的结果（登录后，安卓）：只上传每天的狗度、使用分钟数和犬种，不上传具体用了哪些 App。前两天没打开 App 的话，下次打开时补报。',
        'iOS：系统只告诉 App 今天用量到了哪个阶段；监控扩展会记下最近每天到过的最高阶段，用来做历史统计。这些数据只留在你的手机上，不上传。',
        '桌面小组件：添加以后，狗度在手机上算（安卓按当天的使用时长，iOS 按系统告诉的阶段），只显示狗度、阶段和你的形象，不联网、不上传。',
        '卡通形象：用自拍做形象时，照片只在你手机的内存里处理，变成卡通后就丢掉，不保存、不上传；第一次用照片前会单独征得你同意。'
            '卡通形象存在你的手机上，登录后上传到服务器（只传卡通形象，不传照片），换手机时能找回来。请只用你本人的照片。',
        'AI 生成标识：卡通形象由 AI 模型在你手机上生成。导出、分享的结算卡上会标“AI生成”，图片文件里也写有 AI 生成的标识。',
        '导出到「什么鬼天气」（你主动操作时）：在“我的 › 形象”里生成导出码，填进「什么鬼天气」后，它的服务器凭码从我们这里取一次你的卡通形象（不是照片）。'
            '导出码 10 分钟内有效、只能用一次；两边账号不互通，导过去以后互不影响。',
      ],
    ),
    (
      '我们申请的权限',
      [
        '使用情况访问（安卓）：读取当天各 App 的使用时长，用来算狗度和犬种，并在 App 里给你看今日排行。',
        '读取已安装应用（安卓）：判断各 App 属于视频、社交、游戏等哪一类，用来判定犬种；排行里显示 App 名称和图标。这些只在你手机上用，不上传。',
        '屏幕使用时间（iOS）：用来知道你今天用到了哪个阶段，并显示排行；设了单个 App 限时的话，额度用满后由系统挡一下你选的 App，可以选择再玩 10 分钟。排行由系统直接画在 App 里，我们拿不到你具体用了哪些 App，也拿不到准确时长。',
        '无障碍服务（安卓，用超时来电才需要）：只用来发现你设了限时的 App 被打开，额度用满后弹出来电提醒你（可以接着玩）。不读取屏幕内容，不记录你的操作。',
        '超时来电（安卓）：来电页会响铃、震动；接听后，如果手机有中文语音，会用手机自带的语音念几句提醒，念的话里不带 App 名称。',
        '通知：每晚提醒你看结算卡。提醒在手机本地，不经过服务器，可以在“我的 › 结算卡提醒”里关掉。',
        '相机：拍自拍做卡通形象。拍的照片不存进相册，也不上传。',
        '选照片：用系统的选图器，App 只拿到你选的那一张，用来做卡通形象，不读取整个相册。',
        '相册（只添加）：把结算卡保存到相册。我们不会读取你的相册。',
        '网络：登录和同步设置。',
      ],
    ),
    (
      '我们怎么使用和共享',
      [
        '只用来计算狗度、生成结算卡和图鉴、每晚提醒你。',
        '不做广告，不卖数据，不和第三方共享你的信息。',
        '目前没有接入第三方统计、广告或推送 SDK。以后接入短信验证码、微信登录或推送服务时，会在这里写明服务商和它们收集的信息。',
      ],
    ),
    (
      '保存和删除',
      [
        '登录后同步的数据保存在我们的服务器上，直到你删除账号。',
        '在“我的 › 删除我的形象和数据”可以删除账号：账号、每天的记录、图鉴和卡通形象会一起删除，不能恢复。',
        '退出登录或卸载 App，会清除手机上保存的数据。',
      ],
    ),
    (
      '未成年人',
      ['未满 14 周岁的用户，请在监护人同意并陪同下使用。'],
    ),
    (
      '变更和联系我们',
      [
        '政策有重要变化时，会在 App 里告诉你。',
        '运营者名称和联系方式：上线前补充。',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隐私政策')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            const Text('更新日期：$updated', style: PopText.small),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: Pop.card(color: Pop.softYellow, shadow: false),
              child: const Text(summary, style: TextStyle(fontSize: 15, height: 1.6, fontWeight: FontWeight.w700)),
            ),
            for (final (title, items) in sections) ...[
              const SizedBox(height: 22),
              Text(title, style: PopText.h2),
              const SizedBox(height: 8),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('·  ', style: PopText.body),
                      Expanded(child: Text(item, style: PopText.body)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
