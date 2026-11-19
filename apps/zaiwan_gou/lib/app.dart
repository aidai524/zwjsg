import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'core/app_state.dart';
import 'package:pop_ui/pop_ui.dart';
import 'features/card/card_page.dart';
import 'features/dex/dex_page.dart';
import 'features/group/group_page.dart';
import 'features/history/history_page.dart';
import 'features/history/stats_page.dart';
import 'features/locks/locks_page.dart';
import 'features/me/cartoon_lab_page.dart';
import 'features/me/me_page.dart';
import 'features/me/privacy_page.dart';
import 'features/me/screen_time_page.dart';
import 'features/onboarding/avatar_page.dart';
import 'features/onboarding/consent_page.dart';
import 'features/onboarding/goal_page.dart';
import 'features/onboarding/login_page.dart';
import 'features/onboarding/welcome_page.dart';
import 'features/today/ranking_page.dart';
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
  void initState() {
    super.initState();
    // 点每晚提醒打开 App 时直接看结算卡
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final launchedFromReminder = await widget.state.startReminders(_openCard);
      if (launchedFromReminder) _openCard();
    });
  }

  void _openCard() {
    if (mounted && widget.state.ready.value) _router.push('/card');
  }

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

/// 引导没走完也能打开的页面（登录页要能看隐私政策）
const _onboardingPaths = {'/welcome', '/login', '/avatar', '/goal', '/privacy'};

/// 还没同意隐私政策时只能看这两页
const _consentPaths = {'/consent', '/privacy'};

GoRouter _buildRouter(AppState state) {
  return GoRouter(
    initialLocation: '/today',
    refreshListenable: Listenable.merge([state.ready, state.consented]),
    redirect: (context, s) {
      final path = s.uri.path;
      if (!state.consented.value) return _consentPaths.contains(path) ? null : '/consent';
      if (path == '/consent') return state.ready.value ? '/today' : '/welcome';
      if (!state.ready.value && !_onboardingPaths.contains(path)) return '/welcome';
      return null;
    },
    routes: [
      GoRoute(path: '/consent', builder: (_, __) => const ConsentPage()),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomePage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/avatar', builder: (_, s) => AvatarPage(editing: s.uri.queryParameters['edit'] == '1')),
      GoRoute(
        path: '/goal',
        builder: (_, s) => GoalPage(editing: s.uri.queryParameters['edit'] == '1'),
      ),
      GoRoute(path: '/card', builder: (_, __) => const CardPage()),
      GoRoute(path: '/privacy', builder: (_, __) => const PrivacyPage()),
      GoRoute(path: '/ranking', builder: (_, __) => const RankingPage()),
      GoRoute(path: '/history', builder: (_, __) => const HistoryPage()),
      GoRoute(path: '/stats', builder: (_, __) => const StatsPage()),
      GoRoute(path: '/locks', builder: (_, __) => const LocksPage()),
      GoRoute(path: '/screen-time', builder: (_, __) => const ScreenTimePage()),
      GoRoute(path: '/cartoon-lab', builder: (_, __) => const CartoonLabPage()),
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
