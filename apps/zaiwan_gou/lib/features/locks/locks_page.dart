import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_lock.dart';
import '../../core/app_state.dart';
import '../../core/call_channel.dart';
import '../../core/dog_meter.dart';
import '../call/call_screen.dart';
import '../call/call_voice.dart';
import 'lock_advice_card.dart';
import 'lock_editor_page.dart';

/// 超时来电：选几个 App，每天合计用满额度，狗版的你就打电话来问还玩不玩。接了学两声狗叫，就能再玩 10 分钟；拒接今天锁死。
/// 最上面是狗版的你看了最近 7 天给的建议，一开始就知道该管哪几个。底下能“试一下来电”，iOS 还能“试一下来电通知”。免费的基础功能。
class LocksPage extends StatefulWidget {
  /// [service]、[adviceLoader]、[callBackend]、[noticeTest] 只在测试里传
  const LocksPage({
    super.key,
    this.service,
    this.adviceLoader,
    this.callBackend = const PlatformCallBackend(),
    this.noticeTest,
  });

  final LockService? service;
  final Future<WeekUsage> Function()? adviceLoader;
  final CallBackend callBackend;

  /// 显示“试一下来电通知”：默认只在 iOS 上（安卓的来电页直接盖在 App 上，没有来电通知）
  final bool? noticeTest;

  /// 试一下来电通知过几秒响：够回到桌面或者锁屏
  static const noticeDelay = Duration(seconds: 8);

  @override
  State<LocksPage> createState() => _LocksPageState();
}

class _LocksPageState extends State<LocksPage> with WidgetsBindingObserver {
  late final LockService? _service = widget.service ?? LockService.platform;
  bool? _ready;
  List<AppLock> _locks = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从系统设置开完权限回来时刷新
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final service = _service;
    if (service == null) return;
    try {
      final ready = await service.ready();
      final locks = await service.list();
      if (mounted) {
        setState(() {
          _ready = ready;
          _locks = locks;
        });
      }
    } on PlatformException catch (e) {
      _toast(e.message ?? '读不到限时，稍后再试');
    }
  }

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _setup() async {
    try {
      await _service!.setup();
    } on PlatformException catch (e) {
      _toast(e.message ?? '没打开，稍后再试');
    }
    await _refresh();
  }

  /// [fromAdvice]：从狗版的你的建议点进来的（iOS 读不到建议的是哪几个 App，编辑页直接打开系统的选择页，额度旁边再列一遍建议）
  Future<void> _edit([AppLock? lock, bool fromAdvice = false]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LockEditorPage(service: _service!, lock: lock, fromAdvice: fromAdvice)),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _delete(AppLock lock) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删掉这个限时？'),
        content: Text('${lock.title}\n删掉后不会再来电。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('再想想')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删掉')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final locks = await _service!.delete(lock.id);
      if (mounted) setState(() => _locks = locks);
    } on PlatformException catch (e) {
      _toast(e.message ?? '没删掉，稍后再试');
    }
  }

  /// 试一下的来电：用第一个限时（没有就用个示例），不锁也不放行
  IncomingCall _previewCall() {
    final lock = _locks.isEmpty ? null : _locks.first;
    final used = lock?.usedMinutes;
    return IncomingCall(
      lockId: 'preview',
      limitMinutes: lock?.minutes ?? 60,
      dogPercent: lock?.dogPercent,
      label: lock == null ? '某短视频' : (lock.labels.isEmpty ? null : lock.title),
      apps: lock?.apps ?? 0,
      categories: lock?.categories ?? 0,
      webDomains: lock?.webDomains ?? 0,
      usedMinutes: lock == null ? 75 : (used == null ? null : math.max(used, lock.minutes)),
      stage: AppScope.of(context).stage,
      preview: true,
    );
  }

  /// 试一下来电：马上弹出来电界面，响铃、说话、听狗叫都是真的
  void _tryCall() => showCallScreen(context, _previewCall(), backend: widget.callBackend);

  /// 试一下来电通知（iOS）：过几秒响一条和真的一样的来电通知，点它回到 App 就是来电界面。要先离开 App，在 App 里面不弹
  Future<void> _tryNotice() async {
    final seconds = LocksPage.noticeDelay.inSeconds;
    final result = await widget.callBackend.previewNotice(_previewCall(), delay: LocksPage.noticeDelay);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    switch (result) {
      case 'scheduled':
        _toast('$seconds 秒后狗版的你打来。先回到桌面或者锁屏，等它响，再点通知接听');
      case 'noSound':
        _toast('$seconds 秒后会弹来电通知，但这个 App 的通知声音关着，听不到铃声。先回到桌面或者锁屏');
      case 'denied':
        messenger.showSnackBar(SnackBar(
          content: const Text('通知没开，用满时收不到来电。去设置里打开「再玩我是狗」的通知'),
          action: SnackBarAction(label: '去设置', onPressed: widget.callBackend.openSettings),
        ));
      default:
        _toast('没发出去，稍后再试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    return Scaffold(
      appBar: AppBar(title: const Text('超时来电')),
      body: SafeArea(
        child: service == null
            ? const Center(child: Text('这台设备用不了超时来电', style: PopText.bodyMuted))
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    const Text(
                      '选几个最上头的 App，每天合计用满额度，狗版的你就打电话过来问你：还确定要玩吗？'
                      '接了电话学两声狗叫，就能再玩 ${LockService.snoozeMinutes} 分钟，到点再打；拒接就今天锁死，明天 0 点解开。'
                      '限时只存在手机上，不上传。',
                      style: PopText.small,
                    ),
                    const SizedBox(height: 16),
                    if (_ready == false) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: Pop.card(color: Pop.softYellow, shadow: false),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(service.setupTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text(service.setupBody, style: const TextStyle(fontSize: 13, height: 1.5)),
                            const SizedBox(height: 10),
                            PopButton(
                              label: service.setupAction,
                              style: PopButtonStyle.dark,
                              height: 46,
                              onPressed: _setup,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_ready != null)
                      LockAdviceCard(
                        service: service,
                        locks: _locks,
                        ready: _ready!,
                        loader: widget.adviceLoader,
                        onApplied: _refresh,
                        onSetup: _setup,
                        onPick: () => _edit(null, true),
                      ),
                    for (final lock in _locks)
                      _LockCard(
                        lock: lock,
                        preview: service.selectionPreview(
                            lockId: lock.id, count: lock.apps + lock.categories + lock.webDomains),
                        onTap: () => _edit(lock),
                        onDelete: () => _delete(lock),
                      ),
                    if (_locks.isEmpty && _ready == true)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('还没设限时', textAlign: TextAlign.center, style: PopText.bodyMuted),
                      ),
                    const SizedBox(height: 8),
                    PopButton(
                      label: '加一个限时',
                      onPressed: _ready == true && _locks.length < LockService.maxLocks ? () => _edit() : null,
                    ),
                    if (_locks.length >= LockService.maxLocks) ...[
                      const SizedBox(height: 8),
                      const Text('最多 ${LockService.maxLocks} 个限时', textAlign: TextAlign.center, style: PopText.small),
                    ],
                    const SizedBox(height: 20),
                    _VoicePicker(onPreview: (voice) => widget.callBackend.playVoice(voice.asset(CallVoice.sample))),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        onPressed: _tryCall,
                        icon: const Icon(Icons.phone_in_talk, size: 18),
                        label: const Text('试一下来电：听听狗版的你打来是什么样'),
                        style: TextButton.styleFrom(foregroundColor: Pop.ink),
                      ),
                    ),
                    if (widget.noticeTest ?? Platform.isIOS)
                      Center(
                        child: TextButton.icon(
                          onPressed: _tryNotice,
                          icon: const Icon(Icons.notifications_active_outlined, size: 18),
                          label: Text('试一下来电通知：${LocksPage.noticeDelay.inSeconds} 秒后响，先回到桌面'),
                          style: TextButton.styleFrom(foregroundColor: Pop.ink),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// 狗版的你的声音：用户自己挑（打来的是用户自己，男生女生可能想要不一样的声音），点一下就试听
class _VoicePicker extends StatelessWidget {
  const _VoicePicker({required this.onPreview});

  final ValueChanged<CallVoice> onPreview;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.maybeOf(context);
    if (state == null) return const SizedBox.shrink();
    final selected = CallVoice.byName(state.callVoiceName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('狗版的你的声音', style: PopText.label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final voice in CallVoice.values)
              ChoiceChip(
                label: Text(voice == CallVoice.fallback ? '${voice.label}（默认）' : voice.label),
                selected: voice == selected,
                onSelected: (_) {
                  state.setCallVoiceName(voice.name);
                  onPreview(voice);
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        const Text('点一下就能试听。AI 合成语音（MiniMax），提前装在 App 里，来电时不联网。', style: PopText.small),
      ],
    );
  }
}

class _LockCard extends StatelessWidget {
  const _LockCard({
    required this.lock,
    required this.onTap,
    required this.onDelete,
    this.preview,
  });

  final AppLock lock;

  /// iOS：系统画的选中项（图标和名字）
  final Widget? preview;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final status = limitStatus(lock);
    // 白底：iOS 的选中项是系统画的深色字，放在深色底上看不清
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Pop.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: lock.locked ? const BorderSide(color: Pop.ink, width: 2) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: lock.locked ? Pop.ink : Pop.gray,
                  child: Icon(lock.declined ? Icons.lock : (lock.locked ? Icons.phone_in_talk : Icons.timer_outlined),
                      size: 18, color: lock.locked ? Pop.yellow : Pop.ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lock.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                      ),
                      if (preview != null) ...[const SizedBox(height: 6), preview!],
                      const SizedBox(height: 4),
                      Text(
                        '${lock.rule} · $status',
                        style: TextStyle(
                          fontSize: 13,
                          color: lock.locked ? Pop.ink : Pop.muted,
                          fontWeight: lock.locked ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '删掉',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: Pop.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一个限时今天的状态，设置页和“今天”页的卡片共用
String limitStatus(AppLock lock) {
  final used = lock.usedMinutes;
  if (lock.declined) return '拒接了来电，今天锁死';
  if (lock.graceActive) return '再玩中，再用满 ${LockService.snoozeMinutes} 分钟又会来电';
  if (lock.byDog) return lock.locked ? '今天狗度到了，打开就来电' : '今天狗度还没到';
  if (lock.locked) return '今天已经超时，打开就来电';
  if (used == null) return '还没到点';
  return '今天用了 ${DogMeter.formatMinutes(used)}，还剩 ${DogMeter.formatMinutes((lock.minutes - used).clamp(0, lock.minutes))}';
}
