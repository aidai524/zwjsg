import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:pop_ui/pop_ui.dart';

/// 底部导航：今天 / 狗群 / 图鉴 / 我的
class TabShell extends StatelessWidget {
  const TabShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _items = [
    (Icons.home_outlined, '今天'),
    (Icons.groups_outlined, '狗群'),
    (Icons.grid_view_rounded, '图鉴'),
    (Icons.person_outline, '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Pop.white,
          border: Border(top: BorderSide(color: Pop.ink, width: Pop.stroke)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: _TabItem(
                      icon: _items[i].$1,
                      label: _items[i].$2,
                      active: shell.currentIndex == i,
                      onTap: () => shell.goBranch(i, initialLocation: i == shell.currentIndex),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? Pop.ink : Pop.muted;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 30,
              decoration: BoxDecoration(
                color: active ? Pop.yellow : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: active ? Pop.ink : Colors.transparent, width: 2),
              ),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: active ? FontWeight.w900 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
