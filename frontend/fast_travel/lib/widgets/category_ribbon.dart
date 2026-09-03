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

  // Tags come straight from whatever destinations/suggestions exist —
  // free-form strings, not a fixed enum — so this is a best-effort lookup
  // over the common ones rather than an exhaustive switch. Anything not
  // recognized falls back to a plain generic tag icon rather than leaving
  // the chip icon-less.
  static const Map<String, IconData> _icons = {
    'adventure': Icons.hiking_rounded,
    'animals': Icons.pets_rounded,
    'wildlife': Icons.pets_rounded,
    'architecture': Icons.account_balance_rounded,
    'art': Icons.palette_rounded,
    'art-gallery': Icons.palette_rounded,
    'bar': Icons.local_bar_rounded,
    'beach': Icons.beach_access_rounded,
    'biodiversity': Icons.eco_rounded,
    'birds': Icons.flutter_dash_rounded,
    'boating': Icons.directions_boat_rounded,
    'bridge': Icons.alt_route_rounded,
    'business': Icons.business_center_rounded,
    'cathedral': Icons.church_rounded,
    'religion': Icons.church_rounded,
    'cinema': Icons.theaters_rounded,
    'city': Icons.location_city_rounded,
    'craft': Icons.handyman_rounded,
    'culture': Icons.theater_comedy_rounded,
    'dance': Icons.music_note_rounded,
    'ecotourism': Icons.forest_rounded,
    'festival': Icons.celebration_rounded,
    'fishing': Icons.phishing_rounded,
    'food': Icons.restaurant_rounded,
    'street-food': Icons.lunch_dining_rounded,
    'forest': Icons.forest_rounded,
    'government': Icons.account_balance_rounded,
    'hiking': Icons.hiking_rounded,
    'history': Icons.history_edu_rounded,
    'historical': Icons.history_edu_rounded,
    'hotel': Icons.hotel_rounded,
    'lake': Icons.water_rounded,
    'landmark': Icons.location_on_rounded,
    'local': Icons.storefront_rounded,
    'market': Icons.storefront_rounded,
    'monument': Icons.temple_hindu_rounded,
    'mountain': Icons.landscape_rounded,
    'museum': Icons.museum_rounded,
    'music': Icons.music_note_rounded,
    'nature': Icons.eco_rounded,
    'nightlife': Icons.nightlife_rounded,
    'palace': Icons.castle_rounded,
    'park': Icons.park_rounded,
    'restaurant': Icons.restaurant_rounded,
    'river': Icons.water_rounded,
    'shopping': Icons.shopping_bag_rounded,
    'sports': Icons.sports_soccer_rounded,
    'waterfall': Icons.water_drop_rounded,
  };

  static IconData _iconFor(String tag) =>
      _icons[tag.toLowerCase()] ?? Icons.local_offer_rounded;

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
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
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
