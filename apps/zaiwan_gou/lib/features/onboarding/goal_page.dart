import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/dog_meter.dart';
import 'package:pop_ui/pop_ui.dart';
import 'package:avatar_engine/avatar_engine.dart';

class GoalPage extends StatefulWidget {
  const GoalPage({super.key, this.editing = false});

  /// 从“我的”进来修改目标时为 true，保存后返回
  final bool editing;

  @override
  State<GoalPage> createState() => _GoalPageState();
}

class _GoalPageState extends State<GoalPage> {
  late int _hours = (AppScope.read(context).goalMinutes / 60).round().clamp(1, 8);

  void _set(int h) => setState(() => _hours = h.clamp(1, 8));

  Future<void> _save() async {
    final state = AppScope.read(context);
    await state.setGoal(_hours * 60);
    if (!widget.editing) await state.completeOnboarding();
    if (!mounted) return;
    widget.editing ? context.pop() : context.go('/today');
  }

  @override
  Widget build(BuildContext context) {
    final goal = _hours * 60;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            const Text('每天刷多久，还算是个人？', style: PopText.title),
            const SizedBox(height: 8),
            const Text('超过这个时长的三成就开始长耳朵。说实话，别骗自己。', style: PopText.bodyMuted),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _RoundButton(icon: Icons.remove, label: '减少一小时', onTap: () => _set(_hours - 1)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$_hours', style: const TextStyle(fontSize: 88, fontWeight: FontWeight.w900, height: 1)),
                    const SizedBox(width: 6),
                    const Text('小时/天', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ],
                ),
                _RoundButton(icon: Icons.add, label: '增加一小时', filled: true, onTap: () => _set(_hours + 1)),
              ],
            ),
            Slider(
              value: _hours.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              activeColor: Pop.ink,
              label: '$_hours 小时',
              semanticFormatterCallback: (v) => '${v.round()} 小时',
              onChanged: (v) => _set(v.round()),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: Pop.card(),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: Pop.ink,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: const Text('按这个目标，你会这样变狗',
                        style: TextStyle(color: Pop.white, fontSize: 14, fontWeight: FontWeight.w700)),
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
                          DogAvatar(stage: i + 1, size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(DogMeter.nextChange[i],
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          ),
                          Text('刷到 ${DogMeter.formatMinutes((goal * DogMeter.stageThresholds[i] / 100).round())}',
                              style: PopText.small),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            PopButton(label: widget.editing ? '保存' : '就这么定，开始做人', onPressed: _save),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap, this.filled = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: filled ? Pop.yellow : Pop.white,
            shape: BoxShape.circle,
            border: Border.all(color: Pop.ink, width: Pop.stroke),
            boxShadow: const [BoxShadow(color: Pop.ink, offset: Offset(3, 3))],
          ),
          child: Icon(icon, size: 26, color: Pop.ink),
        ),
      ),
    );
  }
}
