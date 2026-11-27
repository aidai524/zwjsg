import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pop_ui/pop_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// 带描边的圆形图标按钮
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({super.key, required this.icon, required this.label, required this.onTap, this.badge = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Pop.white,
                shape: BoxShape.circle,
                border: Border.all(color: Pop.ink, width: Pop.stroke),
              ),
              child: Icon(icon, size: 22, color: Pop.ink),
            ),
            if (badge)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Pop.kingRed,
                    shape: BoxShape.circle,
                    border: Border.all(color: Pop.ink, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 小标签：如“常驻”
class Chip2 extends StatelessWidget {
  const Chip2(this.text, {super.key, this.color = Pop.white});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Pop.ink, width: 2),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}

/// 页尾的数据来源说明（合规要求：注明来源）
class SourceNote extends StatelessWidget {
  const SourceNote(this.text, {super.key, this.color = Pop.muted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: color, height: 1.5)),
    );
  }
}

/// 和风的来源标注（dev.qweather.com/docs/terms/attribution）：产品里要写明“天气服务由和风天气驱动”并链到官网；
/// 用了预警、空气质量的地方，必须完整、原样显示接口给的来源（refer.sources，这里的 attributions）。
/// 2026-11-19 用户要求“由和风天气驱动”只在设置页显示，别的页面用 brand: false 只显示来源。不改写内容，只把网址做成链接。
class QWeatherCredit extends StatelessWidget {
  const QWeatherCredit({super.key, this.attributions = const [], this.brand = true, this.opener = _launch});

  static const label = '天气服务由和风天气驱动';
  static const homepage = 'https://www.qweather.com';

  final List<String> attributions;

  /// 显示“天气服务由和风天气驱动”（链到和风官网）。2026-11-19 用户要求只在设置页显示；
  /// 别的页面传 false，只原样显示接口给的来源（和风要求：用了预警、空气质量的页面必须完整显示 refer.sources）
  final bool brand;

  /// 打开链接，返回是否成功。测试时替换
  final Future<bool> Function(Uri) opener;

  static Future<bool> _launch(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<void> _open(BuildContext context, String url) async {
    var opened = false;
    try {
      opened = await opener(Uri.parse(url));
    } on PlatformException {
      // 手机上没有能打开网页的应用
    }
    if (!opened && context.mounted) showToast(context, '打不开链接，稍后再试');
  }

  @override
  Widget build(BuildContext context) {
    Widget link(String text, String url) => Semantics(
          link: true,
          child: InkWell(
            onTap: () => _open(context, url),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Pop.muted, decoration: TextDecoration.underline)),
            ),
          ),
        );

    if (!brand && attributions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          if (brand) link(label, homepage),
          for (final a in attributions)
            if (a.startsWith('http'))
              link(a, a)
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(a, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Pop.muted, height: 1.5)),
              ),
        ],
      ),
    );
  }
}

void showToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}
