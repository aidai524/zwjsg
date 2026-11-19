import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/dog_meter.dart';
import '../../core/screen_time_channel.dart';
import '../../core/usage_channel.dart';

/// 今日 App 排行，只在手机上显示，不上传。
/// 安卓：原生层给出各 App 的名称、图标和用时，这里画列表。
/// iOS：系统的报告扩展（ios/ScreenTimeReport/）把排行画在嵌入的视图里，Flutter 拿不到数字。
class RankingPage extends StatelessWidget {
  /// [loader] 只在测试里传，代替安卓原生层
  const RankingPage({super.key, this.loader});

  final Future<List<AppUsage>> Function()? loader;

  static const privacyNote = '只在你手机上显示，不上传。';

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (loader != null || UsageChannel.isSupported) {
      body = _AndroidRanking(loader: loader ?? UsageChannel.todayRanking);
    } else if (ScreenTimeChannel.isSupported) {
      body = const _IosRanking();
    } else {
      body = const Center(child: Text('这台设备拿不到使用数据', style: PopText.bodyMuted));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('今日 App 排行')),
      body: SafeArea(child: body),
    );
  }
}

class _AndroidRanking extends StatefulWidget {
  const _AndroidRanking({required this.loader});

  final Future<List<AppUsage>> Function() loader;

  @override
  State<_AndroidRanking> createState() => _AndroidRankingState();
}

class _AndroidRankingState extends State<_AndroidRanking> with WidgetsBindingObserver {
  List<AppUsage>? _items;
  bool _noPermission = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从系统设置开完权限回来时重新读
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.loader();
      if (!mounted) return;
      setState(() {
        _items = items;
        _noPermission = false;
        _error = null;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => e.code == 'NO_PERMISSION' ? _noPermission = true : _error = '读不到使用数据，下拉再试一次');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_noPermission) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('还差一步：打开“使用情况访问权限”', style: PopText.h2),
            SizedBox(height: 8),
            Text('打开后才能看到今天每个 App 用了多久。${RankingPage.privacyNote}', style: PopText.bodyMuted),
            SizedBox(height: 16),
            PopButton(label: '去打开', style: PopButtonStyle.dark, onPressed: UsageChannel.openPermissionSettings),
          ],
        ),
      );
    }
    final items = _items;
    if (items == null && _error == null) return const Center(child: CircularProgressIndicator(color: Pop.ink));

    final top = math.max(1, items?.firstOrNull?.minutes ?? 1);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text(RankingPage.privacyNote, style: PopText.small),
          const SizedBox(height: 12),
          if (_error != null)
            Text(_error!, style: PopText.bodyMuted)
          else if (items!.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Text('今天还没有用满 1 分钟的 App', textAlign: TextAlign.center, style: PopText.bodyMuted),
            )
          else
            for (final (i, app) in items.indexed) _RankRow(rank: i + 1, app: app, fill: app.minutes / top),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.app, required this.fill});

  final int rank;
  final AppUsage app;

  /// 进度条长度：和第一名相比
  final double fill;

  @override
  Widget build(BuildContext context) {
    final icon = app.icon;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Pop.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text('$rank', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: icon == null
                ? const SizedBox(width: 34, height: 34, child: Icon(Icons.apps, color: Pop.muted))
                : Image.memory(icon, width: 34, height: 34, gaplessPlayback: true),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                FractionallySizedBox(
                  widthFactor: fill.clamp(0.04, 1.0),
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 9,
                    decoration: BoxDecoration(
                      color: Pop.yellow,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Pop.ink, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(DogMeter.formatMinutes(app.minutes), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _IosRanking extends StatefulWidget {
  const _IosRanking();

  @override
  State<_IosRanking> createState() => _IosRankingState();
}

class _IosRankingState extends State<_IosRanking> {
  bool? _authorized;

  @override
  void initState() {
    super.initState();
    _check(ScreenTimeChannel.status);
  }

  Future<void> _check(Future<ScreenTimeStatus> Function() action) async {
    try {
      final s = await action();
      if (mounted) setState(() => _authorized = s.authorized);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _authorized = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? '没有拿到授权')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authorized = _authorized;
    if (authorized == null) return const Center(child: CircularProgressIndicator(color: Pop.ink));
    if (!authorized) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('还差一步：授权“屏幕使用时间”', style: PopText.h2),
            const SizedBox(height: 8),
            const Text('授权后能看到今天每个 App 用了多久。排行由系统画在这里，我们读不到具体数字。', style: PopText.bodyMuted),
            const SizedBox(height: 16),
            PopButton(
              label: '去授权',
              style: PopButtonStyle.dark,
              onPressed: () => _check(ScreenTimeChannel.requestAuthorization),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text('${RankingPage.privacyNote}排行由系统画在这里，我们读不到具体数字。', style: PopText.small),
        ),
        Expanded(
          child: UiKitView(
            viewType: 'zwjsg/screen_time_report',
            // 报告里的列表自己会滚动，手势全交给它
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{Factory(() => EagerGestureRecognizer())},
          ),
        ),
      ],
    );
  }
}
