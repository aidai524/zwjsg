import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

/// 隐私政策。内容要和 App 实际的数据处理一致：改了收集、上传或权限，这里一起改，并把 AppState.privacyVersion 加 1。
/// 上架前还要请法务看一遍，并补上运营者名称和联系方式。
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  static const updated = '2026 年 11 月 18 日';

  static const summary = '我们只为了给你看天气、发关心提醒使用你的数据。不用定位，位置只到城市；不登录也能看天气。';

  static const sections = <(String, List<String>)>[
    (
      '我们收集哪些信息',
      [
        '不登录也能用：关注的城市、毒舌档位和温度单位只存在你的手机上。',
        '查天气：App 把城市编号发给我们的服务器，服务器再向和风天气查询，同一个城市的结果大家共用。查询时不带你的个人信息。',
        '登录时：手机号，用来登录和找回账号。',
        '登录后同步：关注的城市（只到城市）和常驻城市，换手机时能恢复；毒舌档位、温度单位和推送设置，用来按你的设置发早安播报。',
        '关心群（登录后）：群名、成员，以及谁在什么时候给谁发了哪句关心话、对方点没点“收到 ♥”，用来限频和合并提醒，30 天后自动删除。'
            '群里的家人只看得到你的昵称、你导入的卡通形象、常驻城市名和那里的天气，看不到你的位置。',
        '形象：默认用代码画的形象，不收集照片。你可以用「再玩我是狗」生成的导出码导入卡通形象：我们的服务器凭码从「再玩我是狗」那里取一次图（只有卡通形象，不是照片），存在你的手机上；'
            '登录后存到我们的服务器，换手机能找回来，关心群里的家人也能看到。两边账号不互通，导进来以后互不影响。',
        '推送（接入后）：保存推送用的设备标识，只用来给你发早安播报、预警和关心群提醒。',
      ],
    ),
    (
      '我们申请的权限',
      [
        '网络：查天气、登录和同步。',
        '相册（只写入）：你点“保存图片”时把天气卡存进相册，不读取相册里的照片。',
        '通知（接入推送后）：早安播报、预警和关心群提醒，可以在“设置 › 推送”里关掉。',
        '定位：现在不申请，城市由你手动选。以后接定位也只取到区县，不记录你去过哪。',
      ],
    ),
    (
      '我们怎么使用和共享',
      [
        '只用来给你看天气、发推送和关心提醒。',
        '分享天气卡用手机系统的分享面板，发给谁由你选，我们不经手。卡上用了导入的卡通形象时，会标“AI生成”，图片文件里也写有 AI 生成的标识。',
        '天气数据来自和风天气：我们只把城市编号发给它，不发你的个人信息。预报和预警来自气象部门所属台站，原文照登；吐槽文案是人工写的，不改写预报结论。',
        '不做广告，不卖数据，不和第三方共享你的个人信息。',
        '目前没有接入第三方统计、广告或推送 SDK。以后接入短信验证码、微信登录或推送服务时，会在这里写明服务商和它们收集的信息。',
      ],
    ),
    (
      '保存和删除',
      [
        '登录后同步的数据保存在我们的服务器上，直到你注销账号；关心群的提醒记录 30 天后自动删除。',
        '在“设置 › 注销账号”可以删除账号：账号、城市、关心群记录和形象会一起删除，不能恢复。',
        '在“设置 › 我的形象”可以用回默认形象：导入的形象会从手机上删掉，登录了的话服务器上的也删掉。',
        '退出登录后，手机上关注的城市还留着，不登录也能接着看天气；导入的形象会从手机上删掉，再登录时找回来。卸载 App 会清除手机上的数据。',
      ],
    ),
    (
      '未成年人',
      ['未满 14 周岁的用户，请在监护人同意并陪同下使用。'],
    ),
    (
      '变更和联系我们',
      [
        '政策有重要变化时，会在 App 里告诉你，并请你重新同意。',
        '运营者名称和联系方式：上线前补充。',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pop.gray,
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
