import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'core/app_state.dart';
import 'core/theme.dart';
import 'features/card/card_page.dart';
import 'features/dex/dex_page.dart';
import 'features/group/group_page.dart';
import 'features/me/hardcore_page.dart';
import 'features/me/me_page.dart';
import 'features/onboarding/avatar_page.dart';
import 'features/onboarding/goal_page.dart';
import 'features/onboarding/login_page.dart';
import 'features/onboarding/welcome_page.dart';
import 'features/today/today_page.dart';
import 'widgets/tab_shell.dart';

class ZwjsgApp extends StatefulWidget {
  const ZwjsgApp({super.key, required this.state});

  final AppState state;

  @override
  State<ZwjsgApp> createState() => _ZwjsgAppState();
}

class _ZwjsgAppState extends State<ZwjsgApp> {
  late final GoRouter _router = _buildRouter(widget.state);

  @override
  Widget build(BuildContext context) {
    // 没有 AppBar 的页面（四个 Tab、欢迎页）不设置状态栏，这里给默认值，
    // 否则从结算卡这样的深色页面返回后，图标会停留在白色
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Pop.overlayOnLight,
      child: MaterialApp.router(
        title: '再玩我是狗',
        debugShowCheckedModeBanner: false,
        theme: Pop.theme(),
        routerConfig: _router,
      ),
    );
  }
}

const _onboardingPaths = {'/welcome', '/login', '/avatar', '/goal'};

GoRouter _buildRouter(AppState state) {
  return GoRouter(
    initialLocation: '/today',
    refreshListenable: state,
    redirect: (context, s) {
      final path = s.uri.path;
      if (!state.onboarded && !_onboardingPaths.contains(path)) return '/welcome';
      return null;
    },
    routes: [
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomePage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/avatar', builder: (_, __) => const AvatarPage()),
      GoRoute(
        path: '/goal',
        builder: (_, s) => GoalPage(editing: s.uri.queryParameters['edit'] == '1'),
      ),
      GoRoute(path: '/card', builder: (_, __) => CardPage()),
      GoRoute(path: '/hardcore', builder: (_, __) => const HardcorePage()),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => TabShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/today', builder: (_, __) => const TodayPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/group', builder: (_, __) => const GroupPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/dex', builder: (_, __) => const DexPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/me', builder: (_, __) => const MePage())]),
        ],
      ),
    ],
  );
}
