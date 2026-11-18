import 'dart:math' as math;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';
import 'package:series_share/series_share.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/scene.dart';
import '../../widgets/common.dart';
import '../../widgets/weather_avatars.dart';

/// 天气卡（需求文档 P1）：形象 + 吐槽 + 当天天气，3:4，能存相册、发给朋友。
/// 严肃模式（黄色及以上预警）下不生成：预警期间不分享带吐槽的卡片。
/// 卡片包在 RepaintBoundary 里，保存、分享时截成图片。
class WeatherCardPage extends StatefulWidget {
  /// [exporter]、[now] 只在测试里传
  const WeatherCardPage({
    super.key,
    required this.locationId,
    this.exporter = const DefaultCardExporter(appName: '什么鬼天气', filePrefix: 'shenmetianqi'),
    this.now,
  });

  final String locationId;
  final CardExporter exporter;
  final DateTime? now;

  /// 写进图片隐式标识的生成合成服务提供者：先写 App 名，公司和备案号定了再换
  static const aigcProducer = '什么鬼天气';

  @override
  State<WeatherCardPage> createState() => _WeatherCardPageState();
}

class _WeatherCardPageState extends State<WeatherCardPage> {
  final GlobalKey _cardKey = GlobalKey();
  final GlobalKey _shareKey = GlobalKey();
  bool _busy = false;
  bool _saved = false;

  /// 出错时的提示：浮在两个按钮上面，不挡住按钮
  void _notify(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(28, 0, 28, 104),
      ));
  }

  /// 导出成功返回 true
  Future<bool> _export(Future<void> Function(Uint8List png) action, {required String failed}) async {
    if (_busy) return false;
    setState(() => _busy = true);
    final aiAvatar = AppScope.read(context).avatar != null;
    try {
      var png = await widget.exporter.capture(_cardKey);
      // 导入的照片形象是 AI 生成的：导出的图片文件里还要写上隐式标识
      if (aiAvatar) png = AigcLabel.embed(png, producer: WeatherCardPage.aigcProducer);
      await action(png);
      return true;
    } on CardExportException catch (e) {
      _notify(e.message);
    } on PlatformException {
      _notify(failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return false;
  }

  /// 存好了就把按钮改成“已保存到相册”，不用弹提示挡住旁边的分享按钮
  Future<void> _save() async {
    if (await _export(widget.exporter.save, failed: '没存上，稍后再试') && mounted) setState(() => _saved = true);
  }

  Future<void> _share() {
    // iPad 的分享面板要从按钮的位置弹出
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    return _export((png) => widget.exporter.share(png, origin: origin), failed: '分享面板没打开，稍后再试');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final city = state.cities.where((c) => c.locationId == widget.locationId).firstOrNull;
    final w = state.weatherOf(widget.locationId);

    final Widget body;
    if (city == null || w == null) {
      body = const _Notice('天气还没加载好，回首页刷新一下再来晒。');
    } else if (w.serious) {
      body = const _Notice('预警期间不生成带吐槽的卡片，注意安全。\n预警原文在首页，可以直接告诉家人。');
    } else {
      body = Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: RepaintBoundary(
                  key: _cardKey,
                  // 深色底：导出的图片四角是深色，不是透明（发到微信会变黑或变白）
                  child: LayoutBuilder(
                    builder: (_, c) => ColoredBox(
                      color: Pop.ink,
                      child: WeatherCard(city: city, weather: w, now: widget.now ?? DateTime.now(), width: c.maxWidth),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Pop.white,
                    side: const BorderSide(color: Pop.white, width: Pop.stroke),
                    minimumSize: const Size.fromHeight(54),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  onPressed: _busy ? null : _save,
                  child: Text(_saved ? '已保存到相册' : '保存图片'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PopButton(key: _shareKey, label: '晒给朋友', height: 54, onPressed: _busy ? null : _share),
              ),
            ],
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Pop.ink,
      appBar: AppBar(
        backgroundColor: Pop.ink,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        foregroundColor: Pop.white,
        title: const Text('晒天气', style: TextStyle(color: Pop.white, fontSize: 16, fontWeight: FontWeight.w900)),
        centerTitle: true,
        leading: IconButton(tooltip: '关闭', icon: const Icon(Icons.close), onPressed: () => context.pop()),
      ),
      body: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(28, 4, 28, 24), child: body)),
    );
  }
}

/// 天气卡本身（3:4）：城市和日期、温度、形象和吐槽、四张决策卡的结论、来源。截图用，里面不放按钮。
/// 天气数字照搬数据源（按用户选的温度单位换算），写明“天气服务由和风天气驱动”和实况时间；吐槽是人工写的。
/// 用了导入的照片形象（AI 生成）时，右下角标“AI生成”，文字高度不低于卡片宽的 5%。
class WeatherCard extends StatelessWidget {
  const WeatherCard({super.key, required this.city, required this.weather, required this.now, required this.width});

  final City city;
  final WeatherData weather;
  final DateTime now;

  /// 卡片宽度：AI 标识的字号按它算
  final double width;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// 决策卡在天气卡上的短名字
  static const shortTitles = {'umbrella': '伞', 'long_johns': '秋裤', 'car_wash': '洗车', 'laundry': '晾衣'};

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final unit = state.tempUnit;
    final w = weather;
    final obs = w.obsTime == null ? null : DateTime.tryParse(w.obsTime!)?.toLocal();
    final date = '${now.month} 月 ${now.day} 日 周${_weekdays[now.weekday - 1]}${obs == null ? '' : ' · ${hm(obs)} 实况'}';
    final range = w.todayMax == null ? '' : ' · ${unit.deg(w.todayMin!)}～${unit.deg(w.todayMax!)}';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: sceneColor(w.cond, w.outfitKey),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Pop.ink, width: 6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(city.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, height: 1.15)),
                    const SizedBox(height: 2),
                    Text(date, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Text(unit.deg(w.temp), style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w900, height: 1)),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Pop.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Pop.ink, width: Pop.stroke),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 11,
                    child: LayoutBuilder(
                      builder: (_, c) => Align(
                        alignment: Alignment.bottomCenter,
                        child: MyWeatherAvatar(
                          temp: weatherTempFromKey(w.outfitKey),
                          cond: weatherCondFromKey(w.cond),
                          size: math.min(c.maxWidth, c.maxHeight),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 9,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: Pop.card(radius: 14, shadow: false),
                          child: Text(
                            w.quip ?? w.outfitLabel,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text('${w.text} · 体感 ${unit.deg(w.feelsLike)}$range',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (i, key) in decisionKeys.indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: _DecisionChip(title: shortTitles[key]!, decision: w.decision(key))),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Pop.ink, width: 2))),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('什么鬼天气', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      // 和风要求：用了它的数据就要写明
                      Text(QWeatherCredit.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (state.avatar != null) ...[
                  // 导入的照片形象是 AI 生成的，导出的图片要有显式标识：放在卡片右下角，
                  // 文字高度不低于卡片短边（宽）的 5%，这里取 5.5% 留点余量
                  AiTag(fontSize: math.max(15, width * 0.055)),
                  const SizedBox(width: 8),
                ],
                // 还没上架，没有下载二维码，先放 App 图标
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Pop.ink, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset('assets/icon/icon_full.png', fit: BoxFit.cover),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 决策卡的结论：要行动的（带伞、穿秋裤、洗车、晾衣）用黄底
class _DecisionChip extends StatelessWidget {
  const _DecisionChip({required this.title, required this.decision});

  final String title;
  final Decision decision;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: decision.isAction ? Pop.yellow : Pop.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Pop.ink, width: 2),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('$title ${decision.label}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Pop.white, fontSize: 16, height: 1.6, fontWeight: FontWeight.w700)),
    );
  }
}
