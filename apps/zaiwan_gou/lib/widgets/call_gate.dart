import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../core/call_channel.dart';
import '../features/call/call_screen.dart';

/// iOS 的超时来电：限时用满时监控扩展挡上屏蔽页、发一条响铃的通知。
/// 点那条通知、在屏蔽页上点“接听”（通知把人带回来），或者 10 分钟内自己打开 App，就弹出来电界面。
/// 屏蔽页和它的按钮扩展不能放动画、不能开麦克风，所以来电界面只能在 App 里。
/// 安卓的来电页是单独的 Activity（CallReminderActivity），不走这里。
class CallGate extends StatefulWidget {
  /// [backend]、[enabled] 只在测试里传
  const CallGate({super.key, required this.child, this.backend = const PlatformCallBackend(), this.enabled});

  final Widget child;
  final CallBackend backend;

  /// 默认只在 iOS 上看
  final bool? enabled;

  @override
  State<CallGate> createState() => _CallGateState();
}

class _CallGateState extends State<CallGate> with WidgetsBindingObserver {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_showing || !mounted || !(widget.enabled ?? Platform.isIOS)) return;
    final call = await widget.backend.pending();
    if (call == null || !mounted || _showing) return;
    _showing = true;
    await showCallScreen(context, call, backend: widget.backend);
    _showing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
