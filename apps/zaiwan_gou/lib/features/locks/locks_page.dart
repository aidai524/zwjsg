import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/app_lock.dart';
import '../../core/dog_meter.dart';
import 'lock_editor_page.dart';

/// App 时间锁：选几个 App，每天合计用满额度就锁到第二天 0 点。免费的基础功能。
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
      _toast(e.message ?? '读不到时间锁，稍后再试');
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
        title: const Text('删掉这个时间锁？'),
        content: Text('${lock.title}\n删掉后马上解锁。'),
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

  /// 紧急解锁前再确认一次，给想放弃的人一个台阶
  Future<void> _grace(AppLock lock) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('真的还要刷？'),
        content: Text('再用 ${LockService.graceMinutes} 分钟，用满自动锁回去。今天还能解锁 ${lock.graceLeft} 次。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('算了，不刷了')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('再刷 ${LockService.graceMinutes} 分钟')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final locks = await _service!.grantGrace(lock.id);
      if (mounted) setState(() => _locks = locks);
    } on PlatformException catch (e) {
      _toast(e.message ?? '没解开，稍后再试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    return Scaffold(
      appBar: AppBar(title: const Text('App 时间锁')),
      body: SafeArea(
        child: service == null
            ? const Center(child: Text('这台设备用不了时间锁', style: PopText.bodyMuted))
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    const Text('选几个 App，每天合计用满额度就锁到第二天 0 点。锁只存在手机上，不上传。', style: PopText.small),
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
                        onGrace: () => _grace(lock),
                      ),
                    if (_locks.isEmpty && _ready == true)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('还没有时间锁', textAlign: TextAlign.center, style: PopText.bodyMuted),
                      ),
                    const SizedBox(height: 8),
                    PopButton(
                      label: '加一个时间锁',
                      onPressed: _ready == true && _locks.length < LockService.maxLocks ? () => _edit() : null,
                    ),
                    if (_locks.length >= LockService.maxLocks) ...[
                      const SizedBox(height: 8),
                      const Text('最多 ${LockService.maxLocks} 个时间锁', textAlign: TextAlign.center, style: PopText.small),
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
    required this.onGrace,
    this.preview,
  });

  final AppLock lock;

  /// iOS：系统画的选中项（图标和名字）
  final Widget? preview;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onGrace;

  @override
  Widget build(BuildContext context) {
    final used = lock.usedMinutes;
    final status = lock.graceActive
        ? '临时解锁中，再用满 ${LockService.graceMinutes} 分钟就锁回去'
        : lock.locked
            ? (lock.graceLeft > 0 ? '今天已锁，明天 0 点解开' : '今天已锁，临时解锁也用完了')
            : used == null
                ? '今天还没用满'
                : '今天用了 ${DogMeter.formatMinutes(used)}，还剩 ${DogMeter.formatMinutes(lock.minutes - used)}';
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
                  child: Icon(lock.locked ? Icons.lock : Icons.lock_open, size: 18, color: lock.locked ? Pop.yellow : Pop.ink),
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
                      if (lock.locked && lock.graceLeft > 0)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                            onPressed: onGrace,
                            child: Text('临时解锁 ${LockService.graceMinutes} 分钟（今天还剩 ${lock.graceLeft} 次）'),
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
