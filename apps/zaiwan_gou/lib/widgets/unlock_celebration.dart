import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../core/app_state.dart';
import '../core/breeds.dart';
import '../features/card/card_page.dart';
import 'my_avatar.dart';

/// 首次获得新犬种时弹解锁动画（需求文档 P0“犬种解锁”）。
/// 挂在底部导航外面，在哪个 Tab 都能弹；一次解锁了几种就一个个弹，看过一个删一个。
class UnlockListener extends StatefulWidget {
  const UnlockListener({super.key, required this.child});

  final Widget child;

  @override
  State<UnlockListener> createState() => _UnlockListenerState();
}

class _UnlockListenerState extends State<UnlockListener> {
  bool _showing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 订阅 AppState：上报结果回来、有新解锁时会走到这里
    if (AppScope.of(context).newlyUnlocked.isNotEmpty && !_showing) {
      _showing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showAll());
    }
  }

  Future<void> _showAll() async {
    final state = AppScope.read(context);
    try {
      while (state.newlyUnlocked.isNotEmpty) {
        if (!mounted) return;
        final key = state.newlyUnlocked.first;
        final breed = breedByKey(key);
        // 认不出的犬种（两端配置没对齐）就不弹了
        final goDex = breed != null && await showUnlockDialog(context, breed) == true;
        await state.markUnlockSeen(key);
        if (!mounted) return;
        if (goDex) context.go('/dex');
      }
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 弹出解锁动画；点了“去图鉴看看”返回 true
Future<bool?> showUnlockDialog(BuildContext context, Breed breed) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0x991B1B1F),
    transitionDuration: const Duration(milliseconds: 500),
    pageBuilder: (_, __, ___) => UnlockDialog(breed: breed),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut, reverseCurve: Curves.easeIn),
        child: child,
      ),
    ),
  );
}

class UnlockDialog extends StatelessWidget {
  const UnlockDialog({super.key, required this.breed});

  final Breed breed;

  @override
  Widget build(BuildContext context) {
    final frame = CardPage.frameColor(breed.rarity);
    final tagFg = breed.rarity == Rarity.legend ? Pop.ink : Pop.white;
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: '解锁新犬种：${breed.name}',
          child: Container(
            width: 300,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            decoration: Pop.card(color: Pop.softYellow, radius: 28, border: frame),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('解锁新犬种', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: frame, borderRadius: BorderRadius.circular(8)),
                      child: Text(breed.rarity.label,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: tagFg)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _Wobble(
                  child: Container(
                    width: 164,
                    height: 164,
                    decoration: BoxDecoration(
                      color: Pop.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: frame, width: 4),
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.bottomCenter,
                    child: MyAvatar(stage: breed.previewStage, size: 150),
                  ),
                ),
                const SizedBox(height: 12),
                Text(breed.name, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, height: 1.1)),
                const SizedBox(height: 4),
                Text(breed.quip, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('解锁条件：${breed.rule}',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Pop.mutedOnYellow)),
                const SizedBox(height: 16),
                PopButton(
                  label: '去图鉴看看',
                  style: PopButtonStyle.dark,
                  height: 50,
                  onPressed: () => Navigator.pop(context, true),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('知道了', style: TextStyle(color: Pop.ink, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 形象弹出来时晃两下
class _Wobble extends StatelessWidget {
  const _Wobble({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.elasticOut,
      child: child,
      builder: (_, v, child) => Transform.rotate(
        angle: -0.35 * (1 - v),
        child: Transform.scale(scale: 0.6 + 0.4 * v, child: child),
      ),
    );
  }
}
