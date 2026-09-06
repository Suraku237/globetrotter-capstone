import 'dart:ui';

import 'package:flutter/material.dart';
import '../Services/api_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../screens/assistant/assistant_screen.dart';
import '../theme/app_theme.dart';

/// One shell, two interfaces. Below 600px (phones) it shows a bottom nav
/// bar for one-tap reach. From 600px up (tablets, desktop, web) the
/// horizontal top-nav strip is gone — navigation lives in a hamburger-
/// triggered [Drawer] on both layouts, freeing the whole viewport for
/// content instead of eating a persistent row of chrome.
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
  // Called both by the phone AppBar's friends icon and the wide top nav
  // bar's "Friends" item — it is a pushed screen (like the admin review
  // screen), not one of the indexed tabs in `destinations`, so it isn't
  // part of selectedIndex/onDestinationSelected.
  final VoidCallback onOpenFriends;

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
    required this.onOpenFriends,
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
    final drawer = _buildDrawer(context, l10n, destinations);

    if (!isWide) {
      // Feed (index 1) already puts its own controls in that same
      // bottom-left corner — the caption/author block on the video, plus
      // its own small "new post" button up top — so the floating Ask AI
      // button just sits on top of them there. Every other tab still gets
      // it.
      final showAskAi = selectedIndex != 1;
      return Scaffold(
        drawer: drawer,
        appBar: showAppBar
            ? AppBar(
                title: Text(title),
                // Explicit leading builder so we get the same hamburger
                // regardless of what the current route's AppBar theme
                // decided to override.
                leading: Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu_rounded,
                        color: AppColors.inkSoft),
                    tooltip: MaterialLocalizations.of(context)
                        .openAppDrawerTooltip,
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Friends',
                    icon: const Icon(Icons.people_outline_rounded,
                        color: AppColors.inkSoft),
                    onPressed: onOpenFriends,
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

    // Wide/desktop: no more horizontal top-nav strip. A slim, transparent
    // AppBar carries the hamburger + screen title (and any actions the
    // screen passed in), the drawer handles navigation, and the whole
    // viewport width is free for the actual content.
    return Scaffold(
      backgroundColor: Colors.transparent,
      drawer: drawer,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: AppColors.inkSoft),
            tooltip:
                MaterialLocalizations.of(context).openAppDrawerTooltip,
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Friends',
            icon: const Icon(Icons.people_outline_rounded,
                color: AppColors.inkSoft),
            onPressed: onOpenFriends,
          ),
          ...?actions,
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
          child: child,
        ),
      ),
      floatingActionButton: const _AskAiButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }

  /// The hamburger-triggered navigation panel shared by both layouts.
  ///
  /// Styled after the reference mockup: a dark, blurred translucent
  /// panel that lets the Yaoundé backdrop show through, a GlobeTrotter
  /// wordmark at the top, and one row per app section. Selected item
  /// gets a soft filled bar; the currently selected screen dismisses
  /// the drawer without re-navigating (matches how Material drawers are
  /// expected to behave when the tap target is already active).
  Widget _buildDrawer(
    BuildContext context,
    AppLocalizations l10n,
    List<({IconData icon, IconData selected, String label})> destinations,
  ) {
    final profileIndex = destinations.length;
    return Drawer(
      width: 280,
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.canopy.withValues(alpha: 0.68),
              border: Border(
                right: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Row(
                      children: [
                        // Fast Travel brand mark. Landscape aspect (~2:1) so
                        // it's sized by height and lets width follow — no
                        // square-cropping. cacheHeight keeps decode cost low
                        // even if the source is a high-res JPEG. errorBuilder
                        // falls back to the classic globe if the asset ever
                        // fails to load (missing bundle, stale build, etc.)
                        // so the drawer header never renders as broken.
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.asset(
                            'assets/images/brand_logo.jpg',
                            height: 32,
                            fit: BoxFit.contain,
                            cacheHeight: 96,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                              Icons.travel_explore_rounded,
                              color: AppColors.ochre,
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'GlobeTrotter',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        for (int i = 0; i < destinations.length; i++)
                          _DrawerItem(
                            icon: destinations[i].icon,
                            selectedIcon: destinations[i].selected,
                            label: destinations[i].label,
                            selected: selectedIndex == i,
                            onTap: () {
                              Navigator.of(context).pop();
                              if (selectedIndex != i) {
                                onDestinationSelected(i);
                              }
                            },
                          ),
                        _DrawerItem(
                          icon: Icons.account_circle_outlined,
                          selectedIcon: Icons.account_circle_rounded,
                          label: l10n.navProfile,
                          selected: selectedIndex == profileIndex,
                          onTap: () {
                            Navigator.of(context).pop();
                            if (selectedIndex != profileIndex) {
                              onDestinationSelected(profileIndex);
                            }
                          },
                        ),
                        _DrawerItem(
                          icon: Icons.people_outline_rounded,
                          selectedIcon: Icons.people_rounded,
                          label: 'Friends',
                          selected: false,
                          onTap: () {
                            Navigator.of(context).pop();
                            onOpenFriends();
                          },
                        ),
                        _DrawerItem(
                          icon: Icons.forum_outlined,
                          selectedIcon: Icons.forum_rounded,
                          label: 'Assistant',
                          selected: false,
                          onTap: () {
                            Navigator.of(context).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AssistantScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// One row inside the app-navigation Drawer — icon, label, and (when it
// represents the currently selected tab) a soft ochre background pill.
// Style mirrors the reference mockup: white text on the translucent
// dark panel, a filled highlight behind the active row.
class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? Colors.white : Colors.white.withValues(alpha: 0.82);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 22,
                  color: foreground,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 15,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
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
