import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../widgets/common.dart';

/// 手机号登录。看天气不用登录；关心群、跨设备同步才需要。
/// 账号和“再玩我是狗”不互通（各自独立的后端和用户）。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.next});

  final String? next;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _sending = false;
  bool _loggingIn = false;
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _phoneOk => RegExp(r'^1[3-9]\d{9}$').hasMatch(_phone.text.trim());

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await AppScope.read(context).api.sendSms(_phone.text.trim());
      if (!mounted) return;
      setState(() => _countdown = 60);
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _countdown <= 1) {
          t.cancel();
          if (mounted) setState(() => _countdown = 0);
          return;
        }
        setState(() => _countdown--);
      });
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _login() async {
    setState(() => _loggingIn = true);
    try {
      await AppScope.read(context).login(_phone.text.trim(), _code.text.trim());
      if (!mounted) return;
      // 从关心群等页面点进来时，返回原页面即可（它会随登录状态刷新）；否则再按 next 跳转，避免栈里叠两个同样的页面
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(widget.next ?? '/');
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('登录后可以建关心群，\n提醒家人带伞、加衣服', style: TextStyle(fontSize: 22, height: 1.4, fontWeight: FontWeight.w900)),
          const SizedBox(height: 24),
          _Field(
            child: TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              maxLength: 11,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: '手机号', border: InputBorder.none, counterText: ''),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Field(
                  child: TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: '验证码', border: InputBorder.none, counterText: ''),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: PopButton(
                  label: _countdown > 0 ? '${_countdown}s' : '获取验证码',
                  style: PopButtonStyle.secondary,
                  loading: _sending,
                  onPressed: _phoneOk && _countdown == 0 ? _send : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          PopButton(
            label: '登录',
            loading: _loggingIn,
            onPressed: _phoneOk && _code.text.trim().length == 6 ? _login : null,
          ),
          const SourceNote('微信登录接入中 · 账号和“再玩我是狗”各自独立'),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: Pop.card(shadow: false),
      child: child,
    );
  }
}
