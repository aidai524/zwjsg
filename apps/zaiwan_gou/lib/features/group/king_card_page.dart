import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pop_ui/pop_ui.dart';
import 'package:series_share/series_share.dart';

import '../../core/breeds.dart';
import '../../core/dog_meter.dart';
import '../../core/groups.dart';
import 'member_avatar.dart';

/// 狗王调侃卡：昨天群里最狗的人，3:4，能存相册、用系统分享发出去。
/// 狗王用的是拍照形象（AI 生成）时，卡上标“AI生成”，图片文件里也写上隐式标识。
class KingCardPage extends StatefulWidget {
  const KingCardPage({
    super.key,
    required this.king,
    required this.groupName,
    this.exporter = const DefaultCardExporter(appName: '再玩我是狗', filePrefix: 'zaiwangou-king'),
  });

  final KingOfDay king;
  final String groupName;
  final CardExporter exporter;

  /// 损友语气的调侃，按狗王那天的阶段（不拿身材、长相开玩笑）
  static const _roasts = [
    '昨天全员做人，没有狗王',
    '冒个耳朵就封王了，这群人是有多自律',
    '鼻子湿了一整天，狗王实至名归',
    '毛都长齐了，今天把手机交给群主保管吧',
    '舌头收不回去，狗王请大家喝奶茶（不是）',
    '完全体狗王，汪！今天先从放下手机开始',
  ];

  static String roastFor(int stage) => _roasts[stage.clamp(0, _roasts.length - 1)];

  @override
  State<KingCardPage> createState() => _KingCardPageState();
}

class _KingCardPageState extends State<KingCardPage> {
  final _cardKey = GlobalKey();
  final _shareKey = GlobalKey();
  bool _busy = false;

  /// 狗王上传过拍照形象：是 AI 生成的
  bool get _ai => widget.king.avatarUrl != null;

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _export(Future<void> Function(Uint8List png) action, {String? done, required String failed}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      var png = await widget.exporter.capture(_cardKey);
      if (_ai) png = AigcLabel.embed(png, producer: '再玩我是狗');
      await action(png);
      if (done != null) _toast(done);
    } on CardExportException catch (e) {
      _toast(e.message);
    } on PlatformException {
      _toast(failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _export(widget.exporter.save, done: '已保存到相册', failed: '没存上，稍后再试');

  Future<void> _share() {
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    return _export((png) => widget.exporter.share(png, origin: origin), failed: '分享面板没打开，稍后再试');
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.king;
    final d = DateTime.tryParse(k.date);
    final breed = breedByKey(k.breedKey);
    return Scaffold(
      backgroundColor: Pop.ink,
      appBar: AppBar(
        systemOverlayStyle: Pop.overlayOnDark,
        foregroundColor: Pop.white,
        backgroundColor: Pop.ink,
        leading: IconButton(tooltip: '关闭', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: const Text('狗王调侃卡'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: RepaintBoundary(
                      key: _cardKey,
                      child: LayoutBuilder(builder: (_, c) {
                        final w = c.maxWidth;
                        return Container(
                          decoration: BoxDecoration(
                            color: Pop.white,
                            borderRadius: BorderRadius.circular(w * 0.06),
                            border: Border.all(color: Pop.legendGold, width: w * 0.02),
                          ),
                          padding: EdgeInsets.all(w * 0.06),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.emoji_events, color: Pop.legendGold, size: w * 0.08),
                                  SizedBox(width: w * 0.02),
                                  Text('昨日狗王', style: TextStyle(fontSize: w * 0.065, fontWeight: FontWeight.w900)),
                                ],
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '「${widget.groupName}」${d == null ? '' : ' · ${d.month} 月 ${d.day} 日'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: w * 0.04, color: Pop.muted, fontWeight: FontWeight.w700),
                                ),
                              ),
                              const Spacer(),
                              MemberBadge(url: k.avatarUrl, preset: k.avatarPreset, stage: k.stage, size: w * 0.44, highlight: true),
                              SizedBox(height: w * 0.025),
                              Text(k.nickname,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: w * 0.08, fontWeight: FontWeight.w900)),
                              Text(
                                '狗度 ${k.dogPercent}% · ${DogMeter.stageNames[k.stage]}${breed == null ? '' : ' · ${breed.name}'}',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: w * 0.042, fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: w * 0.03),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: w * 0.04, vertical: w * 0.025),
                                decoration: BoxDecoration(
                                  color: Pop.softYellow,
                                  borderRadius: BorderRadius.circular(w * 0.03),
                                ),
                                child: Text(KingCardPage.roastFor(k.stage),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: w * 0.045, fontWeight: FontWeight.w900)),
                              ),
                              const Spacer(),
                              Row(
                                children: [
                                  Text('再玩我是狗 · 刷多了就变狗', style: TextStyle(fontSize: w * 0.035, color: Pop.muted)),
                                  const Spacer(),
                                  if (_ai) AiTag(fontSize: w * 0.035),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: PopButton(label: '存到相册', style: PopButtonStyle.secondary, loading: _busy, onPressed: _save),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: PopButton(key: _shareKey, label: '分享', loading: _busy, onPressed: _share)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
