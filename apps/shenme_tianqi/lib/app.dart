import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';

import 'core/app_state.dart';
import 'features/care/care_page.dart';
import 'features/care/group_page.dart';
import 'features/cities/cities_page.dart';
import 'features/cities/city_search_page.dart';
import 'features/home/decision_page.dart';
import 'features/home/home_page.dart';
import 'features/login/login_page.dart';
import 'features/onboarding/welcome_page.dart';
import 'features/settings/settings_page.dart';

class ShenmeTianqiApp extends StatefulWidget {
  const ShenmeTianqiApp({super.key, required this.state});

  final AppState state;

  @override
  State<ShenmeTianqiApp> createState() => _ShenmeTianqiAppState();
}

class _ShenmeTianqiAppState extends State<ShenmeTianqiApp> {
  late final GoRouter _router = buildRouter(widget.state);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Pop.overlayOnLight,
      child: MaterialApp.router(
        title: '什么鬼天气',
        debugShowCheckedModeBanner: false,
        theme: Pop.theme(),
        routerConfig: _router,
      ),
    );
  }
}

const _openPaths = {'/welcome', '/city-search'};

GoRouter buildRouter(AppState state) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: state,
    redirect: (context, s) {
      final path = s.uri.path;
      final ready = state.onboarded && state.cities.isNotEmpty;
      if (!ready && !_openPaths.contains(path)) return '/welcome';
      return null;
    },
    routes: [
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomePage()),
      GoRoute(
        path: '/city-search',
        builder: (_, s) => CitySearchPage(onboarding: s.uri.queryParameters['onboarding'] == '1'),
      ),
      GoRoute(path: '/', builder: (_, __) => const HomePage()),
      GoRoute(
        path: '/decision/:key',
        builder: (_, s) => DecisionPage(decisionKey: s.pathParameters['key']!, locationId: s.uri.queryParameters['city'] ?? ''),
      ),
      GoRoute(path: '/cities', builder: (_, __) => const CitiesPage()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
      GoRoute(path: '/login', builder: (_, s) => LoginPage(next: s.uri.queryParameters['next'])),
      GoRoute(
        path: '/care',
        builder: (_, s) => CarePage(initialTab: s.uri.queryParameters['tab'] == 'inbox' ? 1 : 0),
      ),
      GoRoute(path: '/care/:id', builder: (_, s) => GroupPage(groupId: int.parse(s.pathParameters['id']!))),
    ],
  );
}
