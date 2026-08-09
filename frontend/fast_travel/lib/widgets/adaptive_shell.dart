import 'package:flutter/material.dart';
import '../Services/api_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../screens/assistant/assistant_screen.dart';
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
  // Backs the trailing "Profile" nav destination — shows the user's actual
  // avatar there instead of a generic icon, per the "profile icon should be
  // filled with the profile image" request.
  final String? avatarUrl;
  final String? userName;

  // ✅ UPDATED: Added 4th destination: Map
  // Labels come from AppLocalizations at build time (see _destinations),
  // not stored here — a static const can't depend on BuildContext.
  static const _destinationIcons = [
    (icon: Icons.explore_outlined, selected: Icons.explore_rounded),
    (icon: Icons.dynamic_feed_outlined, selected: Icons.dynamic_feed_rounded),
    (icon: Icons.map_outlined, selected: Icons.map_rounded),
    (icon: Icons.public_outlined, selected: Icons.public_rounded),
  ];

  List<({IconData icon, IconData selected, String label})> _destinations(
      AppLocalizations l10n) {
    final labels = [
      l10n.navDiscover,
      l10n.navFeed,
      l10n.navMyTrips,
      l10n.navMap,
    ];
    return List.generate(
      _destinationIcons.length,
      (i) => (
        icon: _destinationIcons[i].icon,
        selected: _destinationIcons[i].selected,
        label: labels[i],
      ),
    );
  }

  const AdaptiveShell({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
    required this.title,
    this.actions,
    this.avatarUrl,
    this.userName,
  });

  Widget _profileIcon({required bool selected}) {
    final url = avatarUrl;
    if (url != null) {
      return CircleAvatar(
        radius: 12,
        backgroundColor: AppColors.sandDim,
        backgroundImage: NetworkImage(ApiService.resolveUrl(url)),
      );
    }
    final name = userName?.trim();
    if (name != null && name.isNotEmpty) {
      return CircleAvatar(
        radius: 12,
        backgroundColor: selected ? AppColors.ochre : AppColors.inkSoft,
        child: Text(
          name[0].toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      );
    }
    return Icon(selected ? Icons.account_circle_rounded : Icons.account_circle_outlined);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    final l10n = AppLocalizations.of(context)!;
    final destinations = _destinations(l10n);

    if (!isWide) {
      return Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: SafeArea(child: child),
        floatingActionButton: const _AskAiButton(),
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          backgroundColor: AppColors.canopy,
          indicatorColor: AppColors.ochre.withValues(alpha: 0.2),
          destinations: [
            ...destinations.map((d) => NavigationDestination(
                  icon: Icon(d.icon,
                      color: AppColors.sand.withValues(alpha: 0.7)),
                  selectedIcon: Icon(d.selected, color: AppColors.ochre),
                  label: d.label,
                )),
            NavigationDestination(
              icon: _profileIcon(selected: false),
              selectedIcon: _profileIcon(selected: true),
              label: l10n.navProfile,
            ),
          ],
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
            destinations: [
              ...destinations.map((d) => NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: Text(d.label),
                  )),
              NavigationRailDestination(
                icon: _profileIcon(selected: false),
                selectedIcon: _profileIcon(selected: true),
                label: Text(l10n.navProfile),
              ),
            ],
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
      floatingActionButton: const _AskAiButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }
}

// Styled and positioned the same way as the "Suggest a destination" FAB on
// Discover, just parked on the opposite (start) side so the two never
// collide on screens that have both.
class _AskAiButton extends StatelessWidget {
  const _AskAiButton();

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'ask_ai_fab',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AssistantScreen()),
      ),
      icon: const Icon(Icons.smart_toy_rounded),
      label: Text(AppLocalizations.of(context)!.askAi),
    );
  }
}
