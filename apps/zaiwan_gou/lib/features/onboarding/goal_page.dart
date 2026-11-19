import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/dog_meter.dart';
import 'package:pop_ui/pop_ui.dart';
import '../../widgets/my_avatar.dart';

class GoalPage extends StatefulWidget {
  const GoalPage({super.key, this.editing = false});

  /// 从“我的”进来修改目标时为 true，保存后返回
  final bool editing;

  @override
  State<GoalPage> createState() => _GoalPageState();
}

class _GoalPageState extends State<GoalPage> {
  late GoalTier _tier = AppScope.read(context).goalTier;

  Future<void> _save() async {
    final state = AppScope.read(context);
    await state.setGoalTier(_tier);
    if (!widget.editing) {
      await state.completeOnboarding();
      // 引导最后一步顺带打开每晚提醒：按钮下面写了会提醒，系统弹窗问权限时用户知道是为什么
      await state.enableReminder();
    }
    if (!mounted) return;
    widget.editing ? context.pop() : context.go('/today');
  }

  @override
  Widget build(BuildContext context) {
    final goal = _tier.minutes;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        // 内容不多，一次全部建好（ListView 只建屏幕里的，底部按钮测试时找不到）
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('你平时刷手机，算哪一档？', style: PopText.title),
              const SizedBox(height: 8),
              const Text('选的这档就是每天的额度，用到三成就开始长耳朵。说实话，别骗自己。', style: PopText.bodyMuted),
              const SizedBox(height: 18),
              for (final t in GoalTier.values) ...[
                _TierCard(tier: t, selected: t == _tier, onTap: () => setState(() => _tier = t)),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              Container(
                decoration: Pop.card(),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      color: Pop.ink,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Text('按「${_tier.label}」，你会这样变狗',
                          style: const TextStyle(color: Pop.white, fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                    for (var i = 0; i < DogMeter.stageThresholds.length; i++)
                      Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          border: i == 0 ? null : const Border(top: BorderSide(color: Color(0xFFEDEDED), width: 2)),
                        ),
                        child: Row(
                          children: [
                            MyAvatar(stage: i + 1, size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(DogMeter.nextChange[i],
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            ),
                            Text('刷到 ${DogMeter.formatMinutes(DogMeter.stageStartMinutes(i + 1, goal))}',
                                style: PopText.small),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              PopButton(label: widget.editing ? '保存' : '就这么定，开始做人', onPressed: _save),
              if (!widget.editing) ...[
                const SizedBox(height: 12),
                Text(
                  '每晚 ${AppState.formatHhmm(AppState.defaultRemindAt)} 提醒你看结算卡，可以在“我的”里关掉或改时间。',
                  textAlign: TextAlign.center,
                  style: PopText.small,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 一档使用程度：选中的亮黄带阴影
class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier, required this.selected, required this.onTap});

  final GoalTier tier;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hours = DogMeter.formatMinutes(tier.minutes);
    return Semantics(
      button: true,
      selected: selected,
      label: '${tier.label}，每天 $hours。${tier.description}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: Pop.card(color: selected ? Pop.yellow : Pop.white, shadow: selected),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tier.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(tier.description,
                        style: TextStyle(fontSize: 13, color: selected ? Pop.mutedOnYellow : Pop.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(hours, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }
}
