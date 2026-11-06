import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import 'package:pop_ui/pop_ui.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  int _countdown = 0;
  Timer? _timer;
  bool _loading = false;
  String? _error;

  bool get _phoneOk => RegExp(r'^1[3-9]\d{9}$').hasMatch(_phone.text);

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() => _error = null);
    try {
      await AppScope.read(context).api.sendSms(_phone.text);
      setState(() => _countdown = 60);
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _countdown--);
        if (_countdown <= 0) t.cancel();
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _login() async {
    final state = AppScope.read(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await state.login(_phone.text, _code.text);
      if (!mounted) return;
      context.go(state.onboarded ? '/today' : '/avatar');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Pop.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Pop.ink, width: Pop.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Pop.ink, width: 4),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            const Text('先报个到', style: PopText.title),
            const SizedBox(height: 8),
            const Text('用手机号登录，换手机也能找回你的狗', style: PopText.bodyMuted),
            const SizedBox(height: 28),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
              decoration: _deco('手机号'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    decoration: _deco('6 位验证码'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 130,
                  child: PopButton(
                    label: _countdown > 0 ? '${_countdown}s' : '获取验证码',
                    style: PopButtonStyle.secondary,
                    height: 54,
                    onPressed: _phoneOk && _countdown <= 0 ? _sendCode : null,
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Pop.danger, fontSize: 14)),
            ],
            const SizedBox(height: 28),
            PopButton(
              label: '登录',
              loading: _loading,
              onPressed: _phoneOk && _code.text.length == 6 ? _login : null,
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () => context.go('/avatar'),
                child: const Text('先不登录，随便看看', style: TextStyle(color: Pop.muted, fontSize: 14)),
              ),
            ),
            const SizedBox(height: 8),
            const Text('微信登录：开放平台配置好后开启', textAlign: TextAlign.center, style: PopText.small),
          ],
        ),
      ),
    );
  }
}
