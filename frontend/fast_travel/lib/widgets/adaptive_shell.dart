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
  // Called both by the phone AppBar's chat icon and the wide top nav
  // bar's "Chat" item — chat is a pushed screen (like the admin review
  // screen), not one of the indexed tabs in `destinations`, so it isn't
  // part of selectedIndex/onDestinationSelected.
  final VoidCallback onOpenChat;

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
    required this.onOpenChat,
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
        appBar: showAppBar
            ? AppBar(
                title: Text(title),
                actions: [
                  IconButton(
                    tooltip: 'Messages',
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        color: AppColors.inkSoft),
                    onPressed: onOpenChat,
                  ),
                  ...?actions,
                ],
              )
            : null,
        body: showAppBar
            ? SafeArea(child: child)
            // Feed (and any other future full-bleed screen) opts out of
            // the top-level SafeArea so its background — the vertical
            // video — actually extends edge-to-edge under the status bar,
            // instead of leaving a black strip that clips the top of the
            // video. Overlaid controls (tabs, search, "new post" button)
            // apply their own SafeArea from inside the screen so they
            // stay clear of the notch.
            : child,
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
        children: [
          _TopNavBar(
            destinations: destinations,
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            onOpenChat: onOpenChat,
            profileLabel: l10n.navProfile,
            profileIndex: destinations.length,
            profileIcon: _profileIcon,
            actions: actions,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: const _AskAiButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }
}

// Horizontal top nav bar for the wide/web layout — icon + label per item,
// a short underline beneath whichever one is active. Replaces the old
// left-hand NavigationRail with the more familiar top-bar pattern.
class _TopNavBar extends StatelessWidget {
  final List<({IconData icon, IconData selected, String label})> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onOpenChat;
  final String profileLabel;
  final int profileIndex;
  final Widget Function({required bool selected}) profileIcon;
  final List<Widget>? actions;

  const _TopNavBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onOpenChat,
    required this.profileLabel,
    required this.profileIndex,
    required this.profileIcon,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: AppColors.sand,
        border: Border(bottom: BorderSide(color: Color(0x1A16181D))),
      ),
      child: Row(
        children: [
          const Icon(Icons.travel_explore_rounded,
              color: AppColors.ochre, size: 26),
          const SizedBox(width: 32),
          ...destinations.asMap().entries.map(
                (entry) => _NavBarItem(
                  icon: entry.value.icon,
                  selectedIcon: entry.value.selected,
                  label: entry.value.label,
                  selected: entry.key == selectedIndex,
                  onTap: () => onDestinationSelected(entry.key),
                ),
              ),
          _NavBarItem(
            icon: Icons.chat_bubble_outline_rounded,
            selectedIcon: Icons.chat_bubble_rounded,
            label: 'Chat',
            // Chat is a pushed screen, not a tab — it never shows as
            // "active" in the bar the way Discover/Feed/etc. do.
            selected: false,
            onTap: onOpenChat,
          ),
          const Spacer(),
          ...?actions,
          _NavBarItem(
            icon: null,
            customIcon: profileIcon(selected: selectedIndex == profileIndex),
            label: profileLabel,
            selected: selectedIndex == profileIndex,
            onTap: () => onDestinationSelected(profileIndex),
          ),
        ],
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData? icon;
  final IconData? selectedIcon;
  final Widget? customIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavBarItem({
    this.icon,
    this.selectedIcon,
    this.customIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.ochre : AppColors.inkSoft;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  customIcon ??
                      Icon(selected ? (selectedIcon ?? icon) : icon,
                          size: 20, color: color),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? AppColors.ink : AppColors.inkSoft,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                height: 2,
                width: double.infinity,
                color: selected ? AppColors.ochre : Colors.transparent,
              ),
            ],
          ),
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
