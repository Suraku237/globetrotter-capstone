import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// One shell, three interfaces. Below 600px (phones) it shows a bottom nav
/// bar. From 600px up (tablets, desktop, web) it switches to a
/// NavigationRail so wide screens aren't just a stretched phone layout.
class AdaptiveShell extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;
  final String title;
  final List<Widget>? actions;

  // ✅ UPDATED: Added 4th destination: Map
  static const _destinations = [
    (
      icon: Icons.explore_outlined,
      selected: Icons.explore_rounded,
      label: 'Discover'
    ),
    (
      icon: Icons.auto_awesome_outlined,
      selected: Icons.auto_awesome_rounded,
      label: 'For You'
    ),
    (icon: Icons.map_outlined, selected: Icons.map_rounded, label: 'My Trips'),
    (icon: Icons.public_outlined, selected: Icons.public_rounded, label: 'Map'),
  ];

  const AdaptiveShell({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
    required this.title,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    if (!isWide) {
      return Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: SafeArea(child: child),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          backgroundColor: AppColors.canopy,
          indicatorColor: AppColors.ochre.withValues(alpha: 0.2),
          destinations: _destinations
              .map((d) => NavigationDestination(
                    icon: Icon(d.icon,
                        color: AppColors.sand.withValues(alpha: 0.7)),
                    selectedIcon: Icon(d.selected, color: AppColors.ochre),
                    label: d.label,
                  ))
              .toList(),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            backgroundColor: AppColors.canopy,
            extended: MediaQuery.sizeOf(context).width >= 1024,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Icon(Icons.travel_explore_rounded,
                  color: AppColors.ochre, size: 32),
            ),
            destinations: _destinations
                .map((d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selected),
                      label: Text(d.label),
                    ))
                .toList(),
          ),
          const VerticalDivider(width: 1, color: Color(0x22000000)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 28, 32, 8),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(title,
                              style:
                                  Theme.of(context).textTheme.headlineMedium)),
                      ...?actions,
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
