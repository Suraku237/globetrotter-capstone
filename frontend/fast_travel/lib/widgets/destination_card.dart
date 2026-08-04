import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../screens/home/destination_detail_screen.dart';

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

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                DestinationDetailScreen(destination: destination),
          ),
        );
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ BIGGER IMAGE SIZE
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 135, // <--- INCREASED FROM 118 TO 135
                  width: double.infinity,
                  child: Image.network(
                    destination.imageUrl,
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

              // Title
              Text(
                destination.name,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 4),

              // Region
              Text(
                destination.region.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // Description
              if (destination.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  destination.description,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 12),

              // Tags
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
