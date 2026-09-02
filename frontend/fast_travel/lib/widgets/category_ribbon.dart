import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Horizontally scrolling filter chips for destination categories (tags) —
/// replaces the old region-based ribbon. The category list itself always
/// matches whatever tags actually appear on the loaded destinations (see
/// DiscoverScreen), so it can never drift out of sync with real data.
///
/// Chips use a near-opaque light fill rather than a faint tinted one so
/// they stay legible over the busy background photo, the same treatment
/// already used for the search bar on this screen.
class CategoryRibbon extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const CategoryRibbon({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  // Tags are stored lowercase (e.g. "beach", "wildlife") — capitalized
  // here for display only; filtering still compares the raw tag string.
  static String _label(String tag) =>
      tag.isEmpty ? tag : tag[0].toUpperCase() + tag.substring(1);

  // Best-effort icon per tag, matched by keyword rather than an exact
  // lookup table — tags are freeform (whatever admins/users have entered
  // on destinations), so this can't be an exhaustive enum. Falls through
  // to a generic "place" icon for anything unrecognized rather than
  // leaving the chip iconless.
  static const _iconsByKeyword = <String, IconData>{
    'market': Icons.storefront_rounded,
    'shop': Icons.storefront_rounded,
    'nature': Icons.eco_rounded,
    'wildlife': Icons.eco_rounded,
    'forest': Icons.forest_rounded,
    'rainforest': Icons.forest_rounded,
    'park': Icons.park_rounded,
    'garden': Icons.park_rounded,
    'museum': Icons.museum_rounded,
    'art': Icons.palette_rounded,
    'cathedral': Icons.church_rounded,
    'church': Icons.church_rounded,
    'restaurant': Icons.restaurant_rounded,
    'food': Icons.restaurant_rounded,
    'soya': Icons.restaurant_rounded,
    'street-food': Icons.restaurant_rounded,
    'cinema': Icons.movie_rounded,
    'nightlife': Icons.nightlife_rounded,
    'bar': Icons.local_bar_rounded,
    'sport': Icons.sports_soccer_rounded,
    'hotel': Icons.hotel_rounded,
    'hiking': Icons.hiking_rounded,
    'mountain': Icons.terrain_rounded,
    'volcano': Icons.terrain_rounded,
    'beach': Icons.beach_access_rounded,
    'relax': Icons.spa_rounded,
    'river': Icons.water_rounded,
    'boating': Icons.directions_boat_rounded,
    'fishing': Icons.phishing_rounded,
    'lake': Icons.water_rounded,
    'bird': Icons.flutter_dash_rounded,
    'animal': Icons.pets_rounded,
    'conservation': Icons.eco_rounded,
    'biodiversity': Icons.eco_rounded,
    'ecotourism': Icons.travel_explore_rounded,
    'bridge': Icons.architecture_rounded,
    'architecture': Icons.architecture_rounded,
    'city': Icons.location_city_rounded,
    'business': Icons.business_center_rounded,
    'adventure': Icons.hiking_rounded,
    'local': Icons.place_rounded,
  };

  static IconData _iconFor(String tag) {
    final lower = tag.toLowerCase();
    for (final entry in _iconsByKeyword.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return Icons.place_rounded;
  }

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final category = categories[i];
          final color =
              AppColors.regionGradient[i % AppColors.regionGradient.length];
          final isSelected = selected == category;

          return GestureDetector(
            onTap: () => onSelect(isSelected ? null : category),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color:
                    isSelected ? color : AppColors.sand.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isSelected ? color : color.withValues(alpha: 0.7),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconFor(category),
                    size: 16,
                    color: isSelected ? Colors.white : color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _label(category),
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.ink,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
