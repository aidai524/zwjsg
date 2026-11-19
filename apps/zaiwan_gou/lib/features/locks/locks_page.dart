import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_lock.dart';
import '../../core/dog_meter.dart';
import 'lock_editor_page.dart';

/// 超时来电：选几个 App，每天合计用满额度，你的狗就打电话来问还玩不玩。不禁止，接了可以再玩 10 分钟。免费的基础功能。
class LocksPage extends StatefulWidget {
  /// [service] 只在测试里传
  const LocksPage({super.key, this.service});

  final LockService? service;

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

  Future<void> _edit([AppLock? lock]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LockEditorPage(service: _service!, lock: lock)),
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
                      '选几个最上头的 App，每天合计用满额度，你的狗就打电话过来问你：还确定要玩吗？'
                      '不禁止，接了电话可以再玩 ${LockService.snoozeMinutes} 分钟，到点再打。限时只存在手机上，不上传。',
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
                    for (final lock in _locks)
                      _LockCard(
                        lock: lock,
                        preview: service.selectionPreview(lockId: lock.id),
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
                  ],
                ),
              ),
      ),
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
                  child: Icon(lock.locked ? Icons.phone_in_talk : Icons.timer_outlined,
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
                        '每天 ${DogMeter.formatMinutes(lock.minutes)} · $status',
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
  if (lock.graceActive) return '再玩中，再用满 ${LockService.snoozeMinutes} 分钟又会来电';
  if (lock.locked) return '今天已经超时，打开就来电';
  if (used == null) return '还没到点';
  return '今天用了 ${DogMeter.formatMinutes(used)}，还剩 ${DogMeter.formatMinutes((lock.minutes - used).clamp(0, lock.minutes))}';
}
