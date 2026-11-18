import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/scene.dart';
import '../../core/temp_unit.dart';
import '../../widgets/common.dart';
import '../../widgets/weather_avatars.dart';
import 'import_avatar_sheet.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _heading = TextStyle(fontSize: 18, fontWeight: FontWeight.w900);

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('嘴有多毒', style: _heading),
          const SizedBox(height: 4),
          const Text('只影响吐槽，不影响天气。预警时自动切成正经。', style: TextStyle(fontSize: 12, color: Pop.muted)),
          const SizedBox(height: 12),
          _Choices(labels: snarkLevels, selected: state.snarkLevel, onSelect: state.setSnark),
          const SizedBox(height: 28),
          const Text('温度单位', style: _heading),
          const SizedBox(height: 4),
          const Text('数据源给的是摄氏度，选华氏度时换算后显示。', style: TextStyle(fontSize: 12, color: Pop.muted)),
          const SizedBox(height: 12),
          _Choices(
            labels: [for (final u in TempUnit.values) u.label],
            selected: state.tempUnit.index,
            onSelect: (i) => state.setTempUnit(TempUnit.values[i]),
          ),
          const SizedBox(height: 28),
          const PushSection(),
          const SizedBox(height: 28),
          const Text('我的形象', style: _heading),
          const SizedBox(height: 4),
          const Text('从「再玩我是狗」导入卡通形象，让它在这里替你遭罪。', style: TextStyle(fontSize: 12, color: Pop.muted)),
          const SizedBox(height: 12),
          const AvatarSection(),
          const SizedBox(height: 28),
          const Text('账号', style: _heading),
          const SizedBox(height: 12),
          if (!state.isLoggedIn)
            PopButton(label: '登录（关心群需要）', onPressed: () => context.push('/login'))
          else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('退出登录'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => state.logout(),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('注销账号', style: TextStyle(color: Pop.danger)),
              subtitle: const Text('删除账号、城市、关心群记录和形象，不能恢复'),
              onTap: () => _confirmDelete(context, state),
            ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('隐私政策'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/privacy'),
          ),
          const SourceNote('预警信息来自当地气象部门\n吐槽文案为人工撰写，不改写预报结论'),
          const QWeatherCredit(),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确定注销？'),
        content: const Text('账号和所有数据会被删除，不能恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('算了')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('注销', style: TextStyle(color: Pop.danger))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await state.deleteAccount();
      if (context.mounted) showToast(context, '已注销');
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.message);
    }
  }
}

/// 我的形象：显示现在用的形象，可以从“再玩我是狗”导入、重新导入，或者用回默认形象
class AvatarSection extends StatelessWidget {
  const AvatarSection({super.key});

  Future<void> _import(BuildContext context) async {
    if (await showImportAvatarSheet(context) == true && context.mounted) showToast(context, '导入好了，回首页看它遭罪');
  }

  Future<void> _reset(BuildContext context) async {
    final state = AppScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('用回默认形象？'),
        content: const Text('导入的形象会从手机上删掉，登录了的话服务器上的也删掉。想再用，回「再玩我是狗」重新导出。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('算了')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('用回默认')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await state.clearAvatar();
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imported = AppScope.of(context).avatar != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: Pop.card(),
      child: Row(
        children: [
          const MyWeatherAvatar(temp: WeatherTemp.mild, cond: WeatherCond.cloudy, size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(imported ? '用的是导入的形象' : '现在是默认形象', style: const TextStyle(fontWeight: FontWeight.w800)),
                if (imported)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: () => _reset(context),
                    child: const Text('用回默认形象', style: TextStyle(fontSize: 13, color: Pop.muted)),
                  ),
              ],
            ),
          ),
          TextButton(onPressed: () => _import(context), child: Text(imported ? '重新导入' : '导入')),
        ],
      ),
    );
  }
}

/// 一排只能选一个的卡片：毒舌档位、温度单位
class _Choices extends StatelessWidget {
  const _Choices({required this.labels, required this.selected, required this.onSelect});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              button: true,
              selected: selected == i,
              child: GestureDetector(
                onTap: () => onSelect(i),
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: Pop.card(color: selected == i ? Pop.yellow : Pop.white, shadow: selected == i),
                  child: Text(labels[i], style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 推送：早安播报（工作日、周末分开设时间）和预警推送。推送要发到账号上，所以登录后才能设，设置存在服务端
class PushSection extends StatefulWidget {
  const PushSection({super.key});

  static const weekdayTimes = ['06:30', '07:00', '07:30', '08:00', '08:30', '09:00'];
  static const weekendTimes = ['07:30', '08:00', '08:30', '09:00', '09:30', '10:00', '10:30'];

  @override
  State<PushSection> createState() => _PushSectionState();
}

class _PushSectionState extends State<PushSection> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 进设置页、或者刚登录回来，拉一次推送设置
    final state = AppScope.of(context);
    if (state.isLoggedIn && state.push == null && !state.pushLoading && state.pushError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppScope.read(context).loadPush();
      });
    }
  }

  Future<void> _update(PushSettings next) async {
    try {
      await AppScope.read(context).updatePush(next);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  Future<void> _pickTime(String title, String current, List<String> presets, PushSettings Function(String) apply) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Pop.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: PopText.h2),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in presets)
                    ChoiceChip(label: Text(t), selected: t == current, onSelected: (_) => Navigator.pop(c, t)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != current && mounted) await _update(apply(picked));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final push = state.push;

    final Widget body;
    if (!state.isLoggedIn) {
      body = const Text('登录后可以设置：推送要发到你的账号上。', style: TextStyle(fontSize: 14, color: Pop.muted));
    } else if (push == null) {
      final error = state.pushError;
      body = error == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 3, color: Pop.ink)),
              ),
            )
          : Row(
              children: [
                Expanded(child: Text('推送设置没拉到：$error', style: const TextStyle(fontSize: 14, color: Pop.muted))),
                TextButton(onPressed: state.loadPush, child: const Text('重试')),
              ],
            );
    } else {
      body = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: Pop.card(shadow: false),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('早安播报', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('每天一句话天气，按常驻城市'),
              value: push.morningOn,
              activeThumbColor: Pop.ink,
              onChanged: (v) => _update(push.copyWith(morningOn: v)),
            ),
            if (push.morningOn) ...[
              _TimeRow(
                label: '工作日',
                value: push.weekday,
                onTap: () => _pickTime(
                    '工作日几点推', push.weekday, PushSection.weekdayTimes, (t) => push.copyWith(weekday: t)),
              ),
              _TimeRow(
                label: '周末',
                value: push.weekend,
                onTap: () =>
                    _pickTime('周末几点推', push.weekend, PushSection.weekendTimes, (t) => push.copyWith(weekend: t)),
              ),
            ],
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('预警推送', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('常驻城市有黄色及以上预警时推一次，原文照登'),
              value: push.alertOn,
              activeThumbColor: Pop.ink,
              onChanged: (v) => _update(push.copyWith(alertOn: v)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('推送', style: SettingsPage._heading),
        const SizedBox(height: 4),
        const Text('推送通道还在接入：设置先保存，接好后按这里推送。', style: TextStyle(fontSize: 12, color: Pop.muted)),
        const SizedBox(height: 12),
        body,
      ],
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 12),
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 15)),
      trailing: Text('$value  ›', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      onTap: onTap,
    );
  }
}
