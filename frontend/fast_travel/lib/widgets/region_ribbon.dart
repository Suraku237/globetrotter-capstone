import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The signature element of GlobeTrotter: a horizontally scrolling ribbon of
/// Cameroon's regions, each tinted along a geography-inspired gradient
/// (forest -> savanna -> coast -> highland). Doubles as a destination filter.
class RegionRibbon extends StatelessWidget {
  static const regions = [
    'Centre',
    'Littoral',
    'Southwest',
    'South',
    'West',
    'Northwest',
    'Far North',
    'North',
    'Adamawa',
    'East',
  ];

  final String? selected;
  final ValueChanged<String?> onSelect;

  const RegionRibbon(
      {super.key, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: regions.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final region = regions[i];
          final color =
              AppColors.regionGradient[i % AppColors.regionGradient.length];
          final isSelected = selected == region;
          return GestureDetector(
            onTap: () => onSelect(isSelected ? null : region),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? color : color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isSelected ? color : color.withValues(alpha: 0.4),
                  width: 1.2,
                ),
              ),
              child: Text(
                region,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.ink,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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
