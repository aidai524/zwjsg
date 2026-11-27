import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../widgets/my_avatar.dart';

/// 来电界面的颜色：接听、挂断用手机通话界面常见的绿和红，其余是深色底上的白
class CallColors {
  CallColors._();

  static const accept = Color(0xFF34C759);
  static const decline = Color(0xFFFF3B30);
  static const night = Color(0xFF17171A);

  /// 深色底上半透明的白（控制面板、提示条、没选中的按钮）
  static const glass = Color(0x2EFFFFFF);
  static const faint = Color(0xB3FFFFFF);
}

/// 系统开了“减弱动态效果”（测试里也是）：只画静止的一帧
bool _still(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

const _grayscale = ColorFilter.matrix([
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// 整页背景：放大、模糊的狗版的你，像来电时铺满屏幕的联系人海报；上下压暗，字和按钮看得清
class CallBackdrop extends StatelessWidget {
  const CallBackdrop({super.key, required this.stage, this.gloomy = false});

  final int stage;

  /// 拒接了、锁死了：再暗一点，褪成灰的
  final bool gloomy;

  @override
  Widget build(BuildContext context) {
    Widget poster = MyAvatar(stage: stage, size: 560);
    if (gloomy) poster = ColorFiltered(colorFilter: _grayscale, child: poster);
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF5A4A1E), CallColors.night],
              ),
            ),
          ),
          ClipRect(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 42, sigmaY: 42, tileMode: TileMode.decal),
              child: Align(
                alignment: const Alignment(0, -0.62),
                child: OverflowBox(maxWidth: double.infinity, maxHeight: double.infinity, child: poster),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  CallColors.night.withValues(alpha: gloomy ? 0.7 : 0.3),
                  CallColors.night.withValues(alpha: gloomy ? 0.62 : 0.12),
                  CallColors.night.withValues(alpha: 0.82),
                  CallColors.night.withValues(alpha: 0.96),
                ],
                stops: const [0, 0.4, 0.72, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 形象在干什么：响铃时一圈圈往外扩的波纹，说话时一层层的光晕，听狗叫时亮着一圈
enum CallAvatarMood { ringing, speaking, listening, quiet, sad }

/// 圆框里的狗版的你；[hops] 每加 1 就跳一下（听到一声狗叫）
class CallAvatar extends StatefulWidget {
  const CallAvatar({super.key, required this.stage, required this.mood, this.size = 168, this.hops = 0});

  final int stage;
  final CallAvatarMood mood;
  final double size;
  final int hops;

  @override
  State<CallAvatar> createState() => _CallAvatarState();
}

class _CallAvatarState extends State<CallAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this);
  bool _isStill = false;

  bool get _moving => switch (widget.mood) {
        CallAvatarMood.ringing || CallAvatarMood.speaking || CallAvatarMood.listening => true,
        _ => false,
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isStill = _still(context);
    _sync();
  }

  @override
  void didUpdateWidget(CallAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) _sync();
  }

  void _sync() {
    _pulse.stop();
    if (!_moving || _isStill) {
      _pulse.value = 0.3;
      return;
    }
    // 响铃的波纹跟着铃声一句一句来（2.4 秒一轮）；说话、听的时候快一些
    _pulse.duration = Duration(milliseconds: widget.mood == CallAvatarMood.ringing ? 2400 : 1100);
    _pulse.repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final sad = widget.mood == CallAvatarMood.sad;
    Widget face = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: Pop.paper,
        shape: BoxShape.circle,
        border: Border.all(color: sad ? const Color(0x80FFFFFF) : Pop.yellow, width: 5),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.bottomCenter,
      child: MyAvatar(stage: widget.stage, size: s * 0.92),
    );
    if (sad) face = ColorFiltered(colorFilter: _grayscale, child: face);
    face = TweenAnimationBuilder<double>(
      key: ValueKey(widget.hops),
      tween: Tween(begin: widget.hops == 0 || _isStill ? 0 : 1, end: 0),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOut,
      builder: (context, t, child) => Transform.translate(offset: Offset(0, -math.sin(t * math.pi) * 22), child: child),
      child: face,
    );
    return SizedBox.square(
      dimension: s * 1.75,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => CustomPaint(
          painter: _AuraPainter(t: _pulse.value, mood: widget.mood, radius: s / 2),
          child: child,
        ),
        child: Center(child: face),
      ),
    );
  }
}

class _AuraPainter extends CustomPainter {
  _AuraPainter({required this.t, required this.mood, required this.radius});

  final double t;
  final CallAvatarMood mood;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    switch (mood) {
      case CallAvatarMood.ringing:
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        for (var k = 0; k < 3; k++) {
          final p = (t + k / 3) % 1;
          ring.color = Colors.white.withValues(alpha: (1 - p) * 0.5);
          canvas.drawCircle(c, radius * (1.04 + 0.7 * p), ring);
        }
      case CallAvatarMood.speaking:
        final wave = math.sin(t * 2 * math.pi);
        canvas.drawCircle(c, radius * (1.2 + 0.1 * (0.5 + 0.5 * math.sin(t * 2 * math.pi + 1.3))),
            Paint()..color = Pop.yellow.withValues(alpha: 0.13));
        canvas.drawCircle(c, radius * (1.09 + 0.06 * (0.5 + 0.5 * wave)), Paint()..color = Pop.yellow.withValues(alpha: 0.26));
      case CallAvatarMood.listening:
        canvas.drawCircle(
          c,
          radius * (1.1 + 0.03 * math.sin(t * 2 * math.pi)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = Pop.yellow.withValues(alpha: 0.75),
        );
      case CallAvatarMood.quiet:
      case CallAvatarMood.sad:
        break;
    }
  }

  @override
  bool shouldRepaint(_AuraPainter old) => old.t != t || old.mood != mood || old.radius != radius;
}

/// 按下去缩一点，像真的按钮
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (widget.onTap != null && _down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(scale: _down ? 0.9 : 1, duration: const Duration(milliseconds: 110), child: widget.child),
    );
  }
}

/// 圆形的通话按钮，下面一行字
class CallButton extends StatelessWidget {
  const CallButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.iconColor = Colors.white,
    this.onTap,
    this.size = 74,
    this.semanticsLabel,
    this.child,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback? onTap;
  final double size;

  /// 读屏念的；默认就是 [label]
  final String? semanticsLabel;

  /// 代替图标（接听键要晃）
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      child: _Pressable(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: child ?? Icon(icon, color: iconColor, size: size * 0.44),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/// 绿色的接听键：电话图标一阵一阵地晃，外面一圈光往外扩，像真的来电
class AcceptCallButton extends StatefulWidget {
  const AcceptCallButton({super.key, required this.onTap, this.size = 74});

  final VoidCallback onTap;
  final double size;

  @override
  State<AcceptCallButton> createState() => _AcceptCallButtonState();
}

class _AcceptCallButtonState extends State<AcceptCallButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        // 往外扩的一圈光
        Positioned(
          top: 0,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              return IgnorePointer(
                child: Transform.scale(
                  scale: 1 + 0.45 * t,
                  child: Container(
                    width: s,
                    height: s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: CallColors.accept.withValues(alpha: _c.isAnimating ? 0.45 * (1 - t) : 0),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        CallButton(
          icon: Icons.call,
          label: '接听',
          color: CallColors.accept,
          size: s,
          onTap: widget.onTap,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final t = _c.value;
              // 前 40% 的时间晃几下，后面停一停
              final shake = t < 0.4 ? math.sin(t / 0.4 * math.pi * 6) * 0.24 * (1 - t / 0.4) : 0.0;
              return Transform.rotate(angle: shake, child: child);
            },
            child: Icon(Icons.call, color: Colors.white, size: s * 0.44),
          ),
        ),
      ],
    );
  }
}

/// 通话中的按钮放在一块半透明的面板上
class CallControls extends StatelessWidget {
  const CallControls({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
      decoration: BoxDecoration(color: CallColors.glass, borderRadius: BorderRadius.circular(32)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: children),
    );
  }
}

/// 狗版的你说的话：像实时字幕，一句一句冒出来；旧的淡一点，最多留 [maxLines] 句
class CallCaptions extends StatelessWidget {
  const CallCaptions({super.key, required this.lines, this.maxLines = 3});

  final List<String> lines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final shown = lines.length > maxLines ? lines.sublist(lines.length - maxLines) : lines;
    final first = lines.length - shown.length;
    final still = _still(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++)
          _Bubble(key: ValueKey('${first + i}:${shown[i]}'), text: shown[i], faded: i < shown.length - 1, still: still),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.text, required this.faded, required this.still});

  final String text;
  final bool faded;
  final bool still;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedOpacity(
        opacity: faded ? 0.62 : 1,
        duration: const Duration(milliseconds: 300),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: still ? 1 : 0, end: 1),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) =>
              Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: child)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 330),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Text(text, style: const TextStyle(fontSize: 16, height: 1.4, fontWeight: FontWeight.w800, color: Pop.ink)),
          ),
        ),
      ),
    );
  }
}

/// 学狗叫：两个爪印格子（听到一声就盖一个章），下面一行写刚才那声判成了什么、像狗多少，再下面是跟着声音跳的波形
class BarkMeter extends StatelessWidget {
  const BarkMeter({
    super.key,
    required this.heard,
    this.levels = const [],
    this.need = 2,
    this.listening = true,
    this.paused = false,
    this.note,
  });

  final int heard;

  /// 最近的音量（dBFS），画波形
  final List<double> levels;
  final int need;

  /// 学狗叫的这一阶段：画波形和“我在听”
  final bool listening;

  /// 狗版的你正在插话，这会儿没在听
  final bool paused;

  /// 刚才那声判成了什么，比如“这声像狗 63%”
  final String? note;

  @override
  Widget build(BuildContext context) {
    final still = _still(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          container: true,
          label: '听到 $heard 声',
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < need; i++) ...[
                if (i > 0) const SizedBox(width: 26),
                _PawSlot(filled: i < heard, still: still),
              ],
            ],
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(
            note!,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white, height: 1.35),
          ),
        ],
        if (listening) ...[
          const SizedBox(height: 10),
          SizedBox(width: 240, height: 44, child: CustomPaint(painter: _WavePainter(levels))),
          const SizedBox(height: 6),
          Text(
            paused ? '狗版的你在说话，说完接着听' : '我在听…只在手机上听，不录音',
            style: const TextStyle(fontSize: 12.5, color: CallColors.faint),
          ),
        ],
      ],
    );
  }
}

class _PawSlot extends StatelessWidget {
  const _PawSlot({required this.filled, required this.still});

  final bool filled;
  final bool still;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(filled),
      tween: Tween(begin: filled && !still ? 0.45 : 1, end: 1),
      duration: const Duration(milliseconds: 480),
      curve: Curves.elasticOut,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          color: filled ? Pop.yellow : const Color(0x14FFFFFF),
          shape: BoxShape.circle,
          border: Border.all(color: filled ? Pop.ink : const Color(0x8CFFFFFF), width: filled ? 3 : 2),
        ),
        child: Icon(Icons.pets, size: 32, color: filled ? Pop.ink : const Color(0x4DFFFFFF)),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.levels);

  final List<double> levels;

  static const bars = 30;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    final w = (size.width - gap * (bars - 1)) / bars;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w;
    final mid = size.height / 2;
    for (var i = 0; i < bars; i++) {
      final index = levels.length - bars + i;
      final db = index >= 0 ? levels[index] : -80.0;
      // -60 dB 以下是一个点，-15 dB 顶满
      final v = ((db + 60) / 45).clamp(0.0, 1.0);
      final h = math.max(0.0, v * (size.height - w));
      final x = i * (w + gap) + w / 2;
      paint.color = Colors.white.withValues(alpha: 0.3 + 0.7 * i / (bars - 1));
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}

/// 按住不放 [progress] 从 0 走到 1：没开麦克风时代替学狗叫
class HoldToConfirm extends StatelessWidget {
  const HoldToConfirm({super.key, required this.label, required this.progress, required this.onDown, required this.onUp});

  final String label;
  final double progress;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (_) => onDown(),
        onPointerUp: (_) => onUp(),
        onPointerCancel: (_) => onUp(),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress.clamp(0.0, 1.0),
                child: const ColoredBox(color: Color(0x80FFD23F)),
              ),
              Center(
                child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 拒接以后：一张锁死了的卡片（白底黑框，亮黄的硬阴影）
class LockedCard extends StatelessWidget {
  const LockedCard({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        color: Pop.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Pop.ink, width: Pop.stroke),
        boxShadow: const [BoxShadow(color: Pop.yellow, offset: Pop.shadowOffset)],
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Pop.yellow,
              shape: BoxShape.circle,
              border: Border.all(color: Pop.ink, width: Pop.stroke),
            ),
            child: const Icon(Icons.lock, color: Pop.ink, size: 28),
          ),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: PopText.h2.copyWith(fontSize: 22)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: PopText.body),
        ],
      ),
    );
  }
}

/// 深色底上的小提示条
class CallHint extends StatelessWidget {
  const CallHint({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 14, 7),
      decoration: BoxDecoration(color: CallColors.glass, borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

/// “语音通话…”后面的三个点一个一个冒出来
class CallingDots extends StatefulWidget {
  const CallingDots({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<CallingDots> createState() => _CallingDotsState();
}

class _CallingDotsState extends State<CallingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final dots = (_c.value * 4).floor().clamp(0, 3);
        // 点的位置先占好，字不会左右跳
        return Text.rich(
          TextSpan(children: [
            TextSpan(text: widget.text),
            TextSpan(text: '.' * dots),
            TextSpan(text: '.' * (3 - dots), style: const TextStyle(color: Colors.transparent)),
          ]),
          style: widget.style,
        );
      },
    );
  }
}
