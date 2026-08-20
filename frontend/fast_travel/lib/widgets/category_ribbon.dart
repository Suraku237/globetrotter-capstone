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
              child: Text(
                _label(category),
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.ink,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
