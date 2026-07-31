import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// Tag -> icon, so cards read at a glance without needing photography
IconData _iconForTag(String tag) {
  switch (tag) {
    case 'beach':
      return Icons.waves_rounded;
    case 'wildlife':
    case 'safari':
      return Icons.pets_rounded;
    case 'mountain':
    case 'hiking':
      return Icons.terrain_rounded;
    case 'culture':
    case 'history':
      return Icons.museum_rounded;
    case 'city':
    case 'nightlife':
      return Icons.location_city_rounded;
    case 'relax':
      return Icons.spa_rounded;
    case 'adventure':
      return Icons.landscape_rounded;
    default:
      return Icons.place_rounded;
  }
}

class DestinationCard extends StatelessWidget {
  final Destination destination;
  final VoidCallback? onTap;

  const DestinationCard({super.key, required this.destination, this.onTap});

  @override
  Widget build(BuildContext context) {
    final primaryTag =
        destination.tags.isNotEmpty ? destination.tags.first : 'place';

    // ==========================================
    // FIX: Build the full image URL using imageUrl
    // ==========================================
    String getImageUrl() {
      final rawUrl = destination.imageUrl;
      if (rawUrl.isNotEmpty) {
        // If it's already a full link (starts with http), use it directly
        if (rawUrl.startsWith('http')) {
          return rawUrl;
        }
        // Otherwise, prepend your backend URL to the relative path
        return 'http://109.199.120.38:8000$rawUrl';
      }
      // Ultimate fallback placeholder if imageUrl is empty
      return 'https://images.unsplash.com/photo-1527631746610-bca00a040d60?auto=format&fit=crop&w=900&q=80';
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 118,
                  width: double.infinity,
                  child: Image.network(
                    getImageUrl(),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: AppColors.canopy,
                      alignment: Alignment.center,
                      child: Icon(
                        _iconForTag(primaryTag),
                        color: AppColors.ochre,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                destination.name,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                destination.region.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (destination.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  destination.description,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: destination.tags
                        .map(
                          (t) => Chip(
                            label:
                                Text(t, style: const TextStyle(fontSize: 11)),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            backgroundColor: AppColors.sandDim,
                            side: BorderSide.none,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
