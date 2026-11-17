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

/// 和风要求：显示了和风数据的页面都要写明“天气服务由和风天气驱动”并链到官网，
/// 接口返回的 attributions 也要原样显示。所以这里不改写内容，只把网址做成链接。
class QWeatherCredit extends StatelessWidget {
  const QWeatherCredit({super.key, this.attributions = const [], this.opener = _launch});

  static const label = '天气服务由和风天气驱动';
  static const homepage = 'https://www.qweather.com';

  final List<String> attributions;

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

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          link(label, homepage),
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
