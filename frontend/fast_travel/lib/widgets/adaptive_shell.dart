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
  // False hides the phone-layout AppBar entirely (edge-to-edge body,
  // e.g. Feed matching TikTok's full-bleed screen with no title bar).
  // Wide/web layout still gets its title row regardless — that layout
  // already looks nothing like a full-bleed phone screen, so there's
  // no "TikTok look" to preserve there.
  final bool showAppBar;

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
    this.showAppBar = true,
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
    return Icon(selected
        ? Icons.account_circle_rounded
        : Icons.account_circle_outlined);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    final l10n = AppLocalizations.of(context)!;
    final destinations = _destinations(l10n);

    if (!isWide) {
      // Feed (index 1) already puts its own controls in that same
      // bottom-left corner — the caption/author block on the video, plus
      // its own small "new post" button up top — so the floating Ask AI
      // button just sits on top of them there. Every other tab still gets
      // it.
      final showAskAi = selectedIndex != 1;
      return Scaffold(
        appBar:
            showAppBar ? AppBar(title: Text(title), actions: actions) : null,
        body: SafeArea(child: child),
        floatingActionButton: showAskAi ? const _AskAiButton() : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          backgroundColor: AppColors.canopy.withValues(alpha: 0.75),
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopNavBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: destinations,
            actions: actions,
            profileIcon: _profileIcon(selected: selectedIndex == destinations.length),
            profileLabel: l10n.navProfile,
          ),
          const Divider(height: 1, color: Color(0x1A16181D)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 20, 32, 8),
                  child: Text(title,
                      style: Theme.of(context).textTheme.headlineMedium),
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

/// Light horizontal top nav bar for wide/desktop screens — icon + label
/// per destination in a row, with the active tab underlined. Replaces the
/// previous dark vertical NavigationRail so the wide layout reads like a
/// standard web app header instead of a stretched phone shell.
class _TopNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<({IconData icon, IconData selected, String label})> destinations;
  final List<Widget>? actions;
  final Widget profileIcon;
  final String profileLabel;

  const _TopNavBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.actions,
    required this.profileIcon,
    required this.profileLabel,
  });

  @override
  Widget build(BuildContext context) {
    final profileIndex = destinations.length;
    return Container(
      color: AppColors.sand,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.travel_explore_rounded,
              color: AppColors.ochre, size: 28),
          const SizedBox(width: 32),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ...List.generate(destinations.length, (i) {
                  final d = destinations[i];
                  return _TopNavItem(
                    icon: d.icon,
                    selectedIcon: d.selected,
                    label: d.label,
                    selected: selectedIndex == i,
                    onTap: () => onDestinationSelected(i),
                  );
                }),
                _TopNavItem(
                  iconWidget: profileIcon,
                  label: profileLabel,
                  selected: selectedIndex == profileIndex,
                  onTap: () => onDestinationSelected(profileIndex),
                ),
              ],
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

class _TopNavItem extends StatelessWidget {
  final IconData? icon;
  final IconData? selectedIcon;
  final Widget? iconWidget;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TopNavItem({
    this.icon,
    this.selectedIcon,
    this.iconWidget,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.canopy : AppColors.inkSoft;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                iconWidget ??
                    Icon(selected ? (selectedIcon ?? icon) : icon,
                        size: 20, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 2,
              width: selected ? 28 : 0,
              color: AppColors.canopy,
            ),
          ],
        ),
      ),
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
